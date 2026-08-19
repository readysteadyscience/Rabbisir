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
  site/index.html \
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
  site/release.json \
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
  'PagesSourceManifest.json' \
  'UPSTREAM.md' \
  'appcast.xml' \
  'assets/rabbisir/discord-symbol-blurple.svg' \
  'assets/rabbisir/rabbisir-mark-dark.png' \
  'assets/rabbisir/x-logo-white-v1.svg' \
  'assets/rabbisir/yelzap-avatar.png' \
  'assets/rabbisir/yelzap-wechat-qr-v1.png' \
  'checksums.txt' \
  'index.html' \
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

verify_sha256 c024ce612271d548157d230e2fb087d0c01a95d5ec60658d98f1d538b1cd676b \
  site/index.html
verify_sha256 f3a44a62c2a1eb3ff97c321bf9e3cc54d3c50fb4252bebd8c04fbabfe8417095 \
  site/styles.css
verify_sha256 fe5fbcfe213e9a0d487b6f84fbf8beb6db0d6e10525d3625ddb869d19aca0ba6 \
  site/site.js
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
verify_sha256 37d0489163b2aca4a788ed644fe90ba23c8d787b4b560ebc9ff2693ae7f740a5 \
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
if rg -n -i "$private_site_pattern" site/index.html site/styles.css site/site.js site/assets site/DOWNLOADS.md site/UPSTREAM.md site/LICENSE
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
html_path = site_root / "index.html"
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
    ("icon", "assets/rabbisir/rabbisir-mark-dark.png"),
    ("stylesheet", "styles.css"),
}
if set(parser.resources) != expected_resources:
    failures.append("the reviewed local icon or stylesheet reference changed")
if parser.scripts != [("site.js?v=20260815-wechat2", True)]:
    failures.append("the reviewed deferred local script reference changed")
if parser.images != [
    "assets/rabbisir/rabbisir-mark-dark.png",
    "assets/rabbisir/discord-symbol-blurple.svg",
    "assets/rabbisir/rabbisir-mark-dark.png",
    "assets/rabbisir/yelzap-avatar.png",
    "assets/rabbisir/x-logo-white-v1.svg",
    "assets/rabbisir/yelzap-wechat-qr-v1.png",
]:
    failures.append("the reviewed local image closure changed")

