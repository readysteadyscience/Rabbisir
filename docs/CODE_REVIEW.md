# Code review and quality governance

This document defines Rabbisir's independent code-review and quality-governance process. It applies
after a primary development task is complete and before that change can enter official release or
open-source governance. It complements, but never replaces, explicit user authorization for a push,
merge, publication, signing, notarization, deployment, installation, or other external action.

## Trigger and independence

Primary development submits the exact source revision, scope, validation evidence, known limits, and
rollback impact for review when a task is complete. A reviewer independent of the implementing task
reviews that fixed evidence set. New material changes restart the relevant review scope.

Pull requests require a maintainer review conclusion before merge. A formal release candidate requires
a completed independent review and independent re-verification of every accepted repair. CI and a
passing local test run are evidence for review; neither is the review conclusion itself.

The delivery workflow has two independent review stages. A complete private official-App candidate
first enters private official-app review. A separately assembled public candidate enters public-version
review before open-source governance. Neither review may be skipped because the other passed. This
handoff is a required evidence protocol after the current task completes; it does not claim that the
platform automatically creates, wakes, or modifies a task.

## Read-only review boundary

The review window observes, reproduces, analyzes, and reports. It must not directly modify product
code, commit, push, merge a pull request, publish, deploy, sign, notarize, install, change repository
settings, access credentials, or operate production systems. It returns findings to primary development
with reproducible evidence, impact, exact affected location, and a precise repair recommendation.

Primary development owns repairs and validation. The same independent review boundary then verifies
the repaired result against the reported finding and records whether it is resolved, still present, or
unverified.

Do not append unrelated work to a task that is currently executing unless the user explicitly asks to
interrupt, supplement, or add it. A review request captures a fixed candidate; material new work is
handled by the appropriate subsequent task and restarts the affected review scope.

Sub agents are optional support for an executing agent, not an independent review shortcut. They may
be used only after the executing agent has assessed that two or more independent, clearly bounded
subtasks can be verified in parallel without shared worktree or mutable-state contention. The primary
agent retains responsibility for integration, conflict checks, validation, and the review conclusion;
delegation cannot bypass this review boundary, project gates, or explicit user authorization.

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
- public repository hygiene: generated files, user data, private information, internal material, and
  accidental credentials;
- documentation, CHANGELOG, version-policy, release-process, and user-visible behavior consistency.

## Finding severity

| Severity | Meaning and required disposition |
| --- | --- |
| P0 — critical | Security, privacy, data-loss, production-safety, or legal risk. Block merge and release until repaired and independently re-verified. |
| P1 — high | Material functional regression, architecture-boundary breach, inaccessible core workflow, or missing required release evidence. Block release readiness until repaired and independently re-verified. |
| P2 — medium | Significant correctness, resilience, performance, or maintainability concern. Require repair or an explicit maintainer scope decision; it remains a release blocker if it affects the candidate's declared acceptance. |
| P3 — low | Narrow improvement or clarity issue. Track it with rationale; it is not evidence that the reviewed work is complete. |

Do not downgrade a finding solely to obtain a passing conclusion. A recommendation is not an
implementation, validation result, or approval.

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

`Pass` means the reviewed scope has no unresolved release-blocking finding and all accepted repairs
were independently re-verified. `Needs changes` means primary development must repair or obtain a
documented scope decision. `Unverified` means evidence or reproduction is insufficient; it is not a
pass and cannot be represented as release-ready.

## Mandatory handoff closure

For `Needs changes` or `Unverified`, the review task returns an evidence-backed defect list, impact,
reproduction, affected location, and precise repair requirement to primary development. Primary
development repairs the findings and performs targeted validation, then returns the updated candidate
to the independent review task. Re-verification cannot be skipped.

For `Pass`, the review task records the conclusion, reviewed scope, validation evidence, and uncovered
risks, then hands the candidate to its next governance stage: private official-app review goes to
private-repository governance; public-version review goes to open-source governance. That governance
stage accepts only a candidate carrying this independent `Pass` record.

Automatic handoff means only this required task-completion order and evidence transfer. It never
authorizes or executes a GitHub push, pull-request merge, tag, Release, signing, notarization,
deployment, formal publication, or installation. Each external action still requires explicit user
authorization for that exact action.

## Repair and re-verification loop

1. The reviewer reports evidence-backed findings without changing product code.
2. Primary development implements the agreed repair and runs the affected validation.
3. The reviewer independently re-runs or inspects the relevant evidence against the original finding.
4. The reviewer updates the conclusion. Only `Pass` with required re-verification permits the
   mandatory handoff to release governance.

Do not use a review suggestion, a review request, an unchanged CI badge, or a pending discussion as
proof that a repair is complete. Keep review records free of credentials, user data, private paths,
internal task transcripts, and raw private payloads.
