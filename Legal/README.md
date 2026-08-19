# Legal and upstream attribution

- [`LICENSE.upstream.txt`](LICENSE.upstream.txt) preserves the upstream MIT license.
- [`THIRD_PARTY_NOTICES.upstream.md`](THIRD_PARTY_NOTICES.upstream.md) preserves the dependency notice generated for the compatible upstream baseline.
- [`THIRD_PARTY_NOTICES.testing.md`](THIRD_PARTY_NOTICES.testing.md) records public test-only Swift package dependencies.
- [`UPSTREAM.md`](UPSTREAM.md) records the source repository, compatible revision, runtime boundary, and synchronization procedure.
- [`BRAND_ASSETS.md`](BRAND_ASSETS.md) separates source licensing from product identity and
  third-party trademark use.
- [`ASSET_MANIFEST.sha256`](ASSET_MANIFEST.sha256) pins every public static brand resource.

Generated release bundles must also include the staged Node license and runtime dependency notices produced by `scripts/stage-vendor-runtime.sh`.