expected_hrefs = {
    "#top",
    "https://github.com/deepseek-ai/deepseek-harness",
    "https://discord.gg/gT4TUHGkQm",
    "https://x.com/YelZap1987",
    "DOWNLOADS.md",
    "UPSTREAM.md",
    "LICENSE",
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

if rg -n '@import|url\(' site/styles.css; then
  fail "the reviewed stylesheet unexpectedly loads another resource"
fi
if rg -n 'fetch\(|XMLHttpRequest|WebSocket|EventSource|sendBeacon|document\.cookie|window\.open|location\.|eval\(|new Function' \
  site/site.js
then
  fail "the reviewed interaction script gained a network, cookie, navigation, or dynamic-code path"
fi
grep -q '<meta name="color-scheme" content="dark">' site/index.html \
  || fail "the final fixed-dark document metadata is missing"
grep -q '<meta name="theme-color" content="#080a0d">' site/index.html \
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
if rg -n -i 'deepseek[^<]*(logo|mark|avatar)|deepseek-(logo|mark|avatar)|wechat[^<]*(logo|mark)|wechat-(logo|mark)' \
  site/index.html site/assets
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
const runtimeReceiptIsPresent = fs.existsSync(runtimeReceiptPath);
let manifest, release;
try {
  manifest = JSON.parse(fs.readFileSync(manifestPath, "utf8"));
  release = JSON.parse(fs.readFileSync(path.join(root, "site/release.json"), "utf8"));
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
    !exact(manifest, ["files", "publicAppcastURL", "publicBase", "releaseTag", "runtime", "schemaVersion", "verification", "workflow"]) ||
    manifest.schemaVersion !== 2 || manifest.publicBase.commit !== "d8e7d659888a5894e4e41b1817da5b60d6dc44f9" ||
    manifest.publicBase.tree !== "33368c038608f1518f263bf4aa539ecde939b3d8" || manifest.releaseTag !== "v0.1.0-r1.00" ||
    manifest.publicAppcastURL !== "https://readysteadyscience.github.io/Rabbisir/appcast.xml" || manifest.workflow.path !== ".github/workflows/pages.yml" ||
    manifest.workflow.ref !== "refs/heads/main" || manifest.workflow.sha256 !== sha(path.join(root, manifest.workflow.path)) ||
    manifest.runtime.contractSHA256 !== sha(path.join(root, "Sources/RabbisirCore/Resources/VendorRuntime/provenance-contract.json")) ||
    !/^[0-9a-f]{64}$/.test(manifest.runtime.receiptSHA256) ||
    (runtimeReceiptIsPresent && manifest.runtime.receiptSHA256 !== sha(runtimeReceiptPath)) ||
    (actualRuntimeTree && JSON.stringify(actualRuntimeTree) !== JSON.stringify(manifest.runtime.tree)) ||
    manifest.verification.governanceSHA256 !== sha(path.join(root, "scripts/verify-code-review-governance.sh")) ||
    manifest.verification.pagesSHA256 !== sha(path.join(root, "scripts/verify-pages-site.sh")) ||
    manifest.verification.publicRepositorySHA256 !== sha(path.join(root, "scripts/verify-public-repository.sh")) ||
    manifest.verification.downloadsSHA256 !== sha(path.join(root, "site/DOWNLOADS.md"))) {
  fail("Pages integration provenance differs from the reviewed candidate");
}
const expectedFiles = ["appcast.xml", "checksums.txt", "release.json"];
if (!Array.isArray(manifest.files) || manifest.files.map((entry) => entry.name).join(",") !== expectedFiles.join(","))
  fail("generated Pages file inventory differs from the reviewed closure");
for (const entry of manifest.files) {
  const file = path.join(root, "site", entry.name);
  if (sha(file) !== entry.sha256 || fs.statSync(file).size !== entry.size)
    fail("a generated Pages file differs from its manifest");
}
if (!exact(release, ["assets", "build", "releaseURL", "schemaVersion", "tag", "version"]) ||
    release.schemaVersion !== 1 || release.version !== "0.1.0" || release.build !== "1" ||
    release.tag !== "v0.1.0-r1.00" || release.releaseURL !== "https://github.com/readysteadyscience/Rabbisir/releases/tag/v0.1.0-r1.00" ||
    !Array.isArray(release.assets) || release.assets.length !== 4) fail("release metadata differs from the frozen plan");
const checksumLines = fs.readFileSync(path.join(root, "site/checksums.txt"), "utf8").trim().split("\n").sort();
const expectedChecksums = release.assets.map((asset) => asset.sha256 + "  " + asset.name).sort();
if (JSON.stringify(checksumLines) !== JSON.stringify(expectedChecksums)) fail("checksums and release assets differ");
const appcast = fs.readFileSync(path.join(root, "site/appcast.xml"), "utf8");
const archive = release.assets.find((asset) => asset.name.endsWith(".zip"));
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
if (!archive || !appcast.includes("production") || !appcast.includes(archive.url) ||
    !hasExactSparkleMetadata("shortVersionString", "0.1.0") ||
    !hasExactSparkleMetadata("version", "1"))
  fail("Appcast semantics differ from the frozen production Release");
const downloads = fs.readFileSync(path.join(root, "site/DOWNLOADS.md"), "utf8");
if (/No official Rabbisir installation asset is available|目前尚无可用的 Rabbisir 官方安装包/.test(downloads) ||
    !downloads.includes(release.releaseURL) || !release.assets.filter((asset) => /\.(dmg|zip)$/.test(asset.name))
      .every((asset) => downloads.includes(asset.url) && downloads.includes(asset.sha256) && downloads.includes(String(asset.size))) ||
    !downloads.includes("Official installation acceptance is not yet complete") || !downloads.includes("正式安装验收尚未完成"))
  fail("download status does not describe the frozen assets and pending installation acceptance");
NODE

echo "verify-pages-site: fixed public base and release Pages integration passed"
