# Delivery workflow

Rabbisir uses one private development source of truth and a separately governed public export. The
public repository is a reviewable snapshot of the released private candidate, not a second day-to-day
development branch.

## Default order

1. Primary development builds and validates a local DEV candidate.
2. Private official-app review independently reviews that complete candidate.
3. Private-repository governance freezes provenance and prepares the private transaction.
4. Official release prepares and, when separately authorized, performs the official distribution work.
5. Public-version review independently reviews the public export.
6. Open-source governance prepares and, when separately authorized, writes the public repository.
7. Release summary records actual results in a local-only, ignored archive.

Findings return to primary development. A material repair requires the review that found it to
re-verify the repaired candidate. A pass at one review never substitutes for another review.

## Boundary

The public export contains only public source, documentation, approved assets and public build
verification. It excludes private overlays, payment/support resources, official update/distribution
code and configuration, signing/notarization material, credentials, user data, local diagnostics and
release archives. The private repository and official distribution environment remain separately
controlled.

## Authorization

Evidence transfer between stages may be automatic. Repository creation or visibility changes, commit,
push, signing, notarization, upload, publication, installation, and any credential use always require
explicit authorization for the exact action. A local pass is not an external-operation authorization.
