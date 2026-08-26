#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

scripts/verify-public-delivery-boundary.sh "$repository_root" >/dev/null

suite_root=$(mktemp -d "${TMPDIR:-/tmp}/rabbisir-public-delivery-boundary.XXXXXX")
cleanup() {
  if [ -d "$suite_root" ]; then
    find "$suite_root" -depth -delete
  fi
}
trap cleanup EXIT HUP INT TERM

make_fixture() {
  name=$1
  fixture="$suite_root/$name"
  mkdir -p "$fixture/docs" "$fixture/site" "$fixture/.github"
  cp README.md README.zh.md "$fixture/"
  cp docs/DEVELOPMENT.md docs/PUBLIC_SOURCE_POLICY.md docs/RELEASING.md \
    docs/DELIVERY_WORKFLOW.md "$fixture/docs/"
  cp site/index.html site/download.html "$fixture/site/"
  cp -R scripts "$fixture/scripts"
  cp -R .github/workflows "$fixture/.github/workflows"
  printf '%s\n' "$fixture"
}

expect_failure() {
  label=$1
  fixture=$2
  if "$fixture/scripts/verify-public-delivery-boundary.sh" "$fixture" >/dev/null 2>&1; then
    echo "test-public-delivery-boundary: negative fixture passed: $label" >&2
    exit 1
  fi
}

baseline=$(make_fixture baseline)
"$baseline/scripts/verify-public-delivery-boundary.sh" "$baseline" >/dev/null

official_release=$(make_fixture official-release)
printf '%s\n' '#!/bin/sh' \
  'gh release create v9.0.0 Rabbisir.dmg --repo readysteadyscience/Rabbisir-Releases' \
  >"$official_release/scripts/publish-official.sh"
expect_failure "official Release creation" "$official_release"

distribution_push=$(make_fixture distribution-push)
printf '%s\n' '#!/bin/sh' \
  'git -C . push https://github.com/readysteadyscience/Rabbisir-Releases.git HEAD:main' \
  >"$distribution_push/scripts/push-distribution.sh"
expect_failure "distribution repository push" "$distribution_push"

implicit_post=$(make_fixture implicit-post)
printf '%s\n' '#!/bin/sh' \
  'gh api repos/readysteadyscience/Rabbisir-Releases/releases -f tag_name=v9.0.0' \
  >"$implicit_post/scripts/create-release-through-api.sh"
expect_failure "implicit gh api POST" "$implicit_post"

curl_post=$(make_fixture curl-post)
printf '%s\n' '#!/bin/sh' \
  'curl -d tag_name=v9.0.0 https://api.github.com/repos/readysteadyscience/Rabbisir-Releases/releases' \
  >"$curl_post/scripts/create-release-through-curl.sh"
expect_failure "curl data POST" "$curl_post"

official_assets=$(make_fixture official-assets)
printf '%s\n' '#!/bin/sh' \
  'gh release upload open-v9.0.0 Rabbisir.dmg appcast.xml PublicReleaseManifest.json checksums.txt' \
  >"$official_assets/scripts/upload-official-assets.sh"
expect_failure "official asset upload" "$official_assets"

content_write=$(make_fixture content-write)
printf '\npermissions:\n  contents: write\n' >>"$content_write/.github/workflows/ci.yml"
expect_failure "workflow content-write permission" "$content_write"

write_all=$(make_fixture write-all)
printf '\npermissions: write-all\n' >>"$write_all/.github/workflows/ci.yml"
expect_failure "workflow write-all permission" "$write_all"

flow_write=$(make_fixture flow-write)
printf '\npermissions: { contents: write }\n' >>"$flow_write/.github/workflows/ci.yml"
expect_failure "workflow flow-mapping content write" "$flow_write"

quoted_write=$(make_fixture quoted-write)
printf '\npermissions: { contents: "write" }\n' >>"$quoted_write/.github/workflows/ci.yml"
expect_failure "workflow quoted content write" "$quoted_write"

secret_token=$(make_fixture secret-token)
printf '\nenv:\n  GH_TOKEN: ${{ secrets.RELEASE_TOKEN }}\n' >>"$secret_token/.github/workflows/ci.yml"
expect_failure "workflow release secret" "$secret_token"

wrong_latest=$(make_fixture wrong-latest)
sed 's#readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg#readysteadyscience/Rabbisir/releases/latest/download/Rabbisir.dmg#g' \
  "$wrong_latest/README.md" >"$wrong_latest/README.md.next"
mv "$wrong_latest/README.md.next" "$wrong_latest/README.md"
expect_failure "Open repository used as official latest" "$wrong_latest"

wrong_button=$(make_fixture wrong-button)
sed 's#href="https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg"#href="https://github.com/readysteadyscience/Rabbisir/releases/download/open-v9.0.0/Rabbisir-Open.dmg"#' \
  "$wrong_button/site/index.html" >"$wrong_button/site/index.html.next"
