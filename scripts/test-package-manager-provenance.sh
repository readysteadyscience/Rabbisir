#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
provenance_tool="$repository_root/scripts/runtime-provenance.mjs"
temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root%/}"
fixture_root="$(/usr/bin/mktemp -d "$temporary_root/rabbisir-package-manager.XXXXXX")"

cleanup() {
  [[ "$fixture_root" == "$temporary_root"/rabbisir-package-manager.* ]] || exit 70
  /usr/bin/find "$fixture_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM

archive="$fixture_root/pnpm.tgz"
contract="$fixture_root/contract.json"
print 'reviewed package manager archive' >"$archive"
/bin/cp "$repository_root/RuntimeProvenance/contract.json" "$contract"
node - "$contract" "$archive" <<'NODE'
const crypto = require('node:crypto')
const fs = require('node:fs')
const [contractPath, archivePath] = process.argv.slice(2)
const contract = JSON.parse(fs.readFileSync(contractPath, 'utf8'))
contract.toolchain.packageManagerArchiveURL =
  'https://registry.npmjs.org/pnpm/-/pnpm-11.7.0.tgz'
contract.toolchain.packageManagerArchiveSHA256 = crypto
  .createHash('sha256')
  .update(fs.readFileSync(archivePath))
  .digest('hex')
contract.toolchain.packageManagerExecutable = 'package/bin/pnpm.cjs'
fs.writeFileSync(contractPath, `${JSON.stringify(contract, null, 2)}\n`)
NODE

node "$provenance_tool" verify-package-manager-archive "$archive" "$contract" >/dev/null
print 'tampered' >>"$archive"
if node "$provenance_tool" verify-package-manager-archive \
  "$archive" "$contract" >/dev/null 2>&1
then
  print -u2 "test-package-manager-provenance: a changed package-manager archive was accepted"
  exit 1
fi

print 'reviewed package manager archive' >"$archive"
node - "$contract" <<'NODE'
const fs = require('node:fs')
const path = process.argv[2]
const contract = JSON.parse(fs.readFileSync(path, 'utf8'))
contract.toolchain.packageManagerArchiveURL = 'https://example.invalid/pnpm.tgz'
fs.writeFileSync(path, `${JSON.stringify(contract, null, 2)}\n`)
NODE
if node "$provenance_tool" verify-package-manager-archive \
  "$archive" "$contract" >/dev/null 2>&1
then
  print -u2 "test-package-manager-provenance: a non-official package-manager source was accepted"
  exit 1
fi

if "$repository_root/scripts/rebuild-vendor-runtime.sh" a b c >/dev/null 2>&1; then
  print -u2 "test-package-manager-provenance: rebuild accepted a missing archive input"
  exit 1
fi

if rg -n 'corepack[[:space:]]+prepare' "$repository_root/scripts/rebuild-vendor-runtime.sh"
then
  print -u2 "test-package-manager-provenance: online Corepack preparation remains"
  exit 1
fi

print "test-package-manager-provenance: official source, archive digest, and explicit offline input fail closed"
