#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
build_helper="$repository_root/scripts/build-fresh-public-product.sh"
bundle_verifier="$repository_root/scripts/verify-public-resource-bundle.sh"
test_helper="$repository_root/scripts/test-public-swiftpm.sh"
derived_cleanup="$repository_root/scripts/clean-derived-rabbisir-resource-bundles.sh"
generated_verifier="$repository_root/scripts/verify-generated-public-bundles.sh"

[[ -x "$build_helper" ]] || {
  print -u2 "test-public-resource-gates: fresh public build helper is missing"
  exit 1
}
[[ -x "$bundle_verifier" ]] || {
  print -u2 "test-public-resource-gates: public bundle verifier is missing"
  exit 1
}
[[ -x "$test_helper" ]] || {
  print -u2 "test-public-resource-gates: controlled public test helper is missing"
  exit 1
}
[[ -x "$derived_cleanup" ]] || {
  print -u2 "test-public-resource-gates: precise derived-resource cleanup is missing"
  exit 1
}
[[ -x "$generated_verifier" ]] || {
  print -u2 "test-public-resource-gates: generated public bundle verifier is missing"
  exit 1
}

default_debug_bundle="$repository_root/.build/arm64-apple-macosx/debug/Rabbisir_RabbisirCore.bundle"
default_release_bundle="$repository_root/.build/arm64-apple-macosx/release/Rabbisir_RabbisirCore.bundle"
unrelated_sentinel="$repository_root/.build/rabbisir-unrelated-cache/sentinel"
unrelated_fixture_root="${unrelated_sentinel:h}"
cleanup_unrelated_fixture() {
  [[ "$unrelated_fixture_root" == "$repository_root/.build/rabbisir-unrelated-cache" ]] \
    || exit 70
  [[ -e "$unrelated_fixture_root" ]] \
    && /usr/bin/find "$unrelated_fixture_root" -depth -delete
}
trap cleanup_unrelated_fixture EXIT HUP INT TERM
for stale_default_bundle in "$default_debug_bundle" "$default_release_bundle"; do
  /bin/mkdir -p "$stale_default_bundle/Icons"
  print '<svg />' >"$stale_default_bundle/Icons/folder-open.svg"
  print '<svg />' >"$stale_default_bundle/Icons/folder-close.svg"
done
/bin/mkdir -p "${unrelated_sentinel:h}"
print 'preserve unrelated derived state' >"$unrelated_sentinel"

"$test_helper" --filter PublicFlavorBoundaryTests
for stale_default_bundle in "$default_debug_bundle" "$default_release_bundle"; do
  [[ ! -e "$stale_default_bundle" ]] || {
    print -u2 "test-public-resource-gates: stale default SwiftPM resource bundle survived"
    exit 1
  }
done
[[ -f "$unrelated_sentinel" ]] || {
  print -u2 "test-public-resource-gates: unrelated SwiftPM cache was removed"
  exit 1
}
cleanup_unrelated_fixture
trap - EXIT HUP INT TERM

scratch_root="$repository_root/.build/rabbisir-canonical-RabbisirOpen-debug"
stale_bundle="$scratch_root/arm64-apple-macosx/debug/Rabbisir_RabbisirCore.bundle"
/bin/mkdir -p "$stale_bundle/Icons"
print '<svg />' >"$stale_bundle/Icons/folder-open.svg"
print '<svg />' >"$stale_bundle/Icons/folder-close.svg"

bin_path="$($build_helper RabbisirOpen debug)"
resource_bundle="$bin_path/Rabbisir_RabbisirCore.bundle"
[[ -d "$resource_bundle" ]] || {
  print -u2 "test-public-resource-gates: canonical resource bundle is missing"
  exit 1
}
[[ ! -e "$resource_bundle/Icons" ]] || {
  print -u2 "test-public-resource-gates: stale derived Icons survived the canonical build"
  exit 1
}
"$bundle_verifier" "$resource_bundle"
generated_output="$($generated_verifier)"
print "$generated_output"
if print "$generated_output" | /usr/bin/grep -E \
  'official-private|RabbisirDEV|dist/Rabbisir DEV' >/dev/null
then
  print -u2 "test-public-resource-gates: private or retired bundles entered public verification"
  exit 1
fi

temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root%/}"
fixture_root="$(/usr/bin/mktemp -d "$temporary_root/rabbisir-public-bundle.XXXXXX")"
cleanup() {
  [[ "$fixture_root" == "$temporary_root"/rabbisir-public-bundle.* ]] || exit 70
  /usr/bin/find "$fixture_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM
/bin/cp -cR "$resource_bundle" "$fixture_root/bundle"
/bin/mkdir "$fixture_root/bundle/Icons"
print '<svg />' >"$fixture_root/bundle/Icons/folder-open.svg"
if "$bundle_verifier" "$fixture_root/bundle" >/dev/null 2>&1; then
  print -u2 "test-public-resource-gates: an extra resource directory was accepted"
  exit 1
fi

print "test-public-resource-gates: canonical build removes stale resources and strict bundle allowlist rejects extras"
