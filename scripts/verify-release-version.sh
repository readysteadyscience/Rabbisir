#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
manifest="$repository_root/Sources/RabbisirCore/Resources/VendorRuntime/manifest.json"
version_source="$repository_root/Sources/RabbisirCore/App/AppVersion.swift"
previous=""
candidate=""
kind=""
previous_upstream_version=""
previous_upstream_commit=""

usage() {
  echo "usage: $0 --candidate '<product> · r<stage>.<patch>' --kind initial|maintenance|stage|upstream [--previous '<product> · r<stage>.<patch>'] [--manifest path] [--version-source path] [--previous-upstream-version version --previous-upstream-commit commit]" >&2
  exit 64
}

fail() {
  echo "verify-release-version: $*" >&2
  exit 1
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --previous) previous=${2-}; shift 2 ;;
    --candidate) candidate=${2-}; shift 2 ;;
    --kind) kind=${2-}; shift 2 ;;
    --manifest) manifest=${2-}; shift 2 ;;
    --version-source) version_source=${2-}; shift 2 ;;
    --previous-upstream-version) previous_upstream_version=${2-}; shift 2 ;;
    --previous-upstream-commit) previous_upstream_commit=${2-}; shift 2 ;;
    *) usage ;;
  esac
done

[ -n "$candidate" ] || usage
[ -n "$kind" ] || usage
[ -f "$manifest" ] || fail "missing manifest: $manifest"
[ -f "$version_source" ] || fail "missing Rabbisir version source: $version_source"

read_manifest_string() {
  key=$1
  value=$(sed -n "s/^[[:space:]]*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\\1/p" "$manifest")
  [ -n "$value" ] || fail "manifest has no $key"
  [ "$(printf '%s\n' "$value" | wc -l | tr -d ' ')" -eq 1 ] \
    || fail "manifest has ambiguous $key"
  printf '%s' "$value"
}

read_version_constant() {
  key=$1
  value=$(sed -n "s/^[[:space:]]*public static let $key[[:space:]]*=[[:space:]]*\"\([^\"]*\)\".*/\\1/p" "$version_source")
  [ -n "$value" ] || fail "Rabbisir version source has no $key"
  [ "$(printf '%s\n' "$value" | wc -l | tr -d ' ')" -eq 1 ] \
    || fail "Rabbisir version source has ambiguous $key"
  printf '%s' "$value"
}

validate_upstream_version() {
  value=$1
  label=$2
  printf '%s\n' "$value" \
    | grep -Eq '^[0-9]+(\.[0-9]+){2}(-[0-9A-Za-z]+([.-][0-9A-Za-z]+)*)?$' \
    || fail "$label is not a complete upstream release version: $value"
}

product_version=$(read_version_constant displayVersion)
apple_short_version=$(read_version_constant appleShortVersion)
apple_build_version=$(read_version_constant appleBuildVersion)
compatible_upstream_version=$(read_version_constant upstreamCompatibleVersion)
compatible_upstream_commit=$(read_version_constant upstreamCompatibleCommit)
manifest_product_version=$(read_manifest_string rabbisirVersion)
manifest_upstream_version=$(read_manifest_string upstreamVersion)
manifest_upstream_commit=$(read_manifest_string upstreamCommit)

printf '%s\n' "$product_version" | grep -Eq '^[0-9]+(\.[0-9]+){2}$' \
  || fail "Rabbisir displayVersion is not an Apple release version"
[ "$apple_short_version" = "$product_version" ] \
  || fail "Apple short version does not match Rabbisir displayVersion"
printf '%s\n' "$apple_build_version" | grep -Eq '^[1-9][0-9]*$' \
  || fail "Apple build version is not a positive integer"
validate_upstream_version "$compatible_upstream_version" "pinned upstream compatibility version"
[ "$manifest_product_version" = "$product_version" ] \
  || fail "runtime manifest rabbisirVersion does not match Rabbisir displayVersion"
[ "$manifest_upstream_version" = "$compatible_upstream_version" ] \
  || fail "runtime manifest upstreamVersion does not match the pinned compatibility version"
[ "$manifest_upstream_commit" = "$compatible_upstream_commit" ] \
  || fail "runtime manifest upstreamCommit does not match the pinned compatibility commit"
printf '%s\n' "$compatible_upstream_commit" | grep -Eq '^[0-9a-f]{40}$' \
  || fail "pinned upstream compatibility commit is not a full commit SHA"

