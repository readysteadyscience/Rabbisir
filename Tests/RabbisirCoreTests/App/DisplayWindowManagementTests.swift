import AppKit
import Testing

@testable import RabbisirCore

@MainActor
private final class DisplayFixtureStore {
  var displays: [RabbisirDisplayDescriptor]
  var migrations: [UInt32] = []
  var canMigrate = false

  init(displays: [RabbisirDisplayDescriptor]) {
    self.displays = displays
  }
}

@Suite("Display window management")
struct DisplayWindowManagementTests {
  @Test("Display entries are stable, sorted, localized, and distinguish identical names")
  func displayEntriesDistinguishIdenticalNames() {
    let displays = [
      descriptor(
        id: 30,
        name: "Studio Display",
        primary: false,
        builtIn: false,
        pixels: CGSize(width: 5_120, height: 2_880)
      ),
      descriptor(
        id: 10,
        name: "Built-in Retina Display",
        primary: true,
        builtIn: true,
        pixels: CGSize(width: 3_456, height: 2_234)
      ),
      descriptor(
        id: 20,
        name: "Studio Display",
        primary: false,
        builtIn: false,
        pixels: CGSize(width: 5_120, height: 2_880)
      ),
    ]

    let chinese = RabbisirDisplayCatalog.entries(from: displays, language: .chinese)
    let english = RabbisirDisplayCatalog.entries(from: displays, language: .english)

    #expect(chinese.map(\.identifier) == [10, 20, 30])
    #expect(chinese[0].title == "内建显示器 · 主显示器 · Built-in Retina Display · 3456 × 2234")
    #expect(chinese[1].title == "外接显示器 1 · Studio Display · 5120 × 2880")
    #expect(chinese[2].title == "外接显示器 2 · Studio Display · 5120 × 2880")
    #expect(
      english[0].title == "Built-in Display · Main Display · Built-in Retina Display · 3456 × 2234")
    #expect(english[1].title == "External Display 1 · Studio Display · 5120 × 2880")
    #expect(Set(english.map(\.title)).count == 3)
  }

  @Test("Window fitting preserves relative placement and clamps every edge to the target")
  func windowFrameFitsTargetVisibleArea() {
    let source = CGRect(x: 0, y: 0, width: 1_000, height: 800)
    let target = CGRect(x: 2_000, y: -400, width: 1_000, height: 800)

    let translated = RabbisirWindowPlacement.frame(
      currentFrame: CGRect(x: 100, y: 100, width: 400, height: 300),
      minimumSize: CGSize(width: 320, height: 240),
      sourceVisibleFrame: source,
      targetVisibleFrame: target
    )
    let clamped = RabbisirWindowPlacement.frame(
      currentFrame: CGRect(x: -500, y: 900, width: 1_400, height: 900),
      minimumSize: CGSize(width: 880, height: 620),
      sourceVisibleFrame: source,
      targetVisibleFrame: target
    )

    #expect(translated == CGRect(x: 2_100, y: -300, width: 400, height: 300))
    #expect(target.contains(clamped))
    #expect(clamped.size == target.size)
  }

  @Test("A target smaller than the current minimum still leaves the complete window reachable")
  func undersizedDisplayKeepsWindowReachable() {
    let target = CGRect(x: -900, y: 100, width: 700, height: 500)
    let frame = RabbisirWindowPlacement.frame(
      currentFrame: CGRect(x: 0, y: 0, width: 980, height: 700),
      minimumSize: CGSize(width: 880, height: 620),
      sourceVisibleFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
      targetVisibleFrame: target
    )

    #expect(frame == target)
  }

  @Test("Screen-parameter notification refreshes the installed menu")
  @MainActor
  func screenNotificationRefreshesMenu() throws {
    let center = NotificationCenter()
    let store = DisplayFixtureStore(
      displays: [descriptor(id: 1, name: "Display A", primary: true)]
    )
    let coordinator = RabbisirDisplayMenuCoordinator(
      notificationCenter: center,
      descriptors: { store.displays }
    )
    coordinator.configure(canMigrate: { true }, migrate: { _ in true })
    let menu = coordinator.makeMenu(language: .english)
    #expect(menu.items.filter { $0.representedObject != nil }.count == 1)

    store.displays.append(descriptor(id: 2, name: "Display B"))
    center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)

    #expect(menu.items.filter { $0.representedObject != nil }.count == 2)
    #expect(menu.items.map(\.title).contains { $0.contains("Display B") })
  }

  @Test("A disconnected target falls back without invoking a stale menu destination")
  @MainActor
  func disconnectedTargetFailsSafely() throws {
    let center = NotificationCenter()
    let store = DisplayFixtureStore(
      displays: [
        descriptor(id: 1, name: "Primary", primary: true),
        descriptor(id: 2, name: "External"),
      ]
    )
    let coordinator = RabbisirDisplayMenuCoordinator(
      notificationCenter: center,
      descriptors: { store.displays }
    )
    coordinator.configure(
      canMigrate: { true },
      migrate: { display in
        store.migrations.append(display.identifier)
        return true
      }
    )
    let menu = coordinator.makeMenu(language: .chinese)
    let external = try #require(
      menu.items.first { ($0.representedObject as? NSNumber)?.uint32Value == 2 }
    )
    coordinator.selectDisplay(external)
    #expect(store.migrations == [2])

    store.displays = [descriptor(id: 1, name: "Primary", primary: true)]
    center.post(name: NSApplication.didChangeScreenParametersNotification, object: nil)
    #expect(store.migrations == [2, 1])

    coordinator.selectDisplay(external)
    #expect(store.migrations == [2, 1])
    #expect(coordinator.selectedDisplayIdentifier == 1)
  }

  @Test("Display actions are disabled when Rabbisir has no migratable windows")
  @MainActor
  func menuDisablesUnavailableMigration() throws {
    let store = DisplayFixtureStore(
      displays: [descriptor(id: 1, name: "Only Display", primary: true)]
    )
    let coordinator = RabbisirDisplayMenuCoordinator(
      notificationCenter: NotificationCenter(),
      descriptors: { store.displays }
    )
    coordinator.configure(canMigrate: { store.canMigrate }, migrate: { _ in true })

    let chinese = coordinator.makeMenu(language: .chinese)
    let display = try #require(chinese.items.first { $0.representedObject != nil })
    #expect(!display.isEnabled)
    #expect(chinese.items.map(\.title).contains("当前没有可迁移的 Rabbisir 窗口"))

    store.canMigrate = true
    coordinator.menuNeedsUpdate(chinese)
    let enabledDisplay = try #require(
      chinese.items.first { $0.representedObject != nil }
    )
    #expect(enabledDisplay.isEnabled)
    #expect(!chinese.items.map(\.title).contains("当前没有可迁移的 Rabbisir 窗口"))

    store.canMigrate = false
    let english = coordinator.makeMenu(language: .english)
    #expect(english.items.map(\.title).contains("No Rabbisir windows are available to move"))
  }

  private func descriptor(
    id: UInt32,
    name: String,
    primary: Bool = false,
    builtIn: Bool = false,
    pixels: CGSize = CGSize(width: 1_920, height: 1_080)
  ) -> RabbisirDisplayDescriptor {
    RabbisirDisplayDescriptor(
      identifier: id,
      localizedName: name,
      isPrimary: primary,
      isBuiltIn: builtIn,
      pixelSize: pixels,
      frame: CGRect(x: 0, y: 0, width: pixels.width / 2, height: pixels.height / 2),
      visibleFrame: CGRect(x: 0, y: 0, width: pixels.width / 2, height: pixels.height / 2)
    )
  }
}
