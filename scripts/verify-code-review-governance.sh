#!/bin/sh
set -eu

repository_root=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
cd "$repository_root"

fail() {
  echo "verify-code-review-governance: $*" >&2
  exit 1
}

test -f AGENTS.md || fail "missing AGENTS.md"
test -f docs/CODE_REVIEW.md || fail "missing docs/CODE_REVIEW.md"
test -f CONTRIBUTING.md || fail "missing CONTRIBUTING.md"
test -f docs/DEVELOPMENT.md || fail "missing docs/DEVELOPMENT.md"
test -f docs/DELIVERY_WORKFLOW.md || fail "missing docs/DELIVERY_WORKFLOW.md"
test -f docs/RELEASING.md || fail "missing docs/RELEASING.md"

grep -q '^# Rabbisir public-source development rules$' AGENTS.md \
  || fail "AGENTS.md lacks the public-source development rules"
grep -q 'Use a branch and pull request for contributions' AGENTS.md \
  || fail "AGENTS.md lacks the public contribution boundary"
grep -q 'Public builds use only the `RabbisirOpen` product' AGENTS.md \
  || fail "AGENTS.md lacks the public product boundary"
grep -q 'distribution implementation or configuration outside this repository' AGENTS.md \
  || fail "AGENTS.md lacks the public distribution boundary"
grep -q 'Read-only review boundary' docs/CODE_REVIEW.md \
  || fail "CODE_REVIEW.md lacks the read-only boundary"
grep -q 'Finding severity' docs/CODE_REVIEW.md \
  || fail "CODE_REVIEW.md lacks the severity model"
grep -q 'Review conclusion format' docs/CODE_REVIEW.md \
  || fail "CODE_REVIEW.md lacks the conclusion format"
grep -q 'Repair and re-verification loop' docs/CODE_REVIEW.md \
  || fail "CODE_REVIEW.md lacks the repair loop"
grep -q 'maintainer review conclusion' CONTRIBUTING.md \
  || fail "CONTRIBUTING.md lacks the maintainer review requirement"
grep -q '## Public contribution workflow' docs/DEVELOPMENT.md \
  || fail "DEVELOPMENT.md lacks the public contribution workflow"
grep -q 'Pull request and review' docs/DEVELOPMENT.md \
  || fail "DEVELOPMENT.md lacks the review gate"
grep -q '^# Public contribution workflow$' docs/DELIVERY_WORKFLOW.md \
  || fail "DELIVERY_WORKFLOW.md lacks the public contribution workflow"
grep -q '^## Public boundary$' docs/DELIVERY_WORKFLOW.md \
  || fail "DELIVERY_WORKFLOW.md lacks the public boundary"
grep -q '^# Public release information$' docs/RELEASING.md \
  || fail "RELEASING.md lacks public release information"
grep -q '^## Published release$' docs/RELEASING.md \
  || fail "RELEASING.md lacks the published release record"

if rg -n -i \
  'seven-stage|private official-app review|private-repository governance|public-version review|open-source governance|Rabbisir｜[1-5]|private candidate|candidate freeze|official-only overlay|release summary records|local-only, ignored archive|step-specific authorization|exact-action authorization|signing/notarization|sign, notarize|stapled.*Gatekeeper' \
  AGENTS.md CONTRIBUTING.md CHANGELOG.md README.md README.zh.md ASSETS.md NOTICE.md \
  docs .github/pull_request_template.md Legal/*.md site/*.md
then
  fail "public documentation contains internal delivery or distribution-process details"
fi

echo "verify-code-review-governance: public contribution and documentation boundaries are present"
