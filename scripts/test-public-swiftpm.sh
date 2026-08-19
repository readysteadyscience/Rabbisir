#!/bin/zsh
set -euo pipefail

package_root="${0:A:h:h}"
scratch_root="$package_root/.build/rabbisir-canonical-tests"
test_arguments=()

while (( $# > 0 )); do
  case "$1" in
    --filter)
      (( $# >= 2 )) || {
        print -u2 "test-public-swiftpm: --filter requires a value"
        exit 64
      }
      test_arguments+=(--filter "$2")
      shift
      ;;
    *)
      print -u2 "test-public-swiftpm: unsupported argument: $1"
      exit 64
      ;;
  esac
  shift
done

[[ "$package_root" != "/" && "$scratch_root" == "$package_root/.build/rabbisir-canonical-tests" ]] \
  || {
    print -u2 "test-public-swiftpm: unsafe scratch root"
    exit 70
  }

cd "$package_root"
scripts/clean-derived-rabbisir-resource-bundles.sh
if [[ -e "$scratch_root" ]]; then
  /usr/bin/find "$scratch_root" -depth -delete
fi
/bin/mkdir -p "$scratch_root"

scripts/verify-staged-runtime.sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/swift test \
  --scratch-path "$scratch_root" \
  "${test_arguments[@]}"

bundle_count=0
while IFS= read -r -d '' bundle; do
  scripts/verify-public-resource-bundle.sh "$bundle"
  (( bundle_count += 1 ))
done < <(
  /usr/bin/find "$scratch_root" \
    -type d -name 'Rabbisir_RabbisirCore.bundle' -print0
)
(( bundle_count > 0 )) || {
  print -u2 "test-public-swiftpm: no Rabbisir resource bundle was generated"
  exit 1
}

print "test-public-swiftpm: tests and $bundle_count generated resource bundle(s) verified"
