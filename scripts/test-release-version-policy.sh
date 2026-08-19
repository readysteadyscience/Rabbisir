#!/bin/sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
validator="$script_root/verify-release-version.sh"
manifest="$script_root/../Sources/RabbisirCore/Resources/VendorRuntime/manifest.json"
version_source="$script_root/../Sources/RabbisirCore/App/AppVersion.swift"
product_version=0.1.0
current_upstream=0.1.0-rc.5
current_commit=47f943859bef60e4160492346772ded9b24f765a

grep -Fq 'public static let displayVersion = "0.1.0"' "$version_source"
grep -Fq 'public static let appleShortVersion = "0.1.0"' "$version_source"
grep -Fq 'public static let appleBuildVersion = "1"' "$version_source"
grep -Fq 'public static let upstreamCompatibleVersion = "0.1.0-rc.5"' "$version_source"
grep -Fq "public static let upstreamCompatibleCommit = \"$current_commit\"" "$version_source"

"$validator" --manifest "$manifest" --version-source "$version_source" \
  --candidate "$product_version · r1.00" --kind initial
"$validator" --manifest "$manifest" --version-source "$version_source" \
  --previous "$product_version · r1.01" --candidate "$product_version · r1.02" --kind maintenance
"$validator" --manifest "$manifest" --version-source "$version_source" \
  --previous "$product_version · r1.99" --candidate "$product_version · r2.00" --kind stage
previous_upstream="${current_upstream}.previous"
previous_commit=0000000000000000000000000000000000000000
"$validator" --manifest "$manifest" --version-source "$version_source" \
  --previous "$product_version · r9.99" --candidate "$product_version · r1.00" --kind upstream \
  --previous-upstream-version "$previous_upstream" --previous-upstream-commit "$previous_commit"

if "$validator" --manifest "$manifest" --version-source "$version_source" \
  --previous "9.9.9 · r9.99" --candidate "$product_version · r1.00" --kind upstream \
  --previous-upstream-version "$previous_upstream" \
  --previous-upstream-commit "$previous_commit" >/dev/null 2>&1
then
  echo "test-release-version-policy: upstream transition changed the Rabbisir product version" >&2
  exit 1
fi

if "$validator" --manifest "$manifest" --version-source "$version_source" \
  --previous "$product_version · r9.99" --candidate "$product_version · r1.00" --kind upstream \
  --previous-upstream-version not-a-version \
  --previous-upstream-commit "$previous_commit" >/dev/null 2>&1
then
  echo "test-release-version-policy: upstream transition accepted an invalid previous version" >&2
  exit 1
fi

if "$validator" --manifest "$manifest" --version-source "$version_source" \
  --previous "$product_version · r1.99" --candidate "$product_version · r2.00" \
  --kind maintenance >/dev/null 2>&1
then
  echo "test-release-version-policy: maintenance transition incorrectly accepted a stage jump" >&2
  exit 1
fi

if "$validator" --manifest "$manifest" --version-source "$version_source" \
  --candidate "0.1.1 · r1.00" --kind initial >/dev/null 2>&1
then
  echo "test-release-version-policy: candidate accepted a tampered Rabbisir product version" >&2
  exit 1
fi

fixture_root=$(mktemp -d "${TMPDIR:-/tmp}/rabbisir-version-policy.XXXXXX")
cleanup() {
  case "$fixture_root" in
    "${TMPDIR:-/tmp}"/rabbisir-version-policy.*) find "$fixture_root" -depth -delete ;;
    *) echo "test-release-version-policy: unsafe fixture cleanup path" >&2; exit 70 ;;
  esac
}
trap cleanup EXIT HUP INT TERM

tampered_version_source="$fixture_root/AppVersion.swift"
sed 's/appleShortVersion = "0.1.0"/appleShortVersion = "0.1.1"/' \
  "$version_source" >"$tampered_version_source"
if "$validator" --manifest "$manifest" --version-source "$tampered_version_source" \
  --candidate "$product_version · r1.00" --kind initial >/dev/null 2>&1
then
  echo "test-release-version-policy: candidate accepted a tampered Apple short version" >&2
  exit 1
fi

tampered_manifest="$fixture_root/manifest.json"
sed 's/upstreamCompatibleVersion = "0.1.0-rc.5"/upstreamCompatibleVersion = "not-a-version"/' \
  "$version_source" >"$tampered_version_source"
sed 's/"upstreamVersion": "0.1.0-rc.5"/"upstreamVersion": "not-a-version"/' \
  "$manifest" >"$tampered_manifest"
if "$validator" --manifest "$tampered_manifest" --version-source "$tampered_version_source" \
  --candidate "$product_version · r1.00" --kind initial >/dev/null 2>&1
then
  echo "test-release-version-policy: candidate accepted an invalid current upstream version" >&2
  exit 1
fi

sed 's/"upstreamVersion": "0.1.0-rc.5"/"upstreamVersion": "0.1.0-rc.6"/' \
  "$manifest" >"$tampered_manifest"
if "$validator" --manifest "$tampered_manifest" --version-source "$version_source" \
  --candidate "$product_version · r1.00" --kind initial >/dev/null 2>&1
then
  echo "test-release-version-policy: candidate accepted a tampered upstream manifest version" >&2
  exit 1
fi

sed "s/\"upstreamCommit\": \"$current_commit\"/\"upstreamCommit\": \"$previous_commit\"/" \
  "$manifest" >"$tampered_manifest"
if "$validator" --manifest "$tampered_manifest" --version-source "$version_source" \
  --candidate "$product_version · r1.00" --kind initial >/dev/null 2>&1
then
  echo "test-release-version-policy: candidate accepted a tampered upstream manifest commit" >&2
  exit 1
fi

echo "test-release-version-policy: product release and independent upstream compatibility policy verified"
