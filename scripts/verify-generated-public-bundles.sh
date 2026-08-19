#!/bin/zsh
set -euo pipefail

repository_root="${0:A:h:h}"
build_root="$repository_root/.build"
bundle_count=0

verify_bundle() {
  local bundle="$1"
  "$repository_root/scripts/verify-public-resource-bundle.sh" "$bundle"
  print "verify-generated-public-bundles: verified ${bundle#$repository_root/}"
  (( bundle_count += 1 ))
}

for supported_root in \
  "$build_root/rabbisir-canonical-tests" \
  "$build_root/rabbisir-canonical-RabbisirOpen-debug" \
  "$build_root/rabbisir-canonical-RabbisirOpen-release"
do
  [[ -d "$supported_root" ]] || continue
  while IFS= read -r -d '' bundle; do
    verify_bundle "$bundle"
  done < <(
    /usr/bin/find "$supported_root" \
      -type d -name 'Rabbisir_RabbisirCore.bundle' -print0
  )
done

(( bundle_count > 0 )) || {
  print -u2 "verify-generated-public-bundles: no supported public bundle was generated"
  exit 1
}
print "verify-generated-public-bundles: $bundle_count supported public bundle(s) verified"
