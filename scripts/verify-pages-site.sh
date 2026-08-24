#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

fail() {
  echo "verify-pages-site: $*" >&2
  exit 1
}

reject_pattern() {
  reason=$1
  pattern=$2
  shift 2
  if LC_ALL=C grep -ErIn -- "$pattern" "$@"; then
    fail "$reason"
  else
    grep_result=$?
    [ "$grep_result" -eq 1 ] || fail "the Pages pattern scan failed"
  fi
}

reject_pattern_i() {
  reason=$1
  pattern=$2
  shift 2
  if LC_ALL=C grep -ErIin -- "$pattern" "$@"; then
    fail "$reason"
  else
    grep_result=$?
    [ "$grep_result" -eq 1 ] || fail "the Pages pattern scan failed"
  fi
}

for required in \
  site/.nojekyll \
  site/index.html \
  site/download.html \
  site/styles.css \
  site/site.js \
  site/assets/rabbisir/discord-symbol-blurple.svg \
  site/assets/rabbisir/rabbisir-mark-dark.png \
  site/assets/rabbisir/x-logo-white-v1.svg \
  site/assets/rabbisir/yelzap-avatar.png \
  site/assets/rabbisir/yelzap-wechat-qr-v1.png \
  site/DOWNLOADS.md \
  site/PagesSourceManifest.json \
  site/appcast.xml \
  site/checksums.txt \
  site/official-app-release-source.json \
  site/official-app-release-source.json.sha256 \
  site/official-app-releases.json \
  site/official-app-releases.json.sha256 \
  site/release.json \
  site/release-data.mjs \
  site/release-details.mjs \
  site/UPSTREAM.md \
  site/LICENSE \
  .github/workflows/pages.yml \
  .github/workflows/ci.yml \
  docs/WEBSITE.md \
  scripts/test-official-release-feed.mjs \
  scripts/verify-official-release-feed.mjs
do
  test -f "$required" || fail "missing required Pages file: $required"
done

expected_site_files=$(printf '%s\n' \
  '.nojekyll' \
  'DOWNLOADS.md' \
  'LICENSE' \
  'PagesSourceManifest.json' \
  'UPSTREAM.md' \
  'appcast.xml' \
  'assets/rabbisir/discord-symbol-blurple.svg' \
  'assets/rabbisir/rabbisir-mark-dark.png' \
  'assets/rabbisir/x-logo-white-v1.svg' \
  'assets/rabbisir/yelzap-avatar.png' \
  'assets/rabbisir/yelzap-wechat-qr-v1.png' \
  'checksums.txt' \
  'download.html' \
  'index.html' \
  'official-app-release-source.json' \
  'official-app-release-source.json.sha256' \
  'official-app-releases.json' \
  'official-app-releases.json.sha256' \
  'release-data.mjs' \
  'release-details.mjs' \
  'release.json' \
  'site.js' \
  'styles.css')
actual_site_files=$(find site -type f -print | sed 's#^site/##' | LC_ALL=C sort)
[ "$actual_site_files" = "$expected_site_files" ] \
  || fail "site file allowlist differs from the reviewed Pages closure"

test ! -s site/.nojekyll || fail ".nojekyll must remain empty"
test ! -e site/rabbisir-site \
  || fail "the legacy nested Pages route must not remain in the artifact"
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

verify_sha256 e8dee7e5682c16162207c1a2314e98707696886761c2815b18e7796c298dceb3 \
  site/index.html
verify_sha256 04a918c56421607e2d50d7e7d62f218abb6ae70310bd34f5f01ef4bb4316efd1 \
  site/download.html
verify_sha256 a45dda569f11868d1062d73a9f10b1b9c2d4cb29c9c9fb6513c7f573803055b1 \
  site/styles.css
verify_sha256 fe5fbcfe213e9a0d487b6f84fbf8beb6db0d6e10525d3625ddb869d19aca0ba6 \
  site/site.js
verify_sha256 b76580f09ca3eefe3ecfb40707c10fec17444db7547ae19ae79a687ae4e3050a \
  site/release-data.mjs
