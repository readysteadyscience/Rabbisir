#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
if [ "$#" -eq 0 ]; then
  runtime_root="$repository_root/Sources/RabbisirCore/Resources/VendorRuntime"
  contract="$repository_root/RuntimeProvenance/contract.json"
elif [ "$#" -eq 2 ]; then
  runtime_root=$1
  contract=$2
else
  echo "usage: verify-staged-runtime.sh [<runtime-root> <contract>]" >&2
  exit 64
fi
packaged_contract="$runtime_root/provenance-contract.json"
manifest="$runtime_root/manifest.json"

fail() {
  echo "verify-staged-runtime: staged runtime provenance verification failed" >&2
  exit 1
}

cmp -s "$contract" "$packaged_contract" || fail
node "$repository_root/scripts/runtime-provenance.mjs" verify-manifest \
  "$manifest" "$contract" >/dev/null 2>&1 || fail
node "$repository_root/scripts/runtime-provenance.mjs" verify-runtime \
  "$runtime_root" "$contract" >/dev/null 2>&1 || fail

echo "verify-staged-runtime: staged runtime matches its public provenance contract"
