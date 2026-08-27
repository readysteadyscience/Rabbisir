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
  scripts/materialize-pages-assets.mjs \
  scripts/update-official-release-feed.mjs \
  scripts/verify-official-release-feed.mjs
do
  test -f "$required" || fail "missing required Pages file: $required"
done

expected_site_files=$(
  {
    printf '%s\n' \
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
      'styles.css'
    if [ "${RABBISIR_PAGES_DEPLOY_ARTIFACT:-}" = true ]; then
      printf '%s\n' 'Rabbisir.dmg'
    fi
  } | LC_ALL=C sort -u
)
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

verify_sha256 1b499831b736da2a4d1c691a13fbfffc342d409d8aae444a5dd0cfe79a7a49c7 \
  site/index.html
verify_sha256 04a918c56421607e2d50d7e7d62f218abb6ae70310bd34f5f01ef4bb4316efd1 \
  site/download.html
verify_sha256 fa326bbcc8b7b0c05ef9e2be6a86c4a5f4f6e9ec77e91aa94ff3424a745e1b59 \
  site/styles.css
verify_sha256 fe5fbcfe213e9a0d487b6f84fbf8beb6db0d6e10525d3625ddb869d19aca0ba6 \
  site/site.js
verify_sha256 7c05b081caf48f312c799d26dbbb8ddc8503163caafe5bc2cf5112b9ddd502c8 \
  site/release-data.mjs
verify_sha256 09fa876c5b1e91168b1c3f7897c7d90bd18a157bb44681e0a3c0be9560f2e66c \
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
verify_sha256 dea9ab33dae41b87b451f9154a6febdab9ef5369e772f376fa37c0a399a1fbc7 \
  site/UPSTREAM.md
verify_sha256 d93ad1be836aa1867aada55e97a7d00a60e2ebd8f25239782475b97049b888b9 \
  site/LICENSE

grep -q 'Copyright (c) 2026 YelZap' LICENSE \
  || fail "the Rabbisir root license was replaced or lost"
grep -q 'Copyright (c) 2026 YelZap' site/LICENSE \
  || fail "the Pages-local Rabbisir MIT attribution is missing"
cmp -s LICENSE site/LICENSE \
  || fail "the Pages-local license differs from the reviewed Rabbisir root license"

private_site_pattern='spar''kle|support rab''bisir|appear''ance|wall''paper|official''overlay|overlay''receipt|developer id app''lication:|apple team i''d|begin (rsa |ec |openssh )?private ke''y|/use''rs/[^/ ]+|/pri''vate/tm''p/|deepseek_api''_key[[:space:]]*='
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
dmg_url = "https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg"
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
grep -Fq 'export const feedURL = "https://raw.githubusercontent.com/readysteadyscience/Rabbisir-Releases/main/official-app-releases.json";' site/release-details.mjs \
  || fail "the Release Details page does not use the public release authority"
grep -Fq 'export const fallbackFeedURL = "official-app-releases.json";' site/release-details.mjs \
  || fail "the Release Details page lacks its bundled fallback"
grep -Fq 'export const latestDownloadURL = "https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg";' site/release-details.mjs \
  || fail "the Release Details page download authority changed"
grep -Fq 'mergeNormalizedReleaseFeeds(liveResult.value.normalized, history.normalized)' site/release-details.mjs \
  || fail "the live Release Details feed no longer preserves bundled release history"
[ "$(grep -c 'fetchFunction(url' site/release-details.mjs)" -eq 1 ] \
  || fail "the Release Details page must have one bounded request implementation"
reject_pattern \
  "the official App feed path gained a credential, active navigation, or dynamic-code dependency" \
  'api\.github\.com|document\.cookie|window\.open|location\.|eval\(|new Function|authorization|bearer[[:space:]]|token[[:space:]]*=' \
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
const exactKeys = (value, keys) => value && typeof value === "object" && !Array.isArray(value)
  && JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort());
const sha256 = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const manifest = JSON.parse(fs.readFileSync("site/PagesSourceManifest.json", "utf8"));
const release = JSON.parse(fs.readFileSync("site/release.json", "utf8"));
const deployArtifact = process.env.RABBISIR_PAGES_DEPLOY_ARTIFACT === "true";
if (Object.hasOwn(process.env, "RABBISIR_PAGES_DEPLOY_ARTIFACT") && !deployArtifact)
  failManifest("deployment-capsule mode must be exactly true when present");
