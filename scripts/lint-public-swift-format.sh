#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root%/}"
configuration="$(/usr/bin/mktemp "$temporary_root/rabbisir-swift-format.XXXXXX.json")"

cleanup() {
  [[ "$configuration" == "$temporary_root"/rabbisir-swift-format.*.json ]] || exit 70
  /bin/rm -f "$configuration"
}
trap cleanup EXIT HUP INT TERM

xcrun swift-format dump-configuration >"$configuration"
node - "$configuration" <<'NODE'
const fs = require('node:fs')
const configurationPath = process.argv[2]
const configuration = JSON.parse(fs.readFileSync(configurationPath, 'utf8'))
const rule = 'UseLetInEveryBoundCaseVariable'

if (configuration.rules?.[rule] !== true) {
  console.error(`lint-public-swift-format: unexpected ${rule} configuration`)
  process.exit(70)
}

configuration.rules[rule] = false
fs.writeFileSync(configurationPath, `${JSON.stringify(configuration, null, 2)}\n`)
NODE

cd "$repository_root"
xcrun swift-format lint \
  --configuration "$configuration" \
  --strict \
  --recursive \
  Package.swift Sources Tests

print "lint-public-swift-format: public source conforms to the selected Xcode rule set"