verify_sha256 bfdb8cdfc8c6d51d0528bb01cca08c15443867600f25fadc13691f2a9dced5b8 \
  site/release-details.mjs
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
verify_sha256 c249ba284ef2460f1f0e6de64b41a02eaf9f7fca737f1501b762a8e0ba3d21a3 \
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
run_private_site_scan() {
  if command -v rg >/dev/null 2>&1
  then
    rg -n -i "$private_site_pattern" site/index.html site/download.html site/styles.css site/site.js \
      site/release-data.mjs site/release-details.mjs site/official-app-release-source.json \
      site/official-app-releases.json site/assets site/DOWNLOADS.md site/UPSTREAM.md site/LICENSE
  else
    grep -E -n -i -r -I -- "$private_site_pattern" site/index.html site/download.html site/styles.css site/site.js \
      site/release-data.mjs site/release-details.mjs site/official-app-release-source.json \
      site/official-app-releases.json site/assets site/DOWNLOADS.md site/UPSTREAM.md site/LICENSE
  fi
}
if run_private_site_scan
then
  fail "private, official-only, credential, or local-path material entered the site"
else
  scan_result=$?
  [ "$scan_result" -eq 1 ] || fail "the private-site boundary scan failed"
fi

python3 - <<'PY'
from html.parser import HTMLParser
from pathlib import Path
from urllib.parse import urlsplit
import sys

site_root = Path("site").resolve()


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
            self.scripts.append((values.get("src"), values.get("type"), "defer" in values))
        if tag == "h1":
            self.h1_count += 1
        if tag == "main":
            self.main_count += 1
        if tag == "html":
            self.html_lang = values.get("lang")


failures = []
forbidden_tags = {"style", "form", "iframe", "source", "video", "audio", "object", "embed"}
dmg_url = "https://github.com/readysteadyscience/Rabbisir/releases/latest/download/Rabbisir.dmg"
index_resources = {
    ("icon", "assets/rabbisir/rabbisir-mark-dark.png"),
    ("stylesheet", "styles.css"),
}
release_resources = index_resources | {
    ("canonical", "https://readysteadyscience.github.io/Rabbisir/download.html"),
}
index_scripts = [("site.js?v=20260815-wechat2", None, True)]
release_scripts = [
    ("site.js?v=20260815-wechat2", None, True),
    ("release-details.mjs", "module", False),
]
index_images = [
    "assets/rabbisir/rabbisir-mark-dark.png",
    "assets/rabbisir/discord-symbol-blurple.svg",
    "assets/rabbisir/rabbisir-mark-dark.png",
    "assets/rabbisir/yelzap-avatar.png",
    "assets/rabbisir/x-logo-white-v1.svg",
    "assets/rabbisir/yelzap-wechat-qr-v1.png",
]
index_hrefs = {
    "#top",
    "https://github.com/deepseek-ai/deepseek-harness",
    dmg_url,
    "download.html",
    "https://discord.gg/gT4TUHGkQm",
    "https://x.com/YelZap1987",
    "UPSTREAM.md",
    "LICENSE",
}
release_images = [
    "assets/rabbisir/rabbisir-mark-dark.png",
    "assets/rabbisir/yelzap-avatar.png",
    "assets/rabbisir/x-logo-white-v1.svg",
    "assets/rabbisir/yelzap-wechat-qr-v1.png",
]
release_hrefs = {
    "index.html",
    "https://github.com/deepseek-ai/deepseek-harness",
    "https://x.com/YelZap1987",
    "UPSTREAM.md",
    "LICENSE",
}


