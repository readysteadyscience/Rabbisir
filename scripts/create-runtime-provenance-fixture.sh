#!/bin/zsh
set -euo pipefail

if (( $# != 2 )); then
  print -u2 "usage: create-runtime-provenance-fixture.sh <runtime-root> <contract-path>"
  exit 64
fi

repository_root="${0:A:h:h}"
inventory_tool="$repository_root/scripts/runtime-provenance.mjs"
temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root:A}"
runtime_root="${1:A}"
contract="${2:A}"
native_projection="node/node_modules/@deepseek-ai/fixture/lib/types/client/native-projection.js"

[[ "$runtime_root" == "$temporary_root"/rabbisir-*/* \
  && "$contract" == "$temporary_root"/rabbisir-*/* \
  && ! -e "$runtime_root" \
  && ! -e "$contract" ]] \
  || { print -u2 "create-runtime-provenance-fixture: unsafe or existing fixture path"; exit 70; }

/bin/mkdir -p \
  "$runtime_root/bin" \
  "$runtime_root/node/lib" \
  "$runtime_root/${native_projection:h}"
cat >"$runtime_root/bin/rabbisir-runtime" <<'SH'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = "--version" ]; then
  printf '0.1.0-rc.5\n'
fi
exit 0
SH
cat >"$runtime_root/bin/node-spawn-helper" <<'SH'
#!/bin/sh
exit 0
SH
cat >"$runtime_root/bin/node" <<'SH'
#!/bin/sh
if [ "$#" -eq 1 ] && [ "$1" = "--version" ]; then
  printf 'v24.19.0\n'
  exit 0
fi
if [ "$#" -eq 2 ] && [ "$2" = "--version" ]; then
  printf '0.1.0-rc.5\n'
  exit 0
fi
exit 64
SH
/bin/chmod 755 \
  "$runtime_root/bin/rabbisir-runtime" \
  "$runtime_root/bin/node-spawn-helper" \
  "$runtime_root/bin/node"
print 'fixture entrypoint' >"$runtime_root/node/lib/bin.js"
print 'fixture third-party notices' >"$runtime_root/node/THIRD_PARTY_NOTICES.md"
print 'fixture Node license' >"$runtime_root/LICENSE.node.txt"
print '{"name":"@deepseek-ai/fixture","version":"0.0.0"}' \
  >"$runtime_root/node/node_modules/@deepseek-ai/fixture/package.json"
print 'fixture projection' >"$runtime_root/$native_projection"

node - "$runtime_root" "$contract" "$inventory_tool" "$native_projection" <<'NODE'
const crypto = require('node:crypto')
const fs = require('node:fs')
const { execFileSync } = require('node:child_process')
const path = require('node:path')
const [runtimeRoot, contractPath, inventoryTool, nativeProjection] = process.argv.slice(2)
const sha256 = file => crypto.createHash('sha256').update(fs.readFileSync(file)).digest('hex')
const inventory = JSON.parse(execFileSync(
  process.execPath,
  [inventoryTool, 'inventory-runtime', runtimeRoot],
  { encoding: 'utf8' }
))
const contract = {
  schemaVersion: 3,
  manifest: { schemaVersion: 3, rabbisirVersion: 'fixture' },
  upstream: {
    version: '0.1.0-rc.5',
    commit: 'fixture-commit',
    tree: 'fixture-tree',
  },
  toolchain: {
    nodeVersion: '24.19.0',
    nodeBinarySHA256: sha256(path.join(runtimeRoot, 'bin/node')),
    packageManager: 'pnpm@11.7.0',
    packageManagerArchiveURL: 'https://registry.npmjs.org/pnpm/-/pnpm-11.7.0.tgz',
    packageManagerArchiveSHA256: '0'.repeat(64),
    packageManagerExecutable: 'package/bin/pnpm.cjs',
  },
  build: { normalizedSourceRoot: 'rabbisir-upstream-source' },
  launch: {
    executable: 'bin/rabbisir-runtime',
    node: 'bin/node',
    nodeSpawnHelper: 'bin/node-spawn-helper',
  },
  output: {
    ...inventory,
    nativeProjection: {
      path: nativeProjection,
      sha256: sha256(path.join(runtimeRoot, nativeProjection)),
    },
  },
}
fs.writeFileSync(contractPath, `${JSON.stringify(contract, null, 2)}\n`)
NODE
node "$inventory_tool" write-manifest "$runtime_root" "$contract" >/dev/null
/bin/cp "$contract" "$runtime_root/provenance-contract.json"
node "$inventory_tool" write-receipt "$runtime_root" "$contract" >/dev/null
node "$inventory_tool" verify-runtime "$runtime_root" "$contract" >/dev/null

print "create-runtime-provenance-fixture: valid fixture created"
