#!/bin/zsh
set -euo pipefail

version_source=""
runtime_manifest=""
while (( $# > 0 )); do
  case "$1" in
    --version-source) shift; version_source="${1:-}" ;;
    --manifest) shift; runtime_manifest="${1:-}" ;;
    *)
      print -u2 "usage: $0 --version-source <AppVersion.swift> --manifest <runtime-manifest.json>"
      exit 64
      ;;
  esac
  shift
done
[[ -f "$version_source" && -f "$runtime_manifest" ]] || {
  print -u2 "verify-release-version: version source and runtime manifest are required"
  exit 66
}

/usr/bin/env node - "$version_source" "$runtime_manifest" <<'NODE'
const fs = require("node:fs");
const [sourcePath, manifestPath] = process.argv.slice(2);
const fail = (message) => { console.error(`verify-release-version: ${message}`); process.exit(1); };
const source = fs.readFileSync(sourcePath, "utf8");
let manifest;
try { manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8")); }
catch { fail("runtime manifest is unreadable"); }
const field = (name) => new RegExp(`${name}\\s*=\\s*"([^"]+)"`).exec(source)?.[1];
const semver = /^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$/;
const shortVersion = field("appleShortVersion");
const displayVersion = field("displayVersion");
const fallbackBuild = field("appleBuildVersion");
const upstreamVersion = field("upstreamCompatibleVersion");
const upstreamCommit = field("upstreamCompatibleCommit");
if (!semver.test(shortVersion || "") || displayVersion !== `v${shortVersion}`) {
  fail("Rabbisir short/display version projection is not canonical three-component SemVer");
}
if (!/^[1-9]\d*$/.test(fallbackBuild || "")) {
  fail("DEV fallback build metadata is invalid");
}
if (!/^[A-Za-z0-9][A-Za-z0-9._+-]*$/.test(upstreamVersion || "") ||
    !/^[0-9a-f]{40}$/.test(upstreamCommit || "")) {
  fail("upstream compatibility metadata is invalid");
}
if (manifest.rabbisirVersion !== shortVersion || manifest.upstreamVersion !== upstreamVersion ||
    manifest.upstreamCommit !== upstreamCommit) {
  fail("runtime compatibility manifest drifts from AppVersion");
}
console.log(`verify-release-version: Rabbisir ${displayVersion} source projection and independent upstream compatibility metadata verified; DEV fallback build is not a formal allocation`);
NODE
