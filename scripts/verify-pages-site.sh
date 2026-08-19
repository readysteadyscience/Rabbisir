#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

fail() {
  echo "verify-pages-site: $*" >&2
  exit 1
}

for required in \
  site/.nojekyll \
  site/rabbisir-site/index.html \
  site/rabbisir-site/styles.css \
  site/rabbisir-site/site.js \
  site/assets/rabbisir/discord-symbol-blurple.svg \
  site/assets/rabbisir/rabbisir-mark-dark.png \
  site/assets/rabbisir/x-logo-white-v1.svg \
  site/assets/rabbisir/yelzap-avatar.png \
  site/assets/rabbisir/yelzap-wechat-qr-v1.png \
  site/DOWNLOADS.md \
  site/UPSTREAM.md \
  site/LICENSE \
  .github/workflows/pages.yml \
  .github/workflows/ci.yml \
  docs/WEBSITE.md
do
  test -f "$required" || fail "missing required Pages file: $required"
done

expected_site_files=$(printf '%s\n' \
  '.nojekyll' \
  'DOWNLOADS.md' \
  'LICENSE' \
  'UPSTREAM.md' \
  'assets/rabbisir/discord-symbol-blurple.svg' \
  'assets/rabbisir/rabbisir-mark-dark.png' \
  'assets/rabbisir/x-logo-white-v1.svg' \
  'assets/rabbisir/yelzap-avatar.png' \
  'assets/rabbisir/yelzap-wechat-qr-v1.png' \
  'rabbisir-site/index.html' \
  'rabbisir-site/site.js' \
  'rabbisir-site/styles.css')
actual_site_files=$(find site -type f -print | sed 's#^site/##' | LC_ALL=C sort)
[ "$actual_site_files" = "$expected_site_files" ] \
  || fail "site file allowlist differs from the reviewed Pages closure"

test ! -s site/.nojekyll || fail ".nojekyll must remain empty"
if find site -type l -print | grep -q .; then
  fail "symbolic links are not allowed in the Pages capsule"
fi

verify_sha256() {
  expected=$1
  file=$2
  actual=$(shasum -a 256 "$file" | awk '{print $1}')
  [ "$actual" = "$expected" ] \
    || fail "$file differs from the reviewed public-candidate digest"
}

verify_sha256 80e3bd249e79e7ac16e2c73919ccfcb6f6e19c962b3c036fda3a967eb57d351c \
  site/rabbisir-site/index.html
verify_sha256 f3a44a62c2a1eb3ff97c321bf9e3cc54d3c50fb4252bebd8c04fbabfe8417095 \
  site/rabbisir-site/styles.css
verify_sha256 fe5fbcfe213e9a0d487b6f84fbf8beb6db0d6e10525d3625ddb869d19aca0ba6 \
  site/rabbisir-site/site.js
verify_sha256 296286aa112c4400af8e96191ab888f81abd4bd1d5dc7294112a622ef43581b1 \
  site/assets/rabbisir/discord-symbol-blurple.svg
verify_sha256 3eb50dd54404dbedb76a1c1b6dae85fb058e274cff0629c500d6379fddb8ab7c \
  site/assets/rabbisir/rabbisir-mark-dark.png
verify_sha256 dd46f96b6f47fcd33683b79ddfaf3daca1d4f8aeba3c0f2bde1584c69cc699d4 \
  site/assets/rabbisir/x-logo-white-v1.svg
verify_sha256 4d30bc3ccdc9b646a4ee4e3a230f00b855b07b04f2011dec81290a3fe27d395d \
  site/assets/rabbisir/yelzap-avatar.png
verify_sha256 caa389488834e64489ca805937d8d1bf5a745b388a1138b429556dc1684bcc05 \
  site/assets/rabbisir/yelzap-wechat-qr-v1.png
verify_sha256 4b986eb8504b525295bc287735a29e3b1924a8d0be7d2da180403034082c6d87 \
  site/DOWNLOADS.md
verify_sha256 5082086b3f32b37da781c0a58216875f10e3281dbba8a297a0a5e26e8319d3df \
  site/UPSTREAM.md
verify_sha256 d93ad1be836aa1867aada55e97a7d00a60e2ebd8f25239782475b97049b888b9 \
  site/LICENSE

grep -q 'Copyright (c) 2026 YelZap' LICENSE \
  || fail "the Rabbisir root license was replaced or lost"
grep -q 'Copyright (c) 2026 YelZap' site/LICENSE \
  || fail "the Pages-local Rabbisir MIT attribution is missing"
cmp -s LICENSE site/LICENSE \
  || fail "the Pages-local license differs from the reviewed Rabbisir root license"

private_site_pattern='app''cast|spar''kle|support rab''bisir|appear''ance|wall''paper|official''overlay|overlay''receipt|developer id app''lication:|apple team i''d|begin (rsa |ec |openssh )?private ke''y|/use''rs/[^/ ]+|/pri''vate/tm''p/|deepseek_api''_key[[:space:]]*='
if rg -n -i "$private_site_pattern" site
then
  fail "private, official-only, credential, or local-path material entered the site"