const expectedFiles = [
  "appcast.xml",
  "checksums.txt",
  "official-app-release-source.json",
  "official-app-release-source.json.sha256",
  "official-app-releases.json",
  "official-app-releases.json.sha256",
  "release.json",
];
const stableDownloadURL = "https://readysteadyscience.github.io/Rabbisir/Rabbisir.dmg";
const stableDiskImage = "site/Rabbisir.dmg";
const usesStablePagesDownload = release.stableDownloadURL === stableDownloadURL;
if (usesStablePagesDownload) {
  if (fs.existsSync(stableDiskImage) !== deployArtifact)
    failManifest("the stable DMG presence does not match source or deployment-capsule mode");
} else if (fs.existsSync(stableDiskImage)) {
  failManifest("an unbound stable DMG entered the Pages source");
}
expectedFiles.sort((left, right) => left.localeCompare(right));
if ((usesStablePagesDownload ? manifest.schemaVersion !== 4 : manifest.schemaVersion !== 2)
  || !Array.isArray(manifest.files)
  || manifest.files.map((entry) => entry.name).join("\n") !== expectedFiles.join("\n")) {
  failManifest("Pages source manifest file closure changed");
}
if (manifest.schemaVersion === 4) {
  const productSource = manifest.provenance?.productArtifactSource;
  const toolingSource = manifest.provenance?.websiteToolingSource;
  const deploymentAsset = manifest.deploymentAssets?.[0];
  const releaseDiskImage = release.assets?.find((asset) => asset.name.endsWith(".dmg"));
  if (!exactKeys(manifest, ["deploymentAssets", "files", "provenance", "publicAppcastURL", "publicBase", "releaseTag", "runtime", "schemaVersion", "verification", "workflow"])
    || !Array.isArray(manifest.deploymentAssets) || manifest.deploymentAssets.length !== 1
    || !exactKeys(deploymentAsset, ["name", "sha256", "size", "sourceURL"])
    || deploymentAsset.name !== "Rabbisir.dmg"
    || deploymentAsset.sourceURL !== releaseDiskImage?.url
    || deploymentAsset.sha256 !== releaseDiskImage?.sha256
    || deploymentAsset.size !== releaseDiskImage?.size
    || !exactKeys(manifest.provenance, ["productArtifactSource", "websiteToolingSource"])
    || !exactKeys(productSource, ["commit", "tree"])
    || !exactKeys(toolingSource, ["commit", "overlayReceiptSHA256", "tree"])
    || !/^[0-9a-f]{40}$/.test(productSource.commit || "")
    || !/^[0-9a-f]{40}$/.test(productSource.tree || "")
    || !/^[0-9a-f]{40}$/.test(toolingSource.commit || "")
    || !/^[0-9a-f]{40}$/.test(toolingSource.tree || "")
    || !/^[0-9a-f]{64}$/.test(toolingSource.overlayReceiptSHA256 || "")) {
    failManifest("Pages source manifest dual provenance or deployment asset is invalid");
  }
} else if (Object.hasOwn(manifest, "provenance")) {
  failManifest("a legacy Pages source manifest contains unsupported provenance");
}
for (const entry of manifest.files) {
  const file = path.join("site", entry.name);
  if (entry.sha256 !== sha256(file) || entry.size !== fs.statSync(file).size) {
    failManifest(`Pages source manifest receipt differs for ${entry.name}`);
  }
}
if (deployArtifact) {
  const deploymentAsset = manifest.deploymentAssets?.[0];
  if (!deploymentAsset || deploymentAsset.sha256 !== sha256(stableDiskImage)
    || deploymentAsset.size !== fs.statSync(stableDiskImage).size) {
    failManifest("the materialized stable DMG differs from its frozen deployment record");
  }
}
const expectedVerification = {
  ...(manifest.schemaVersion === 4
    ? { appVersionSHA256: sha256("Sources/RabbisirCore/App/AppVersion.swift") }
    : {}),
  downloadsSHA256: sha256("site/DOWNLOADS.md"),
  governanceSHA256: sha256("scripts/verify-code-review-governance.sh"),
  ...(manifest.schemaVersion === 4
    ? { materializerSHA256: sha256("scripts/materialize-pages-assets.mjs") }
    : {}),
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
official_dmg_url='https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg'
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
node <<'NODE'
const fs = require("node:fs");
const release = JSON.parse(fs.readFileSync("site/release.json", "utf8"));
const downloads = fs.readFileSync("site/DOWNLOADS.md", "utf8");
const versionedAssets = release.assets.filter((asset) => /Rabbisir-\d+\.\d+\.\d+-\d+\.(?:dmg|zip)$/.test(asset.name));
if (versionedAssets.length !== 2 || versionedAssets.some((asset) => !downloads.includes(asset.name))) {
  console.error("verify-pages-site: the auditable source record omits a versioned release filename");
  process.exit(1);
}
NODE
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
grep -q 'node scripts/materialize-pages-assets.mjs verify-source site/PagesSourceManifest.json site' "$pages_workflow" \
  || fail "Pages workflow does not verify the source-mode asset boundary"
grep -q 'node scripts/materialize-pages-assets.mjs materialize site/PagesSourceManifest.json site' "$pages_workflow" \
  || fail "Pages workflow does not materialize the stable DMG from the frozen Release asset"
grep -q '^          RABBISIR_PAGES_DEPLOY_ARTIFACT: "true"$' "$pages_workflow" \
  || fail "Pages workflow does not verify the deployable capsule after materialization"
grep -q 'scripts/verify-pages-site.sh' "$pages_workflow" \
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
/usr/bin/env node <<'NODE'
const crypto = require("node:crypto");
const fs = require("node:fs");
const path = require("node:path");
const root = process.cwd();
const sha = (file) => crypto.createHash("sha256").update(fs.readFileSync(file)).digest("hex");
const digest = (value) => crypto.createHash("sha256").update(value).digest("hex");
const exact = (value, keys) => value && typeof value === "object" && !Array.isArray(value) &&
  JSON.stringify(Object.keys(value).sort()) === JSON.stringify([...keys].sort());
const fail = (message) => { console.error("verify-pages-site: " + message); process.exit(1); };
const inside = (rootPath, candidate) => {
  const relative = path.relative(rootPath, candidate);
  return relative === "" || (relative !== ".." && !relative.startsWith(".." + path.sep) && !path.isAbsolute(relative));
};
const completeRuntimeTree = (runtimeRoot) => {
  const resolvedRoot = fs.realpathSync(runtimeRoot);
  const records = [];
  let directoryCount = 0, fileCount = 0, symlinkCount = 0;
  const safe = (value) => {
    if (value.includes("\n") || value.includes("\r") || value.includes("\0"))
      throw new Error("unsupported runtime inventory text");
  };
  const visit = (directory) => {
    const entries = fs.readdirSync(directory, { withFileTypes: true })
      .sort((left, right) => Buffer.from(left.name).compare(Buffer.from(right.name)));
    for (const entry of entries) {
      const absolute = path.join(directory, entry.name);
      const relative = path.relative(resolvedRoot, absolute).split(path.sep).join("/");
      safe(relative);
      const stat = fs.lstatSync(absolute);
      if (stat.isDirectory()) {
        records.push("directory " + relative + "\n");
        directoryCount += 1;
        visit(absolute);
      } else if (stat.isSymbolicLink()) {
        const target = fs.readlinkSync(absolute);
        safe(target);
        if (!inside(resolvedRoot, fs.realpathSync(absolute))) throw new Error("runtime symlink escape");
        records.push("link " + target + " " + relative + "\n");
        symlinkCount += 1;
      } else if (stat.isFile()) {
        const mode = stat.mode & 0o111 ? "0755" : "0644";
        records.push("file " + mode + " " + sha(absolute) + " " + relative + "\n");
        fileCount += 1;
      } else throw new Error("unsupported runtime entry");
    }
  };
  visit(resolvedRoot);
  records.sort();
  return { algorithm: "sha256(complete-path-kind-mode-content-v1)", digest: digest(records.join("")),
    directoryCount, fileCount, symlinkCount };
};
const manifestPath = path.join(root, "site/PagesSourceManifest.json");
const runtimeReceiptPath = path.join(root, "Sources/RabbisirCore/Resources/VendorRuntime/.rabbisir-runtime-provenance.json");
const isPublicSourceExport = process.env.RABBISIR_PUBLIC_SOURCE_EXPORT === "true";
const deployArtifact = process.env.RABBISIR_PAGES_DEPLOY_ARTIFACT === "true";
const runtimeReceiptIsPresent = fs.existsSync(runtimeReceiptPath);
let manifest, release, officialFeed, officialSourceReceipt;
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  release = JSON.parse(fs.readFileSync(path.join(root, "site/release.json"), "utf8"));
  officialFeed = JSON.parse(fs.readFileSync(path.join(root, "site/official-app-releases.json"), "utf8"));
  officialSourceReceipt = JSON.parse(fs.readFileSync(path.join(root, "site/official-app-release-source.json"), "utf8"));
} catch { fail("generated Pages metadata is unreadable"); }
if (!exact(manifest.runtime, ["contractSHA256", "receiptSHA256", "tree"]) ||
    !exact(manifest.runtime.tree, ["algorithm", "digest", "directoryCount", "fileCount", "symlinkCount"]) ||
    manifest.runtime.tree.algorithm !== "sha256(complete-path-kind-mode-content-v1)" ||
    !/^[0-9a-f]{64}$/.test(manifest.runtime.tree.digest || "") ||
    !Number.isSafeInteger(manifest.runtime.tree.directoryCount) || manifest.runtime.tree.directoryCount < 1 ||
    !Number.isSafeInteger(manifest.runtime.tree.fileCount) || manifest.runtime.tree.fileCount < 1 ||
    !Number.isSafeInteger(manifest.runtime.tree.symlinkCount) || manifest.runtime.tree.symlinkCount < 0)
  fail("runtime tree provenance is invalid");
