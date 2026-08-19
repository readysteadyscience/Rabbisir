#!/usr/bin/env node

import { execFile as execFileCallback } from 'node:child_process'
import { createHash } from 'node:crypto'
import {
  lstat,
  readFile,
  readdir,
  readlink,
  realpath,
  writeFile,
} from 'node:fs/promises'
import { dirname, isAbsolute, relative, resolve, sep } from 'node:path'
import { fileURLToPath } from 'node:url'
import { promisify } from 'node:util'

const execFile = promisify(execFileCallback)
const repositoryRoot = resolve(dirname(fileURLToPath(import.meta.url)), '..')
const defaultContractPath = resolve(repositoryRoot, 'RuntimeProvenance/contract.json')
const receiptName = '.rabbisir-runtime-provenance.json'
const inventoryAlgorithm = 'sha256(canonical-path-mode-content-v1)'
const normalizedSourceRoot = 'rabbisir-upstream-source'

function fail(message) {
  throw new Error(`runtime-provenance: ${message}`)
}

function sha256(value) {
  return createHash('sha256').update(value).digest('hex')
}

function isInside(root, candidate) {
  return candidate === root || candidate.startsWith(`${root}${sep}`)
}

function assertCanonicalText(value, label) {
  if (value.includes('\n') || value.includes('\r')) fail(`${label} contains a line break`)
}

async function filesUnder(root) {
  const files = []
  async function visit(directory) {
    const entries = await readdir(directory, { withFileTypes: true })
    entries.sort((left, right) => Buffer.from(left.name).compare(Buffer.from(right.name)))
    for (const entry of entries) {
      const path = resolve(directory, entry.name)
      if (entry.isDirectory()) await visit(path)
      else if (entry.isFile()) files.push(path)
    }
  }
  await visit(root)
  return files
}

async function inventory(rootArgument, includedTopLevelNames) {
  const root = await realpath(resolve(rootArgument))
  const records = []
  let fileCount = 0
  let symlinkCount = 0

  async function visit(directory) {
    const entries = await readdir(directory, { withFileTypes: true })
    entries.sort((left, right) => Buffer.from(left.name).compare(Buffer.from(right.name)))
    for (const entry of entries) {
      if (directory === root
        && includedTopLevelNames
        && !includedTopLevelNames.has(entry.name)) continue
      const path = resolve(directory, entry.name)
      const relativePath = relative(root, path).split(sep).join('/')
      assertCanonicalText(relativePath, 'runtime path')
      if (relativePath === receiptName || relativePath.endsWith(`/${receiptName}`)) continue
      const metadata = await lstat(path)
      if (metadata.isDirectory()) {
        await visit(path)
        continue
      }
      if (metadata.isSymbolicLink()) {
        const destination = await realpath(path).catch(() => fail(`broken symlink: ${relativePath}`))
        if (!isInside(root, destination)) fail(`symlink escapes runtime root: ${relativePath}`)
        const target = await readlink(path)
        assertCanonicalText(target, 'symlink target')
        records.push(`link ${target} ${relativePath}\n`)
        symlinkCount += 1
        continue
      }
      if (!metadata.isFile()) fail(`unsupported filesystem entry: ${relativePath}`)
      const mode = metadata.mode & 0o111 ? '0755' : '0644'
      records.push(`file ${mode} ${sha256(await readFile(path))} ${relativePath}\n`)
      fileCount += 1
    }
  }

  await visit(root)
  records.sort()
  return {
    algorithm: inventoryAlgorithm,
    digest: sha256(records.join('')),
    fileCount,
    symlinkCount,
  }
}

async function runtimeCarrierInventory(rootArgument) {
  return inventory(rootArgument, new Set(['bin', 'node']))
}

function canonicalRuntimePath(value, label) {
  if (typeof value !== 'string' || value.length === 0 || isAbsolute(value)) {
    fail(`${label} is not a canonical runtime-relative path`)
  }
  assertCanonicalText(value, label)
  if (value.includes('\0') || value.includes('\\')) {
    fail(`${label} is not a canonical runtime-relative path`)
  }
  const components = value.split('/')
  if (components.some(component => component.length === 0 || component === '.' || component === '..')) {
    fail(`${label} is not a canonical runtime-relative path`)
  }
  return value
}

