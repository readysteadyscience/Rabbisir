#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

fail() {
  echo "verify-public-flavor: $*" >&2
  exit 1
}

framework_name='Spar''kle'
framework_lower='spar''kle'
private_surface_pattern='OpenSource''Maintenance|Support''OpenSource|Rabbisir''Support|Appearance''PlaceholderMenu|Appearance''SettingsView|settings''Appearance|RabbisirSoftware''Update|Software''UpdateIndicator|checkFor''Updates|SU''FeedURL|SU''PublicEDKey'
public_files=$(mktemp "${TMPDIR:-/tmp}/rabbisir-public-flavor.XXXXXX")
trap 'rm -f "$public_files"' EXIT HUP INT TERM
git ls-files --cached --others --exclude-standard -z -- \
  .github Package.swift Sources Tests docs Legal scripts site README.md README.zh.md NOTICE.md \
  ':(exclude)Sources/RabbisirApp/**' \
  ':(exclude)Sources/RabbisirDEVApp/**' \
  ':(exclude)scripts/build-and-run.sh' \
  ':(exclude)scripts/build-and-run-dev.sh' \
  ':(exclude)scripts/build-and-run-production.sh' \
  ':(exclude)scripts/verify-official-overlay.sh' \
  >"$public_files"

if xargs -0 rg -n "$framework_name|$private_surface_pattern" <"$public_files"
then
  fail "private product source or dependency remains in the public tree"
fi

test ! -d Sources/RabbisirCore/Updates || fail "private update source directory remains"
test ! -f docs/UPDATES.md || fail "private update documentation remains"
test ! -f "scripts/verify-${framework_lower}-local.sh" || fail "private update verifier remains"
git check-ignore --no-index -q .rabbisir-private/OfficialOverlay \
  || fail "private overlay root is not ignored"

bin_path=$(scripts/build-fresh-public-product.sh RabbisirOpen debug)
scripts/test-public-swiftpm.sh --filter PublicFlavorBoundaryTests
binary="$bin_path/RabbisirOpen"
resource_bundle="$bin_path/Rabbisir_RabbisirCore.bundle"
test -x "$binary" || fail "Rabbisir Open binary is missing"
test -d "$resource_bundle" || fail "public resource bundle is missing"

if /usr/bin/strings "$binary" | rg -n "$framework_name|$private_surface_pattern"
then
  fail "private product text remains in the public binary"
fi
if otool -L "$binary" | rg -n "$framework_name"
then
  fail "a private update framework remains linked in the public binary"
fi
scripts/verify-public-resource-bundle.sh "$resource_bundle"

echo "verify-public-flavor: Rabbisir Open source, binary, menu surface, and resources are isolated; this shell gate does not claim a live Accessibility inspection"
