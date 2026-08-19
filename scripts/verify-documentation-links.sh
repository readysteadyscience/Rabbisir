#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

python3 - <<'PY'
from pathlib import Path
import re
import sys
from urllib.parse import unquote

root = Path.cwd()
documents = sorted(
    list(root.glob("*.md"))
    + list((root / "docs").rglob("*.md"))
    + list((root / ".github").rglob("*.md"))
)
failures = []

for document in documents:
    text = document.read_text(encoding="utf-8")
    for match in re.finditer(r"(?<!!)\[[^\]]+\]\(([^)]+)\)", text):
        destination = match.group(1).strip()
        if destination.startswith(("http://", "https://", "mailto:", "#")):
            continue
        path_text = unquote(destination.split("#", 1)[0])
        if not path_text:
            continue
        target = (document.parent / path_text).resolve()
        try:
            target.relative_to(root)
        except ValueError:
            failures.append(f"{document.relative_to(root)}: link escapes repository: {destination}")
            continue
        if not target.exists():
            failures.append(f"{document.relative_to(root)}: missing link target: {destination}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)

print(f"verify-documentation-links: checked {len(documents)} Markdown files")
PY
