# Public contribution workflow

This repository is the public source for `Rabbisir Open`. The workflow below covers contributions to
that source; it does not document or contain the operator process used to publish the official App.

## Default order

1. Describe the problem, expected behavior, affected data, and acceptance evidence in an Issue or
   pull-request summary.
2. Make a focused change on a branch while preserving unrelated work.
3. Run the public repository checks, formatting, build, tests, and applicable `Rabbisir Open`
   acceptance workflow from [`DEVELOPMENT.md`](DEVELOPMENT.md).
4. Open a pull request with the exact scope, evidence, known limits, and rollback-relevant behavior.
5. A maintainer records `Pass`, `Needs changes`, or `Unverified` using
   [`CODE_REVIEW.md`](CODE_REVIEW.md). Accepted repairs receive targeted re-verification.
6. A maintainer merges only after required checks and review are complete.

Findings return to the pull-request author with reproducible evidence and a precise repair request.
`Unverified` is not a pass.

## Public boundary

The repository contains public source, documentation, approved assets, attribution, reproducible
runtime-provenance inputs, and public build verification. It excludes generated runtime payloads,
credentials, user data, personal paths, unpublished material, and official distribution
implementation or configuration.

Official downloads are published through the project's website and GitHub Releases. A local
`Rabbisir Open` build is a contributor build and must not be represented as the official App.
