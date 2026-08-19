import AppKit
import Testing

@testable import RabbisirCore

@Suite("Panel transition policy")
struct PanelTransitionPolicyTests {
  @Test("Leading and trailing panels move only on the X axis")
  func sideDirectionsAreMirroredAndSingleAxis() {
    let bounds = CGRect(x: 0, y: 0, width: 720, height: 800)
    let visible = PanelTransitionPolicy.visibleContentFrame(in: bounds)
    let leading = PanelTransitionPolicy.hiddenContentFrame(in: bounds, edge: .leading)
    let trailing = PanelTransitionPolicy.hiddenContentFrame(in: bounds, edge: .trailing)

    #expect(leading.minX == -bounds.width)
    #expect(trailing.minX == bounds.width)
    #expect(PanelTransitionPolicy.isStrictHorizontalTransition(from: visible, to: leading))
    #expect(PanelTransitionPolicy.isStrictHorizontalTransition(from: visible, to: trailing))
    #expect(leading.minY == visible.minY)
    #expect(trailing.minY == visible.minY)
    #expect(leading.size == visible.size)
    #expect(trailing.size == visible.size)
  }

  @Test("A replacement transition owns completion and stale completion cannot recycle")
  @MainActor
  func rapidRetargetCancelsStaleCompletion() async throws {
    let view = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
    view.wantsLayer = true
    let coordinator = PanelTransitionCoordinator()
    var staleCompletions = 0
    var latestCompletions = 0

    coordinator.transition(
      contentView: view,
      to: CGRect(x: 120, y: 0, width: 120, height: 80)
    ) {
      staleCompletions += 1
    }
    coordinator.transition(
      contentView: view,
      to: CGRect(x: 0, y: 0, width: 120, height: 80)
    ) {
      latestCompletions += 1
    }

    let clock = ContinuousClock()
    let deadline = clock.now.advanced(by: .seconds(2))
    while latestCompletions == 0, clock.now < deadline {
      try await Task.sleep(for: .milliseconds(50))
    }
    #expect(staleCompletions == 0)
    #expect(latestCompletions == 1)
    #expect(view.frame == CGRect(x: 0, y: 0, width: 120, height: 80))
    #expect(!coordinator.isTransitioning)
  }

  @Test("Reduced motion settles immediately")
  @MainActor
  func reduceMotionSettlesImmediately() {
    let view = NSView(frame: CGRect(x: 0, y: 0, width: 120, height: 80))
    view.wantsLayer = true
    let coordinator = PanelTransitionCoordinator()
    var completed = false

    coordinator.transition(
      contentView: view,
      to: CGRect(x: -120, y: 0, width: 120, height: 80),
      policy: MotionAccessibilityPolicy(reduceMotion: true)
    ) {
      completed = true
    }

    #expect(completed)
    #expect(view.frame.minX == -120)
    #expect(!coordinator.isTransitioning)
  }
}
