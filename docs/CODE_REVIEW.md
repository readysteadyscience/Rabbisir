# Public code review and quality

This document defines the review process for public Rabbisir source contributions. A passing build or
CI job is evidence for review; it is not a maintainer review conclusion by itself.

## Trigger and independence

A pull request supplies its exact source revision, scope, validation evidence, known limits, and
rollback-relevant behavior. A maintainer who did not author the material change reviews that fixed
evidence set. New material changes restart the affected review scope.

## Read-only review boundary

The reviewer reproduces, analyzes, and reports without directly editing the pull-request branch.
Findings include impact, reproduction, affected location, and a precise repair recommendation. The
author implements accepted repairs and returns the updated branch for targeted re-verification.

## Required review coverage

Review the applicable areas below, and state why any non-applicable area was not exercised:

- functional behavior and regressions in affected user workflows;
- architecture boundaries, native UI ownership, protocol compatibility, and runtime isolation;
- automated tests, test relevance, missing cases, and validation evidence;
- performance, memory, process lifecycle, disk, network, and other resource impact;
- error handling, recovery, cancellation, diagnostics, and failure-safe behavior;
- accessibility, including keyboard, VoiceOver, contrast, focus, and reduced-motion behavior;
- privacy and security: data exposure, credentials, permissions, logs, paths, and unsafe input;
- licenses, notices, upstream attribution, and compatible use of upstream protocol identifiers;
- public repository hygiene: generated files, user data, private information, unpublished material,
  and accidental credentials; and
- documentation, changelog, version-policy, and user-visible behavior consistency.

## Finding severity

| Severity | Meaning and required disposition |
| --- | --- |
| P0 — critical | Security, privacy, data-loss, or legal risk. Block merge until repaired and independently re-verified. |
| P1 — high | Material functional regression, architecture-boundary breach, inaccessible core workflow, or missing required evidence. Block merge until repaired and independently re-verified. |
| P2 — medium | Significant correctness, resilience, performance, or maintainability concern. Require repair or a documented maintainer scope decision. |
| P3 — low | Narrow improvement or clarity issue. Track it with rationale; it is not evidence that the reviewed work is complete. |

Do not downgrade a finding solely to obtain a passing conclusion. A recommendation is not an
implementation or validation result.

## Review conclusion format

Every review records a public-safe conclusion using this shape:

```text
Conclusion: Pass | Needs changes | Unverified
Reviewed revision and scope:
Evidence and commands:
Findings: severity, impact, reproduction, affected location, and repair recommendation
Residual risks and non-applicable coverage:
Re-verification: resolved | still present | unverified
```

`Pass` means the reviewed scope has no unresolved blocking finding and accepted repairs were
re-verified. `Needs changes` means the author must repair the contribution or obtain a documented
scope decision. `Unverified` means evidence or reproduction is insufficient; it is not a pass.

## Repair and re-verification loop

1. The reviewer reports evidence-backed findings without changing the contribution.
2. The author implements the agreed repair and runs the affected validation.
3. The reviewer independently re-runs or inspects the relevant evidence against the original finding.
4. The reviewer updates the conclusion. Only `Pass` permits maintainer merge.

Keep review records free of credentials, user data, personal paths, private service details, task
transcripts, and raw private payloads.
