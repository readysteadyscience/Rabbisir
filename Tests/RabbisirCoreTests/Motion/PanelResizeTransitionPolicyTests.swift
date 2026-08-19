import AppKit
import Testing

@testable import RabbisirCore

@Suite("Panel resize transition policy")
struct PanelResizeTransitionPolicyTests {
  @Test("Upward growth keeps the panel bottom fixed at every sample")
  func upwardGrowthKeepsBottomFixed() {
    let start = CGRect(x: 120, y: 18, width: 700, height: 129)
    let target = CGRect(x: 120, y: 18, width: 700, height: 310)

    for step in 0...20 {
      let frame = PanelResizeTransitionPolicy.frame(
        from: start,
        to: target,
        progress: CGFloat(step) / 20,
        curve: .easeInOut
      )
      #expect(frame.minX == start.minX)
      #expect(frame.minY == start.minY)
      #expect(frame.width == start.width)
      #expect(frame.height >= start.height)
      #expect(frame.height <= target.height)
    }
  }

  @Test("Replacement samples start from the supplied visible frame")
  func replacementStartsFromVisibleFrame() {
    let visible = CGRect(x: 120, y: 18, width: 700, height: 218)
    let target = CGRect(x: 120, y: 18, width: 700, height: 129)

    #expect(
      PanelResizeTransitionPolicy.frame(
        from: visible,
        to: target,
        progress: 0,
        curve: .easeOut
      ) == visible
    )
    #expect(
      PanelResizeTransitionPolicy.frame(
        from: visible,
        to: target,
        progress: 1,
        curve: .easeOut
      ) == target
    )
  }

  @Test("Conversation and detail reset samples share one progress value")
  func coordinatedWidthResetSamples() {
    let conversationStart = CGRect(x: 1_420, y: 18, width: 920, height: 129)
    let conversationTarget = CGRect(x: 1_570, y: 18, width: 700, height: 129)
    let detailsStart = CGRect(x: 3_000, y: 18, width: 840, height: 1_014)
    let detailsTarget = CGRect(x: 3_120, y: 18, width: 720, height: 1_014)

    for step in 0...20 {
      let progress = CGFloat(step) / 20
      let conversation = PanelResizeTransitionPolicy.frame(
        from: conversationStart,
        to: conversationTarget,
        progress: progress,
        curve: .easeInOut
      )
      let details = PanelResizeTransitionPolicy.frame(
        from: detailsStart,
        to: detailsTarget,
        progress: progress,
        curve: .easeInOut
      )
      #expect(conversation.minY == conversationStart.minY)
      #expect(conversation.height == conversationStart.height)
      #expect(details.minY == detailsStart.minY)
      #expect(details.maxX == detailsStart.maxX)
      #expect(details.height == detailsStart.height)
    }
  }

  @Test("Reduced motion settles every coordinated window immediately")
  @MainActor
  func reducedMotionSettlesCoordinatedWindowsImmediately() {
    let conversation = NSWindow(
      contentRect: CGRect(x: 1_420, y: 18, width: 920, height: 129),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let details = NSWindow(
      contentRect: CGRect(x: 3_000, y: 18, width: 840, height: 1_014),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let conversationTarget = CGRect(x: 1_570, y: 18, width: 700, height: 129)
    let detailsTarget = CGRect(x: 3_120, y: 18, width: 720, height: 1_014)
    let coordinator = PanelResizeTransitionCoordinator()
    var completed = false

    coordinator.transition(
      windowTargets: [
        (conversation, conversationTarget),
        (details, detailsTarget),
      ],
      spec: RabbisirMotionToken.panelWidthReset,
      policy: MotionAccessibilityPolicy(reduceMotion: true)
    ) {
      completed = true
    }

    #expect(completed)
    #expect(conversation.frame == conversationTarget)
    #expect(details.frame == detailsTarget)
    #expect(!coordinator.isTransitioning)
  }

  @Test("A replacement reset continues from the visible frames and owns completion")
  @MainActor
  func replacementResetCancelsStaleCompletion() async throws {
    let conversation = NSWindow(
      contentRect: CGRect(x: 1_420, y: 18, width: 920, height: 129),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let details = NSWindow(
      contentRect: CGRect(x: 3_000, y: 18, width: 840, height: 1_014),
      styleMask: .borderless,
      backing: .buffered,
      defer: false
    )
    let conversationTarget = CGRect(x: 1_570, y: 18, width: 700, height: 129)
    let detailsTarget = CGRect(x: 3_120, y: 18, width: 720, height: 1_014)
    let coordinator = PanelResizeTransitionCoordinator()
    var staleCompletions = 0
    var latestCompletions = 0

    coordinator.transition(
      windowTargets: [
        (conversation, conversationTarget),
        (details, detailsTarget),
      ],
      spec: RabbisirMotionSpec(duration: 5, curve: .easeInOut),
      policy: MotionAccessibilityPolicy(reduceMotion: false)
    ) {
      staleCompletions += 1
    }
    try await Task.sleep(for: .milliseconds(70))
    let visibleConversation = conversation.frame
    let visibleDetails = details.frame

    coordinator.transition(
      windowTargets: [
        (conversation, conversationTarget),
        (details, detailsTarget),
      ],
      spec: RabbisirMotionToken.panelWidthReset,
      policy: MotionAccessibilityPolicy(reduceMotion: false)
    ) {
      latestCompletions += 1
    }

    #expect(conversation.frame == visibleConversation)
    #expect(details.frame == visibleDetails)
    try await Task.sleep(for: .milliseconds(450))
    #expect(staleCompletions == 0)
    #expect(latestCompletions == 1)
    #expect(conversation.frame == conversationTarget)
    #expect(details.frame == detailsTarget)
    #expect(!coordinator.isTransitioning)
  }
}
