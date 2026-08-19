import AppKit
import CoreGraphics

private final class RabbisirDisplayObservationToken: @unchecked Sendable {
  private let center: NotificationCenter
  private let value: NSObjectProtocol

  init(center: NotificationCenter, value: NSObjectProtocol) {
    self.center = center
    self.value = value
  }

  func remove() {
    center.removeObserver(value)
  }
}

struct RabbisirDisplayDescriptor: Equatable, Sendable {
  let identifier: UInt32
  let localizedName: String
  let isPrimary: Bool
  let isBuiltIn: Bool
  let pixelSize: CGSize
  let frame: CGRect
  let visibleFrame: CGRect
}

struct RabbisirDisplayMenuEntry: Equatable, Sendable {
  let identifier: UInt32
  let title: String
}

enum RabbisirDisplayCatalog {
  @MainActor
  static func current() -> [RabbisirDisplayDescriptor] {
    let primaryIdentifier = RabbisirPrimaryScreen.current?.rabbisirDisplayIdentifier
    return NSScreen.screens.compactMap { screen in
      guard let identifier = screen.rabbisirDisplayIdentifier else { return nil }
      return RabbisirDisplayDescriptor(
        identifier: identifier,
        localizedName: screen.localizedName,
        isPrimary: identifier == primaryIdentifier,
        isBuiltIn: CGDisplayIsBuiltin(identifier) != 0,
        pixelSize: CGSize(
          width: CGDisplayPixelsWide(identifier),
          height: CGDisplayPixelsHigh(identifier)
        ),
        frame: screen.frame,
        visibleFrame: screen.visibleFrame
      )
    }
  }

  static func entries(
    from descriptors: [RabbisirDisplayDescriptor],
    language: RabbisirInterfaceLanguage
  ) -> [RabbisirDisplayMenuEntry] {
    let sorted = descriptors.sorted(by: displayOrder)
    var externalIndex = 0
    return sorted.map { descriptor in
      let kind: String
      if descriptor.isBuiltIn {
        kind = language == .chinese ? "内建显示器" : "Built-in Display"
      } else {
        externalIndex += 1
        kind =
          language == .chinese
          ? "外接显示器 \(externalIndex)"
          : "External Display \(externalIndex)"
      }
      let primary =
        descriptor.isPrimary
        ? (language == .chinese ? " · 主显示器" : " · Main Display")
        : ""
      let width = Int(descriptor.pixelSize.width.rounded())
      let height = Int(descriptor.pixelSize.height.rounded())
      return RabbisirDisplayMenuEntry(
        identifier: descriptor.identifier,
        title: "\(kind)\(primary) · \(descriptor.localizedName) · \(width) × \(height)"
      )
    }
  }

  private static func displayOrder(
    _ lhs: RabbisirDisplayDescriptor,
    _ rhs: RabbisirDisplayDescriptor
  ) -> Bool {
    if lhs.isPrimary != rhs.isPrimary { return lhs.isPrimary }
    if lhs.isBuiltIn != rhs.isBuiltIn { return lhs.isBuiltIn }
    let nameOrder = lhs.localizedName.localizedStandardCompare(rhs.localizedName)
    if nameOrder != .orderedSame { return nameOrder == .orderedAscending }
    if lhs.pixelSize.width != rhs.pixelSize.width {
      return lhs.pixelSize.width < rhs.pixelSize.width
    }
    if lhs.pixelSize.height != rhs.pixelSize.height {
      return lhs.pixelSize.height < rhs.pixelSize.height
    }
    return lhs.identifier < rhs.identifier
  }
}

enum RabbisirWindowPlacement {
  static func frame(
    currentFrame: CGRect,
    minimumSize: CGSize,
    sourceVisibleFrame: CGRect?,
    targetVisibleFrame: CGRect
  ) -> CGRect {
    let target = targetVisibleFrame.standardized
    guard target.width > 0, target.height > 0 else { return currentFrame }

    let minimumWidth = min(max(1, minimumSize.width), target.width)
    let minimumHeight = min(max(1, minimumSize.height), target.height)
    let width = min(max(currentFrame.width, minimumWidth), target.width)
    let height = min(max(currentFrame.height, minimumHeight), target.height)
    let source = sourceVisibleFrame?.standardized
    let sourceIsUsable = source.map { $0.width > 0 && $0.height > 0 } == true

    let normalizedCenterX: CGFloat
    let normalizedCenterY: CGFloat
    if let source, sourceIsUsable {
      normalizedCenterX = (currentFrame.midX - source.minX) / source.width
      normalizedCenterY = (currentFrame.midY - source.minY) / source.height
    } else {
      normalizedCenterX = 0.5
      normalizedCenterY = 0.5
    }

    var origin = CGPoint(
      x: target.minX + target.width * normalizedCenterX - width / 2,
      y: target.minY + target.height * normalizedCenterY - height / 2
    )
    origin.x = min(max(origin.x, target.minX), target.maxX - width)
    origin.y = min(max(origin.y, target.minY), target.maxY - height)
    return CGRect(origin: origin, size: CGSize(width: width, height: height)).integral
  }
}

@MainActor
enum RabbisirWindowMover {
  static func move(_ window: NSWindow, to screen: NSScreen) {
    let frame = RabbisirWindowPlacement.frame(
      currentFrame: window.frame,
      minimumSize: window.minSize,
      sourceVisibleFrame: window.screen?.visibleFrame,
      targetVisibleFrame: screen.visibleFrame
    )
    window.setFrame(frame, display: window.isVisible)
  }
}

