#!/bin/sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
inventory_tool="$script_root/runtime-provenance.mjs"
fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/rabbisir-runtime-provenance-test.XXXXXX")
trap 'rm -rf "$fixture_root"' EXIT HUP INT TERM

printf 'alpha\n' >"$fixture_root/alpha.txt"
chmod 644 "$fixture_root/alpha.txt"
ln -s alpha.txt "$fixture_root/link"
printf '{"excluded":"receipt"}\n' >"$fixture_root/.rabbisir-runtime-provenance.json"

actual=$(
  node "$inventory_tool" inventory "$fixture_root"
)
expected='{"algorithm":"sha256(canonical-path-mode-content-v1)","digest":"1e32b9c5d7d256ad01603062fbc70859b1432978cd26e5b387ffe6a94b1e1368","fileCount":1,"symlinkCount":1}'
if [ "$actual" != "$expected" ]; then
  echo "test-runtime-provenance: canonical inventory mismatch" >&2
  echo "expected: $expected" >&2
  echo "actual:   $actual" >&2
  exit 1
fi

mkdir "$fixture_root/outside"
printf 'outside\n' >"$fixture_root/outside/value.txt"
mkdir "$fixture_root/contained"
ln -s ../../outside/value.txt "$fixture_root/contained/escape"
if node "$inventory_tool" inventory "$fixture_root/contained" >/dev/null 2>&1; then
  echo "test-runtime-provenance: escaping symlink was accepted" >&2
  exit 1
fi

source_a="$fixture_root/source-a"
source_b="$fixture_root/source-b"
runtime_a="$fixture_root/runtime-a"
runtime_b="$fixture_root/runtime-b"
mkdir "$source_a" "$source_b" "$runtime_a" "$runtime_b"
source_a=$(CDPATH= cd -- "$source_a" && pwd -P)
source_b=$(CDPATH= cd -- "$source_b" && pwd -P)
runtime_a=$(CDPATH= cd -- "$runtime_a" && pwd -P)
runtime_b=$(CDPATH= cd -- "$runtime_b" && pwd -P)
cat >"$runtime_a/client.js" <<EOF
//#region $source_a/client/Example.module.css.mjs
var Example_module_css_default = {
  "zeta": "hash_zeta",
  "alpha": "hash_alpha"
};
EOF
cat >"$runtime_b/client.js" <<EOF
//#region $source_b/client/Example.module.css.mjs
var Example_module_css_default = {
  "alpha": "hash_alpha",
  "zeta": "hash_zeta"
};
EOF

node "$inventory_tool" normalize-runtime "$source_a" "$runtime_a" >/dev/null
node "$inventory_tool" normalize-runtime "$source_b" "$runtime_b" >/dev/null
normalized_a=$(node "$inventory_tool" inventory "$runtime_a")
normalized_b=$(node "$inventory_tool" inventory "$runtime_b")
if [ "$normalized_a" != "$normalized_b" ]; then
  echo "test-runtime-provenance: normalized builds differ by source path or CSS key order" >&2
  exit 1
fi
grep -q 'rabbisir-upstream-source/client/Example.module.css.mjs' "$runtime_a/client.js"
alpha_line=$(grep -n '"alpha"' "$runtime_a/client.js" | cut -d: -f1)
zeta_line=$(grep -n '"zeta"' "$runtime_a/client.js" | cut -d: -f1)
if [ "$alpha_line" -ge "$zeta_line" ]; then
  echo "test-runtime-provenance: CSS module keys were not normalized" >&2
  exit 1
fi
if node "$inventory_tool" write-receipt "$runtime_a" >/dev/null 2>&1; then
  echo "test-runtime-provenance: non-contract runtime received a provenance receipt" >&2
  exit 1
fi

manifest_fixture="$fixture_root/manifest.json"
cp "$script_root/../Sources/RabbisirCore/Resources/VendorRuntime/manifest.json" "$manifest_fixture"
node -e '
  const fs = require("fs")
  const path = process.argv[1]
  const manifest = JSON.parse(fs.readFileSync(path, "utf8"))
  manifest.executable = "../../../../../../usr/bin/true"
  fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`)
' "$manifest_fixture"
if node "$inventory_tool" verify-manifest \
  "$manifest_fixture" "$script_root/../RuntimeProvenance/contract.json" >/dev/null 2>&1
then
  echo "test-runtime-provenance: manifest executable traversal was accepted" >&2
  exit 1
fi

closure_root="$fixture_root/closure"
mkdir -p \
  "$closure_root/node_modules/@deepseek-ai/present" \
  "$closure_root/node_modules/@deepseek-ai/consumer"
printf '%s\n' '{"name":"@deepseek-ai/present","version":"1.0.0"}' \
  >"$closure_root/node_modules/@deepseek-ai/present/package.json"
printf '%s\n' \
  '{"name":"@deepseek-ai/consumer","version":"1.0.0","dependencies":{"@deepseek-ai/present":"workspace:^","@deepseek-ai/missing":"workspace:^"}}' \
  >"$closure_root/node_modules/@deepseek-ai/consumer/package.json"
if node "$inventory_tool" verify-workspace-closure "$closure_root" >/dev/null 2>&1; then
  echo "test-runtime-provenance: missing workspace dependency was accepted" >&2
  exit 1
fi
mkdir -p "$closure_root/node_modules/@deepseek-ai/missing"
printf '%s\n' '{"name":"@deepseek-ai/missing","version":"1.0.0"}' \
  >"$closure_root/node_modules/@deepseek-ai/missing/package.json"
closure_result=$(node "$inventory_tool" verify-workspace-closure "$closure_root")
if [ "$closure_result" != '{"workspacePackages":3,"workspaceDependencyEdges":2}' ]; then
  echo "test-runtime-provenance: complete workspace dependency closure was rejected" >&2
  exit 1
fi

supplement_source="$fixture_root/supplement-source"
mkdir -p "$supplement_source/packages/present/lib" "$supplement_source/packages/missing/lib"
printf '%s\n' \
  '{"name":"@deepseek-ai/present","version":"1.0.0","files":["lib/index.js"],"peerDependencies":{"@deepseek-ai/missing":"workspace:^"}}' \
  >"$supplement_source/packages/present/package.json"
printf '%s\n' \
  '{"name":"@deepseek-ai/missing","version":"1.0.0","files":["lib/index.js"]}' \
  >"$supplement_source/packages/missing/package.json"
find "$closure_root/node_modules/@deepseek-ai/missing" -depth -delete
supplements=$(node "$inventory_tool" workspace-supplements "$supplement_source" "$closure_root")
expected_supplements='[{"name":"@deepseek-ai/missing","sourceRelativePath":"packages/missing"}]'
if [ "$supplements" != "$expected_supplements" ]; then
  echo "test-runtime-provenance: deterministic workspace supplement list mismatch" >&2
  exit 1
fi

echo "test-runtime-provenance: canonical inventory, normalization, symlink boundary, and workspace dependency closure verified"