fi

python3 - <<'PY'
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import sys

root = Path.cwd()
site_root = (root / "site").resolve()
html_path = site_root / "rabbisir-site" / "index.html"
text = html_path.read_text(encoding="utf-8")


class SiteParser(HTMLParser):
    def __init__(self):
        super().__init__(convert_charrefs=True)
        self.tags = []
        self.ids = set()
        self.hrefs = []
        self.resources = []
        self.images = []
        self.scripts = []
        self.h1_count = 0
        self.main_count = 0
        self.html_lang = None

    def handle_starttag(self, tag, attrs):
        values = dict(attrs)
        self.tags.append(tag)
        if "id" in values:
            self.ids.add(values["id"])
        if tag == "a" and "href" in values:
            self.hrefs.append(values["href"])
        if tag == "link":
            self.resources.append((values.get("rel"), values.get("href")))
        if tag == "img":
            self.images.append(values.get("src"))
        if tag == "script":
            self.scripts.append((values.get("src"), "defer" in values))
        if tag == "h1":
            self.h1_count += 1
        if tag == "main":
            self.main_count += 1
        if tag == "html":
            self.html_lang = values.get("lang")


parser = SiteParser()
parser.feed(text)

failures = []
if parser.html_lang != "en":
    failures.append("the reviewed document language changed")
if parser.h1_count != 1 or parser.main_count != 1:
    failures.append("the reviewed site must contain exactly one h1 and one main landmark")
if not {"top", "hero-title", "wechat-qr-dialog"}.issubset(parser.ids):
    failures.append("the reviewed page landmarks changed")

forbidden_tags = {"style", "form", "iframe", "source", "video", "audio", "object", "embed"}
if forbidden_tags.intersection(parser.tags):
    failures.append("the reviewed site gained inline, framed, or embedded content")

expected_resources = {
    ("icon", "../assets/rabbisir/rabbisir-mark-dark.png"),
    ("stylesheet", "styles.css"),
}
if set(parser.resources) != expected_resources:
    failures.append("the reviewed local icon or stylesheet reference changed")
if parser.scripts != [("site.js?v=20260815-wechat2", True)]:
    failures.append("the reviewed deferred local script reference changed")
if parser.images != [
    "../assets/rabbisir/rabbisir-mark-dark.png",
    "../assets/rabbisir/discord-symbol-blurple.svg",
    "../assets/rabbisir/rabbisir-mark-dark.png",
    "../assets/rabbisir/yelzap-avatar.png",
    "../assets/rabbisir/x-logo-white-v1.svg",
    "../assets/rabbisir/yelzap-wechat-qr-v1.png",
]:
    failures.append("the reviewed local image closure changed")

expected_hrefs = {
    "#top",
    "https://github.com/deepseek-ai/deepseek-harness",
    "https://discord.gg/gT4TUHGkQm",
    "https://x.com/YelZap1987",
    "../DOWNLOADS.md",
    "../UPSTREAM.md",
    "../LICENSE",
}
if set(parser.hrefs) != expected_hrefs:
    failures.append("the reviewed navigation destinations changed")

local_references = [
    href for href in parser.hrefs if not href.startswith(("#", "https://"))
]
local_references.extend(href for _, href in parser.resources)
local_references.extend(parser.images)
local_references.extend(src for src, _ in parser.scripts)
for reference in local_references:
    parsed = urlsplit(reference)
    allowed_query = reference == "site.js?v=20260815-wechat2"
    if parsed.scheme or parsed.netloc or (parsed.query and not allowed_query):
        failures.append(f"unreviewed resource reference: {reference}")
        continue
    target = (html_path.parent / parsed.path).resolve()
    try:
        target.relative_to(site_root)
    except ValueError:
        failures.append(f"resource escapes the Pages root: {reference}")
        continue
    if not target.is_file():
        failures.append(f"missing local dependency: {reference}")

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
PY

if rg -n '@import|url\(' site/rabbisir-site/styles.css; then
  fail "the reviewed stylesheet unexpectedly loads another resource"
fi
if rg -n 'fetch\(|XMLHttpRequest|WebSocket|EventSource|sendBeacon|document\.cookie|window\.open|location\.|eval\(|new Function' \
  site/rabbisir-site/site.js
then
  fail "the reviewed interaction script gained a network, cookie, navigation, or dynamic-code path"
fi
grep -q '<meta name="color-scheme" content="dark">' site/rabbisir-site/index.html \
  || fail "the final fixed-dark document metadata is missing"
grep -q '<meta name="theme-color" content="#080a0d">' site/rabbisir-site/index.html \
  || fail "the final dark browser theme is missing"
grep -q -- '--background: #080a0d;' site/rabbisir-site/styles.css \
  || fail "the final #080a0d background is missing"
grep -q '@media (prefers-reduced-motion: reduce)' site/rabbisir-site/styles.css \
  || fail "the final reduced-motion path is missing"
