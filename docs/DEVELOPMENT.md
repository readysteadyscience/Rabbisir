# Development

## Requirements

- macOS 14 or later.
- Xcode installed at `/Applications/Xcode.app`.
- A compatible deployed vendor runtime and pinned Node distribution when restaging runtime resources.

## Rebuild and stage the compatibility runtime

Runtime inputs come from a separate official upstream checkout and the official Node distribution
pinned by [`RuntimeProvenance/contract.json`](../RuntimeProvenance/contract.json). Neither rebuild nor
staging downloads the upstream repository or Node distribution. The rebuild verifies the official
remote, exact commit and tree, patch and lockfile digests, Node binary, deterministic file inventory,
and native projection:

```sh
scripts/rebuild-vendor-runtime.sh \
  <official-upstream-checkout> \
  <node-distribution-root> \
  <verified-pnpm-archive> \
  <new-output-root>
```

The output path must not exist. A successful output contains a provenance receipt and can then be
staged:

```sh
scripts/stage-vendor-runtime.sh <receipted-runtime-carrier-root> <node-distribution-root>
```

Staging refuses an unreceipted or modified payload, including a manifest with an unknown or changed
field, before changing App resources. It then verifies the staged copy again and writes only
generated files ignored by Git. See
[`RuntimeProvenance/README.md`](../RuntimeProvenance/README.md) for the complete, reviewable contract.

## Public contribution workflow

Public-source changes follow [`DELIVERY_WORKFLOW.md`](DELIVERY_WORKFLOW.md) and the review standard in
[`CODE_REVIEW.md`](CODE_REVIEW.md). Public release versions follow
[`VERSIONING.md`](VERSIONING.md); contributor and local build identifiers do not allocate a public
release version.

1. **Requirement** — record the requested behavior, acceptance evidence, and affected data.
2. **Isolated change** — preserve unrelated worktree state and modify only public Rabbisir source.
   Upstream checkouts remain read-only inputs.
3. **Open build and tests** — build the `RabbisirOpen` product and run the repository and native tests
   below.
4. **Open on-device acceptance** — launch the unsigned temporary `Rabbisir Open.app` and exercise the
   affected public workflow on the target Mac.
5. **Pull request and review** — submit the exact scope and evidence. A maintainer records `Pass`,
   `Needs changes`, or `Unverified`; accepted repairs receive targeted re-verification before merge.

## Rabbisir Open build and test

```sh
scripts/verify-public-repository.sh
scripts/test-runtime-provenance.sh
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
scripts/build-fresh-public-product.sh RabbisirOpen debug
scripts/test-public-swiftpm.sh
```

These helpers use controlled SwiftPM scratch directories and verify every public Rabbisir resource
bundle they generate. Direct `swift build` and `swift test` are not project verification paths
because SwiftPM can otherwise reuse a stale derived resource bundle.

Build an unsigned temporary Open `.app`, launch it with an isolated data home, and verify that the
first-run configuration surface becomes ready:

```sh
scripts/build-and-run-open.sh --verify-first-run
```

The helper never writes to `dist/`, never installs an App, and never reuses official App data. Its
bundle ID is `com.rabbisir.desktop.open`, its display name is `Rabbisir Open`, its managed runtime
component is `Rabbisir Open/Runtime`, and its complete acceptance home remains below the temporary
directory. The App bundle and isolated preferences/runtime data are removed when the helper exits.

The public repository has no official distribution entrypoint. Published official downloads use the
permanent
[`Rabbisir-Releases` latest DMG](https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg);
contributor builds remain local `Rabbisir Open` builds. The tracked `site/DOWNLOADS.md` file is a
historical website migration snapshot, not the current download authority. See
[`PUBLIC_SOURCE_POLICY.md`](PUBLIC_SOURCE_POLICY.md) for the repository role boundary.

## Upstream compatibility work

Keep the official source checkout outside this repository. Compare a requested upstream revision with the baseline in [`Legal/UPSTREAM.md`](../Legal/UPSTREAM.md), update only the compatibility layer and staged runtime, then run the affected native tests and a real App workflow. Do not import upstream application, website, examples, or repository tooling into Rabbisir.
