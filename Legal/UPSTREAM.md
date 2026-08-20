# Upstream compatibility record

English | [中文](UPSTREAM.zh.md)

Rabbisir uses source and runtime components from the MIT-licensed [DeepSeek Harness](https://github.com/deepseek-ai/deepseek-harness) project. Rabbisir is independent and is not affiliated with, sponsored by, or endorsed by DeepSeek.

The compatible baseline is upstream commit `47f943859bef60e4160492346772ded9b24f765a`
(tree `f904efab9ef435201d6ba4da88a34d6366568272`), reported by the runtime as
`0.1.0-rc.5`. [`LICENSE.upstream.txt`](LICENSE.upstream.txt) preserves the upstream license, and
[`THIRD_PARTY_NOTICES.upstream.md`](THIRD_PARTY_NOTICES.upstream.md) preserves the dependency notice
generated for that source baseline.

The Rabbisir repository does not include the upstream monorepo. It contains only the native App, its
compatibility bridge, a tracked runtime launcher and manifest, and the auditable patch set and build
contract in [`RuntimeProvenance`](../RuntimeProvenance/README.md). Generated runtime payloads remain
outside Git. The official source checkout used for comparison or restaging must live in a separate
directory or repository.

Compatibility requires upstream package identifiers, RPC methods, event names, settings namespaces, durable IDs, wire fields, and stored data formats to remain unchanged. Rabbisir-owned files, Swift types, UI, diagnostics, scripts, and logs use Rabbisir or neutral runtime terminology.

To update the baseline, maintainers compare a requested upstream revision in the separate checkout,
refresh the tracked compatibility patches and provenance contract, rebuild with
`scripts/rebuild-vendor-runtime.sh`, stage the verified receipt with
`scripts/stage-vendor-runtime.sh`, and run the native tests plus real App workflows. An upstream
update appears in a published Rabbisir version only after compatibility review and validation.
