# Contributing to Rabbisir

## Contribution workflow

1. Open or reference an Issue that states the problem, expected behavior, and acceptance evidence.
2. Create a short-lived branch from the current `main`. Do not push directly to `main`.
3. Keep the change small and focused. Separate unrelated fixes into separate pull requests.
4. Add or update tests and public documentation with the implementation.
5. Run the local validation commands below and record the results in the pull request template.
6. Open a pull request, wait for CI, and request maintainer review.
7. Record a maintainer review conclusion: `Pass`, `Needs changes`, or `Unverified`.
8. Resolve review findings and update the branch with the requested validation evidence.
9. A maintainer performs the final merge after required checks, resolved discussions, and a review conclusion.

Repository access, review participation, or a passing CI run does not grant permission to merge,
push to protected branches, or perform a release. Security-sensitive reports should not include
credentials, private data, or exploit details in a public Issue; use the repository's private
security reporting channel when one is configured.

The required review scope, severity model, evidence format, and independent re-verification loop are
defined in [`docs/CODE_REVIEW.md`](docs/CODE_REVIEW.md). A passing local run or CI job alone is not a
maintainer review conclusion and does not make a change releasable.

Every pull request supplies its exact scope and validation evidence for maintainer review. Only a
`Pass` conclusion with reviewed scope, evidence, and uncovered risks may be merged. Official
publication is maintained outside the contributor workflow.

## Development setup

Read [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) before changing the package. The repository is a SwiftPM macOS application; it does not contain a standalone Web app or CLI.

All public-source contributor builds, debugging, automated acceptance, and manual testing use the
isolated `RabbisirOpen` product. `scripts/build-and-run-open.sh` creates an unsigned temporary
`Rabbisir Open.app`; it neither installs an App nor operates the official product line.

## Change requirements

- Keep changes scoped and preserve unrelated work.
- Add or update tests for user-visible behavior, protocol parsing, persistence, window lifecycle, and accessibility changes.
- Keep generated vendor runtime payloads out of Git.
- Preserve upstream licenses, notices, protocol identifiers, and source attribution.
- Do not include credentials, user data, local paths, screenshots, task transcripts, or unpublished product plans.

Before review, run:

```sh
scripts/verify-public-repository.sh
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
scripts/build-fresh-public-product.sh RabbisirOpen debug
scripts/test-public-swiftpm.sh
scripts/build-and-run-open.sh --verify-first-run
```

The build and test helpers use dedicated SwiftPM scratch directories, remove only Rabbisir's exact
default derived resource bundles, and fail if a generated public bundle contains resources outside
the reviewed manifest. Direct `swift build` and `swift test` are not supported project verification
commands because they may reuse stale derived resources.

Successful local validation establishes a reviewable Open source contribution only; it does not make
the resulting build an official Rabbisir distribution. Public release information is in
[`docs/RELEASING.md`](docs/RELEASING.md), and development gates are documented in
[`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md).
