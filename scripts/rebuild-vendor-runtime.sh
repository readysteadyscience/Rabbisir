#!/bin/sh
set -eu

if [ "$#" -ne 4 ]; then
  echo "usage: rebuild-vendor-runtime.sh <official-upstream-checkout> <node-distribution-root> <pnpm-archive> <output-root>" >&2
  exit 64
fi

upstream_root=$1
node_root=$2
pnpm_archive=$3
output_root=$4
repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
provenance_tool="$repository_root/scripts/runtime-provenance.mjs"
contract="$repository_root/RuntimeProvenance/contract.json"

if [ -e "$output_root" ]; then
  echo "rebuild-vendor-runtime: output must not already exist: $output_root" >&2
  exit 65
fi

contract_value() {
  node -e '
    const contract = require(process.argv[1])
    let value = contract
    for (const component of process.argv[2].split(".")) value = value[component]
    if (value === undefined || typeof value === "object") process.exit(2)
    process.stdout.write(String(value))
  ' "$contract" "$1"
}

upstream_commit=$(contract_value upstream.commit)
package_manager=$(contract_value toolchain.packageManager)
package_manager_executable=$(contract_value toolchain.packageManagerExecutable)
derived_lock_sha=$(contract_value build.derivedInjectedLockSHA256)
expected_client_bundles=$(contract_value build.sequentialClientBundles)
runtime_supplement=$(contract_value build.runtimeSupplement)
expected_workspace_supplements=$(contract_value build.requiredWorkspacePeerSupplements)

node "$provenance_tool" verify-source "$upstream_root" "$node_root" "$contract" >/dev/null
node "$provenance_tool" verify-package-manager-archive \
  "$pnpm_archive" "$contract" >/dev/null

work_root=$(mktemp -d "${TMPDIR:-/tmp}/rabbisir-runtime-rebuild.XXXXXX")
cleanup() {
  if [ -d "$work_root" ]; then
    find "$work_root" -depth -delete
  fi
}
trap cleanup EXIT HUP INT TERM

source_root="$work_root/source"
deploy_root="$work_root/deploy"
package_manager_root="$work_root/package-manager"
mkdir "$source_root" "$package_manager_root"

git -C "$upstream_root" archive "$upstream_commit" | tar -x -C "$source_root"
patch_list="$work_root/patches.txt"
node -e '
  const contract = require(process.argv[1])
  for (const patch of contract.patches) process.stdout.write(`${patch.path}\n`)
' "$contract" >"$patch_list"
while IFS= read -r patch; do
  git -C "$source_root" apply "$repository_root/$patch"
done <"$patch_list"

export CI=true
export npm_config_cache="$work_root/npm-cache"
export pnpm_config_store_dir="$work_root/pnpm-store"

tar -xzf "$pnpm_archive" -C "$package_manager_root"
pnpm_executable="$package_manager_root/$package_manager_executable"
test -f "$pnpm_executable"
node -e '
  const manifest = require(process.argv[1])
  if (manifest.name !== "pnpm" || `pnpm@${manifest.version}` !== process.argv[2]) process.exit(1)
' "$package_manager_root/package/package.json" "$package_manager"
pnpm() {
  "$node_root/bin/node" "$pnpm_executable" "$@"
}
pnpm --version | grep -qx "${package_manager#pnpm@}"

(
  cd "$source_root"
  pnpm install --frozen-lockfile
  pnpm run build

  client_list="$work_root/client-bundles.txt"
  find apps packages vendor -path '*/lib/client.js' -type f | LC_ALL=C sort >"$client_list"
  client_count=$(wc -l <"$client_list" | tr -d ' ')
  if [ "$client_count" != "$expected_client_bundles" ]; then
    echo "rebuild-vendor-runtime: expected $expected_client_bundles client bundles, got $client_count" >&2
    exit 66
  fi
  while IFS= read -r client; do
    package_root=${client%/lib/client.js}
    config="$package_root/tsdown.config.ts"
    test -f "$config"
    pnpm exec tsdown -c "$config" --env.DSH_BUILD_FACE client --logLevel error >/dev/null
  done <"$client_list"

  pnpm --config.inject-workspace-packages=true install --no-frozen-lockfile
  actual_derived_lock=$(shasum -a 256 pnpm-lock.yaml | awk '{print $1}')
  if [ "$actual_derived_lock" != "$derived_lock_sha" ]; then
    echo "rebuild-vendor-runtime: derived lock digest mismatch: $actual_derived_lock" >&2
    exit 67
  fi
  pnpm \
    --config.inject-workspace-packages=true \
    --config.node-linker=hoisted \
    --filter @deepseek-ai/dsh \
    deploy --prod --ignore-scripts "$deploy_root"
)

group_target="$deploy_root/node_modules/@deepseek-ai/cordis-plugin-group"
mkdir -p "$group_target"
rsync -a \
  --exclude node_modules \
  --exclude README.md \
  --exclude README.zh.md \
  --exclude README.i18n.yaml \
  "$source_root/$runtime_supplement/" "$group_target/"