@MainActor
final class RabbisirDisplayMenuCoordinator: NSObject {
  static let shared = RabbisirDisplayMenuCoordinator()

  private let notificationCenter: NotificationCenter
  private let descriptors: @MainActor () -> [RabbisirDisplayDescriptor]
  private var observation: RabbisirDisplayObservationToken?
  private weak var installedMenu: NSMenu?
  private var installedLanguage: RabbisirInterfaceLanguage = .chinese
  private var canMigrate: @MainActor () -> Bool = { false }
  private var migrate: @MainActor (RabbisirDisplayDescriptor) -> Bool = { _ in false }
  private(set) var selectedDisplayIdentifier: UInt32?

  init(
    notificationCenter: NotificationCenter = .default,
    descriptors: @escaping @MainActor () -> [RabbisirDisplayDescriptor] = {
      RabbisirDisplayCatalog.current()
    }
  ) {
    self.notificationCenter = notificationCenter
    self.descriptors = descriptors
    super.init()
    let observer = notificationCenter.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.screenParametersDidChange()
      }
    }
    observation = RabbisirDisplayObservationToken(
      center: notificationCenter,
      value: observer
    )
  }

  deinit {
    observation?.remove()
  }

  func configure(
    canMigrate: @escaping @MainActor () -> Bool,
    migrate: @escaping @MainActor (RabbisirDisplayDescriptor) -> Bool
  ) {
    self.canMigrate = canMigrate
    self.migrate = migrate
    refreshMenu()
  }

  func makeMenu(language: RabbisirInterfaceLanguage) -> NSMenu {
    let title = language == .chinese ? "窗口" : "Window"
    let menu = NSMenu(title: title)
    menu.autoenablesItems = false
    menu.delegate = self
    installedMenu = menu
    installedLanguage = language
    refreshMenu()
    return menu
  }

  var targetScreen: NSScreen? {
    let available = NSScreen.screens
    if let selectedDisplayIdentifier,
      let selected = available.first(where: {
        $0.rabbisirDisplayIdentifier == selectedDisplayIdentifier
      })
    {
      return selected
    }
    return RabbisirPrimaryScreen.current ?? available.first
  }

  @objc func selectDisplay(_ sender: NSMenuItem) {
    guard canMigrate(),
      let identifier = (sender.representedObject as? NSNumber)?.uint32Value,
      let descriptor = descriptors().first(where: { $0.identifier == identifier }),
      migrate(descriptor)
    else {
      refreshMenu()
      return
    }
    selectedDisplayIdentifier = identifier
    refreshMenu()
  }

  func menuNeedsUpdate(_ menu: NSMenu) {
    guard menu === installedMenu else { return }
    refreshMenu()
  }

  private func screenParametersDidChange() {
    let available = descriptors()
    guard !available.isEmpty else {
      selectedDisplayIdentifier = nil
      refreshMenu(using: available)
      return
    }
    let target =
      available.first(where: { $0.identifier == selectedDisplayIdentifier })
      ?? available.first(where: \.isPrimary)
      ?? available.first
    if let target, canMigrate(), migrate(target) {
      selectedDisplayIdentifier = target.identifier
    } else if selectedDisplayIdentifier == nil {
      selectedDisplayIdentifier = target?.identifier
    }
    refreshMenu(using: available)
  }

  private func refreshMenu(using available: [RabbisirDisplayDescriptor]? = nil) {
    guard let menu = installedMenu else { return }
    let available = available ?? descriptors()
    let entries = RabbisirDisplayCatalog.entries(
      from: available,
      language: installedLanguage
    )
    if selectedDisplayIdentifier == nil
      || !available.contains(where: { $0.identifier == selectedDisplayIdentifier })
    {
      selectedDisplayIdentifier =
        available.first(where: \.isPrimary)?.identifier
        ?? entries.first?.identifier
    }

    menu.removeAllItems()
    guard !entries.isEmpty else {
      menu.addItem(
        statusItem(
          installedLanguage == .chinese ? "没有可用显示器" : "No Displays Available"
        ))
      return
    }

    let migrationAvailable = canMigrate()
    let help =
      installedLanguage == .chinese
      ? "将 Rabbisir 的全部窗口移动到此显示器"
      : "Move all Rabbisir windows to this display"
    for entry in entries {
      let item = NSMenuItem(
        title: entry.title,
        action: #selector(selectDisplay(_:)),
        keyEquivalent: ""
      )
      item.target = self
      item.representedObject = NSNumber(value: entry.identifier)
      item.toolTip = help
      item.isEnabled = migrationAvailable
      item.state = entry.identifier == selectedDisplayIdentifier ? .on : .off
      menu.addItem(item)
    }
    if !migrationAvailable {
      menu.addItem(.separator())
      menu.addItem(
        statusItem(
          installedLanguage == .chinese
            ? "当前没有可迁移的 Rabbisir 窗口"
            : "No Rabbisir windows are available to move"
        ))
    }
  }

  private func statusItem(_ title: String) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    item.isEnabled = false
    return item
  }
}

extension RabbisirDisplayMenuCoordinator: NSMenuDelegate {}

extension NSScreen {
  var rabbisirDisplayIdentifier: UInt32? {
    (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.uint32Value
  }
}
