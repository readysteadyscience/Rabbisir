#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
inventory_tool="$repository_root/scripts/runtime-provenance.mjs"
fixture_builder="$repository_root/scripts/create-runtime-provenance-fixture.sh"
temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root%/}"
work_root="$(/usr/bin/mktemp -d "$temporary_root/rabbisir-runtime-closure.XXXXXX")"
source_root="$work_root/valid-runtime"
contract="$work_root/fixture-contract.json"
native_projection="node/node_modules/@deepseek-ai/fixture/lib/types/client/native-projection.js"

cleanup() {
  [[ "$work_root" == "$temporary_root"/rabbisir-runtime-closure.* ]] || exit 70
  /bin/rm -rf "$work_root"
}
trap cleanup EXIT HUP INT TERM

"$fixture_builder" "$source_root" "$contract" >/dev/null

fresh_carrier() {
  /bin/rm -rf "$work_root/runtime"
  /bin/cp -cR "$source_root" "$work_root/runtime"
}

must_reject() {
  if node "$inventory_tool" verify-runtime \
    "$work_root/runtime" "$contract" >/dev/null 2>&1
  then
    print -u2 "test-runtime-launch-closure: accepted $1"
    exit 1
  fi
}

fresh_carrier
/bin/cp /usr/bin/true "$work_root/runtime/bin/rabbisir-runtime"
must_reject "a tampered launcher"

fresh_carrier
/bin/cp /usr/bin/true "$work_root/runtime/bin/node-spawn-helper"
must_reject "a tampered Node spawn helper"

fresh_carrier
/bin/cp /usr/bin/true "$work_root/runtime/bin/node"
must_reject "a tampered Node executable"

fresh_carrier
print 'tampered projection' >"$work_root/runtime/$native_projection"
must_reject "a tampered native projection"

fresh_carrier
/bin/rm "$work_root/runtime/bin/rabbisir-runtime"
/bin/ln -s /usr/bin/true "$work_root/runtime/bin/rabbisir-runtime"
must_reject "an executable symlink escape"

fresh_carrier
node - "$work_root/runtime/manifest.json" <<'NODE'
const fs = require('node:fs')
const path = process.argv[2]
const manifest = JSON.parse(fs.readFileSync(path))
manifest.executable = '../../../../../../usr/bin/true'
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`)
NODE
must_reject "manifest executable traversal"

fresh_carrier
node - "$work_root/runtime/manifest.json" <<'NODE'
const fs = require('node:fs')
const path = process.argv[2]
const manifest = JSON.parse(fs.readFileSync(path))
manifest.rabbisirVersion = 'tampered-review-value'
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`)
NODE
must_reject "a changed manifest rabbisirVersion"

for field in \
  schemaVersion \
  upstreamVersion \
  upstreamCommit \
  upstreamTree \
  provenanceContractSHA256 \
  runtimeInventorySHA256 \
  executable
do
  fresh_carrier
  node - "$work_root/runtime/manifest.json" "$field" <<'NODE'
const fs = require('node:fs')
const [path, field] = process.argv.slice(2)
const manifest = JSON.parse(fs.readFileSync(path))
manifest[field] = field === 'schemaVersion' ? 999 : 'tampered-review-value'
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`)
NODE
  must_reject "a changed manifest $field"
done

fresh_carrier
node - "$work_root/runtime/manifest.json" <<'NODE'
const fs = require('node:fs')
const path = process.argv[2]
const manifest = JSON.parse(fs.readFileSync(path))
manifest.unreviewedField = true
fs.writeFileSync(path, `${JSON.stringify(manifest, null, 2)}\n`)
NODE
must_reject "an unknown manifest key"

fresh_carrier
node - "$work_root/runtime/.rabbisir-runtime-provenance.json" <<'NODE'
const fs = require('node:fs')
const path = process.argv[2]
const receipt = JSON.parse(fs.readFileSync(path))
receipt.schemaVersion = 2
fs.writeFileSync(path, `${JSON.stringify(receipt, null, 2)}\n`)
NODE
must_reject "a legacy schema 2 receipt"

print "test-runtime-launch-closure: executables, paths, manifest fields, and unknown keys rejected"
