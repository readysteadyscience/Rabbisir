import AppKit
import SwiftUI
import Testing

@testable import RabbisirCore

@Suite("Rabbisir application activity")
struct RabbisirApplicationActivityTests {
  @Test("Every glass window follows the application activation lifecycle")
  @MainActor
  func glassWindowsShareApplicationActivity() {
    let center = NotificationCenter()
    let activity = RabbisirApplicationActivity(
      notificationCenter: center,
      initiallyActive: false
    )

    #expect(!activity.appearsActive)

    center.post(name: NSApplication.didBecomeActiveNotification, object: nil)
    #expect(activity.appearsActive)

    center.post(name: NSApplication.didResignActiveNotification, object: nil)
    #expect(!activity.appearsActive)
  }

  @Test("A panel root gives every descendant the application activation state")
  @MainActor
  func panelRootOverridesIndependentWindowFocus() async {
    let recorder = AppearsActiveRecorder()
    let panel = SpatialPanel(
      frame: CGRect(x: 0, y: 0, width: 80, height: 40),
      acceptsKeyWindow: false
    )
    NotificationCenter.default.post(
      name: NSApplication.didResignActiveNotification,
      object: nil
    )
    panel.install(rootView: AnyView(AppearsActiveProbe(recorder: recorder)))
    panel.contentView?.layoutSubtreeIfNeeded()
    await Task.yield()

    #expect(recorder.latest == false)

    NotificationCenter.default.post(
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )
    panel.contentView?.layoutSubtreeIfNeeded()
    await Task.yield()

    #expect(recorder.latest == true)
    NotificationCenter.default.post(
      name: NSApplication.didResignActiveNotification,
      object: nil
    )
  }

  @Test("Workspace panels participate in the application's active appearance")
  @MainActor
  func workspacePanelsAreActivatingWindows() {
    let panel = SpatialPanel(
      frame: CGRect(x: 0, y: 0, width: 80, height: 40),
      acceptsKeyWindow: false
    )

    #expect(!panel.styleMask.contains(.nonactivatingPanel))
    #expect(!panel.canBecomeKey)
  }
}

@MainActor
private final class AppearsActiveRecorder {
  var latest: Bool?
}

private struct AppearsActiveProbe: View {
  @Environment(\.appearsActive) private var appearsActive
  let recorder: AppearsActiveRecorder

  var body: some View {
    Color.clear
      .onAppear { recorder.latest = appearsActive }
      .onChange(of: appearsActive) { _, next in recorder.latest = next }
  }
}