def validate_page(filename, required_ids, expected_images, expected_hrefs, expected_resources,
                  expected_scripts, extra_dependencies=()):
    html_path = site_root / filename
    parser = SiteParser()
    parser.feed(html_path.read_text(encoding="utf-8"))
    if parser.html_lang != "en":
        failures.append(f"{filename} document language changed")
    if parser.h1_count != 1 or parser.main_count != 1:
        failures.append(f"{filename} must contain exactly one h1 and one main landmark")
    if not required_ids.issubset(parser.ids):
        failures.append(f"{filename} landmarks changed")
    if forbidden_tags.intersection(parser.tags):
        failures.append(f"{filename} gained inline, framed, or embedded content")
    if set(parser.resources) != expected_resources:
        failures.append(f"{filename} local resource closure changed")
    if parser.scripts != expected_scripts:
        failures.append(f"{filename} script closure changed")
    if parser.images != expected_images:
        failures.append(f"{filename} local image closure changed")
    if set(parser.hrefs) != expected_hrefs:
        failures.append(f"{filename} navigation destinations changed")

    local_references = [
        href for href in parser.hrefs if not href.startswith(("#", "https://"))
    ]
    local_references.extend(
        href for _, href in parser.resources if not href.startswith("https://")
    )
    local_references.extend(parser.images)
    local_references.extend(src for src, _, _ in parser.scripts)
    local_references.extend(extra_dependencies)
    for reference in local_references:
        parsed = urlsplit(reference)
        allowed_query = reference == "site.js?v=20260815-wechat2"
        if parsed.scheme or parsed.netloc or (parsed.query and not allowed_query):
            failures.append(f"unreviewed resource reference in {filename}: {reference}")
            continue
        target = (html_path.parent / parsed.path).resolve()
        try:
            target.relative_to(site_root)
        except ValueError:
            failures.append(f"resource escapes the Pages root in {filename}: {reference}")
            continue
        if not target.is_file():
            failures.append(f"missing local dependency in {filename}: {reference}")


validate_page(
    "index.html",
    {"top", "hero-title", "wechat-qr-dialog"},
    index_images,
    index_hrefs,
    index_resources,
    index_scripts,
)
validate_page(
    "download.html",
    {"release-title", "release-feed-status", "release-history-title", "release-list", "wechat-qr-dialog"},
    release_images,
    release_hrefs,
    release_resources,
    release_scripts,
    (
        "release-data.mjs",
        "official-app-release-source.json",
        "official-app-release-source.json.sha256",
        "official-app-releases.json",
        "official-app-releases.json.sha256",
    ),
)

if failures:
    print("\n".join(failures), file=sys.stderr)
    sys.exit(1)
PY

reject_pattern \
  "the reviewed stylesheet unexpectedly loads another resource" \
  '@import|url\(' site/styles.css
reject_pattern \
  "the reviewed interaction script gained a network, cookie, navigation, or dynamic-code path" \
  'fetch\(|XMLHttpRequest|WebSocket|EventSource|sendBeacon|document\.cookie|window\.open|location\.|eval\(|new Function' \
  site/site.js
grep -q '^const feedURL = "official-app-releases.json";$' site/release-details.mjs \
  || fail "the Release Details page does not use the same-origin official App feed"
[ "$(grep -c 'fetchFunction(feedURL' site/release-details.mjs)" -eq 1 ] \
  || fail "the Release Details page must have exactly one bounded feed request"
reject_pattern \
  "the official App feed path gained an external Release, credential, navigation, or dynamic-code dependency" \
  'https?://|api\.github\.com|/releases|appcast|document\.cookie|window\.open|location\.|eval\(|new Function' \
  site/release-data.mjs site/release-details.mjs \
  site/official-app-release-source.json site/official-app-releases.json
node scripts/verify-official-release-feed.mjs
node scripts/test-official-release-feed.mjs
node <<'NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");

const failManifest = (message) => {
  console.error(`verify-pages-site: ${message}`);
  process.exit(1);
};
const sha256 = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const manifest = JSON.parse(fs.readFileSync("site/PagesSourceManifest.json", "utf8"));
const expectedFiles = [
  "appcast.xml",
  "checksums.txt",
  "official-app-release-source.json",
  "official-app-release-source.json.sha256",
  "official-app-releases.json",
  "official-app-releases.json.sha256",
  "release.json",
];
if (manifest.schemaVersion !== 2
  || !Array.isArray(manifest.files)
  || manifest.files.map((entry) => entry.name).join("\n") !== expectedFiles.join("\n")) {
  failManifest("Pages source manifest file closure changed");
}
for (const entry of manifest.files) {
  const file = path.join("site", entry.name);
  if (entry.sha256 !== sha256(file) || entry.size !== fs.statSync(file).size) {
    failManifest(`Pages source manifest receipt differs for ${entry.name}`);
  }
}
const expectedVerification = {
  downloadsSHA256: sha256("site/DOWNLOADS.md"),
  governanceSHA256: sha256("scripts/verify-code-review-governance.sh"),
  pagesSHA256: sha256("scripts/verify-pages-site.sh"),
  publicRepositorySHA256: sha256("scripts/verify-public-repository.sh"),
};
if (JSON.stringify(manifest.verification) !== JSON.stringify(expectedVerification)
  || manifest.workflow.path !== ".github/workflows/pages.yml"
  || manifest.workflow.ref !== "refs/heads/main"
  || manifest.workflow.sha256 !== sha256(manifest.workflow.path)) {
  failManifest("Pages source manifest verification receipts changed");
}
NODE
grep -q '<meta name="color-scheme" content="dark">' site/index.html \
  && grep -q '<meta name="color-scheme" content="dark">' site/download.html \
  || fail "the final fixed-dark document metadata is missing"
