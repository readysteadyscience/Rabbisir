# Public release information

The public repository provides the source and validation path for `Rabbisir Open`. Official Rabbisir
downloads are published through the project website and GitHub Releases; the operator tooling and
configuration used to produce those downloads are not part of this source tree.

## Public source validation

From the exact source under review, run:

```sh
scripts/verify-documentation-links.sh
scripts/verify-public-repository.sh
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
scripts/build-fresh-public-product.sh RabbisirOpen debug
scripts/test-public-swiftpm.sh
scripts/build-and-run-open.sh --verify-first-run
```

Exercise affected public workflows in the temporary `Rabbisir Open` build and record the source
revision, commands, results, known limits, compatibility impact, and rollback-relevant data behavior.
A failed required check or unresolved review finding is not release-ready evidence.

## Published release

The first public release is `Rabbisir 0.1.0 · r1.00`; its Apple short version is `0.1.0` and build
number is `1`. The official download links, filenames, sizes, and SHA-256 values are recorded in
[`../site/DOWNLOADS.md`](../site/DOWNLOADS.md). Public version transitions follow
[`VERSIONING.md`](VERSIONING.md).

Contributor builds are unsigned local `Rabbisir Open` builds and are not official distributions.
Do not publish generated App packages or claim that local validation produced the official App.
