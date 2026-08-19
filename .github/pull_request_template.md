## Summary

- What problem does this pull request solve?
- Which Issue does it address?

## Scope and risk

- User-visible behavior changed:
- Compatibility, privacy, accessibility, or data impact:
- Explicitly out of scope:
- Rollback approach:

## Validation

- [ ] `scripts/verify-documentation-links.sh`
- [ ] `scripts/verify-public-repository.sh`
- [ ] `xcrun swift-format lint --strict --recursive Package.swift Sources Tests`
- [ ] `scripts/build-fresh-public-product.sh RabbisirOpen debug`
- [ ] `scripts/test-public-swiftpm.sh`
- [ ] `scripts/build-and-run-open.sh --verify-first-run` when startup, resources, windows, or runtime behavior changed
- [ ] Relevant Rabbisir Open workflow exercised manually, or reason it was not required is stated below

Validation evidence and exceptions:

## Maintainer review

- Review conclusion: `Pass` / `Needs changes` / `Unverified`
- Review evidence, findings, and severity:
- Repair and independent re-verification evidence, if applicable:
- Review-to-release handoff: reviewed scope, evidence, uncovered risks, or `Not seeking release`

A completed CI run is not, by itself, a maintainer review conclusion. See
[`docs/CODE_REVIEW.md`](../docs/CODE_REVIEW.md).

## Public-source checklist

- [ ] No credentials, user data, personal paths, private service details, screenshots, task transcripts, or unpublished plans are included.
- [ ] Generated vendor runtime payloads remain excluded from Git.
- [ ] Upstream protocol identifiers, licenses, notices, and attribution remain compatible.
- [ ] Any formal-release version change has an authorized transition and passes `scripts/verify-release-version.sh`.
- [ ] This pull request does not claim or perform a production release.
