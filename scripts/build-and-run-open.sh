#!/bin/zsh
set -euo pipefail

mode="run"
if (( $# > 1 )); then
  print -u2 "usage: build-and-run-open.sh [--verify-first-run]"
  exit 64
fi
if (( $# == 1 )); then
  [[ "$1" == "--verify-first-run" ]] \
    || { print -u2 "usage: build-and-run-open.sh [--verify-first-run]"; exit 64; }
  mode="verify-first-run"
fi

repository_root="${0:A:h:h}"
temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root:A}"
work_root="$(/usr/bin/mktemp -d "$temporary_root/rabbisir-open-acceptance.XXXXXX")"
app_name="Rabbisir Open"
app_path="$work_root/$app_name.app"
executable_path="$app_path/Contents/MacOS/$app_name"
isolated_home="$work_root/user-home"
readiness_file="$work_root/rabbisir-open-ready.status"
app_pid=""

cleanup() {
  if [[ -n "$app_pid" ]] && /bin/kill -0 "$app_pid" 2>/dev/null; then
    /bin/kill -TERM "$app_pid" 2>/dev/null || true
    for _ in {1..50}; do
      /bin/kill -0 "$app_pid" 2>/dev/null || break
      /bin/sleep 0.1
    done
  fi
  [[ "$work_root" == "$temporary_root"/rabbisir-open-acceptance.* ]] || exit 70
  [[ ! -e "$work_root" ]] || /usr/bin/find "$work_root" -depth -delete
}
trap cleanup EXIT HUP INT TERM

bin_path="$("$repository_root/scripts/build-fresh-public-product.sh" RabbisirOpen debug)"
resource_bundle="$bin_path/Rabbisir_RabbisirCore.bundle"
contents="$app_path/Contents"
/bin/mkdir -p "$contents/MacOS" "$contents/Resources" "$isolated_home/tmp"
/usr/bin/ditto "$bin_path/RabbisirOpen" "$executable_path"
/usr/bin/ditto "$resource_bundle" "$contents/Resources/Rabbisir_RabbisirCore.bundle"
/usr/bin/ditto "$resource_bundle/Brand/AppIcon.icns" "$contents/Resources/AppIcon.icns"

info_plist="$contents/Info.plist"
/usr/bin/plutil -create xml1 "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundlePackageType string APPL' "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleExecutable string $app_name" "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIdentifier string com.rabbisir.desktop.open' "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleName string $app_name" "$info_plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleDisplayName string $app_name" "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleIconFile string AppIcon.icns' "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 0.1.0' "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :CFBundleVersion string 1' "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :LSMinimumSystemVersion string 14.0' "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :NSHighResolutionCapable bool true' "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :NSPrincipalClass string NSApplication' "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :RabbisirApplicationSupportComponent string Rabbisir Open' "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :RabbisirProductFlavor string public-open-acceptance' "$info_plist"
/usr/libexec/PlistBuddy -c 'Add :RabbisirUpdatePolicy string none' "$info_plist"

[[ "$(/usr/bin/plutil -extract CFBundleIdentifier raw -o - "$info_plist")" \
  == "com.rabbisir.desktop.open" ]] || exit 65
[[ "$(/usr/bin/plutil -extract RabbisirProductFlavor raw -o - "$info_plist")" \
  == "public-open-acceptance" ]] || exit 65
for forbidden_key in \
  S''UFeedURL S''UPublicEDKey S''URequireSignedFeed RabbisirCandidate''Fingerprint
do
  ! /usr/bin/plutil -extract "$forbidden_key" raw -o - "$info_plist" >/dev/null 2>&1 \
    || { print -u2 "build-and-run-open: private metadata entered the Open App"; exit 65; }
done
"$repository_root/scripts/verify-public-resource-bundle.sh" \
  "$contents/Resources/Rabbisir_RabbisirCore.bundle" >/dev/null
framework_name='Spar''kle'
if /usr/bin/otool -L "$executable_path" | /usr/bin/grep -i "$framework_name"; then
  print -u2 "build-and-run-open: an update framework entered the Open App"
  exit 65
fi
signature_details="$(/usr/bin/codesign -dvvv "$executable_path" 2>&1 || true)"
if print -r -- "$signature_details" | /usr/bin/grep -q '^Authority='; then
  print -u2 "build-and-run-open: an official signing identity entered the temporary Open App"
  exit 65
fi

launch_arguments=()
if [[ "$mode" == "verify-first-run" ]]; then
  : >"$readiness_file"
  launch_arguments+=("--first-run-preview" "--open-readiness-file" "$readiness_file")
fi

/usr/bin/env \
  CFFIXED_USER_HOME="$isolated_home" \
  RABBISIR_OPEN_ISOLATED_HOME="$isolated_home" \
  "$executable_path" "${launch_arguments[@]}" &
app_pid=$!

if [[ "$mode" == "verify-first-run" ]]; then
  for _ in {1..600}; do
    /bin/kill -0 "$app_pid" 2>/dev/null \
      || { print -u2 "build-and-run-open: App exited before first-run readiness"; exit 1; }
    readiness_status="$(/bin/cat "$readiness_file" 2>/dev/null || true)"
    case "$readiness_status" in
      configuration-required)
        print "build-and-run-open: temporary Rabbisir Open first-run UI is ready"
        print "build-and-run-open: App, preferences, and runtime data are isolated under $work_root and will be removed"
        exit 0
        ;;
      failed)
        print -u2 "build-and-run-open: App reported a launch failure"
        exit 1
        ;;
      workspace-ready)
        print -u2 "build-and-run-open: workspace readiness does not prove a clean first run"
        exit 1
        ;;
    esac
    /bin/sleep 0.25
  done
  print -u2 "build-and-run-open: App did not publish first-run readiness"
  exit 1
fi

print "build-and-run-open: running an unsigned temporary Rabbisir Open from $app_path"
print "build-and-run-open: quitting the App removes its temporary bundle and isolated data"
wait "$app_pid"
app_pid=""
