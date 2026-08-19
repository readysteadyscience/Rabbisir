#!/bin/zsh
set -euo pipefail

package_root="${0:A:h:h}"
build_root="$package_root/.build"
[[ "$package_root" != "/" && "$build_root" == "$package_root/.build" ]] || {
  print -u2 "clean-derived-rabbisir-resource-bundles: unsafe build root"
  exit 70
}

[[ -d "$build_root" ]] || exit 0
while IFS= read -r -d '' triple_root; do
  [[ "$triple_root" == "$build_root/"*-apple-macosx ]] || {
    print -u2 "clean-derived-rabbisir-resource-bundles: unexpected SwiftPM triple root"
    exit 70
  }
  for configuration in debug release; do
    bundle="$triple_root/$configuration/Rabbisir_RabbisirCore.bundle"
    [[ -e "$bundle" ]] || continue
    [[ "$bundle" == "$build_root/"*-apple-macosx/$configuration/Rabbisir_RabbisirCore.bundle ]] \
      || {
        print -u2 "clean-derived-rabbisir-resource-bundles: unsafe resource bundle path"
        exit 70
      }
    /usr/bin/find "$bundle" -depth -delete
    print -u2 "clean-derived-rabbisir-resource-bundles: removed $bundle"
  done
done < <(
  /usr/bin/find "$build_root" \
    -mindepth 1 -maxdepth 1 -type d -name '*-apple-macosx' -print0
)
