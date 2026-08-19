#!/bin/sh
set -eu

if [ "$#" -ne 2 ]; then
  echo "usage: stage-vendor-runtime.sh <receipted-runtime-carrier-root> <node-distribution-root>" >&2
  exit 64
fi

source_root=$1
node_root=$2
app_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
runtime_root="$app_root/Sources/RabbisirCore/Resources/VendorRuntime"
provenance_tool="$app_root/scripts/runtime-provenance.mjs"
provenance_contract="$app_root/RuntimeProvenance/contract.json"
expected_version=0.1.0-rc.5

test -f "$source_root/node/lib/bin.js"
test -f "$source_root/node/THIRD_PARTY_NOTICES.md"
test -x "$source_root/bin/rabbisir-runtime"
test -x "$source_root/bin/node"
test -x "$source_root/bin/node-spawn-helper"
test -f "$source_root/manifest.json"
test -f "$source_root/.rabbisir-runtime-provenance.json"
test -x "$node_root/bin/node"
test -f "$node_root/LICENSE"
node "$provenance_tool" verify-runtime \
  "$source_root" "$provenance_contract" >/dev/null
cmp -s "$source_root/bin/node" "$node_root/bin/node" || {
  echo "stage-vendor-runtime: carrier Node does not match the declared distribution" >&2
  exit 65
}
actual_version=$($source_root/bin/node "$source_root/node/lib/bin.js" --version)
if [ "$actual_version" != "$expected_version" ]; then
  echo "stage-vendor-runtime: expected $expected_version, got $actual_version" >&2
  exit 65
fi

mkdir -p "$runtime_root/bin" "$runtime_root/node"
find "$runtime_root/node" -depth -delete
mkdir -p "$runtime_root/node"
rsync -a "$source_root/node/" "$runtime_root/node/"
cp "$source_root/bin/node" "$runtime_root/bin/node"
cp "$source_root/bin/node-spawn-helper" "$runtime_root/bin/node-spawn-helper"
cp "$node_root/LICENSE" "$runtime_root/LICENSE.node.txt"
cp "$source_root/node/THIRD_PARTY_NOTICES.md" "$runtime_root/THIRD_PARTY_NOTICES.md"
cp "$provenance_contract" "$runtime_root/provenance-contract.json"
cp "$source_root/.rabbisir-runtime-provenance.json" \
  "$runtime_root/.rabbisir-runtime-provenance.json"
cp "$source_root/manifest.json" "$runtime_root/manifest.json"
cmp -s "$source_root/bin/rabbisir-runtime" "$runtime_root/bin/rabbisir-runtime" || {
  echo "stage-vendor-runtime: canonical launcher does not match this source checkout" >&2
  exit 65
}
chmod 755 \
  "$runtime_root/bin/rabbisir-runtime" \
  "$runtime_root/bin/node" \
  "$runtime_root/bin/node-spawn-helper"

node "$provenance_tool" verify-runtime \
  "$runtime_root" "$provenance_contract" >/dev/null
node "$provenance_tool" verify-manifest \
  "$runtime_root/manifest.json" "$provenance_contract" >/dev/null
cmp -s "$provenance_contract" "$runtime_root/provenance-contract.json"

staged_version=$($runtime_root/bin/rabbisir-runtime --version)
if [ "$staged_version" != "$expected_version" ]; then
  echo "stage-vendor-runtime: staged runtime reports $staged_version" >&2
  exit 66
fi
echo "stage-vendor-runtime: staged compatible runtime $staged_version"