mv "$wrong_button/site/index.html.next" "$wrong_button/site/index.html"
printf '\n<!-- %s -->\n' \
  'https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg' \
  >>"$wrong_button/site/index.html"
expect_failure "homepage primary download redirected to Open" "$wrong_button"

wrong_tag=$(make_fixture wrong-tag)
sed 's/`open-vX.Y.Z`/`vX.Y.Z`/g' \
  "$wrong_tag/docs/PUBLIC_SOURCE_POLICY.md" >"$wrong_tag/docs/PUBLIC_SOURCE_POLICY.md.next"
mv "$wrong_tag/docs/PUBLIC_SOURCE_POLICY.md.next" "$wrong_tag/docs/PUBLIC_SOURCE_POLICY.md"
expect_failure "official-style Open tag namespace" "$wrong_tag"

release_action=$(make_fixture release-action)
printf '\n      - uses: softprops/action-gh-release@v2\n' \
  >>"$release_action/.github/workflows/ci.yml"
expect_failure "third-party GitHub Release action" "$release_action"

github_script=$(make_fixture github-script)
printf '%s\n' \
  'name: Invalid formal Release writer' \
  'on: workflow_dispatch' \
  'permissions: {"contents": write}' \
  'jobs:' \
  '  publish:' \
  '    runs-on: ubuntu-latest' \
  '    steps:' \
  '      - uses: actions/github-script@v7' \
  '        with:' \
  '          github-token: ${{ github['"'"'token'"'"'] }}' \
  '          script: |' \
  "            await github.request('POST /repos/{owner}/{repo}/releases', { tag_name: 'v9.0.0' })" \
  >"$github_script/.github/workflows/ci.yml"
expect_failure "GitHub Script formal Release writer" "$github_script"

anchored_write=$(make_fixture anchored-write)
printf '%s\n' \
  'name: Invalid anchored permissions' \
  'on: workflow_dispatch' \
  'permissions: &release_permissions {"contents": write}' \
  'jobs:' \
  '  verify:' \
  '    runs-on: ubuntu-latest' \
  '    steps:' \
  '      - run: true' \
  >"$anchored_write/.github/workflows/ci.yml"
expect_failure "anchored workflow content write" "$anchored_write"

tagged_write=$(make_fixture tagged-write)
printf '%s\n' \
  'name: Invalid tagged permissions' \
  'on: workflow_dispatch' \
  'permissions:' \
  '  contents: !!str write' \
  'jobs: {verify: {runs-on: ubuntu-latest, steps: []}}' \
  >"$tagged_write/.github/workflows/ci.yml"
expect_failure "explicit-tag workflow content write" "$tagged_write"

block_scalar_write=$(make_fixture block-scalar-write)
printf '%s\n' \
  'name: Invalid block-scalar permissions' \
  'on: workflow_dispatch' \
  'permissions:' \
  '  contents: >-' \
  '    write' \
  'jobs: {verify: {runs-on: ubuntu-latest, steps: []}}' \
  >"$block_scalar_write/.github/workflows/ci.yml"
expect_failure "block-scalar workflow content write" "$block_scalar_write"

escaped_write=$(make_fixture escaped-write)
printf '%s\n' \
  'name: Invalid escaped permissions' \
  'on: workflow_dispatch' \
  'permissions:' \
  '  contents: "wri\u0074e"' \
  'jobs: {verify: {runs-on: ubuntu-latest, steps: []}}' \
  >"$escaped_write/.github/workflows/ci.yml"
expect_failure "escaped workflow content write" "$escaped_write"

explicit_mapping_write=$(make_fixture explicit-mapping-write)
printf '%s\n' \
  'name: Invalid explicit-mapping writer' \
  'on: workflow_dispatch' \
  'permissions:' \
  '  contents: read' \
  'jobs:' \
  '  publish:' \
  '    runs-on: ubuntu-latest' \
  '    ? permissions' \
  '    :' \
  '      contents: write' \
  '    steps:' \
  '      - uses: actions/checkout@11d5960a326750d5838078e36cf38b85af677262' \
  '      - run: |' \
  '          git ta""g v9.0.0' \
  '          git pu""sh origin v9.0.0' \
  >"$explicit_mapping_write/.github/workflows/ci.yml"
expect_failure "explicit-mapping workflow writer" "$explicit_mapping_write"

inherited_secrets=$(make_fixture inherited-secrets)
printf '%s\n' \
  'name: Invalid inherited secrets' \
  'on: workflow_dispatch' \
  'permissions:' \
  '  contents: read' \
  'jobs:' \
  '  delegated:' \
  '    uses: owner/repository/.github/workflows/publish.yml@0123456789012345678901234567890123456789' \
  '    secrets: inherit' \
  >"$inherited_secrets/.github/workflows/ci.yml"
expect_failure "workflow inherited secrets" "$inherited_secrets"

echo "test-public-delivery-boundary: real checkout, baseline, and twenty-one fail-closed fixtures passed"
