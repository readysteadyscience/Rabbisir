#!/bin/zsh
set -euo pipefail

script_root="${0:A:h}"
repository_root="${script_root:h}"
validator="$script_root/verify-release-version.sh"
source="$repository_root/Sources/RabbisirCore/App/AppVersion.swift"
manifest="$repository_root/Sources/RabbisirCore/Resources/VendorRuntime/manifest.json"
work_root="$(/usr/bin/mktemp -d "${TMPDIR:-/tmp}/rabbisir-version-policy.XXXXXX")"
cleanup() {
  [[ "$work_root" == "${TMPDIR:-/tmp}"/rabbisir-version-policy.* ]] || exit 70
  /usr/bin/find "$work_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM

must_reject() {
  local label="$1"
  shift
  if "$@" >/dev/null 2>&1; then
    print -u2 "test-release-version-policy: accepted $label"
    exit 1
  fi
}

"$validator" --version-source "$source" --manifest "$manifest" >/dev/null
read_source_field() {
  /usr/bin/env node - "$source" "$1" <<'NODE'
const fs = require("node:fs");
const [sourcePath, name] = process.argv.slice(2);
const match = new RegExp(`${name}\\s*=\\s*"([^"]+)"`).exec(fs.readFileSync(sourcePath, "utf8"));
if (!match) process.exit(1);
process.stdout.write(match[1]);
NODE
}
short_version="$(read_source_field appleShortVersion)"
display_version="$(read_source_field displayVersion)"
fallback_build="$(read_source_field appleBuildVersion)"
upstream_version="$(read_source_field upstreamCompatibleVersion)"

/usr/bin/sed "s/appleShortVersion = \"$short_version\"/appleShortVersion = \"0$short_version\"/" \
  "$source" >"$work_root/leading-zero.swift"
must_reject "a leading-zero Rabbisir version" "$validator" \
  --version-source "$work_root/leading-zero.swift" --manifest "$manifest"
/usr/bin/sed "s/displayVersion = \"$display_version\"/displayVersion = \"$short_version\"/" \
  "$source" >"$work_root/noncanonical-display.swift"
must_reject "a display version without v" "$validator" \
  --version-source "$work_root/noncanonical-display.swift" --manifest "$manifest"
/usr/bin/sed "s/appleBuildVersion = \"$fallback_build\"/appleBuildVersion = \"0\"/" \
  "$source" >"$work_root/invalid-fallback.swift"
must_reject "an invalid DEV fallback build" "$validator" \
  --version-source "$work_root/invalid-fallback.swift" --manifest "$manifest"
/bin/cp "$manifest" "$work_root/product-drift.json"
/usr/bin/plutil -replace rabbisirVersion -string 26.15.1234 "$work_root/product-drift.json"
must_reject "runtime product-version drift" "$validator" \
  --version-source "$source" --manifest "$work_root/product-drift.json"
/bin/cp "$manifest" "$work_root/upstream-drift.json"
/usr/bin/plutil -replace upstreamVersion -string "$upstream_version-drift" \
  "$work_root/upstream-drift.json"
must_reject "upstream compatibility drift" "$validator" \
  --version-source "$source" --manifest "$work_root/upstream-drift.json"

print "test-release-version-policy: Rabbisir-owned SemVer projection and independent upstream compatibility policy verified"
