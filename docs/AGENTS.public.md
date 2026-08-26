# Rabbisir public-source development rules

Rabbisir is a native macOS application. Keep user-visible UI in SwiftUI or AppKit; the staged vendor
runtime is an App-owned compatibility component, not a second product surface.

- Preserve unrelated working-tree changes and keep contributions scoped to the public source tree.
- Use a branch and pull request for contributions. Do not push to protected branches, change
  repository settings, or publish an official distribution from a contributor checkout.
- This repository owns `Rabbisir Open` source, community material, and the reviewed website. Official
  Rabbisir App tags, Releases, installers, Appcast, manifests, and checksums belong only to
  `readysteadyscience/Rabbisir-Releases`; Open milestones use `open-vX.Y.Z` tags.
- Public builds use only the `RabbisirOpen` product. Run
  `scripts/build-and-run-open.sh --verify-first-run` for an unsigned, isolated, temporary App
  acceptance build. Do not commit generated App packages, DMGs, ZIPs, or runtime payloads.
- Keep credentials, user data, personal paths, task transcripts, unpublished plans, and official
  distribution implementation or configuration outside this repository.
- Use `scripts/stage-vendor-runtime.sh` only with inputs that satisfy the tracked provenance contract.
  Generated runtime payloads stay ignored and must pass `scripts/verify-staged-runtime.sh`.
- Run `scripts/test-public-swiftpm.sh` after source changes. Run
  `scripts/build-and-run-open.sh --verify-first-run` when startup, resources, windows, or runtime
  behavior changes. Direct `swift build` and `swift test` are not verification paths because they can
  reuse unreviewed derived resource bundles.
- Keep public documentation current and concise.
- Keep the public website inside the reviewed static `site/` capsule and run
  `scripts/verify-pages-site.sh` after website-source changes.

See [`../CONTRIBUTING.md`](../CONTRIBUTING.md), [`PUBLIC_SOURCE_POLICY.md`](PUBLIC_SOURCE_POLICY.md),
[`DEVELOPMENT.md`](DEVELOPMENT.md), and [`DELIVERY_WORKFLOW.md`](DELIVERY_WORKFLOW.md) for the public
contribution workflow and repository boundary.