grep -q 'const languageStorageKey = "rabbisir-language";' site/rabbisir-site/site.js \
  || fail "the bounded language preference key changed"
grep -q 'wechatDialog.showModal();' site/rabbisir-site/site.js \
  || fail "the reviewed creator-contact dialog no longer opens"
grep -q 'data-en="Built on DeepSeek Harness" data-zh="基于 DeepSeek Harness 构建"' \
  site/rabbisir-site/index.html \
  || fail "the prominent bilingual DeepSeek Harness attribution is missing"
grep -q 'Not affiliated with, sponsored by, or endorsed by DeepSeek' site/rabbisir-site/index.html \
  || fail "the English independence disclaimer is missing"
grep -q '与 DeepSeek 不存在隶属、赞助或背书关系' site/rabbisir-site/index.html \
  || fail "the Chinese independence disclaimer is missing"
grep -q '<span class="wechat-profile-label" data-en="WeChat" data-zh="微信">WeChat</span>' \
  site/rabbisir-site/index.html \
  || fail "the explicit bilingual WeChat contact entry is missing"
if rg -n -i 'deepseek[^<]*(logo|mark|avatar)|deepseek-(logo|mark|avatar)|wechat[^<]*(logo|mark)|wechat-(logo|mark)' \
  site/rabbisir-site site/assets
then
  fail "an excluded DeepSeek graphic or unverified WeChat graphic entered the site"
fi

grep -q 'cabcd17d40403a73b3eac517dfcc02e2df3a42b32a68093307f727080d1f9f28' docs/WEBSITE.md \
  || fail "the final website source baseline is not recorded"
grep -q 'https://about.x.com/en/who-we-are/brand-toolkit' Legal/BRAND_ASSETS.md \
  || fail "the official X Brand Toolkit source is not recorded"
grep -q 'caa389488834e64489ca805937d8d1bf5a745b388a1138b429556dc1684bcc05' \
  Legal/BRAND_ASSETS.md \
  || fail "the authorized creator-contact QR record is missing"
grep -q '3eb50dd54404dbedb76a1c1b6dae85fb058e274cff0629c500d6379fddb8ab7c' \
  Legal/BRAND_ASSETS.md \
  || fail "the dark mark provenance is not recorded"
shasum -a 256 -c Legal/SITE_ASSET_MANIFEST.sha256 >/dev/null \
  || fail "a public website asset differs from its reviewed manifest"
manifest_site_assets=$(sed -E 's/^[0-9a-f]{64}  //' Legal/SITE_ASSET_MANIFEST.sha256 | LC_ALL=C sort)
actual_site_assets=$(find site/assets -type f -print | LC_ALL=C sort)
[ "$manifest_site_assets" = "$actual_site_assets" ] \
  || fail "the website asset inventory differs from the reviewed manifest"

pages_workflow=.github/workflows/pages.yml
grep -q '^  workflow_dispatch:$' "$pages_workflow" \
  || fail "Pages deployment is not an explicit manual transaction"
if grep -Eq '^  (push|pull_request):' "$pages_workflow"; then
  fail "Pages deployment must not run automatically on source push or pull request"
fi
grep -q "if: github.ref == 'refs/heads/main'" "$pages_workflow" \
  || fail "Pages deployment is not restricted to main"
grep -q 'run: scripts/verify-pages-site.sh' "$pages_workflow" \
  || fail "Pages workflow does not verify the site before packaging"
grep -q 'actions/checkout@11d5960a326750d5838078e36cf38b85af677262' "$pages_workflow" \
  || fail "Pages checkout action is not pinned"
grep -q 'actions/configure-pages@45bfe0192ca1faeb007ade9deae92b16b8254a0d' "$pages_workflow" \
  || fail "configure-pages action is not pinned"
grep -q 'actions/upload-pages-artifact@fc324d3547104276b827a68afc52ff2a11cc49c9' "$pages_workflow" \
  || fail "upload-pages-artifact action is not pinned"
grep -q 'actions/deploy-pages@cd2ce8fcbc39b97be8ca5fce6e763baed58fa128' "$pages_workflow" \
  || fail "deploy-pages action is not pinned"
grep -q '^          path: site$' "$pages_workflow" \
  || fail "Pages workflow does not package the reviewed public site root"
grep -q '^          include-hidden-files: true$' "$pages_workflow" \
  || fail "Pages artifact would omit the reviewed .nojekyll file"
grep -q '^      pages: write$' "$pages_workflow" \
  || fail "Pages deploy job lacks the required scoped permission"
grep -q '^      id-token: write$' "$pages_workflow" \
  || fail "Pages deploy job lacks the required OIDC permission"
grep -q 'run: scripts/verify-pages-site.sh' .github/workflows/ci.yml \
  || fail "CI does not verify the Pages capsule"

echo "verify-pages-site: final fixed-dark baseline, adapted public closure, provenance, and manual Pages packaging passed"