let actualRuntimeTree = null;
if (runtimeReceiptIsPresent) {
  try { actualRuntimeTree = completeRuntimeTree(path.dirname(runtimeReceiptPath)); }
  catch { fail("runtime tree cannot be verified"); }
}
if (isPublicSourceExport === runtimeReceiptIsPresent ||
    !exact(manifest, ["deploymentAssets", "files", "provenance", "publicAppcastURL", "publicBase", "releaseTag", "runtime", "schemaVersion", "verification", "workflow"]) ||
    manifest.schemaVersion !== 4 || manifest.publicBase.commit !== "bf0cc8f6343f14498f12932c2ea10fe724b67827" ||
    manifest.publicBase.tree !== "7fbab71f9528ad540e6fcea7621409d7f21d8739" || manifest.releaseTag !== "v0.1.4" ||
    JSON.stringify(manifest.provenance) !== "{\"productArtifactSource\":{\"commit\":\"afc1003370c0d318179b6f640babbe2afcb96462\",\"tree\":\"dcf40a085bd21b99aab965908bb7e1da3154e2b1\"},\"websiteToolingSource\":{\"commit\":\"0f3cb4e08b5c20bbdd8154c9bca921f854f1d70f\",\"overlayReceiptSHA256\":\"01aebf40f33be9bf4f41ea52a77fabf0dd03dbaf79d9e4f80e9c33dc48efae51\",\"tree\":\"b40f2ce4bc77c3a039df7571eb59ffaa93cb22e9\"}}" ||
    manifest.publicAppcastURL !== "https://readysteadyscience.github.io/Rabbisir/appcast.xml" || manifest.workflow.path !== ".github/workflows/pages.yml" ||
    manifest.workflow.ref !== "refs/heads/main" || manifest.workflow.sha256 !== sha(path.join(root, manifest.workflow.path)) ||
    manifest.runtime.contractSHA256 !== sha(path.join(root, "Sources/RabbisirCore/Resources/VendorRuntime/provenance-contract.json")) ||
    !/^[0-9a-f]{64}$/.test(manifest.runtime.receiptSHA256) ||
    (runtimeReceiptIsPresent && manifest.runtime.receiptSHA256 !== sha(runtimeReceiptPath)) ||
    (actualRuntimeTree && JSON.stringify(actualRuntimeTree) !== JSON.stringify(manifest.runtime.tree)) ||
    manifest.verification.appVersionSHA256 !== sha(path.join(root, "Sources/RabbisirCore/App/AppVersion.swift")) ||
    manifest.verification.materializerSHA256 !== sha(path.join(root, "scripts/materialize-pages-assets.mjs")) ||
    manifest.verification.governanceSHA256 !== sha(path.join(root, "scripts/verify-code-review-governance.sh")) ||
    manifest.verification.pagesSHA256 !== sha(path.join(root, "scripts/verify-pages-site.sh")) ||
    manifest.verification.publicRepositorySHA256 !== sha(path.join(root, "scripts/verify-public-repository.sh")) ||
    manifest.verification.downloadsSHA256 !== sha(path.join(root, "site/DOWNLOADS.md"))) {
  fail("Pages integration provenance differs from the reviewed candidate");
}
const expectedFiles = ["appcast.xml","checksums.txt","official-app-release-source.json","official-app-release-source.json.sha256","official-app-releases.json","official-app-releases.json.sha256","release.json"];
if (!Array.isArray(manifest.files) || manifest.files.map((entry) => entry.name).join(",") !== expectedFiles.join(","))
  fail("generated Pages file inventory differs from the reviewed closure");
