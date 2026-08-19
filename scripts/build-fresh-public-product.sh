#!/bin/zsh
set -euo pipefail

if (( $# < 1 || $# > 2 )); then
  print -u2 "usage: build-fresh-public-product.sh RabbisirOpen [debug|release]"
  exit 64
fi

product_name="$1"
configuration="${2:-debug}"
case "$product_name" in
  RabbisirOpen) ;;
  *) print -u2 "build-fresh-public-product: unsupported product"; exit 64 ;;
esac
case "$configuration" in
  debug|release) ;;
  *) print -u2 "build-fresh-public-product: unsupported configuration"; exit 64 ;;
esac

package_root="${0:A:h:h}"
scratch_root="$package_root/.build/rabbisir-canonical-$product_name-$configuration"
expected_prefix="$package_root/.build/rabbisir-canonical-"
[[ "$package_root" != "/" && "$scratch_root" == "$expected_prefix"* ]] || {
  print -u2 "build-fresh-public-product: unsafe derived build root"
  exit 70
}

if [[ -e "$scratch_root" ]]; then
  /usr/bin/find "$scratch_root" -depth -delete
fi
/bin/mkdir -p "$scratch_root"

cd "$package_root"
scripts/clean-derived-rabbisir-resource-bundles.sh >&2
scripts/verify-staged-runtime.sh >&2
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/swift build \
  --scratch-path "$scratch_root" \
  --configuration "$configuration" \
  --product "$product_name" >&2
bin_path="$(
  DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer /usr/bin/swift build \
    --scratch-path "$scratch_root" \
    --show-bin-path \
    --configuration "$configuration"
)"
scripts/verify-public-resource-bundle.sh \
  "$bin_path/Rabbisir_RabbisirCore.bundle" >&2
print "$bin_path"