grep -q '<meta name="theme-color" content="#080a0d">' site/index.html \
  && grep -q '<meta name="theme-color" content="#080a0d">' site/download.html \
  || fail "the final dark browser theme is missing"
grep -q -- '--background: #080a0d;' site/styles.css \
  || fail "the final #080a0d background is missing"
grep -q '@media (prefers-reduced-motion: reduce)' site/styles.css \
  || fail "the final reduced-motion path is missing"
grep -q 'const languageStorageKey = "rabbisir-language";' site/site.js \
  || fail "the bounded language preference key changed"
grep -q 'wechatDialog.showModal();' site/site.js \
  || fail "the reviewed creator-contact dialog no longer opens"
grep -q 'data-en="Built on DeepSeek Harness" data-zh="基于 DeepSeek Harness 构建"' \
  site/index.html \
  || fail "the prominent bilingual DeepSeek Harness attribution is missing"
grep -q 'Not affiliated with, sponsored by, or endorsed by DeepSeek' site/index.html \
  || fail "the English independence disclaimer is missing"
grep -q '与 DeepSeek 不存在隶属、赞助或背书关系' site/index.html \
  || fail "the Chinese independence disclaimer is missing"
grep -q '<span class="wechat-profile-label" data-en="WeChat" data-zh="微信">WeChat</span>' \
  site/index.html \
  || fail "the explicit bilingual WeChat contact entry is missing"
official_dmg_url='https://github.com/readysteadyscience/Rabbisir/releases/latest/download/Rabbisir.dmg'
grep -Fq "<a class=\"download-button\" href=\"$official_dmg_url\"" site/index.html \
  || fail "the homepage primary download does not point directly to the official DMG"
grep -Fq '<span data-en="Download" data-zh="下载">Download</span>' site/index.html \
  || fail "the homepage download button must remain version-neutral"
if grep -Fq 'data-en="Download ·' site/index.html \
  || grep -Fq 'data-zh="下载 ·' site/index.html \
  || grep -Eq '<a class="download-button"[^>]*(Rabbisir [0-9]|Rabbisir v[0-9])' site/index.html
then
  fail "a primary download action exposes a release version"
fi
grep -q 'href="download.html" data-en="Release details" data-zh="版本详情"' site/index.html \
  || fail "the stable Release Details page is not linked from the homepage"
if grep -q 'href="DOWNLOADS.md"' site/index.html site/download.html; then
  fail "raw Markdown remains exposed as a browser-facing download destination"
fi
for expected_versioned_asset in \
  'Rabbisir-0.1.0-2.dmg' \
  'Rabbisir-0.1.0-2.zip'
do
  grep -Fq "$expected_versioned_asset" site/DOWNLOADS.md \
    || fail "the auditable source record omits a versioned release filename"
done
reject_pattern_i \
  "an excluded DeepSeek graphic or unverified WeChat graphic entered the site" \
  'deepseek[^<]*(logo|mark|avatar)|deepseek-(logo|mark|avatar)|wechat[^<]*(logo|mark)|wechat-(logo|mark)' \
  site/index.html site/download.html site/release-data.mjs site/release-details.mjs \
  site/official-app-releases.json site/assets

grep -q '^# Public website$' docs/WEBSITE.md \
  || fail "the public website boundary is not documented"
grep -q '^## Official App release information channel$' docs/WEBSITE.md \
  || fail "the official App release information channel is not documented"
grep -q '^## Direct download continuity$' docs/WEBSITE.md \
  || fail "the homepage download continuity boundary is not documented"
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
grep -q '^          RABBISIR_PUBLIC_SOURCE_EXPORT: "true"$' "$pages_workflow" \
  || fail "Pages workflow does not use the public-export verification mode"
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
echo "verify-pages-site: maintenance-release public base and manual Pages packaging passed"
