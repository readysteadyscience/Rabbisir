#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  print -u2 "usage: verify-public-export.sh <public-source-root>"
  exit 64
fi

public_root="${1:A}"
fail() {
  print -u2 "verify-public-export: $*"
  exit 1
}

[[ -d "$public_root" && "$public_root" != "/" ]] || fail "invalid public source root"
expected_top_level=$'.github\n.gitignore\nAGENTS.md\nASSETS.md\nCHANGELOG.md\nCONTRIBUTING.md\nLICENSE\nLegal\nNOTICE.md\nPackage.resolved\nPackage.swift\nREADME.md\nREADME.zh.md\nRuntimeProvenance\nSources\nTests\ndocs\nscripts\nsite'
actual_top_level="$(
  /usr/bin/find "$public_root" -mindepth 1 -maxdepth 1 -exec basename {} \; \
    | LC_ALL=C /usr/bin/sort
)"
[[ "$actual_top_level" == "$expected_top_level" ]] \
  || fail "top-level allowlist differs from the reviewed public source shape"

for forbidden_path in \
  .git .rabbisir-private .build dist \
  Sources/RabbisirApp Sources/RabbisirDEVApp \
  scripts/build-and-run.sh scripts/build-and-run-dev.sh \
  scripts/build-and-run-production.sh scripts/verify-official-overlay.sh
do
  [[ ! -e "$public_root/$forbidden_path" ]] \
    || fail "private or official-only path remains: $forbidden_path"
done

if /usr/bin/find "$public_root" -type l -print | /usr/bin/grep -q .; then
  fail "symbolic links are not allowed in the public source snapshot"
fi
if /usr/bin/find "$public_root" -type f \
  \( -name '*.app' -o -name '*.dmg' -o -name '*.zip' -o -name '*.xcarchive' \
    -o -name '*.pkg' -o -name '*.p12' -o -name '*.provisionprofile' \) \
  -print | /usr/bin/grep -q .
then
  fail "a built App, distribution archive, or identity material remains"
fi

grep -q '.executable(name: "RabbisirOpen", targets: \["RabbisirOpenApp"\])' \
  "$public_root/Package.swift" || fail "the Open executable product is missing"
if grep -Eq '.executable\(name: "Rabbisir(DEV)?"' "$public_root/Package.swift"; then
  fail "an official executable product remains in the public Package"
fi
[[ -f "$public_root/Sources/RabbisirOpenApp/main.swift" ]] \
  || fail "the Open launcher is missing"
grep -q 'RabbisirApplication.runOpenSource()' \
  "$public_root/Sources/RabbisirOpenApp/main.swift" \
  || fail "the Open launcher does not bind the public identity"
grep -q 'RabbisirOpenIdentity' "$public_root/Sources/RabbisirCore/App/AppVersion.swift" \
  || fail "the Open display, bundle, and data identity is missing"
grep -q 'com.rabbisir.desktop.open' "$public_root/Sources/RabbisirCore/App/AppVersion.swift" \
  || fail "the Open bundle identifier is not fixed"
grep -q 'com.rabbisir.desktop.open' "$public_root/scripts/build-and-run-open.sh" \
  || fail "the temporary App package does not bind the Open bundle identifier"
grep -q 'YelZap' "$public_root/Sources/RabbisirCore/App/HelpSystem.swift" \
  || fail "creator attribution is missing from public Help"
grep -q 'discord.gg/gT4TUHGkQm' "$public_root/Sources/RabbisirCore/App/HelpSystem.swift" \
  || fail "the public Discord community destination is missing"

for generated in \
  Sources/RabbisirCore/Resources/VendorRuntime/bin/node \
  Sources/RabbisirCore/Resources/VendorRuntime/bin/node-spawn-helper \
  Sources/RabbisirCore/Resources/VendorRuntime/node \
  Sources/RabbisirCore/Resources/VendorRuntime/.rabbisir-runtime-provenance.json \
  Sources/RabbisirCore/Resources/VendorRuntime/LICENSE.node.txt \
  Sources/RabbisirCore/Resources/VendorRuntime/THIRD_PARTY_NOTICES.md
do
  [[ ! -e "$public_root/$generated" ]] \
    || fail "a generated runtime payload entered Git source: $generated"
done

file_list="$(/usr/bin/mktemp "${TMPDIR:-/tmp}/rabbisir-public-export-files.XXXXXX")"
trap '/bin/rm -f "$file_list"' EXIT HUP INT TERM
/usr/bin/find "$public_root" -type f \
  ! -path "$public_root/RuntimeProvenance/rabbisir-runtime.patch" -print0 >"$file_list"
private_material_pattern='BEGIN (RSA |EC |OPENSSH )?PRIVATE KE''Y|Developer ID App''lication:|Apple Team I''D|RabbisirCandidate''Fingerprint|Overlay''Receipt|/Use''rs/[^/ ]+|/private/tm''p/'
if xargs -0 rg -n "$private_material_pattern" <"$file_list"; then
  fail "private identity, candidate, or local-path material remains"
fi

framework_name='Spar''kle'
private_surface_pattern='OpenSource''Maintenance|Support''OpenSource|Rabbisir''Support|Appearance''PlaceholderMenu|Appearance''SettingsView|settings''Appearance|RabbisirSoftware''Update|Software''UpdateIndicator|checkFor''Updates|S''UFeedURL|S''UPublicEDKey'
if xargs -0 rg -n "$framework_name|$private_surface_pattern" <"$file_list"; then
  fail "official-only update or product surface remains"
fi

cd "$public_root"
scripts/verify-pages-site.sh
/usr/bin/shasum -a 256 -c "$public_root/Legal/ASSET_MANIFEST.sha256" \
  >/dev/null || fail "a public asset differs from the reviewed manifest"

print "verify-public-export: history, products, site, generated payloads, private surfaces, and assets are clean"