parse_version() {
  value=$1
  label=$2
  case "$value" in
    *" · r"*) ;;
    *) fail "$label must use '<product> · r<stage>.<two-digit patch>'" ;;
  esac

  base=${value%" · r"*}
  revision=${value#*" · r"}
  [ "$base" != "$value" ] || fail "$label has no Rabbisir product version"
  printf '%s\n' "$base" | grep -Eq '^[0-9]+(\.[0-9]+){2}$' \
    || fail "$label product version is not an Apple release version: $base"
  printf '%s\n' "$revision" | grep -Eq '^[1-9][0-9]*\.[0-9][0-9]$' \
    || fail "$label revision must be r<positive stage>.<two-digit patch>"

  parsed_base=$base
  parsed_stage=${revision%.*}
  parsed_patch=${revision#*.}
  parsed_patch_value=$(( ${parsed_patch%?} * 10 + ${parsed_patch#?} ))
}

parse_version "$candidate" "candidate"
candidate_base=$parsed_base
candidate_stage=$parsed_stage
candidate_patch=$parsed_patch
candidate_patch_value=$parsed_patch_value

[ "$candidate_base" = "$product_version" ] \
  || fail "candidate product version '$candidate_base' does not match Rabbisir displayVersion '$product_version'"

case "$kind" in
  initial)
    [ -z "$previous" ] || fail "initial release must not declare a previous public version"
    [ -z "$previous_upstream_version" ] && [ -z "$previous_upstream_commit" ] \
      || fail "initial release must not declare a previous upstream baseline"
    [ "$candidate_stage" -eq 1 ] && [ "$candidate_patch" = "00" ] \
      || fail "initial release must be r1.00"
    ;;
  maintenance|stage|upstream)
    [ -n "$previous" ] || fail "$kind release requires --previous"
    parse_version "$previous" "previous"
    previous_base=$parsed_base
    previous_stage=$parsed_stage
    previous_patch=$parsed_patch
    previous_patch_value=$parsed_patch_value
    case "$kind" in
      maintenance)
        [ -z "$previous_upstream_version" ] && [ -z "$previous_upstream_commit" ] \
          || fail "maintenance release cannot declare an upstream baseline transition"
        [ "$candidate_base" = "$previous_base" ] \
          || fail "maintenance release cannot change the Rabbisir product version"
        [ "$candidate_stage" -eq "$previous_stage" ] \
          || fail "maintenance release cannot change stage"
        expected_patch=$((previous_patch_value + 1))
        [ "$expected_patch" -le 99 ] \
          || fail "r$previous_stage.$previous_patch cannot advance by maintenance; declare an authorized new stage instead"
        expected_revision=$(printf 'r%s.%02d' "$previous_stage" "$expected_patch")
        [ "$candidate_patch_value" -eq "$expected_patch" ] \
          || fail "maintenance release must advance exactly to $expected_revision"
        ;;
      stage)
        [ -z "$previous_upstream_version" ] && [ -z "$previous_upstream_commit" ] \
          || fail "stage release cannot declare an upstream baseline transition"
        [ "$candidate_base" = "$previous_base" ] \
          || fail "stage release cannot change the Rabbisir product version"
        expected_stage=$((previous_stage + 1))
        [ "$candidate_stage" -eq "$expected_stage" ] && [ "$candidate_patch" = "00" ] \
          || fail "stage release must advance exactly to r$expected_stage.00"
        ;;
      upstream)
        [ -n "$previous_upstream_version" ] && [ -n "$previous_upstream_commit" ] \
          || fail "upstream release requires the previous upstream version and commit"
        [ "$candidate_base" = "$previous_base" ] \
          || fail "upstream release cannot change the Rabbisir product version"
        validate_upstream_version "$previous_upstream_version" "previous upstream compatibility version"
        printf '%s\n' "$previous_upstream_commit" | grep -Eq '^[0-9a-f]{40}$' \
          || fail "previous upstream commit is not a full commit SHA"
        if [ "$previous_upstream_version" = "$compatible_upstream_version" ] \
          && [ "$previous_upstream_commit" = "$compatible_upstream_commit" ]
        then
          fail "upstream release requires a changed compatibility version or commit"
        fi
        [ "$candidate_stage" -eq 1 ] && [ "$candidate_patch" = "00" ] \
          || fail "upstream release must reset to r1.00"
        ;;
    esac
    ;;
  *) usage ;;
esac

echo "verify-release-version: $candidate is a valid $kind product transition; upstream compatibility is $compatible_upstream_version @ $compatible_upstream_commit"