async function resolveRuntimePath(runtimeRoot, value, label) {
  const relativePath = canonicalRuntimePath(value, label)
  const candidate = resolve(runtimeRoot, relativePath)
  if (!isInside(runtimeRoot, candidate)) fail(`${label} escapes the runtime root`)
  const destination = await realpath(candidate).catch(() => fail(`${label} is missing`))
  if (!isInside(runtimeRoot, destination)) fail(`${label} resolves outside the runtime root`)
  return candidate
}

function replaceBuffer(input, search, replacement) {
  const chunks = []
  let cursor = 0
  while (true) {
    const index = input.indexOf(search, cursor)
    if (index < 0) break
    chunks.push(input.subarray(cursor, index), replacement)
    cursor = index + search.length
  }
  if (cursor === 0) return input
  chunks.push(input.subarray(cursor))
  return Buffer.concat(chunks)
}

function normalizeCSSModuleObjects(source, path) {
  const lines = source.split('\n')
  const output = []
  let changed = false
  for (let index = 0; index < lines.length; index += 1) {
    const line = lines[index]
    output.push(line)
    if (!/^\s*var .+_module_css_default = \{$/.test(line)) continue
    const properties = []
    while (index + 1 < lines.length && lines[index + 1].trim() !== '};') {
      properties.push(lines[index + 1])
      index += 1
    }
    if (index + 1 >= lines.length) fail(`unterminated CSS module object: ${path}`)
    if (!properties.every(property => /^\s*"[^"]+": /.test(property))) {
      fail(`unexpected CSS module object: ${path}`)
    }
    const normalized = properties
      .map(property => property.endsWith(',') ? property.slice(0, -1) : property)
      .sort()
      .map((property, propertyIndex, all) => property + (propertyIndex + 1 < all.length ? ',' : ''))
    if (normalized.some((property, propertyIndex) => property !== properties[propertyIndex])) {
      changed = true
    }
    output.push(...normalized)
  }
  return { changed, source: output.join('\n') }
}

async function normalizeRuntime(sourceArgument, runtimeArgument) {
  const sourceRoot = await realpath(resolve(sourceArgument))
  const runtimeRoot = await realpath(resolve(runtimeArgument))
  const sourceBytes = Buffer.from(sourceRoot)
  const normalizedBytes = Buffer.from(normalizedSourceRoot)
  let pathFiles = 0
  let cssFiles = 0

  for (const path of await filesUnder(runtimeRoot)) {
    const original = await readFile(path)
    let contents = replaceBuffer(original, sourceBytes, normalizedBytes)
    if (contents !== original) pathFiles += 1
    if (path.endsWith('/client.js')) {
      const normalized = normalizeCSSModuleObjects(contents.toString('utf8'), path)
      if (normalized.changed) {
        contents = Buffer.from(normalized.source)
        cssFiles += 1
      }
    }
    if (!contents.equals(original)) await writeFile(path, contents)
  }
  return { normalizedSourcePathFiles: pathFiles, normalizedCSSModuleFiles: cssFiles }
}

async function loadContract(contractArgument = defaultContractPath) {
  const path = resolve(contractArgument)
  const bytes = await readFile(path).catch(() => fail(`contract missing: ${path}`))
  const contract = JSON.parse(bytes.toString('utf8'))
  if (contract.schemaVersion !== 3) fail(`unsupported contract schema: ${contract.schemaVersion}`)
  if (contract.manifest?.schemaVersion !== 3
    || typeof contract.manifest.rabbisirVersion !== 'string'
    || contract.manifest.rabbisirVersion.length === 0) {
    fail('contract manifest projection is invalid')
  }
  if (contract.build.normalizedSourceRoot !== normalizedSourceRoot) {
    fail(`unsupported normalized source root: ${contract.build.normalizedSourceRoot}`)
  }
  const packageManagerMatch = /^pnpm@(\d+\.\d+\.\d+)$/.exec(
    contract.toolchain.packageManager ?? ''
  )
  const packageManagerURL = new URL(contract.toolchain.packageManagerArchiveURL ?? '')
  if (!packageManagerMatch
    || packageManagerURL.protocol !== 'https:'
    || packageManagerURL.hostname !== 'registry.npmjs.org'
    || packageManagerURL.pathname !== `/pnpm/-/pnpm-${packageManagerMatch[1]}.tgz`
    || !/^[0-9a-f]{64}$/.test(contract.toolchain.packageManagerArchiveSHA256 ?? '')) {
    fail('package-manager provenance is invalid')
  }
  canonicalRuntimePath(
    contract.toolchain.packageManagerExecutable,
    'package-manager executable'
  )
  return { bytes, contract, path }
}

async function fileSHA256(path) {
  return sha256(await readFile(path))
}

async function verifyNode(nodeBinaryArgument, contract) {
  const nodeBinary = await realpath(resolve(nodeBinaryArgument))
  const actualHash = await fileSHA256(nodeBinary)
  if (actualHash !== contract.toolchain.nodeBinarySHA256) {
    fail(`Node binary digest mismatch: ${actualHash}`)
  }
  const { stdout } = await execFile(nodeBinary, ['--version'])
  if (stdout.trim() !== `v${contract.toolchain.nodeVersion}`) {
    fail(`Node version mismatch: ${stdout.trim()}`)
  }
  return nodeBinary
}

async function verifyPackageManagerArchive(archiveArgument, contractArgument) {
  const archive = await realpath(resolve(archiveArgument))
    .catch(() => fail('package-manager archive is missing'))
  const { contract } = await loadContract(contractArgument)
  const actualHash = await fileSHA256(archive)
  if (actualHash !== contract.toolchain.packageManagerArchiveSHA256) {
    fail('package-manager archive digest mismatch')
  }
  return {
    packageManager: contract.toolchain.packageManager,
    source: contract.toolchain.packageManagerArchiveURL,
    sha256: actualHash,
  }
}

function requiredWorkspaceDependencies(manifest) {
  const requiredPeers = Object.fromEntries(
    Object.entries(manifest.peerDependencies ?? {}).filter(
      ([dependency]) => manifest.peerDependenciesMeta?.[dependency]?.optional !== true
    )
  )
  return Object.entries({
    ...manifest.dependencies,
    ...manifest.optionalDependencies,
    ...requiredPeers,
  })
    .filter(([, version]) => typeof version === 'string' && version.startsWith('workspace:'))
    .map(([dependency]) => dependency)
}

async function verifyWorkspaceClosure(runtimeArgument) {
  const runtimeRoot = await realpath(resolve(runtimeArgument))
  const modulesRoot = resolve(runtimeRoot, 'node_modules')
  const packages = new Map()

  for (const entry of await readdir(modulesRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue
    if (entry.name.startsWith('@')) {
      const scopeRoot = resolve(modulesRoot, entry.name)
      for (const scopedEntry of await readdir(scopeRoot, { withFileTypes: true })) {
        if (!scopedEntry.isDirectory()) continue
        const packageRoot = resolve(scopeRoot, scopedEntry.name)
        const manifest = JSON.parse(await readFile(resolve(packageRoot, 'package.json'), 'utf8'))
        packages.set(manifest.name, manifest)
      }
      continue
    }
    const packageRoot = resolve(modulesRoot, entry.name)
    const manifestPath = resolve(packageRoot, 'package.json')
    const manifest = JSON.parse(await readFile(manifestPath, 'utf8'))
    packages.set(manifest.name, manifest)
  }

  let workspaceDependencyEdges = 0
  for (const manifest of packages.values()) {
    for (const dependency of requiredWorkspaceDependencies(manifest)) {
      workspaceDependencyEdges += 1
      if (!packages.has(dependency)) {
        fail(`workspace dependency missing from runtime: ${manifest.name} -> ${dependency}`)
      }
    }
  }
  return { workspacePackages: packages.size, workspaceDependencyEdges }
}


async function workspaceSupplements(sourceArgument, runtimeArgument) {
  const sourceRoot = await realpath(resolve(sourceArgument))
  const runtimeRoot = await realpath(resolve(runtimeArgument))
  const workspacePackages = new Map()

  async function visitWorkspace(directory) {
    const entries = await readdir(directory, { withFileTypes: true }).catch(() => [])
    for (const entry of entries) {
      if (!entry.isDirectory() || ['.git', 'dist', 'lib', 'node_modules'].includes(entry.name)) continue
      const packageRoot = resolve(directory, entry.name)
      const manifest = await readFile(resolve(packageRoot, 'package.json'), 'utf8')
        .then(JSON.parse)
        .catch(() => undefined)
      if (manifest?.name) {
        workspacePackages.set(manifest.name, { manifest, packageRoot })
      }
      await visitWorkspace(packageRoot)
    }
  }
  for (const workspaceDirectory of ['apps', 'native', 'packages', 'vendor']) {
    await visitWorkspace(resolve(sourceRoot, workspaceDirectory))
  }

  const installed = new Set()
  const modulesRoot = resolve(runtimeRoot, 'node_modules')
  for (const entry of await readdir(modulesRoot, { withFileTypes: true })) {
    if (!entry.isDirectory() || entry.name.startsWith('.')) continue
    if (entry.name.startsWith('@')) {
      for (const scopedEntry of await readdir(resolve(modulesRoot, entry.name), { withFileTypes: true })) {
        if (scopedEntry.isDirectory()) installed.add(`${entry.name}/${scopedEntry.name}`)
      }
    } else {
      installed.add(entry.name)
    }
  }

  const supplements = new Set()
  const visited = new Set()
  const queue = [...installed].filter(name => workspacePackages.has(name))
  while (queue.length > 0) {
    const name = queue.shift()
    if (visited.has(name)) continue
    visited.add(name)
    const workspacePackage = workspacePackages.get(name)
    for (const dependency of requiredWorkspaceDependencies(workspacePackage.manifest)) {
      if (!workspacePackages.has(dependency)) {
        fail(`workspace dependency has no source package: ${name} -> ${dependency}`)
      }
      if (!installed.has(dependency)) supplements.add(dependency)
      queue.push(dependency)
    }
  }

  return [...supplements].sort().map(name => {
    const workspacePackage = workspacePackages.get(name)
    if (!(workspacePackage.manifest.files ?? []).every(path => path.startsWith('lib/'))) {
      fail(`workspace supplement has unsupported package files: ${name}`)
    }
    return {
      name,
      sourceRelativePath: relative(sourceRoot, workspacePackage.packageRoot).split(sep).join('/'),
    }
  })
}

function normalizedRepositoryURL(value) {
  return value.trim().replace(/\.git$/, '').replace(/\/$/, '')
}

async function verifySource(sourceArgument, nodeRootArgument, contractArgument) {
  const sourceRoot = await realpath(resolve(sourceArgument))
  const { contract } = await loadContract(contractArgument)
  const { stdout: remotesOutput } = await execFile('git', ['-C', sourceRoot, 'remote'])
  const remoteNames = remotesOutput.trim().split('\n').filter(Boolean)
  const remoteURLs = []
  for (const remote of remoteNames) {
    const { stdout } = await execFile('git', ['-C', sourceRoot, 'remote', 'get-url', '--all', remote])
    remoteURLs.push(...stdout.trim().split('\n').filter(Boolean))
  }
  const expectedRepository = normalizedRepositoryURL(contract.upstream.repository)
  if (!remoteURLs.some(url => normalizedRepositoryURL(url) === expectedRepository)) {
    fail(`official upstream remote is not configured: ${contract.upstream.repository}`)
  }

  await execFile('git', ['-C', sourceRoot, 'cat-file', '-e', `${contract.upstream.commit}^{commit}`])
  const { stdout: treeOutput } = await execFile(
    'git', ['-C', sourceRoot, 'rev-parse', `${contract.upstream.commit}^{tree}`]
  )
  if (treeOutput.trim() !== contract.upstream.tree) fail(`upstream tree mismatch: ${treeOutput.trim()}`)

  const { stdout: packageOutput } = await execFile(
    'git', ['-C', sourceRoot, 'show', `${contract.upstream.commit}:package.json`]
  )
  if (JSON.parse(packageOutput).version !== contract.upstream.version) {
    fail('upstream package version does not match the contract')
  }
  const { stdout: lockOutput } = await execFile(
    'git', ['-C', sourceRoot, 'show', `${contract.upstream.commit}:pnpm-lock.yaml`],
    { encoding: 'buffer', maxBuffer: 64 * 1024 * 1024 }
  )
  if (sha256(lockOutput) !== contract.build.upstreamLockSHA256) fail('upstream lock digest mismatch')

  for (const patch of contract.patches) {
    const digest = await fileSHA256(resolve(repositoryRoot, patch.path))
    if (digest !== patch.sha256) fail(`patch digest mismatch: ${patch.path}`)
  }
  await verifyNode(resolve(nodeRootArgument, 'bin/node'), contract)
  return {
    upstreamCommit: contract.upstream.commit,
    upstreamTree: contract.upstream.tree,
    nodeVersion: contract.toolchain.nodeVersion,
  }
}

function equalInventory(left, right) {
  return left.algorithm === right.algorithm
    && left.digest === right.digest
    && left.fileCount === right.fileCount
    && left.symlinkCount === right.symlinkCount
}

async function writeReceipt(runtimeArgument, contractArgument) {
  const runtimeRoot = await realpath(resolve(runtimeArgument))
  const { bytes, contract } = await loadContract(contractArgument)
  const manifest = JSON.parse(await readFile(resolve(runtimeRoot, 'manifest.json'), 'utf8')
    .catch(() => fail('runtime manifest missing')))
  verifyManifestPayload(manifest, contract, bytes)
  await verifyLaunchClosure(runtimeRoot, contract)
  await verifyWorkspaceClosure(resolve(runtimeRoot, 'node'))
  const actual = await runtimeCarrierInventory(runtimeRoot)
  if (!equalInventory(actual, contract.output)) fail(`runtime inventory mismatch: ${actual.digest}`)
  const receipt = {
    schemaVersion: 3,
    contractSHA256: sha256(bytes),
    upstreamCommit: contract.upstream.commit,
    inventory: actual,
  }
  await writeFile(resolve(runtimeRoot, receiptName), `${JSON.stringify(receipt, null, 2)}\n`)
  return receipt
}

async function verifyLaunchClosure(runtimeRoot, contract) {
  const executable = await resolveRuntimePath(runtimeRoot, contract.launch.executable, 'launcher')
  const nodeBinary = await resolveRuntimePath(runtimeRoot, contract.launch.node, 'Node executable')
  const spawnHelper = await resolveRuntimePath(
    runtimeRoot, contract.launch.nodeSpawnHelper, 'Node spawn helper'
  )
  for (const [path, label] of [
    [executable, 'launcher'],
    [nodeBinary, 'Node executable'],
    [spawnHelper, 'Node spawn helper'],
  ]) {
    const metadata = await lstat(path)
    if (!(metadata.isFile() || metadata.isSymbolicLink()) || !(metadata.mode & 0o111)) {
      fail(`${label} is not executable`)
    }
  }
  return { executable, nodeBinary, spawnHelper }
}

async function verifyRuntime(runtimeArgument, contractArgument) {
  const runtimeRoot = await realpath(resolve(runtimeArgument))
  const { bytes, contract } = await loadContract(contractArgument)
  const manifest = JSON.parse(await readFile(resolve(runtimeRoot, 'manifest.json'), 'utf8')
    .catch(() => fail('runtime manifest missing')))
  verifyManifestPayload(manifest, contract, bytes)
  const closure = await verifyLaunchClosure(runtimeRoot, contract)
  const nodeBinary = await verifyNode(closure.nodeBinary, contract)
  await verifyWorkspaceClosure(resolve(runtimeRoot, 'node'))
  const receiptPath = resolve(runtimeRoot, receiptName)
  const receipt = JSON.parse(await readFile(receiptPath, 'utf8').catch(() => fail('runtime receipt missing')))
  const actual = await runtimeCarrierInventory(runtimeRoot)
  if (!equalInventory(actual, contract.output)) fail(`runtime inventory mismatch: ${actual.digest}`)
  if (receipt.schemaVersion !== 3
    || receipt.contractSHA256 !== sha256(bytes)
    || receipt.upstreamCommit !== contract.upstream.commit
    || !equalInventory(receipt.inventory, actual)) {
    fail('runtime receipt does not match the contract and payload')
  }
  if (await fileSHA256(await resolveRuntimePath(
    runtimeRoot, contract.output.nativeProjection.path, 'native projection'
  ))
    !== contract.output.nativeProjection.sha256) {
    fail('native projection digest mismatch')
  }
  const { stdout } = await execFile(nodeBinary, [resolve(runtimeRoot, 'node/lib/bin.js'), '--version'])
  if (stdout.trim() !== contract.upstream.version) fail(`runtime version mismatch: ${stdout.trim()}`)
  return { ...actual, version: stdout.trim(), receipt: receiptName }
}

function verifyManifestPayload(manifest, contract, bytes) {
  const expected = {
    schemaVersion: contract.manifest.schemaVersion,
    upstreamVersion: contract.upstream.version,
    rabbisirVersion: contract.manifest.rabbisirVersion,
    upstreamCommit: contract.upstream.commit,
    upstreamTree: contract.upstream.tree,
    provenanceContractSHA256: sha256(bytes),
    runtimeInventorySHA256: contract.output.digest,
    executable: contract.launch.executable,
  }
  if (manifest === null || typeof manifest !== 'object' || Array.isArray(manifest)) {
    fail('manifest is not an object')
  }
  const actualKeys = Object.keys(manifest).sort()
  const expectedKeys = Object.keys(expected).sort()
  if (actualKeys.length !== expectedKeys.length
    || actualKeys.some((key, index) => key !== expectedKeys[index])) {
    fail('manifest field set mismatch')
  }
  for (const [field, value] of Object.entries(expected)) {
    if (manifest[field] !== value) fail(`manifest ${field} mismatch`)
  }
  canonicalRuntimePath(manifest.executable, 'manifest executable')
  return expected
}

async function writeManifest(runtimeArgument, contractArgument) {
  const runtimeRoot = await realpath(resolve(runtimeArgument))
  const { bytes, contract } = await loadContract(contractArgument)
  const manifest = verifyManifestPayload({
    schemaVersion: contract.manifest.schemaVersion,
    upstreamVersion: contract.upstream.version,
    rabbisirVersion: contract.manifest.rabbisirVersion,
    upstreamCommit: contract.upstream.commit,
    upstreamTree: contract.upstream.tree,
    provenanceContractSHA256: sha256(bytes),
    runtimeInventorySHA256: contract.output.digest,
    executable: contract.launch.executable,
  }, contract, bytes)
  await writeFile(resolve(runtimeRoot, 'manifest.json'), `${JSON.stringify(manifest, null, 2)}\n`)
  return manifest
}

async function verifyManifest(manifestArgument, contractArgument) {
  const { bytes, contract } = await loadContract(contractArgument)
  const manifest = JSON.parse(await readFile(resolve(manifestArgument), 'utf8'))
  return verifyManifestPayload(manifest, contract, bytes)
}

async function main() {
  const [command, ...arguments_] = process.argv.slice(2)
  let result
  if (command === 'inventory' && arguments_.length === 1) {
    result = await inventory(arguments_[0])
  } else if (command === 'inventory-runtime' && arguments_.length === 1) {
    result = await runtimeCarrierInventory(arguments_[0])
  } else if (command === 'normalize-runtime' && arguments_.length === 2) {
    result = await normalizeRuntime(arguments_[0], arguments_[1])
  } else if (command === 'verify-source' && (arguments_.length === 2 || arguments_.length === 3)) {
    result = await verifySource(arguments_[0], arguments_[1], arguments_[2])
  } else if (command === 'write-receipt' && (arguments_.length === 1 || arguments_.length === 2)) {
    result = await writeReceipt(arguments_[0], arguments_[1])
  } else if (command === 'write-manifest' && (arguments_.length === 1 || arguments_.length === 2)) {
    result = await writeManifest(arguments_[0], arguments_[1])
  } else if (command === 'verify-runtime' && (arguments_.length === 1 || arguments_.length === 2)) {
    result = await verifyRuntime(arguments_[0], arguments_[1])
  } else if (command === 'verify-workspace-closure' && arguments_.length === 1) {
    result = await verifyWorkspaceClosure(arguments_[0])
  } else if (command === 'workspace-supplements' && arguments_.length === 2) {
    result = await workspaceSupplements(arguments_[0], arguments_[1])
  } else if (command === 'verify-manifest' && (arguments_.length === 1 || arguments_.length === 2)) {
    result = await verifyManifest(arguments_[0], arguments_[1])
  } else if (command === 'verify-package-manager-archive'
    && (arguments_.length === 1 || arguments_.length === 2)) {
    result = await verifyPackageManagerArchive(arguments_[0], arguments_[1])
  } else {
    fail('usage: runtime-provenance.mjs <inventory|inventory-runtime|normalize-runtime|verify-source|write-manifest|write-receipt|verify-runtime|verify-workspace-closure|workspace-supplements|verify-manifest|verify-package-manager-archive> ...')
  }
  process.stdout.write(`${JSON.stringify(result)}\n`)
}

main().catch(error => {
  console.error(error instanceof Error ? error.message : String(error))
  process.exitCode = 1
})
