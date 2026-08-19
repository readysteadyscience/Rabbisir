import AppKit
import Foundation
import Testing

@testable import RabbisirCore

@Suite("Spatial workspace coordinator", .serialized)
struct SpatialWorkspaceCoordinatorTests {
  @Test("Tour panel motion is transient and cancellation restores the exact layout")
  @MainActor
  func tourPanelMotionDoesNotPersistWidths() async throws {
    let state = WorkspaceState()
    state.isDetailsVisible = false
    let runtimeBridge = RuntimeBridgeStore(
      state: state,
      url: try #require(URL(string: "http://127.0.0.1:9"))
    )
    let suiteName = "RabbisirTests.TourPanelMotion.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = RabbisirInterfacePreferencesStore(defaults: defaults)
    preferences.setSidebarWidth(286)
    preferences.setConversationWidth(640)
    preferences.setDetailsWidth(590)
    let coordinator = SpatialWorkspaceCoordinator(
      state: state,
      runtimeBridge: runtimeBridge,
      launchScreen: try #require(NSScreen.screens.first),
      interfacePreferences: preferences
    )
    defer {
      coordinator.cancelTourPanelDemonstration()
      for window in NSApp.windows
      where window.identifier?.rawValue.hasPrefix("RabbisirApp.") == true {
        window.orderOut(nil)
      }
    }

    coordinator.showAll()
    let input = try #require(
      NSApp.windows.first(where: { $0.identifier?.rawValue == "RabbisirApp.input" })
    )
    let originalInputFrame = input.frame
    let originalMainFrame = coordinator.mainWindow.frame
    let originalPreferences = preferences.workspaceWidths

    coordinator.startTourPanelDemonstration(
      for: .conversation,
      policy: MotionAccessibilityPolicy(reduceMotion: false)
    )
    try await Task.sleep(for: .milliseconds(430))

    #expect(input.frame.width > originalInputFrame.width)
    #expect(preferences.workspaceWidths == originalPreferences)

    coordinator.cancelTourPanelDemonstration()

