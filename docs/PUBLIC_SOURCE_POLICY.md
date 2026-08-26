# Public source and repository roles

This document is the contributor-safe boundary for the public
[`readysteadyscience/Rabbisir`](https://github.com/readysteadyscience/Rabbisir) repository.

## Repository responsibilities

| Repository | Public responsibility |
| --- | --- |
| [`readysteadyscience/Rabbisir`](https://github.com/readysteadyscience/Rabbisir) | `Rabbisir Open` source and tests, contributor and community material, the reviewed static website, and explicitly selected Open milestones |
| [`readysteadyscience/Rabbisir-Releases`](https://github.com/readysteadyscience/Rabbisir-Releases) | Official Rabbisir App tags, Releases, signed and notarized assets, checksums/manifests, and public release/update data |

The complete product source and day-to-day development backup are maintained separately. Public
documentation must not disclose a private repository name, local path, credential, receipt, operator
procedure, or other internal material.

## Official App distribution

The permanent official installer entry is:

<https://github.com/readysteadyscience/Rabbisir-Releases/releases/latest/download/Rabbisir.dmg>

Only `readysteadyscience/Rabbisir-Releases` may publish an official App `vX.Y.Z` tag or Release,
`Rabbisir.dmg`, an official Appcast, or official release manifests and checksums. This source
repository and its automation may read public release metadata for the website, but must not mutate
the distribution repository or manufacture official release state.

The website under `site/` remains part of this repository. Its main download action uses the permanent
official installer entry above; a local or downloadable `Rabbisir Open` build must never replace that
target or become the website's official `latest` App.

## Rabbisir Open milestones

An Open milestone is a separately authorized public-source event. Its tag is always
`open-vX.Y.Z`. If an Open-specific GitHub Release is ever needed, its title, tag, asset names, and
description must identify `Rabbisir Open`; it must not use `Rabbisir.dmg`, an official App `vX.Y.Z`
tag, or any official update/feed identity, and it must not be presented as the official App's latest
Release.

Historical official-style tags and Releases already present in this source repository are preserved
unchanged as compatibility records. They are not the authority for future official App distribution,
and this migration does not delete, rewrite, hide, or retag them.

## Public source boundary

The public tree may contain:

- source and tests for `Rabbisir Open`;
- public build and validation scripts, dependency locks, runtime provenance inputs, and permitted
  third-party notices;
- contributor, community, license, attribution, and architecture documentation; and
- the reviewed static website and its public, read-only release-data consumer.

The public tree must not contain credentials, signing or notarization identities, private operator
controls, private receipts, user data, local paths, generated Apps or installer archives, unlicensed
third-party material, or explicitly private product formats and implementation details. `Rabbisir
Open` uses a separate bundle, data, signing, update, and distribution identity from the official App.

## Machine enforcement

Run the [repository role test](../scripts/test-public-delivery-boundary.sh) together with the normal
public checks. The test invokes the tracked
[role verifier](../scripts/verify-public-delivery-boundary.sh) against its baseline and negative
fixtures:

```sh
scripts/test-public-delivery-boundary.sh
scripts/verify-public-repository.sh
scripts/verify-pages-site.sh
```

The role gate pins every tracked file under `scripts/` and `.github/workflows/` (except the manifest
itself) in `scripts/PUBLIC_AUTOMATION_MANIFEST.sha256`. Any automation addition, deletion, or byte
change fails closed until the complete closure and its review are updated together. This prevents
unreviewed public automation from mutating the official distribution repository, creating
official-style App tags/Releases, uploading official App distribution assets, requesting repository
write authority, or redirecting the website's official latest download to an Open/source release.
Any future Open publication automation must first extend this policy and its positive and negative
tests without weakening the official distribution boundary.
