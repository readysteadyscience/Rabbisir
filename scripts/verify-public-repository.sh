#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

fail() {
  echo "verify-public-repository: $*" >&2
  exit 1
}

for required in \
  Package.swift \
  LICENSE \
  AGENTS.md \
  docs/AGENTS.public.md \
  CHANGELOG.md \
  CONTRIBUTING.md \
  docs/DEVELOPMENT.md \
  docs/CODE_REVIEW.md \
  docs/RELEASING.md \
  docs/WEBSITE.md \
  docs/VERSIONING.md \
  .github/pull_request_template.md \
  .github/workflows/ci.yml \
  .github/workflows/pages.yml \
  scripts/build-and-run-open.sh \
  scripts/prepare-public-source.sh \
  scripts/public-source-fingerprint.mjs \
  scripts/verify-public-candidate.sh \
  scripts/verify-public-dependency-lock.mjs \
  scripts/verify-public-export.sh \
  scripts/verify-pages-site.sh \
  scripts/rebuild-vendor-runtime.sh \
  scripts/build-fresh-public-product.sh \
  scripts/clean-derived-rabbisir-resource-bundles.sh \
  scripts/test-public-swiftpm.sh \
  scripts/verify-public-resource-bundle.sh \
  scripts/verify-generated-public-bundles.sh \
  scripts/test-public-resource-gates.sh \
  scripts/test-package-manager-provenance.sh \
  scripts/runtime-provenance.mjs \
  scripts/test-runtime-provenance.sh \
  scripts/test-runtime-launch-closure.sh \
  scripts/test-runtime-manifest-gates.sh \
  scripts/verify-staged-runtime.sh \
  scripts/verify-public-flavor.sh \
  scripts/verify-code-review-governance.sh \
  scripts/verify-release-version.sh \
  scripts/test-release-version-policy.sh \
  Legal/LICENSE.upstream.txt \
  Legal/BRAND_ASSETS.md \
  Legal/ASSET_MANIFEST.sha256 \
  Legal/SITE_ASSET_MANIFEST.sha256 \
  Legal/THIRD_PARTY_NOTICES.upstream.md \
  Legal/THIRD_PARTY_NOTICES.testing.md \
  Legal/UPSTREAM.md \
  RuntimeProvenance/contract.json \
  RuntimeProvenance/README.md \
  RuntimeProvenance/rabbisir-runtime.patch \
  RuntimeProvenance/deterministic-css-modules.patch \
  site/.nojekyll \
  site/rabbisir-site/index.html \
  site/rabbisir-site/site.js \
  site/rabbisir-site/styles.css \
  site/assets/rabbisir/discord-symbol-blurple.svg \
  site/assets/rabbisir/rabbisir-mark-dark.png \
  site/assets/rabbisir/x-logo-white-v1.svg \
  site/assets/rabbisir/yelzap-avatar.png \
  site/assets/rabbisir/yelzap-wechat-qr-v1.png \
  site/DOWNLOADS.md \
  site/UPSTREAM.md \
  site/LICENSE \
  Sources/RabbisirCore/Resources/VendorRuntime/manifest.json \
  Sources/RabbisirCore/Resources/VendorRuntime/provenance-contract.json
do
  test -f "$required" || fail "missing required file: $required"
done

scripts/verify-documentation-links.sh
scripts/verify-pages-site.sh
scripts/verify-code-review-governance.sh
scripts/test-release-version-policy.sh
scripts/test-runtime-provenance.sh
scripts/test-runtime-launch-closure.sh
scripts/test-runtime-manifest-gates.sh
scripts/test-package-manager-provenance.sh
scripts/verify-public-dependency-lock.mjs

grep -q '^MIT License$' LICENSE || fail "root source license is not the approved MIT license"
grep -q 'Copyright (c) 2026 YelZap' LICENSE \
  || fail "root source license lacks the Rabbisir copyright notice"
grep -q 'does not grant rights' \
  Legal/BRAND_ASSETS.md \
  || fail "brand and trademark exclusion is missing"
grep -q 'explicitly authorized those unchanged bytes for public redistribution' \
  Legal/BRAND_ASSETS.md \
  || fail "creator avatar redistribution authorization is missing"
grep -q 'DeepSeek brand graphics, logos, organization avatars, and derivatives are not packaged' \
  Legal/BRAND_ASSETS.md \
  || fail "DeepSeek brand-asset exclusion is missing"

shasum -a 256 -c Legal/ASSET_MANIFEST.sha256 >/dev/null \
  || fail "a public static asset differs from its reviewed manifest"
manifest_asset_list=$(sed -E 's/^[0-9a-f]{64}  //' Legal/ASSET_MANIFEST.sha256 | sort)
public_asset_list=$(find Sources/RabbisirCore/Resources/Brand -type f | sort)
[ "$manifest_asset_list" = "$public_asset_list" ] \
  || fail "a public static asset is missing from the reviewed asset manifest"
