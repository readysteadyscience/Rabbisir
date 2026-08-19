# Development

## Requirements

- macOS 14 or later.
- Xcode installed at `/Applications/Xcode.app`.
- A compatible deployed vendor runtime and pinned Node distribution when restaging runtime resources.

## Rebuild and stage the private runtime

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

## Delivery workflow

The contributor-facing gates below end at a reviewable Rabbisir Open source candidate. The authoritative formal
release checklist, evidence record, authorization boundary, and rollback procedure are in
[`RELEASING.md`](RELEASING.md).
The seven-stage ownership and public/private export boundary are defined in
[`DELIVERY_WORKFLOW.md`](DELIVERY_WORKFLOW.md).
Public release versions are governed separately by [`VERSIONING.md`](VERSIONING.md); Open and local
build identifiers do not allocate a public release version.
Independent review and quality-governance requirements are defined in
[`CODE_REVIEW.md`](CODE_REVIEW.md).

Every change moves through the following gates in order. Passing one gate does not authorize the next.
External contributors normally complete gates 1 through 4 and submit the resulting source and
verification evidence for review. Repository access and successful Open validation do not grant
authority to perform the independent review, release, or external-operation gates.

1. **Requirement** — record the requested behavior, acceptance evidence, affected data, and prohibited external actions.
2. **Isolated change** — preserve unrelated worktree state and modify only Rabbisir source. Upstream checkouts remain read-only inputs.
3. **Open build and tests** — build the `RabbisirOpen` product and run the native tests and repository checks below.
4. **Open on-device acceptance** — launch the unsigned temporary `Rabbisir Open.app` through the public script and exercise the affected public workflow on the target Mac.
5. **Private official-app review** — a read-only reviewer applies [`CODE_REVIEW.md`](CODE_REVIEW.md) to the exact private candidate and records `Pass`, `Needs changes`, or `Unverified`.
6. **Repair and independent re-verification** — primary development repairs every accepted finding and the same independent reviewer re-verifies it. An unresolved or unverified finding blocks the next stage.
7. **Private-repository governance** — freeze the reviewed private candidate and prepare its repository transaction. Commit or push needs current, exact user authorization.
8. **Official delivery** — prepare the official-only overlay, signing/notarization, update and installation acceptance; each external action requires its own authorization and result readback.
9. **Public-version review** — independently review a fresh public export for public-code quality, licensing and complete exclusion of private-only material.
10. **Open-source governance** — prepare the approved public export and its repository transaction. Remote creation, visibility changes, commit and push need current, exact user authorization.
11. **Release summary** — only after actual official-release and public-push readback, create a local-only ignored archive; it must never enter a repository or package.
12. **Rollback boundary** — retain the last accepted artifact and data-compatibility boundary. Stop and request direction if rollback would delete or migrate user data, alter credentials, affect production business state, or require an unapproved external action.

The handoff sequence is a mandatory protocol, not a platform-triggered automation. It cannot execute
external actions, and work is not appended to a currently running task unless the user explicitly
requests an interruption, supplement, or addition.

## Sub agent use

Sub agents are optional and never start automatically. The executing agent first decides whether at
least two independent, clearly bounded subtasks can be verified in parallel without competing for the
same worktree or mutable shared state. Before delegation, it records the task split, each boundary,
model/reasoning rationale, and how results will be merged and verified. The primary agent remains
responsible for integration, conflict checks, final validation, and user reporting.

Do not split a single code change, continuous UI or interaction flow, implementation and testing in
the same worktree, credentials, accounts, permissions, release, deployment, production data, or
another external-state operation merely to create parallel work. Those operations
are sequential by default. Delegation cannot bypass project gates, independent review, release
governance, or explicit user authorization.

Without current step-specific authorization, do not commit or push, operate an official distribution
pipeline, overwrite the production App, change repository visibility, access credentials, or perform
production business operations. Local Open acceptance never implies release authorization.

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

The public repository has no production build, updater, signing, notarization, or publication
entrypoint. Those responsibilities are outside the public source boundary and require a separately
controlled official release process plus exact-action authorization.

## Upstream compatibility work

Keep the official source checkout outside this repository. Compare a requested upstream revision with the baseline in [`Legal/UPSTREAM.md`](../Legal/UPSTREAM.md), update only the compatibility layer and staged runtime, then run the affected native tests and a real App workflow. Do not import upstream application, website, examples, or repository tooling into Rabbisir.
