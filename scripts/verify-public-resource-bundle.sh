#!/bin/sh
set -eu

if [ "$#" -ne 1 ]; then
  echo "usage: verify-public-resource-bundle.sh <resource-bundle>" >&2
  exit 64
fi

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
resource_bundle=$1
asset_manifest="$repository_root/Legal/ASSET_MANIFEST.sha256"
runtime_contract="$repository_root/RuntimeProvenance/contract.json"

fail() {
  echo "verify-public-resource-bundle: public resource bundle verification failed" >&2
  exit 1
}

test -d "$resource_bundle" || fail

actual_top_level=$(find "$resource_bundle" -mindepth 1 -maxdepth 1 -exec basename {} \; | LC_ALL=C sort)
expected_top_level=$(printf '%s\n' Brand VendorRuntime | LC_ALL=C sort)
[ "$actual_top_level" = "$expected_top_level" ] || fail

expected_brand_files=$(
  sed -E 's/^[0-9a-f]{64}  Sources\/RabbisirCore\/Resources\///' "$asset_manifest" \
    | LC_ALL=C sort
)
actual_brand_files=$(
  find "$resource_bundle/Brand" -type f -print \
    | sed "s|^$resource_bundle/||" \
    | LC_ALL=C sort
)
[ "$actual_brand_files" = "$expected_brand_files" ] || fail
if find "$resource_bundle/Brand" ! -type d ! -type f -print | grep -q .; then
  fail
fi
if find "$resource_bundle/Brand" -type d -empty -print | grep -q .; then
  fail
fi

while IFS='  ' read -r expected_hash source_path; do
  relative_path=${source_path#Sources/RabbisirCore/Resources/}
  actual_hash=$(shasum -a 256 "$resource_bundle/$relative_path" | awk '{print $1}')
  [ "$actual_hash" = "$expected_hash" ] || fail
done <"$asset_manifest"

actual_runtime_top_level=$(
  find "$resource_bundle/VendorRuntime" -mindepth 1 -maxdepth 1 -exec basename {} \; \
    | LC_ALL=C sort
)
expected_runtime_top_level=$(
  printf '%s\n' \
    .gitignore \
    .rabbisir-runtime-provenance.json \
    LICENSE.node.txt \
    LICENSE.upstream.txt \
    THIRD_PARTY_NOTICES.md \
    bin \
    manifest.json \
    node \
    provenance-contract.json \
    | LC_ALL=C sort
)
[ "$actual_runtime_top_level" = "$expected_runtime_top_level" ] || fail

"$repository_root/scripts/verify-staged-runtime.sh" \
  "$resource_bundle/VendorRuntime" "$runtime_contract" >/dev/null || fail

echo "verify-public-resource-bundle: Brand and VendorRuntime exactly match reviewed inputs"