supplements_json="$work_root/workspace-supplements.json"
supplements_list="$work_root/workspace-supplements.txt"
node "$provenance_tool" workspace-supplements \
  "$source_root" "$deploy_root" >"$supplements_json"
node -e '
  const supplements = require(process.argv[1])
  for (const supplement of supplements) {
    process.stdout.write(`${supplement.name}\t${supplement.sourceRelativePath}\n`)
  }
' "$supplements_json" >"$supplements_list"
actual_workspace_supplements=$(wc -l <"$supplements_list" | tr -d ' ')
if [ "$actual_workspace_supplements" != "$expected_workspace_supplements" ]; then
  echo "rebuild-vendor-runtime: expected $expected_workspace_supplements workspace peer supplements, got $actual_workspace_supplements" >&2
  exit 68
fi
tab=$(printf '\t')
while IFS="$tab" read -r package_name source_package; do
  test -n "$package_name"
  test -f "$source_root/$source_package/package.json"
  test -d "$source_root/$source_package/lib"
  target_package="$deploy_root/node_modules/$package_name"
  mkdir -p "$target_package"
  cp "$source_root/$source_package/package.json" "$target_package/package.json"
  rsync -a "$source_root/$source_package/lib/" "$target_package/lib/"
done <"$supplements_list"
node "$provenance_tool" verify-workspace-closure "$deploy_root" >/dev/null

replace_library() {
  source_package=$1
  target_package=$2
  target_library="$deploy_root/node_modules/$target_package/lib"
  find "$target_library" -depth -delete
  mkdir -p "$target_library"
  rsync -a "$source_root/$source_package/lib/" "$target_library/"
}
replace_library packages/client/runtime @deepseek-ai/dsh-client-runtime
replace_library packages/client/ui-conversation @deepseek-ai/dsh-client-ui-conversation
replace_library packages/client/ui-sidebar @deepseek-ai/dsh-client-ui-sidebar

client_list="$work_root/client-bundles.txt"
while IFS= read -r client; do
  package_root=${client%/lib/client.js}
  package_name=$(cd "$source_root" && node -p "require('./$package_root/package.json').name")
  target_library="$deploy_root/node_modules/$package_name/lib"
  if [ -d "$target_library" ]; then
    if ! cmp -s "$source_root/$client" "$target_library/client.js"; then
      cp "$source_root/$client" "$target_library/client.js"
    fi
    if [ -f "$source_root/$client.map" ]; then
      if ! cmp -s "$source_root/$client.map" "$target_library/client.js.map"; then
        cp "$source_root/$client.map" "$target_library/client.js.map"
      fi
    fi
  fi
done <"$client_list"

cp "$source_root/apps/cli/package.json" "$deploy_root/package.json"
cp "$source_root/THIRD_PARTY_NOTICES.md" "$deploy_root/THIRD_PARTY_NOTICES.md"
for metadata in \
  node_modules/.modules.yaml \
  node_modules/.pnpm-workspace-state-v1.json \
  node_modules/.pnpm/lock.yaml \
  pnpm-lock.yaml \
  pnpm-workspace.yaml
do
  if [ -e "$deploy_root/$metadata" ]; then
    find "$deploy_root/$metadata" -depth -delete
  fi
done
find "$deploy_root" -type f \( \
  -name README.md -o \
  -name README.zh.md -o \
  -name README.i18n.yaml \
\) -delete
chmod 755 "$deploy_root/node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper"

node "$provenance_tool" normalize-runtime "$source_root" "$deploy_root" >/dev/null

carrier_root="$work_root/carrier"
mkdir -p "$carrier_root/bin" "$carrier_root/node"
rsync -a "$deploy_root/" "$carrier_root/node/"
cp "$repository_root/Sources/RabbisirCore/Resources/VendorRuntime/bin/rabbisir-runtime" \
  "$carrier_root/bin/rabbisir-runtime"
cp "$node_root/bin/node" "$carrier_root/bin/node"
cp "$deploy_root/node_modules/node-pty/prebuilds/darwin-arm64/spawn-helper" \
  "$carrier_root/bin/node-spawn-helper"
chmod 755 \
  "$carrier_root/bin/rabbisir-runtime" \
  "$carrier_root/bin/node" \
  "$carrier_root/bin/node-spawn-helper"
node "$provenance_tool" write-manifest "$carrier_root" "$contract" >/dev/null
node "$provenance_tool" write-receipt "$carrier_root" "$contract" >/dev/null
node "$provenance_tool" verify-runtime "$carrier_root" "$contract" >/dev/null

mkdir -p "$(dirname -- "$output_root")"
mkdir "$output_root"
rsync -a "$carrier_root/" "$output_root/"
node "$provenance_tool" verify-runtime "$output_root" "$contract" >/dev/null
echo "rebuild-vendor-runtime: reproducible runtime $(contract_value upstream.version)"
