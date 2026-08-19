# Rabbisir

English | [中文](README.zh.md)

Rabbisir is a native macOS workspace for DeepSeek models. SwiftUI and AppKit own the product interface, including the spatial workspace, project and session navigation, conversation stream, composer, settings, document workbench, menus, and accessibility behavior.

Rabbisir is an independent product. It is not affiliated with, sponsored by, or endorsed by DeepSeek. The App uses a compatible snapshot of the MIT-licensed DeepSeek Harness runtime; attribution and compatibility records are preserved in [`Legal/`](Legal/README.md).

## Repository scope

This repository contains only the Rabbisir macOS application and the files required to build and test it:

- the SwiftPM App and native test suite;
- Rabbisir-owned brand resources;
- a small launcher, manifest, and reproducible provenance contract for the App-private vendor runtime;
- public development, architecture, privacy, and legal documentation.

It does not contain a standalone Web app, CLI product, documentation website, upstream examples, upstream development tooling, or internal product plans. Generated Node and runtime payloads are staged from a separate compatible upstream checkout and are excluded from Git.

The public package is the reproducible open-source product flavor. It includes creator attribution,
the Discord community destination, public Help, licensing, and GitHub feedback links. It does not
embed an in-app updater, voluntary-contribution surface, or theme/wallpaper placeholders. Any
official-distribution additions are supplied from a separately receipted private overlay; the guarded
production entrypoint fails closed when that overlay or its required configuration is absent.

## Requirements

- macOS 14 or later.
- Xcode at `/Applications/Xcode.app`.
- Staged vendor runtime resources for launching the full App.

## Build and test

```sh
scripts/build-fresh-public-product.sh RabbisirOpen debug
scripts/test-public-swiftpm.sh
scripts/build-and-run-open.sh --verify-first-run
```

The public package exposes only `Rabbisir Open`. The build-and-run helper creates an unsigned App in
a dedicated temporary directory, gives it the independent bundle ID `com.rabbisir.desktop.open`,
isolates preferences and runtime data, verifies first-run readiness, and removes the temporary App and
data when it exits. No built App, DMG, ZIP, or other installable artifact belongs in the Git tree.
Clean-checkout CI verifies the source boundary and formatting. Full App validation uses
`scripts/verify-public-candidate.sh --verify-first-run` only after the documented, receipted runtime
input has been staged; the runtime payload itself remains outside Git.

Maintainers first rebuild a receipted payload from the exact official source revision, then stage it:

```sh
scripts/rebuild-vendor-runtime.sh \
  <official-upstream-checkout> \
  <node-distribution-root> \
  <verified-pnpm-archive> \
  <new-output-root>
scripts/stage-vendor-runtime.sh <receipted-runtime-carrier-root> <node-distribution-root>
```

The public [runtime provenance contract](RuntimeProvenance/README.md) pins and verifies the source,
patches, toolchain, and canonical output inventory. Users never start a localhost service or use a Web
entry point.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Development](docs/DEVELOPMENT.md)
- [Contributing](CONTRIBUTING.md)
- [Code review and quality governance](docs/CODE_REVIEW.md)
- [Release process](docs/RELEASING.md)
- [Versioning policy](docs/VERSIONING.md)
- [Changelog](CHANGELOG.md)
- [Privacy and local data](docs/PRIVACY.md)
- [Asset ownership](ASSETS.md)
- [Upstream compatibility record](Legal/UPSTREAM.md)
- [Runtime provenance](RuntimeProvenance/README.md)

Local build commands perform no external repository or distribution operation.
