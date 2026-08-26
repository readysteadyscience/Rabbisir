#!/bin/sh
set -eu

if [ "$#" -gt 1 ]; then
  echo "usage: verify-public-delivery-boundary.sh [repository-root]" >&2
  exit 64
fi

if [ "$#" -eq 1 ]; then
  repository_root=$(CDPATH= cd -- "$1" && pwd)
else
  repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
fi
cd "$repository_root"

fail() {
  echo "verify-public-delivery-boundary: $*" >&2
  exit 1
}

python3 - "$repository_root" <<'PY'
from html.parser import HTMLParser
from pathlib import Path
import hashlib
import re
import sys

root = Path(sys.argv[1]).resolve()
source_repository = "readysteadyscience/Rabbisir"
release_repository = "readysteadyscience/Rabbisir-Releases"
official_download = "https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg"


def fail(message: str) -> None:
    print(f"verify-public-delivery-boundary: {message}", file=sys.stderr)
    raise SystemExit(1)


required = [
    "README.md",
    "README.zh.md",
    "docs/DEVELOPMENT.md",
    "docs/PUBLIC_SOURCE_POLICY.md",
    "docs/RELEASING.md",
    "docs/DELIVERY_WORKFLOW.md",
    "site/index.html",
    "site/download.html",
    ".github/workflows/ci.yml",
    ".github/workflows/pages.yml",
    ".github/workflows/repository-role.yml",
    "scripts/PUBLIC_AUTOMATION_MANIFEST.sha256",
]
for relative in required:
    if not (root / relative).is_file():
        fail(f"missing repository-role contract file: {relative}")


def text(relative: str) -> str:
    try:
        return (root / relative).read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        fail(f"repository-role file is unreadable UTF-8: {relative}")


readme = text("README.md")
readme_zh = text("README.zh.md")
policy = text("docs/PUBLIC_SOURCE_POLICY.md")
if official_download not in readme:
    fail("English README does not expose the permanent official DMG entry")
if official_download not in readme_zh:
    fail("Chinese README does not expose the permanent official DMG entry")
if "`open-vX.Y.Z`" not in policy:
    fail("public policy does not bind the Open milestone tag namespace")
if source_repository not in policy:
    fail("public policy does not identify the source/community repository")
if release_repository not in policy:
    fail("public policy does not identify the official distribution repository")


class HomepageParser(HTMLParser):
    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.primary_downloads: list[str | None] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        if tag != "a":
            return
        values = dict(attrs)
        classes = (values.get("class") or "").split()
        if "download-button" in classes:
            self.primary_downloads.append(values.get("href"))


homepage = text("site/index.html")
parser = HomepageParser()
parser.feed(homepage)
if parser.primary_downloads != [official_download]:
    fail("the unique homepage primary download does not exactly use the official latest DMG")

source_latest = re.compile(
    r"https://github\.com/readysteadyscience/Rabbisir/releases/latest(?:/download/[^\s\"'<)]*)?",
    re.IGNORECASE,
)
for relative in ["README.md", "README.zh.md", "site/index.html", "site/download.html"]:
    if source_latest.search(text(relative)):
        fail(f"an Open/source-repository latest Release is presented as the official App download: {relative}")

manifest_relative = "scripts/PUBLIC_AUTOMATION_MANIFEST.sha256"
manifest_entries: dict[str, str] = {}
for line_number, line in enumerate(text(manifest_relative).splitlines(), start=1):
    match = re.fullmatch(r"([0-9a-f]{64})  ((?:scripts|\.github/workflows)/[^\s]+)", line)
    if not match or match.group(2) == manifest_relative or match.group(2) in manifest_entries:
        fail(f"automation manifest line is malformed or duplicated: {line_number}")
    manifest_entries[match.group(2)] = match.group(1)

automation_files = sorted(
    path
    for directory in [root / "scripts", root / ".github/workflows"]
    for path in directory.rglob("*")
    if path.is_file() and path.relative_to(root).as_posix() != manifest_relative
)
actual_paths = [path.relative_to(root).as_posix() for path in automation_files]
if sorted(manifest_entries) != actual_paths:
    fail("automation path inventory differs from the reviewed SHA-256 closure")
for path in automation_files:
    relative = path.relative_to(root).as_posix()
    actual_digest = hashlib.sha256(path.read_bytes()).hexdigest()
    if manifest_entries[relative] != actual_digest:
        fail(f"automation bytes differ from the reviewed SHA-256 closure: {relative}")

role_workflow = text(".github/workflows/repository-role.yml")
if "scripts/test-public-delivery-boundary.sh" not in role_workflow:
    fail("repository role workflow does not run the baseline and negative fixtures")

print("verify-public-delivery-boundary: repository roles and the complete public automation SHA-256 closure are isolated")
PY