const deploymentAsset = manifest.deploymentAssets?.[0];
if (!Array.isArray(manifest.deploymentAssets) || manifest.deploymentAssets.length !== 1 ||
    !exact(deploymentAsset, ["name", "sha256", "size", "sourceURL"]) ||
    deploymentAsset.name !== "Rabbisir.dmg" ||
    deploymentAsset.sourceURL !== "https://github.com/readysteadyscience/Rabbisir/releases/download/v0.1.4/Rabbisir-0.1.4-6.dmg" ||
    deploymentAsset.sha256 !== "866917485b24a217c56d63b0419a11e2c731149f39c4ece773202730ade0761e" ||
    deploymentAsset.size !== 96167229)
  fail("generated Pages deployment asset differs from the frozen versioned DMG");
for (const entry of manifest.files) {
  const file = path.join(root, "site", entry.name);
  if (sha(file) !== entry.sha256 || fs.statSync(file).size !== entry.size)
    fail("a generated Pages file differs from its manifest");
}
const expectedOfficialVersion = "Rabbisir 0.1.4";
const expectedReleaseTitles = {
  feature: { en: "Feature update", zh: "功能更新" },
  fix: { en: "Fixes", zh: "修复" },
  optimization: { en: "Optimization", zh: "优化" },
};
if (officialFeed.latest !== expectedOfficialVersion ||
    officialFeed.releases?.[0]?.version !== expectedOfficialVersion ||
    officialFeed.releases?.[0]?.publishedOn !== "2026-08-26" ||
    JSON.stringify(officialFeed.releases?.[0]?.title) !== JSON.stringify(expectedReleaseTitles["fix"]) ||
    officialSourceReceipt.latest !== expectedOfficialVersion ||
    officialSourceReceipt.updatedAt !== officialFeed.updatedAt ||
    officialSourceReceipt.contentReceiptSHA256 !== officialFeed.contentReceiptSHA256)
  fail("official App release feed differs from the frozen ReleaseIdentity and date");