shasum -a 256 -c Legal/SITE_ASSET_MANIFEST.sha256 >/dev/null \
  || fail "the public website asset differs from its reviewed manifest"
for unlicensed_asset in \
  Sources/RabbisirCore/Resources/Brand/DeepSeekLogo.png \
  Sources/RabbisirCore/Resources/Brand/DiscordSymbolBlack.png \
  Sources/RabbisirCore/Resources/Icons
do
  test ! -e "$unlicensed_asset" \
    || fail "unlicensed or superseded static asset remains: $unlicensed_asset"
done
grep -q \
  '^4d30bc3ccdc9b646a4ee4e3a230f00b855b07b04f2011dec81290a3fe27d395d  Sources/RabbisirCore/Resources/Brand/YelZapAvatar.png$' \
  Legal/ASSET_MANIFEST.sha256 \
  || fail "creator avatar is not pinned to the authorized original bytes"

if rg -n 'rpcError\.message|streamError\.message|Text\(failure\.message\)|String\(describing: error\)' \
  Sources/RabbisirCore/Conversation/NativeConversationStore.swift \
  Sources/RabbisirCore/Settings/NativeSettingsStore.swift \
  Sources/RabbisirCore/Settings/NativeSettingsView.swift
then
  fail "a user-visible upstream error path still exposes raw diagnostic text"
fi

grep -q 'scripts/verify-staged-runtime.sh' scripts/build-fresh-public-product.sh \
  || fail "canonical public build does not fail closed on staged runtime provenance"
grep -q 'scripts/verify-public-resource-bundle.sh' scripts/build-fresh-public-product.sh \
  || fail "canonical public build does not verify its actual resource bundle"
grep -q 'scripts/clean-derived-rabbisir-resource-bundles.sh' scripts/build-fresh-public-product.sh \
  || fail "canonical public build does not remove stale default SwiftPM resource bundles"
grep -q -- '--scratch-path' scripts/test-public-swiftpm.sh \
  || fail "canonical public tests do not use a controlled SwiftPM scratch path"
grep -q 'scripts/clean-derived-rabbisir-resource-bundles.sh' scripts/test-public-swiftpm.sh \
  || fail "canonical public tests do not remove stale default SwiftPM resource bundles"
grep -q 'scripts/verify-public-resource-bundle.sh' scripts/test-public-swiftpm.sh \
  || fail "canonical public tests do not verify generated resource bundles"
if rg -n 'DEVELOPER_DIR=.*swift (build|test)|run:[[:space:]]+swift (build|test)' \
  AGENTS.md README.md README.zh.md CONTRIBUTING.md docs .github \
  scripts/verify-public-flavor.sh
then
  fail "a supported public workflow still invokes an uncontrolled SwiftPM build or test"
fi
grep -q 'scripts/verify-public-repository.sh' .github/workflows/ci.yml \
  || fail "CI does not verify the public source boundary"
grep -q 'scripts/verify-pages-site.sh' .github/workflows/ci.yml \
  || fail "CI does not verify the public Pages capsule"
if rg -n 'build-fresh-public-product|test-public-swiftpm|build-and-run-open' \
  .github/workflows/ci.yml
then
  fail "clean-checkout CI claims an App build without a separately staged runtime"
fi
grep -q 'Public builds use only the `RabbisirOpen` product' docs/AGENTS.public.md \
  || fail "public AGENTS rules do not bind the Open product"
grep -q 'RabbisirApplication.runOpenSource()' Sources/RabbisirOpenApp/main.swift \
  || fail "the public launcher does not bind the Open identity"
grep -q 'Without current step-specific authorization' docs/DEVELOPMENT.md \
  || fail "development workflow lacks the current step-specific authorization gate"
grep -q 'Evidence transfer between stages may be automatic' docs/DELIVERY_WORKFLOW.md \
  || fail "delivery workflow lacks the automatic evidence-transfer boundary"
grep -q 'explicit authorization for the exact action' docs/DELIVERY_WORKFLOW.md \
  || fail "delivery workflow lacks the exact-action authorization boundary"
grep -q 'explicit authorization for that exact action' docs/AGENTS.public.md \
  || fail "public AGENTS rules do not separate validation from external authority"
grep -q 'does not authorize a' CONTRIBUTING.md \
  || fail "CONTRIBUTING.md does not state the contributor release boundary"

for forbidden_root in \
  apps packages vendor website examples python native node_modules .agents
do
  test ! -e "$forbidden_root" || fail "forbidden repository root: $forbidden_root"
done

