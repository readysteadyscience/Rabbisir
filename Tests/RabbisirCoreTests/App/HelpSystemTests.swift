import AppKit
import Testing

@testable import RabbisirCore

@Suite("Rabbisir native help", .serialized)
struct HelpSystemTests {
  @Test("The localized catalog covers every currently supported help area")
  func catalogCoversRequiredTopics() throws {
    for language in RabbisirInterfaceLanguage.allCases {
      let catalog = RabbisirHelpCatalog(language: language)

      #expect(Set(catalog.articles.map(\.topic)) == Set(RabbisirHelpTopic.allCases))
      #expect(catalog.articles.allSatisfy { !$0.title.isEmpty && !$0.summary.isEmpty })
      #expect(try catalog.article(for: .quickStart).groups.count >= 2)
      #expect(try catalog.article(for: .workspace).groups.count >= 3)
      #expect(try catalog.article(for: .troubleshooting).groups.count >= 3)
    }
  }

  @Test(
    "Public Help covers privacy, shortcuts, displays, creator, community, license, and feedback")
  func catalogDoesNotInventCapabilities() throws {
    let chinese = RabbisirHelpCatalog(language: .chinese)
    let english = RabbisirHelpCatalog(language: .english)

    #expect(try chinese.article(for: .quickStart).plainText.contains("API Key"))
    #expect(try english.article(for: .workspace).plainText.contains("project"))
    #expect(try english.article(for: .windowsAndDisplays).plainText.contains("visible work area"))
    #expect(try english.article(for: .communityAndLicense).plainText.contains("YelZap"))
    #expect(try english.article(for: .communityAndLicense).plainText.contains("Discord"))
    #expect(try english.article(for: .communityAndLicense).plainText.contains("MIT License"))
    #expect(try english.article(for: .communityAndLicense).plainText.contains("GitHub"))
    #expect(try english.article(for: .privacy).plainText.contains("never displays"))
    #expect(try english.article(for: .shortcuts).plainText.contains("⌃⌥Space"))
    #expect(try english.article(for: .troubleshooting).plainText.contains("Coming Soon"))
    #expect(try english.article(for: .communityAndLicense).externalLinks.count == 3)
    let publicHelp = english.articles.map(\.plainText).joined(separator: "\n")
    #expect(!publicHelp.contains("Spar" + "kle"))
    #expect(!publicHelp.contains(["Check for", "Updates"].joined(separator: " ")))
    #expect(!publicHelp.contains(["Support", "Rabbisir"].joined(separator: " ")))
    #expect(!publicHelp.contains("App" + "earance"))
  }

