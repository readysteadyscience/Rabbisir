# Release boundary

This public repository defines how a source change becomes a reviewable local candidate. It does not
contain the official distribution pipeline, private product overlay, distribution configuration, or
operator procedures.

## Public candidate gates

From the exact source under review, run:

```sh
scripts/verify-documentation-links.sh
scripts/verify-public-repository.sh
xcrun swift-format lint --strict --recursive Package.swift Sources Tests
scripts/build-fresh-public-product.sh RabbisirOpen debug
scripts/test-public-swiftpm.sh
scripts/build-and-run-open.sh --verify-first-run
```

Exercise affected public workflows in the temporary Rabbisir Open build and record the exact source, commands, results, known
limits, compatibility impact, and rollback-relevant data boundary. A failed required check or an
unresolved review finding leaves the candidate at `NO-GO`.

For the confirmed first release, use `0.1.0 · r1.00` consistently in the changelog and release notes;
the Apple short version remains `0.1.0` and build number remains `1`. Validate this product version
under [`VERSIONING.md`](VERSIONING.md). The pinned DeepSeek Harness version and commit are an
independently verified compatibility baseline, not the public version prefix. Add a release date only
during the separately authorized formal release.

## Independent public-version review

The exact public candidate must pass the public-version process in
[`CODE_REVIEW.md`](CODE_REVIEW.md). It is separate from private official-app review; neither pass
substitutes for the other. Any repair invalidates the earlier conclusion and requires targeted
validation plus independent re-verification. A passing review is evidence only; it grants no
repository or distribution authority. Open-source governance accepts a candidate only after the
independent reviewer records that conclusion, its scope, evidence, and uncovered risks.

## Official distribution boundary

Official-only product code and operator procedures live in a separately controlled, receipted private
overlay. The public tree can verify that the overlay is absent from public inputs and that an official
build fails closed when its private receipt or required configuration is unavailable. Contributors,
CI, and routine DEV work cannot operate that pipeline.

Each external repository or distribution action requires explicit authorization for that exact
transaction. Without it, work stops at the verified local candidate. Details that would expose private
distribution inputs, operator configuration, or credentials do not belong in this repository.

## Public repository settings

After the repository becomes public, an authorized administrator should configure protected review,
required CI, resolved discussions, and non-destructive history rules for `main`. Changing repository
visibility or remote settings is an external action and must be verified separately after authorization.
