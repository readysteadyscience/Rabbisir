import Foundation
import Testing

@testable import RabbisirCore

@Suite("First workspace tour")
struct WorkspaceTourTests {
  @Test("Tour bubbles stay on-screen and do not transform workspace geometry")
  func overlayPlacementPreservesWorkspaceGeometry() {
    let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    let layout = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true
    )
    let original = layout

    for step in WorkspaceTourStep.allCases {
      let target =
        switch step {
        case .sidebar: layout.sidebarFrame
        case .conversation: layout.mainFrame.union(layout.inputFrame)
        case .details: layout.detailsFrame ?? .zero
        case .island: CGRect(x: 560, y: 856, width: 320, height: 32)
        }
      let bubble = WorkspaceTourPlacement.bubbleFrame(
        target: target,
        step: step,
        visibleFrame: visible
      )
      #expect(visible.contains(bubble))
    }

    #expect(layout == original)
  }

  @Test("A screen-edge target keeps every highlight border visible")
  func edgeHighlightIsNotClipped() {
    let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    let sidebar = CGRect(x: 0, y: 0, width: 264, height: 900)

    let highlight = WorkspaceTourPlacement.highlightFrame(
      target: sidebar,
      visibleFrame: visible
    )

    #expect(highlight.minX == 0)
    #expect(highlight.minY == 4)
    #expect(highlight.maxY == 896)
    #expect(visible.contains(highlight))
  }

  @Test("The tour follows the four required regions in order")
  func requiredStepOrder() {
    #expect(
      WorkspaceTourStep.allCases == [
        .sidebar,
        .conversation,
        .details,
        .island,
      ]
    )
  }

  @Test("First workspace entry starts the tour and completion persists")
  func firstEntryAndPersistence() throws {
    let suite = "WorkspaceTourTests.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = WorkspaceTourPreferences(defaults: defaults)
    let progress = WorkspaceTourProgress(preferences: preferences)

    #expect(progress.beginIfNeeded())
    #expect(progress.currentStep == .sidebar)
    #expect(progress.advance())
    #expect(progress.currentStep == .conversation)
    #expect(progress.advance())
    #expect(progress.currentStep == .details)
    #expect(progress.advance())
    #expect(progress.currentStep == .island)
    #expect(!progress.advance())
    #expect(progress.currentStep == nil)

    let restored = WorkspaceTourProgress(
      preferences: WorkspaceTourPreferences(defaults: defaults)
    )
    #expect(!restored.beginIfNeeded())
  }

  @Test("The menu can replay a completed tour without clearing completion")
  func replayCompletedTour() throws {
    let suite = "WorkspaceTourTests.Replay.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = WorkspaceTourPreferences(defaults: defaults)
    preferences.markCompleted()
    let progress = WorkspaceTourProgress(preferences: preferences)

    progress.replay()

    #expect(progress.currentStep == .sidebar)
    #expect(WorkspaceTourPreferences(defaults: defaults).isCompleted)
  }

  @Test("Conversation and details demonstrations run in separate required sequences")
  func panelDemonstrationOrder() {
    #expect(
      WorkspaceTourPanelDemonstrationPlan.stages(
        for: .conversation,
        reduceMotion: false
      ) == [
        .conversationMaximum,
        .conversationMinimum,
        .restored,
      ]
    )
    #expect(
      WorkspaceTourPanelDemonstrationPlan.stages(
        for: .details,
        reduceMotion: false
      ) == [
        .detailsMaximum,
        .restored,
      ]
    )
    #expect(
      WorkspaceTourPanelDemonstrationPlan.stages(for: .sidebar, reduceMotion: false)
        .isEmpty
    )
    #expect(
      WorkspaceTourPanelDemonstrationPlan.stages(for: .island, reduceMotion: false)
        .isEmpty
    )
  }

  @Test("Panel demonstrations use the real solver limits and restore exact preferences")
  func panelDemonstrationUsesSolverAndRestores() throws {
    let visible = CGRect(x: 120, y: 36, width: 2_400, height: 1_014)
    let snapshot = RabbisirWorkspaceWidthPreferences(
      sidebar: 318,
      conversation: 846,
      details: 612
    )

    let restored = WorkspaceTourPanelDemonstrationPlan.layout(
      for: .restored,
      visibleFrame: visible,
      navigationBarBottomY: visible.maxY,
      snapshot: snapshot,
      detailsVisible: true
    )
    let expected = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      navigationBarBottomY: visible.maxY,
      preferredSidebarWidth: 318,
      preferredConversationWidth: 846,
      preferredDetailsWidth: 612
    )
    #expect(restored == expected)

    let wideConversation = WorkspaceTourPanelDemonstrationPlan.layout(
      for: .conversationMaximum,
      visibleFrame: visible,
      navigationBarBottomY: visible.maxY,
      snapshot: snapshot,
      detailsVisible: true
    )
    let narrowConversation = WorkspaceTourPanelDemonstrationPlan.layout(
      for: .conversationMinimum,
      visibleFrame: visible,
      navigationBarBottomY: visible.maxY,
      snapshot: snapshot,
      detailsVisible: true
    )
    #expect(wideConversation.inputFrame.width > restored.inputFrame.width)
    #expect(
      wideConversation.inputFrame.width
        <= SpatialWorkspaceLayoutPolicy.maximumConversationWidth
    )
    #expect(
      narrowConversation.inputFrame.width
        == SpatialWorkspaceLayoutPolicy.minimumInputWidth
    )

    let maximumDetails = WorkspaceTourPanelDemonstrationPlan.layout(
      for: .detailsMaximum,
      visibleFrame: visible,
      navigationBarBottomY: visible.maxY,
      snapshot: snapshot,
      detailsVisible: true
    )
    let details = try #require(maximumDetails.detailsFrame)
    #expect(
      maximumDetails.sidebarFrame.width
        == SpatialWorkspaceLayoutPolicy.minimumSidebarWidth
    )
    #expect(
      maximumDetails.inputFrame.width
        == SpatialWorkspaceLayoutPolicy.minimumInputWidth
    )
    #expect(details.maxX == visible.maxX)
    #expect(visible.contains(maximumDetails.sidebarFrame))
    #expect(visible.contains(maximumDetails.inputFrame))
    #expect(visible.contains(details))
  }

  @Test(
    "Small and offset displays keep every demonstration layout safe",
    arguments: [
      CGRect(x: 0, y: 0, width: 1_440, height: 900),
      CGRect(x: 1_440, y: 38, width: 1_728, height: 1_062),
      CGRect(x: -1_280, y: 0, width: 1_280, height: 800),
    ]
  )
  func panelDemonstrationStaysInsideDisplay(visible: CGRect) throws {
    let snapshot = RabbisirWorkspaceWidthPreferences(
      sidebar: 420,
      conversation: 1_100,
      details: 960
    )

    for stage in WorkspaceTourPanelDemonstrationStage.allCases {
      let layout = WorkspaceTourPanelDemonstrationPlan.layout(
        for: stage,
        visibleFrame: visible,
        navigationBarBottomY: visible.maxY,
        snapshot: snapshot,
        detailsVisible: true
      )
      #expect(visible.contains(layout.sidebarFrame))
      #expect(visible.contains(layout.mainFrame))
      #expect(visible.contains(layout.inputFrame))
      if let details = layout.detailsFrame {
        #expect(visible.contains(details))
      }
    }
  }

  @Test("A compact display still has a visible composer width demonstration")
  func compactDisplayComposerDemonstrationRemainsVisible() {
    let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    let snapshot = RabbisirWorkspaceWidthPreferences(
      sidebar: nil,
      conversation: nil,
      details: SpatialWorkspaceLayoutPolicy.detailsWidth
    )
    let restored = WorkspaceTourPanelDemonstrationPlan.layout(
      for: .restored,
      visibleFrame: visible,
      navigationBarBottomY: visible.maxY,
      snapshot: snapshot,
      detailsVisible: true
    )
    let widened = WorkspaceTourPanelDemonstrationPlan.layout(
      for: .conversationMaximum,
      visibleFrame: visible,
      navigationBarBottomY: visible.maxY,
      snapshot: snapshot,
      detailsVisible: true
    )

    #expect(widened.inputFrame.width > restored.inputFrame.width)
    #expect(widened.inputFrame.width > SpatialWorkspaceLayoutPolicy.minimumInputWidth)
  }

  @Test("Reduced Motion skips spatial demonstrations and keeps the tour textual")
  func reducedMotionSkipsPanelDemonstrations() {
    for step in WorkspaceTourStep.allCases {
      #expect(
        WorkspaceTourPanelDemonstrationPlan.stages(for: step, reduceMotion: true)
          .isEmpty
      )
    }
  }

  @Test("Skipping the tour closes progress and persists completion")
  func skippingTourRestoresCompletionState() throws {
    let suite = "WorkspaceTourTests.Skip.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let progress = WorkspaceTourProgress(
      preferences: WorkspaceTourPreferences(defaults: defaults)
    )

    #expect(progress.beginIfNeeded())
    progress.skip()

    #expect(progress.currentStep == nil)
    #expect(WorkspaceTourPreferences(defaults: defaults).isCompleted)
  }

  @Test("Resizable tour guidance is localized without treating motion as the only cue")
  func resizableGuidanceIsBilingual() {
    #expect(
      WorkspaceTourCopy(language: .chinese).body(for: .conversation)
        .contains("拖动")
    )
    #expect(
      WorkspaceTourCopy(language: .english).body(for: .conversation)
        .contains("drag")
    )
    #expect(WorkspaceTourCopy(language: .chinese).skip == "跳过导览")
    #expect(WorkspaceTourCopy(language: .english).skip == "Skip Tour")
  }
}
