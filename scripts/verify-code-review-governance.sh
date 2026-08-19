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
grep -q 'Never commit, push, publish, sign, notarize, deploy, install,' AGENTS.md \
  || fail "AGENTS.md lacks the external-action authorization boundary"
grep -q 'Public builds use only the `RabbisirOpen` product' AGENTS.md \
  || fail "AGENTS.md lacks the public product boundary"
grep -q 'Pages deployment remains a' AGENTS.md \
  || fail "AGENTS.md lacks the independent Pages deployment boundary"
grep -q 'See `docs/DELIVERY_WORKFLOW.md` for the separation' AGENTS.md \
  || fail "AGENTS.md lacks the delivery-governance reference"
grep -q 'Read-only review boundary' docs/CODE_REVIEW.md \
  || fail "CODE_REVIEW.md lacks the read-only boundary"
grep -q 'Finding severity' docs/CODE_REVIEW.md \
  || fail "CODE_REVIEW.md lacks the severity model"
grep -q 'Review conclusion format' docs/CODE_REVIEW.md \
  || fail "CODE_REVIEW.md lacks the conclusion format"
grep -q 'Mandatory handoff closure' docs/CODE_REVIEW.md \
  || fail "CODE_REVIEW.md lacks the mandatory handoff closure"
grep -q 'maintainer review conclusion' CONTRIBUTING.md \
  || fail "CONTRIBUTING.md lacks the maintainer review requirement"
grep -q 'Private official-app review' docs/DEVELOPMENT.md \
  || fail "DEVELOPMENT.md lacks the private official-app review gate"
grep -q 'Repair and independent re-verification' docs/DEVELOPMENT.md \
  || fail "DEVELOPMENT.md lacks the repair re-verification gate"
grep -q 'Private-repository governance' docs/DEVELOPMENT.md \
  || fail "DEVELOPMENT.md lacks the reviewed-candidate handoff"
grep -q 'handoff sequence is a mandatory protocol' docs/DEVELOPMENT.md \
  || fail "DEVELOPMENT.md lacks the mandatory handoff boundary"
grep -q '## Sub agent use' docs/DEVELOPMENT.md \
  || fail "DEVELOPMENT.md lacks the Sub agent guidance"
grep -q 'unresolved review finding leaves the candidate at `NO-GO`' docs/RELEASING.md \
  || fail "RELEASING.md lacks the unresolved-review release blocker"
grep -q 'Open-source governance accepts a candidate only after the' docs/RELEASING.md \
  || fail "RELEASING.md lacks the reviewed-candidate acceptance gate"
grep -q '^2\. Private official-app review independently reviews that complete candidate\.$' \
  docs/DELIVERY_WORKFLOW.md \
  || fail "DELIVERY_WORKFLOW.md lacks the stage 2 review"
grep -q '^3\. Private-repository governance freezes provenance and prepares the private transaction\.$' \
  docs/DELIVERY_WORKFLOW.md \
  || fail "DELIVERY_WORKFLOW.md lacks the stage 3 handoff"
grep -q '^Findings return to primary development\.' docs/DELIVERY_WORKFLOW.md \
  || fail "DELIVERY_WORKFLOW.md lacks the defect-return loop"
grep -q '^Evidence transfer between stages may be automatic\.' docs/DELIVERY_WORKFLOW.md \
  || fail "DELIVERY_WORKFLOW.md lacks the automatic evidence-transfer boundary"

echo "verify-code-review-governance: seven-stage review requirements are present"
