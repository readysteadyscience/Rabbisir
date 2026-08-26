# Public release information

This repository provides the source and validation path for `Rabbisir Open`, community material, and
the reviewed website. Official Rabbisir App distribution is owned by the separate public
[`readysteadyscience/Rabbisir-Releases`](https://github.com/readysteadyscience/Rabbisir-Releases)
repository. The operator tooling and configuration used to produce official downloads are not part of
this source tree.

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

### Official Rabbisir App

The official website presents release information from the read-only public data in the distribution
repository. The permanent installer entry is:

<https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg>

This source repository must not create official App `vX.Y.Z` tags or Releases, upload
`Rabbisir.dmg`, publish official Appcast or release manifests/checksums, or write to the distribution
repository. Historical release-style tags and Releases in this repository remain unchanged as
compatibility records; they are not the authority for future official App publication.

## Rabbisir Open milestones

An explicitly authorized Open milestone uses an `open-vX.Y.Z` tag. If an Open-specific Release is
needed, it must identify Rabbisir Open in its tag, title, text, and asset names and must not appear as
the official App's latest Release. Generated Apps, DMGs, ZIPs, and symbol bundles never enter the Git
source tree.

Contributor builds are unsigned local `Rabbisir Open` builds and are not official distributions.
Do not publish generated App packages or claim that local validation produced the official App.
See [`PUBLIC_SOURCE_POLICY.md`](PUBLIC_SOURCE_POLICY.md) for the complete repository role contract.