candidate_list=$(mktemp "${TMPDIR:-/tmp}/rabbisir-public-files.XXXXXX")
legacy_candidate_list=$(mktemp "${TMPDIR:-/tmp}/rabbisir-public-identity-files.XXXXXX")
private_candidate_list=$(mktemp "${TMPDIR:-/tmp}/rabbisir-public-private-files.XXXXXX")
public_export=$(mktemp -d "${TMPDIR:-/tmp}/rabbisir-public-source.XXXXXX")
find "$public_export" -depth -delete
cleanup_public_gate() {
  rm -f "$candidate_list" "$legacy_candidate_list" "$private_candidate_list"
  if test -e "$public_export"; then
    find "$public_export" -depth -delete
  fi
}
trap cleanup_public_gate EXIT HUP INT TERM
git ls-files --cached --others --exclude-standard -z -- \
  . \
  ':(exclude).rabbisir-private/**' \
  ':(exclude)Sources/RabbisirApp/**' \
  ':(exclude)Sources/RabbisirDEVApp/**' \
  ':(exclude)scripts/build-and-run.sh' \
  ':(exclude)scripts/build-and-run-dev.sh' \
  ':(exclude)scripts/build-and-run-production.sh' \
  ':(exclude)scripts/verify-official-overlay.sh' \
  ':(exclude)Sources/RabbisirCore/Resources/Brand/**' \
  ':(exclude)Sources/RabbisirCore/Resources/Icons/**' \
  >"$candidate_list"
git ls-files --cached --others --exclude-standard -z -- \
  . \
  ':(exclude).rabbisir-private/**' \
  ':(exclude)Sources/RabbisirApp/**' \
  ':(exclude)Sources/RabbisirDEVApp/**' \
  ':(exclude)scripts/build-and-run.sh' \
  ':(exclude)scripts/build-and-run-dev.sh' \
  ':(exclude)scripts/build-and-run-production.sh' \
  ':(exclude)scripts/verify-official-overlay.sh' \
  ':(exclude)Sources/RabbisirCore/Resources/Brand/**' \
  ':(exclude)Sources/RabbisirCore/Resources/Icons/**' \
  ':(exclude)RuntimeProvenance/rabbisir-runtime.patch' \
  >"$legacy_candidate_list"
git ls-files --cached --others --exclude-standard -z -- \
  . \
  ':(exclude).rabbisir-private/**' \
  ':(exclude)Sources/RabbisirApp/**' \
  ':(exclude)Sources/RabbisirDEVApp/**' \
  ':(exclude)scripts/build-and-run.sh' \
  ':(exclude)scripts/build-and-run-dev.sh' \
  ':(exclude)scripts/build-and-run-production.sh' \
  ':(exclude)scripts/verify-official-overlay.sh' \
  ':(exclude)Sources/RabbisirCore/Resources/Brand/**' \
  ':(exclude)Sources/RabbisirCore/Resources/Icons/**' \
  ':(exclude)RuntimeProvenance/rabbisir-runtime.patch' \
  >"$private_candidate_list"

legacy_pattern='DeepSeek Harness E''S|DSH''ES|dsh-e''s|Ra''bix|Ro''box'
if xargs -0 rg -n -i "$legacy_pattern" <"$legacy_candidate_list"
then
  fail "legacy product identity remains"
fi
expected_legacy_storage_key='+  return `dsh-''es:word:${(hash >>> 0).toString(36)}`'
actual_legacy_storage_key=$(rg -i "$legacy_pattern" RuntimeProvenance/rabbisir-runtime.patch || true)
[ "$actual_legacy_storage_key" = "$expected_legacy_storage_key" ] \
  || fail "runtime patch contains an unexpected legacy identity or lost the compatibility storage key"

private_pattern='/Use''rs/[^/]+|/private/tm''p|BEGIN (RSA |EC |OPENSSH )?PRIVATE KE''Y|DEEPSEEK_API''_KEY[[:space:]]*='
if xargs -0 rg -n "$private_pattern" <"$private_candidate_list"
then
  fail "local path or credential material remains"
fi
expected_private_fixtures=$(printf '%s\n%s' \
  "+    const absolute = '/Use""rs/example/private/report.md'" \
  "+    expect((await screen.findByRole('alert')).textContent).not.toContain('/Use""rs/')")
actual_private_fixtures=$(rg "$private_pattern" RuntimeProvenance/rabbisir-runtime.patch || true)
[ "$actual_private_fixtures" = "$expected_private_fixtures" ] \
  || fail "runtime patch contains an unexpected private path or lost its sanitization fixtures"

for generated in \
  Sources/RabbisirCore/Resources/VendorRuntime/bin/node \
  Sources/RabbisirCore/Resources/VendorRuntime/bin/node-spawn-helper \
  Sources/RabbisirCore/Resources/VendorRuntime/node \
  Sources/RabbisirCore/Resources/VendorRuntime/.rabbisir-runtime-provenance.json \
  Sources/RabbisirCore/Resources/VendorRuntime/LICENSE.node.txt \
  Sources/RabbisirCore/Resources/VendorRuntime/THIRD_PARTY_NOTICES.md
do
  git check-ignore -q "$generated" || fail "generated runtime path is not ignored: $generated"
done

git check-ignore --no-index -q .rabbisir-private/OfficialOverlay \
  || fail "private product overlay is not ignored"

scripts/prepare-public-source.sh "$public_export" >/dev/null
test ! -e "$public_export/.git" \
  || fail "the public source export inherited private Git history"

echo "verify-public-repository: public source boundary is clean"
