#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
fixture_builder="$repository_root/scripts/create-runtime-provenance-fixture.sh"
temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root%/}"
work_root="$(/usr/bin/mktemp -d "$temporary_root/rabbisir-manifest-gates.XXXXXX")"
source_runtime="$work_root/valid-runtime"
contract="$work_root/fixture-contract.json"

cleanup() {
  [[ "$work_root" == "$temporary_root"/rabbisir-manifest-gates.* ]] || exit 70
  /bin/rm -rf "$work_root"
}
trap cleanup EXIT HUP INT TERM

"$fixture_builder" "$source_runtime" "$contract" >/dev/null
"$repository_root/scripts/verify-staged-runtime.sh" \
  "$source_runtime" "$contract" >/dev/null

tamper_rabbisir_version() {
  node - "$1/manifest.json" <<'NODE'
const fs = require('node:fs')
const path = process.argv[2]
const manifest = JSON.parse(fs.readFileSync(path))
manifest.rabbisirVersion = 'tampered-review-value'
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`)
NODE
}

tampered_runtime="$work_root/tampered-runtime"
/bin/cp -cR "$source_runtime" "$tampered_runtime"
tamper_rabbisir_version "$tampered_runtime"
if "$repository_root/scripts/verify-staged-runtime.sh" \
  "$tampered_runtime" "$contract" >/dev/null 2>&1
then
  print -u2 "test-runtime-manifest-gates: packaging accepted a changed manifest"
  exit 1
fi

fixture_repository="$work_root/repository"
/bin/mkdir -p \
  "$fixture_repository/scripts" \
  "$fixture_repository/RuntimeProvenance" \
  "$fixture_repository/Sources/RabbisirCore/Resources"
/bin/cp "$repository_root/scripts/runtime-provenance.mjs" "$fixture_repository/scripts/"
/bin/cp "$repository_root/scripts/stage-vendor-runtime.sh" "$fixture_repository/scripts/"
/bin/cp "$contract" "$fixture_repository/RuntimeProvenance/contract.json"
/bin/cp -cR "$source_runtime" \
  "$fixture_repository/Sources/RabbisirCore/Resources/VendorRuntime"

node_distribution="$work_root/node-distribution"
/bin/mkdir -p "$node_distribution/bin"
/bin/cp "$source_runtime/bin/node" "$node_distribution/bin/node"
/bin/cp "$source_runtime/LICENSE.node.txt" "$node_distribution/LICENSE"

"$fixture_repository/scripts/stage-vendor-runtime.sh" \
  "$source_runtime" "$node_distribution" >/dev/null

if "$fixture_repository/scripts/stage-vendor-runtime.sh" \
  "$tampered_runtime" "$node_distribution" >/dev/null 2>&1
then
  print -u2 "test-runtime-manifest-gates: staging accepted a changed manifest"
  exit 1
fi

print "test-runtime-manifest-gates: packaging and staging reject a changed manifest"
