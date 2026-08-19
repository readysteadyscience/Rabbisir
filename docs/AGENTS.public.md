# Rabbisir public-source development rules

Rabbisir is a native macOS application. Keep user-visible UI in SwiftUI or AppKit; the staged vendor
runtime is an App-private compatibility component, not a second product surface.

- Preserve unrelated worktree changes. Never commit, push, publish, sign, notarize, deploy, install,
  or change repository visibility without explicit authorization for that exact action.
- Public builds use only the `RabbisirOpen` product. Run
  `scripts/build-and-run-open.sh --verify-first-run` for an unsigned, isolated, temporary App
  acceptance build. Do not create or commit an Open App package, DMG, ZIP, or Release asset.
- Keep official-only update/distribution features, private overlays, contribution/payment resources,
  signing/notarization material, credentials, user data, local archives, and private configuration
  outside this source tree.
- Use `scripts/stage-vendor-runtime.sh` only with separately reviewed, receipted inputs. Generated
  runtime payloads stay ignored and must pass `scripts/verify-staged-runtime.sh` before consumption.
- Run `scripts/test-public-swiftpm.sh` after source changes. Run
  `scripts/build-and-run-open.sh --verify-first-run` when startup, resources, windows, or runtime
  behavior changes. Direct `swift build` and `swift test` are not verification paths because they can
  reuse unreviewed derived resource bundles.
- Keep public documentation current and concise. Internal plans, task transcripts, screenshots,
  personal paths, credentials, and unreleased distribution material do not belong here.

See `docs/DELIVERY_WORKFLOW.md` for the separation between local evidence, independent review,
repository governance, and separately authorized external actions.
