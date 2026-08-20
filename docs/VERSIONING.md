# Versioning policy

This policy governs the public version displayed by a published Rabbisir release. It
does not allocate a public version to a DEV build, local build, candidate, pull request, or CI run.

## Public version format

Every public Rabbisir release uses exactly this format:

```text
<Rabbisir product version> · r<stage>.<two-digit patch>
```

The product version is `RabbisirVersion.displayVersion`. It must exactly equal
`RabbisirVersion.appleShortVersion`, which becomes `CFBundleShortVersionString` in a published
official build. The `r` suffix identifies the Rabbisir release stage and patch; it is release-note
metadata and is not part of Apple's short version.

The DeepSeek Harness compatibility baseline is independent product metadata, not a Rabbisir public
version prefix. The release gate separately requires the vendor-runtime manifest's complete
`upstreamVersion` and `upstreamCommit` to match `RabbisirVersion.upstreamCompatibleVersion` and
`RabbisirVersion.upstreamCompatibleCommit`. It never truncates, normalizes, silently updates, or
substitutes that compatibility baseline.

The confirmed first-release identity is:

```text
Rabbisir release: 0.1.0 · r1.00
Apple short version: 0.1.0
Apple build version: 1
Compatible DeepSeek Harness baseline: 0.1.0-rc.5
Compatible upstream commit: 47f943859bef60e4160492346772ded9b24f765a
```

## Allowed transitions

| Release condition | Allowed next version |
| --- | --- |
| First formal Rabbisir release | `<product version> · r1.00` |
| Small bug fix or narrow maintenance on the same baseline | same stage, patch increases by exactly one: `r1.01` → `r1.02` |
| Explicit new Rabbisir product stage, major capability, or important architecture change on the same baseline | next stage and reset patch: `r1.xx` → `r2.00` |
| Integrated and verified upstream compatibility upgrade | retain the verified Rabbisir product version and reset: `r1.00`; separately record the previous and new upstream version and commit |

The patch is always two digits from `00` through `99`. A maintenance release at `r1.99` cannot
become `r2.00`; that transition is permitted only as an explicitly justified new stage. An upstream
compatibility change cannot retain or increment the previous Rabbisir stage and must identify the
previous compatibility version and commit independently from the public product label.

## Development versions

DEV and local builds use only their existing build and DEV identifiers. They neither consume
nor reserve a public version. Current internal version values are not retroactively reinterpreted as
public release versions.

Public versions change only when maintainers prepare a published release.

## Version validation

Before proposing a public version change, run the validation command with the declared transition
type. The validator reads both Rabbisir product constants and the tracked runtime manifest:

```sh
scripts/verify-release-version.sh \
  --candidate '0.1.0 · r1.00' \
  --kind initial
```

Valid kinds are `initial`, `maintenance`, `stage`, and `upstream`. The script reads the candidate's
product version from `Sources/RabbisirCore/App/AppVersion.swift` and requires it to match the Apple
short version and manifest `rabbisirVersion`. It independently compares the manifest's upstream
version and commit with the pinned compatibility constants. `stage` requires a documented
product-stage, major capability, or architecture justification in the release record. `upstream`
requires an integrated and independently verified manifest baseline plus explicit
`--previous-upstream-version` and `--previous-upstream-commit` values; these inputs are not displayed
as the Rabbisir product version.

The script validates version-policy transitions. It does not write version metadata, change Git
state, or publish artifacts.
