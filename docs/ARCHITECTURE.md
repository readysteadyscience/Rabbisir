# Rabbisir architecture

Rabbisir is a SwiftPM macOS application. SwiftUI and AppKit own every user-visible window, menu, navigation row, conversation node, editor, settings page, and document workbench.

## Source layout

- `Sources/RabbisirApp/` contains the executable entry point.
- `Sources/RabbisirCore/App/` owns application lifecycle and global commands.
- `Appearance/`, `Motion/`, and `Layout/` own shared visual, animation, and geometry policies.
- `Navigation/`, `Conversation/`, `Workspace/`, `Settings/`, `Artifacts/`, and `MenuBar/` own their native product areas.
- `Runtime/` owns the private runtime lifecycle, protocol models, transports, and the replaceable compatibility bridge.
- `Resources/VendorRuntime/` contains the small tracked launcher and provenance-linked version
  manifest. `RuntimeProvenance/` pins the official source, compatibility patches, toolchain, and
  canonical output inventory. The generated Node binary and deployed runtime payload are ignored by
  Git and staged separately.

## Managed runtime

The App launches its compatible runtime as a child process on an operating-system-assigned loopback port. It completes a health check before presenting the workspace, restarts an unexpected child exit, and stops the child when Rabbisir exits. Users never start or configure a localhost service.

The public repository does not contain the upstream monorepo, standalone Web application, CLI
application, documentation website, examples, or upstream test infrastructure. Maintainers rebuild a
receipted payload from the exact official commit through `scripts/rebuild-vendor-runtime.sh`; staging
then independently verifies that receipt and inventory through `scripts/stage-vendor-runtime.sh`.

## Compatibility bridge

The current compatibility layer retains one hidden `WKWebView` for upstream operations that do not yet have a native host operation. It does not expose upstream React layout or styling. Native views consume versioned, JSON-safe projections and invoke narrowly scoped bridge actions.

Conversation projection is fail-closed. Only user-authored content, user-visible assistant content, approved presentation metadata, safe tool summaries, produced-file references, and completed-turn actions enter the native model. System and developer messages, hidden context, credentials, raw tool arguments or results, unknown nodes, and unapproved metadata are rejected.

## Data ownership

Workspace and session identifiers come from the compatible runtime and remain stable across restart and reordering. Removing a project from Rabbisir removes the navigation registration but does not delete the local project directory. Session history remains in the runtime data store rather than being written into the selected project folder.