  @Test("Help is the localized final top-level menu with native disabled tour semantics")
  @MainActor
  func helpMenuIsLastAndLocalized() async throws {
    await AppKitTestSerialGate.shared.acquire()
    defer { AppKitTestSerialGate.shared.release() }
    let coordinator = RabbisirHelpWindowCoordinator(screenProvider: { NSScreen.screens.first })
    let target = NSObject()
    let chinese = ApplicationMenu.make(
      target: target,
      language: .chinese,
      helpCoordinator: coordinator
    )
    let english = ApplicationMenu.make(
      target: target,
      language: .english,
      helpCoordinator: coordinator
    )

    #expect(chinese.items.last?.title == "帮助")
    #expect(english.items.last?.title == "Help")
    let chineseHelp = try #require(chinese.items.last?.submenu)
    let englishHelp = try #require(english.items.last?.submenu)
    #expect(chineseHelp.items.first?.title == "Rabbisir 帮助")
    #expect(englishHelp.items.first?.title == "Rabbisir Help")
    let disabledTour = try #require(
      englishHelp.items.first {
        $0.action == #selector(RabbisirHelpWindowCoordinator.replayTour(_:))
      }
    )
    #expect(!disabledTour.isEnabled)
    #expect(disabledTour.toolTip == "The interface tour is available after the workspace opens.")
  }

  @Test("The help entry opens a keyboard-accessible localized native window")
  @MainActor
  func helpEntryOpensWindow() async throws {
    await AppKitTestSerialGate.shared.acquire()
    defer { AppKitTestSerialGate.shared.release() }
    let screen = try #require(NSScreen.screens.first)
    var presentedWindow: NSWindow?
    let coordinator = RabbisirHelpWindowCoordinator(
      screenProvider: { screen },
      windowAnimationBehavior: .none,
      windowPresenter: { presentedWindow = $0 }
    )
    coordinator.updateLanguage(.chinese)

    coordinator.showKeyboardShortcuts(nil)

    #expect(presentedWindow != nil)
    #expect(coordinator.selectedTopic == .shortcuts)
    #expect(coordinator.windowAccessibilityLabel == "Rabbisir 帮助")
  }

  @Test("Help restores a persisted size and clamps it to the current visible work area")
  @MainActor
  func helpSizeRestoresAndClamps() async throws {
    await AppKitTestSerialGate.shared.acquire()
    defer { AppKitTestSerialGate.shared.release() }
    let suite = "RabbisirTests.HelpWindow.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = RabbisirInterfacePreferencesStore(defaults: defaults)
    preferences.setHelpWindowSize(CGSize(width: 1_080, height: 760))
    let screen = try #require(NSScreen.screens.first)
    var presentedWindow: NSWindow?
    let coordinator = RabbisirHelpWindowCoordinator(
      screenProvider: { screen },
      interfacePreferences: preferences,
      windowAnimationBehavior: .none,
      windowPresenter: { presentedWindow = $0 }
    )

    coordinator.showHelp(nil)

    let window = try #require(presentedWindow)
    let expected = RabbisirHelpWindowLayout.size(
      preferred: CGSize(width: 1_080, height: 760),
      visibleFrame: screen.visibleFrame
    )
    #expect(window.frame.size == expected)
    #expect(screen.visibleFrame.contains(window.frame))
  }

  @Test("Help persists completed resize and safely resolves a smaller or changed display")
  @MainActor
  func helpResizePersistsAcrossDisplays() async throws {
    await AppKitTestSerialGate.shared.acquire()
    defer { AppKitTestSerialGate.shared.release() }
    let suite = "RabbisirTests.HelpResize.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = RabbisirInterfacePreferencesStore(defaults: defaults)
    let visibleFrame = CGRect(x: -800, y: 40, width: 640, height: 480)

    #expect(
      RabbisirHelpWindowLayout.size(
        preferred: CGSize(width: 4_000, height: 3_000),
        visibleFrame: visibleFrame
      ) == visibleFrame.size
    )
    #expect(
      RabbisirHelpWindowLayout.minimumSize(for: visibleFrame)
        == visibleFrame.size
    )

    let screen = try #require(NSScreen.screens.first)
    var presentedWindow: NSWindow?
    let coordinator = RabbisirHelpWindowCoordinator(
      screenProvider: { screen },
      interfacePreferences: preferences,
      windowAnimationBehavior: .none,
      windowPresenter: { presentedWindow = $0 }
    )
    coordinator.showHelp(nil)
    let window = try #require(presentedWindow)
    let storedSize = RabbisirHelpWindowLayout.size(
      preferred: CGSize(width: 1_000, height: 720),
      visibleFrame: screen.visibleFrame
    )
    window.setFrame(CGRect(origin: window.frame.origin, size: storedSize), display: false)
    coordinator.windowDidEndLiveResize(
      Notification(name: NSWindow.didEndLiveResizeNotification, object: window)
    )

    #expect(preferences.helpWindowSize == storedSize)
    window.close()

    var reopenedWindow: NSWindow?
    let reopenedCoordinator = RabbisirHelpWindowCoordinator(
      screenProvider: { screen },
      interfacePreferences: RabbisirInterfacePreferencesStore(defaults: defaults),
      windowAnimationBehavior: .none,
      windowPresenter: { reopenedWindow = $0 }
    )
    reopenedCoordinator.showHelp(nil)
    #expect(try #require(reopenedWindow).frame.size == storedSize)
  }

  @Test("Help uses untinted native regular glass without app-owned backing")
  @MainActor
  func helpUsesSharedGlassMaterial() async throws {
    await AppKitTestSerialGate.shared.acquire()
    defer { AppKitTestSerialGate.shared.release() }
    let content = NSView()
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 920, height: 680),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    RabbisirHelpMaterialPolicy.configure(window)
    let container = RabbisirHelpMaterialPolicy.makeContainer(contentView: content)

    #expect(!window.isOpaque)
    #expect(window.backgroundColor.alphaComponent == 0)
    #expect(RabbisirGlassAppKitAdapter.contentView(in: container) === content)
    if #available(macOS 26.0, *) {
      let glass = try #require(
        RabbisirGlassAppKitAdapter.nativeGlassView(in: container) as? NSGlassEffectView
      )
      #expect(glass.style == .regular)
      #expect(glass.tintColor == nil)
      #expect(container.subviews == [glass])
    } else {
      #expect(RabbisirGlassAppKitAdapter.nativeGlassView(in: container) is NSVisualEffectView)
    }
  }
}