    #expect(input.frame == originalInputFrame)
    #expect(coordinator.mainWindow.frame == originalMainFrame)
    #expect(preferences.workspaceWidths == originalPreferences)
  }

  @Test("Reduced Motion leaves panel geometry unchanged")
  @MainActor
  func reducedMotionSkipsTourPanelMotion() throws {
    let state = WorkspaceState()
    state.isDetailsVisible = false
    let runtimeBridge = RuntimeBridgeStore(
      state: state,
      url: try #require(URL(string: "http://127.0.0.1:9"))
    )
    let suiteName = "RabbisirTests.TourPanelReducedMotion.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let coordinator = SpatialWorkspaceCoordinator(
      state: state,
      runtimeBridge: runtimeBridge,
      launchScreen: try #require(NSScreen.screens.first),
      interfacePreferences: RabbisirInterfacePreferencesStore(defaults: defaults)
    )
    defer {
      for window in NSApp.windows
      where window.identifier?.rawValue.hasPrefix("RabbisirApp.") == true {
        window.orderOut(nil)
      }
    }
    coordinator.showAll()
    let input = try #require(
      NSApp.windows.first(where: {
        $0.identifier?.rawValue == "RabbisirApp.input" && $0.isVisible
      })
    )
    let mainFrame = coordinator.mainWindow.frame
    let inputFrame = input.frame

    coordinator.startTourPanelDemonstration(
      for: .conversation,
      policy: MotionAccessibilityPolicy(reduceMotion: true)
    )

    #expect(coordinator.mainWindow.frame == mainFrame)
    #expect(input.frame == inputFrame)
  }

  @Test("A workspace visibility change cancels tour motion before applying its layout")
  @MainActor
  func detailsVisibilityChangeCancelsTourMotion() async throws {
    let state = WorkspaceState()
    state.isDetailsVisible = false
    let runtimeBridge = RuntimeBridgeStore(
      state: state,
      url: try #require(URL(string: "http://127.0.0.1:9"))
    )
    let suiteName = "RabbisirTests.TourPanelStateChange.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let preferences = RabbisirInterfacePreferencesStore(defaults: defaults)
    preferences.setConversationWidth(640)
    let screen = try #require(NSScreen.screens.first)
    let coordinator = SpatialWorkspaceCoordinator(
      state: state,
      runtimeBridge: runtimeBridge,
      launchScreen: screen,
      interfacePreferences: preferences
    )
    defer {
      coordinator.cancelTourPanelDemonstration()
      for window in NSApp.windows
      where window.identifier?.rawValue.hasPrefix("RabbisirApp.") == true {
        window.orderOut(nil)
      }
    }
    coordinator.showAll()
    let input = try #require(
      NSApp.windows.first(where: {
        $0.identifier?.rawValue == "RabbisirApp.input" && $0.isVisible
      })
    )

    coordinator.startTourPanelDemonstration(
      for: .conversation,
      policy: MotionAccessibilityPolicy(reduceMotion: false)
    )
    try await Task.sleep(for: .milliseconds(100))
    state.isDetailsVisible = true
    try await Task.sleep(for: .milliseconds(750))

    let expected = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: screen.visibleFrame,
      detailsVisible: true,
      preferredConversationWidth: 640,
      preferredDetailsWidth: SpatialWorkspaceLayoutPolicy.detailsWidth
    )
    #expect(
      input.frame.width - PanelResizeHandleMetrics.protrusion
        == expected.inputFrame.width
    )
    #expect(preferences.workspaceWidths.conversation == 640)
  }

  @Test("The document workbench panel can receive keyboard focus")
  @MainActor
  func detailsWorkbenchCanReceiveKeyboardFocus() throws {
    let state = WorkspaceState()
    state.isDetailsVisible = true
    let runtimeBridge = RuntimeBridgeStore(
      state: state,
      url: try #require(URL(string: "http://127.0.0.1:9"))
    )
    let suiteName = "RabbisirTests.SpatialWorkspaceCoordinator.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let coordinator = SpatialWorkspaceCoordinator(
      state: state,
      runtimeBridge: runtimeBridge,
      launchScreen: try #require(NSScreen.screens.first),
      interfacePreferences: RabbisirInterfacePreferencesStore(defaults: defaults)
    )
    defer {
      for window in NSApp.windows
      where window.identifier?.rawValue.hasPrefix("RabbisirApp.") == true {
        window.orderOut(nil)
      }
    }

    coordinator.showAll()

    let panel = try #require(
      NSApp.windows.first(where: { $0.identifier?.rawValue == "RabbisirApp.details" })
        as? SpatialPanel
    )
    #expect(panel.canBecomeKey)
    #expect(panel.canBecomeMain)
    #expect(!panel.becomesKeyOnlyIfNeeded)
  }

  @Test("Opening a document requests focus for its interactive workbench")
  @MainActor
  func openingDocumentRequestsDetailsWorkbenchFocus() throws {
    let state = WorkspaceState()
    state.isDetailsVisible = true
    let runtimeBridge = RuntimeBridgeStore(
      state: state,
      url: try #require(URL(string: "http://127.0.0.1:9"))
    )
    let suiteName = "RabbisirTests.SpatialWorkspaceDocumentFocus.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let coordinator = SpatialWorkspaceCoordinator(
      state: state,
      runtimeBridge: runtimeBridge,
      launchScreen: try #require(NSScreen.screens.first),
      interfacePreferences: RabbisirInterfacePreferencesStore(defaults: defaults)
    )
    defer {
      for window in NSApp.windows
      where window.identifier?.rawValue.hasPrefix("RabbisirApp.") == true {
        window.orderOut(nil)
      }
    }

    coordinator.showAll()
    let focusRequest = state.detailFocusRequest
    state.showArtifact(
      UpstreamMarkdownDocument(
        path: "document.md",
        content: "# Document",
        bytes: 10,
        modifiedAt: 1
      )
    )

    let panel = try #require(
      NSApp.windows.first(where: { $0.identifier?.rawValue == "RabbisirApp.details" })
    )
    #expect(panel.isVisible)
    #expect(panel.canBecomeKey)
    #expect(state.detailFocusRequest == focusRequest + 1)
  }
}
