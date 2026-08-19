#!/bin/zsh
set -euo pipefail

if (( $# != 1 )); then
  print -u2 "usage: prepare-public-source.sh <new-temporary-output-directory>"
  exit 64
fi

repository_root="${0:A:h:h}"
temporary_root="${TMPDIR:-/tmp}"
temporary_root="${temporary_root:A}"
destination="${1:A}"
[[ "$destination" != "$repository_root" && "$destination" != "/" ]] \
  || { print -u2 "prepare-public-source: unsafe output directory"; exit 70; }
[[ "$destination" == "$temporary_root"/rabbisir-public-source.* ]] \
  || { print -u2 "prepare-public-source: output must be a dedicated temporary directory"; exit 70; }
[[ ! -e "$destination" ]] \
  || { print -u2 "prepare-public-source: output directory must not exist"; exit 73; }

/bin/mkdir -p "$destination"
complete=false
cleanup() {
  $complete && return
  [[ "$destination" == "$temporary_root"/rabbisir-public-source.* ]] || exit 70
  [[ ! -e "$destination" ]] || /usr/bin/find "$destination" -depth -delete
}
trap cleanup EXIT HUP INT TERM

cd "$repository_root"
while IFS= read -r -d '' relative_path; do
  case "$relative_path" in
    /*|../*|*/../*)
      print -u2 "prepare-public-source: unsafe tracked path"
      exit 70
      ;;
  esac
  [[ -f "$relative_path" && ! -L "$relative_path" ]] \
    || { print -u2 "prepare-public-source: only regular public files are allowed"; exit 65; }
  /bin/mkdir -p "$destination/${relative_path:h}"
  /bin/cp -p "$relative_path" "$destination/$relative_path"
done < <(
  git ls-files --cached --others --exclude-standard -z -- \
    .github .gitignore ASSETS.md CHANGELOG.md CONTRIBUTING.md LICENSE \
    Legal NOTICE.md Package.resolved Package.swift README.md README.zh.md \
    RuntimeProvenance Sources Tests docs scripts \
    ':(exclude)Sources/RabbisirApp/**' \
    ':(exclude)Sources/RabbisirDEVApp/**' \
    ':(exclude)scripts/build-and-run.sh' \
    ':(exclude)scripts/build-and-run-dev.sh' \
    ':(exclude)scripts/build-and-run-production.sh' \
    ':(exclude)scripts/verify-official-overlay.sh'
)

/bin/cp -p "$repository_root/docs/AGENTS.public.md" "$destination/AGENTS.md"

"$destination/scripts/verify-public-export.sh" "$destination"
fingerprint="$(node "$destination/scripts/public-source-fingerprint.mjs" "$destination")"
complete=true
print "prepare-public-source: staged a history-free public source candidate at $destination"
print "prepare-public-source: public source fingerprint $fingerprint"