if (!exact(release, ["assets", "build", "displayVersion", "releaseType", "releaseURL", "schemaVersion", "stableDownloadURL", "tag", "version"]) ||
    release.schemaVersion !== 1 || release.version !== "0.1.4" ||
    release.build !== "6" ||
    release.displayVersion !== "v0.1.4" ||
    release.tag !== "v0.1.4" ||
    release.releaseURL !== "https://github.com/readysteadyscience/Rabbisir/releases/tag/v0.1.4" ||
    release.releaseType !== "fix" ||
    release.stableDownloadURL !== "https://readysteadyscience.github.io/Rabbisir/Rabbisir.dmg" ||
    JSON.stringify(release.assets) !== "[{\"name\":\"Rabbisir-0.1.4-6.zip\",\"sha256\":\"ee8f4dacc741da9c3f63edeecb4e0e13d0f0cc2d6322b214d21ec1a1398747b4\",\"size\":133310314,\"url\":\"https://github.com/readysteadyscience/Rabbisir/releases/download/v0.1.4/Rabbisir-0.1.4-6.zip\"},{\"name\":\"Rabbisir-0.1.4-6.dmg\",\"sha256\":\"866917485b24a217c56d63b0419a11e2c731149f39c4ece773202730ade0761e\",\"size\":96167229,\"url\":\"https://github.com/readysteadyscience/Rabbisir/releases/download/v0.1.4/Rabbisir-0.1.4-6.dmg\"},{\"name\":\"PublicReleaseManifest.json\",\"sha256\":\"f77d622073a1974087a7b22716213cbb25e7bc0ff05bbbdfd3178346e2842543\",\"size\":1219,\"url\":\"https://github.com/readysteadyscience/Rabbisir/releases/download/v0.1.4/PublicReleaseManifest.json\"},{\"name\":\"PublicReleaseManifest.json.sha256\",\"sha256\":\"5698864d87c6a78ceea6093fdb840b849dce197bdbb7d30658663c838fc6496d\",\"size\":93,\"url\":\"https://github.com/readysteadyscience/Rabbisir/releases/download/v0.1.4/PublicReleaseManifest.json.sha256\"}]")
  fail("release metadata differs from the frozen plan");
