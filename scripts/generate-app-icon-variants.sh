#!/bin/sh
set -eu

script_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
brand_root="$script_root/Sources/RabbisirCore/Resources/Brand"
source_logo="$brand_root/RabbisirLogoTight.png"
work_root=$(mktemp -d "${TMPDIR:-/tmp}/rabbisir-app-icon.XXXXXX")
trap 'rm -rf "$work_root"' EXIT HUP INT TERM

command -v magick >/dev/null
command -v iconutil >/dev/null
test -f "$source_logo"

make_master() {
  name=$1
  background=$2
  foreground=$3
  master="$work_root/$name.png"
  mask="$work_root/$name-mask.png"
  mark="$work_root/$name-mark.png"

  magick "$source_logo" +profile '*' -alpha extract -filter Lanczos -resize x640 "$mask"
  magick "$mask" -threshold 0 -fill "$foreground" -colorize 100 \
    "$mask" -alpha off -compose CopyOpacity -composite "$mark"
  magick -size 1024x1024 xc:none \
    -fill "$background" -draw "roundrectangle 68,68 956,956 204,204" \
    "$mark" -gravity center -geometry +0+8 -compose Over -composite "$master"
}

make_iconset() {
  name=$1
  master="$work_root/$name.png"
  iconset="$work_root/$name.iconset"
  output="$brand_root/$name.icns"
  mkdir -p "$iconset"

  for points in 16 32 128 256 512; do
    magick "$master" -filter Lanczos -resize "${points}x${points}" \
      "$iconset/icon_${points}x${points}.png"
    pixels=$((points * 2))
    magick "$master" -filter Lanczos -resize "${pixels}x${pixels}" \
      "$iconset/icon_${points}x${points}@2x.png"
  done

  iconutil -c icns "$iconset" -o "$output"
}

make_master AppIconLight '#F2F2EF' '#000000'
make_master AppIconDark '#1C1D21' '#FFFFFF'
make_iconset AppIconLight
make_iconset AppIconDark
cp "$brand_root/AppIconLight.icns" "$brand_root/AppIcon.icns"

echo "Generated Rabbisir light and dark macOS AppIcon resources."