const checksumLines = fs.readFileSync(path.join(root, "site/checksums.txt"), "utf8").trim().split("\n").sort();
const releaseDiskImage = release.assets.find((asset) => asset.name === "Rabbisir-0.1.4-6.dmg");
const stableDiskImage = path.join(root, "site/Rabbisir.dmg");
if (!releaseDiskImage || fs.existsSync(stableDiskImage) !== deployArtifact)
  fail("stable disk image presence differs from source or deployment-capsule mode");
if (deployArtifact && (sha(stableDiskImage) !== releaseDiskImage.sha256 ||
    fs.statSync(stableDiskImage).size !== releaseDiskImage.size))
  fail("materialized stable disk image differs from the frozen versioned disk image");
const expectedChecksums = [
  ...release.assets.map((asset) => asset.sha256 + "  " + asset.name),
  releaseDiskImage.sha256 + "  Rabbisir.dmg",
].sort();
if (JSON.stringify(checksumLines) !== JSON.stringify(expectedChecksums)) fail("checksums and release assets differ");
const appcast = fs.readFileSync(path.join(root, "site/appcast.xml"), "utf8");
const appcastWithoutComments = appcast.replace(/<!--[\s\S]*?-->/g, "");
const sparkleMetadataValues = (name) => {
  const values = [];
  const elementPattern = new RegExp(
    "<sparkle:" + name + "(?:\\s[^>]*)?>([^<]*)</sparkle:" + name + ">",
    "g"
  );
  const enclosureAttributePattern = new RegExp(
    "<enclosure\\b[^>]*\\ssparkle:" + name + "=(?:\\\"([^\\\"]*)\\\"|'([^']*)')[^>]*>",
    "g"
  );
  for (const match of appcastWithoutComments.matchAll(elementPattern)) values.push(match[1].trim());
  for (const match of appcastWithoutComments.matchAll(enclosureAttributePattern))
    values.push(match[1] ?? match[2]);
  return values;
};
const hasExactSparkleMetadata = (name, expected) => {
  const values = sparkleMetadataValues(name);
  return values.length > 0 && values.every((value) => value === expected);
};
const bridgeEnclosureURL = "https://github.com/readysteadyscience/Rabbisir-Releases/releases/download/v0.2.0/Rabbisir-0.2.0-7.zip";
const bridgeEnclosures = [...appcastWithoutComments.matchAll(/<enclosure\b([^>]*)\/?\s*>/g)];
if (sha(path.join(root, "site/appcast.xml")) !== "6fe6728e9e6ebc804b72a789ea336b72f407144f75260ef40b1b08c62c63d8d6" ||
    bridgeEnclosures.length !== 1 || !appcast.includes("production") ||
    !bridgeEnclosures[0][1].includes(`url="${bridgeEnclosureURL}"`) ||
    !bridgeEnclosures[0][1].includes('length="133591473"') ||
    !hasExactSparkleMetadata("shortVersionString", "0.2.0") ||
    !hasExactSparkleMetadata("version", "7"))
  fail("legacy Appcast bridge differs from the signed v0.2.0 successor");
const downloads = fs.readFileSync(path.join(root, "site/DOWNLOADS.md"), "utf8");
if (/No official Rabbisir installation asset is available|目前尚无可用的 Rabbisir 官方安装包/.test(downloads) ||
    !downloads.includes(release.releaseURL) || !downloads.includes(release.stableDownloadURL) ||
    !downloads.includes(releaseDiskImage.sha256) || !downloads.includes(String(releaseDiskImage.size)) ||
    !release.assets.filter((asset) => asset.name === "Rabbisir-0.1.4-6.zip")
      .every((asset) => downloads.includes(asset.url) && downloads.includes(asset.sha256) && downloads.includes(String(asset.size))) ||
    !downloads.includes("Official installation acceptance is not yet complete") || !downloads.includes("正式安装验收尚未完成"))
  fail("download status does not describe the frozen assets and pending installation acceptance");
NODE
echo "verify-pages-site: release-aware public base and manual Pages packaging passed"
