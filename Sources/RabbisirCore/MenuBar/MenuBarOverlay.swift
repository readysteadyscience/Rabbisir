import AppKit
import Combine
import QuartzCore

private final class ObservationToken: @unchecked Sendable {
  let value: NSObjectProtocol

  init(_ value: NSObjectProtocol) {
    self.value = value
  }
}

public struct ScreenInsets: Equatable, Sendable {
  public let top: CGFloat
  public let left: CGFloat
  public let bottom: CGFloat
  public let right: CGFloat

  public init(top: CGFloat, left: CGFloat, bottom: CGFloat, right: CGFloat) {
    self.top = top
    self.left = left
    self.bottom = bottom
    self.right = right
  }
}

public struct MenuBarScreenGeometry: Equatable, Sendable {
  public let frame: CGRect
  public let visibleFrame: CGRect
  public let safeInsets: ScreenInsets
  public let auxiliaryTopLeftArea: CGRect?
  public let auxiliaryTopRightArea: CGRect?

  public init(
    frame: CGRect,
    visibleFrame: CGRect,
    safeInsets: ScreenInsets,
    auxiliaryTopLeftArea: CGRect? = nil,
    auxiliaryTopRightArea: CGRect? = nil
  ) {
    self.frame = frame
    self.visibleFrame = visibleFrame
    self.safeInsets = safeInsets
    self.auxiliaryTopLeftArea = auxiliaryTopLeftArea
    self.auxiliaryTopRightArea = auxiliaryTopRightArea
  }

  @MainActor
  init(screen: NSScreen) {
    let insets = screen.safeAreaInsets
    self.init(
      frame: screen.frame,
      visibleFrame: screen.visibleFrame,
      safeInsets: ScreenInsets(
        top: insets.top,
        left: insets.left,
        bottom: insets.bottom,
        right: insets.right
      ),
      auxiliaryTopLeftArea: screen.auxiliaryTopLeftArea,
      auxiliaryTopRightArea: screen.auxiliaryTopRightArea
    )
  }
}

public enum MenuBarOverlayPlacement {
  public static func frame(
    for geometry: MenuBarScreenGeometry,
    islandSize: CGSize,
    horizontalAnchorOffsetX: CGFloat = 0
  ) -> CGRect? {
    guard islandSize.width > 0, islandSize.height > 0 else { return nil }

    let auxiliaryAreas = [
      geometry.auxiliaryTopLeftArea,
      geometry.auxiliaryTopRightArea,
    ]
    .compactMap { $0 }
    .filter { $0.width >= islandSize.width + 12 && $0.height >= islandSize.height }

    if let area = auxiliaryAreas.min(by: {
      abs($0.midX - geometry.frame.midX) < abs($1.midX - geometry.frame.midX)
    }) {
      let isLeftArea = area.midX < geometry.frame.midX
      let x =
        isLeftArea
        ? area.maxX - islandSize.width - 6
        : area.minX + 6
      return CGRect(
        x: x,
        y: area.midY - islandSize.height / 2,
        width: islandSize.width,
        height: islandSize.height
      )
    }

    let menuBandHeight = max(
      islandSize.height,
      geometry.frame.maxY - geometry.visibleFrame.maxY,
      geometry.safeInsets.top
    )
    let safeMinX = geometry.frame.minX + geometry.safeInsets.left
    let safeMaxX = geometry.frame.maxX - geometry.safeInsets.right
    guard safeMaxX - safeMinX >= islandSize.width else { return nil }

    let centeredX =
      geometry.frame.midX - horizontalAnchorOffsetX - islandSize.width / 2
    let x = min(max(centeredX, safeMinX), safeMaxX - islandSize.width)
    return CGRect(
      x: x,
      y: geometry.frame.maxY - menuBandHeight + (menuBandHeight - islandSize.height) / 2,
      width: islandSize.width,
      height: islandSize.height
    )
  }
}

enum MenuBarIslandPresentation {
  static let browserControlWidth: CGFloat = 38
  static let panelControlWidth: CGFloat = 38
  static let workspaceVisibilityWidth: CGFloat = 38
  static let controlSpacing: CGFloat = 4
  static let controlsWidth =
    browserControlWidth + panelControlWidth * 2
    + workspaceVisibilityWidth + controlSpacing * 3
  static let size = CGSize(width: controlsWidth + 8, height: 30)
  static let containerBackgroundColor = NSColor.clear
  static let hoverIconOpacity: CGFloat = 1
  static let activeIconOpacity: CGFloat = 0.92
  static let inactiveIconOpacity: CGFloat = 0.72
  static let disabledIconOpacity: CGFloat = 0.38
  static let pressedIconOpacity: CGFloat = 0.58
  static let hoverFillOpacity: CGFloat = 0
  static let pressedFillOpacity: CGFloat = 0
  static let hoverBorderOpacity: CGFloat = 0
  static let hoverScale: CGFloat = 1.06
  static let pressedScale: CGFloat = 0.94
  static let interactionDuration: TimeInterval = 0.12
  static let visibilityControlsCenterOffsetX =
    (browserControlWidth - workspaceVisibilityWidth) / 2
  @MainActor
  static var symbolConfiguration: NSImage.SymbolConfiguration {
    NSImage.SymbolConfiguration(pointSize: 13, weight: .semibold)
  }
  static let browserControlSymbolName = "globe"
  static let hideWorkspaceSymbolName = "eye.slash"
  static let showWorkspaceSymbolName = "eye"

  static func workspaceVisibilitySymbolName(isVisible: Bool) -> String {
    isVisible ? hideWorkspaceSymbolName : showWorkspaceSymbolName
  }

  static func sidebarTitle(isVisible: Bool) -> String {
    isVisible ? "隐藏项目与对话" : "显示项目与对话"
  }

  static func sidebarTitle(
    isVisible: Bool,
    language: RabbisirInterfaceLanguage
  ) -> String {
    switch (language, isVisible) {
    case (.chinese, true): "隐藏项目与对话"
    case (.chinese, false): "显示项目与对话"
    case (.english, true): "Hide Projects and Conversations"
    case (.english, false): "Show Projects and Conversations"
    }
  }

  static func detailsTitle(isVisible: Bool) -> String {
    isVisible ? "隐藏详情" : "显示详情"
  }

  static func detailsTitle(
    isVisible: Bool,
    language: RabbisirInterfaceLanguage
  ) -> String {
    switch (language, isVisible) {
    case (.chinese, true): "隐藏详情"
    case (.chinese, false): "显示详情"
    case (.english, true): "Hide Details"
    case (.english, false): "Show Details"
    }
  }

  static func workspaceVisibilityTitle(
    isVisible: Bool,
    language: MenuBarInterfaceLanguage
  ) -> String {
    switch (language, isVisible) {
    case (.chinese, true): "隐藏"
    case (.chinese, false): "显示"
    case (.english, true): "Hide"
    case (.english, false): "Show"
    }
  }

  static func panelControlsEnabled(isWorkspaceVisible: Bool) -> Bool {
    isWorkspaceVisible
  }

  static func iconColor(for appearance: NSAppearance) -> NSColor {
    var color = NSColor.white
    appearance.performAsCurrentDrawingAppearance {
      color = NSColor.labelColor.usingColorSpace(.sRGB) ?? .labelColor
    }
    return color
  }
}

@MainActor
private final class MenuBarAppearanceSentinel {
  nonisolated(unsafe) private let statusItem: NSStatusItem
  private var appearanceObservation: NSKeyValueObservation?
  private let onAppearanceChange: (NSAppearance) -> Void

  init(onAppearanceChange: @escaping (NSAppearance) -> Void) {
    self.onAppearanceChange = onAppearanceChange
    statusItem = NSStatusBar.system.statusItem(withLength: 0)
    guard let button = statusItem.button else { return }
    appearanceObservation = button.observe(\.effectiveAppearance, options: [.initial, .new]) {
      [weak self] _, _ in
      MainActor.assumeIsolated {
        self?.publishCurrentAppearance()
      }
    }
  }

  deinit {
    appearanceObservation?.invalidate()
    NSStatusBar.system.removeStatusItem(statusItem)
  }

  func refresh() {
    publishCurrentAppearance()
  }

  private func publishCurrentAppearance() {
    guard let appearance = statusItem.button?.effectiveAppearance else { return }
    onAppearanceChange(appearance)
  }
}

@MainActor
final class MenuBarOverlayPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
    frameRect
  }
}

@MainActor
private class MenuBarIslandButton: NSButton {
  private var pointerInside = false
  private var pressed = false
  private var representsActiveState = true
  private var pointerTrackingArea: NSTrackingArea?
  private var menuBarIconColor = NSColor.labelColor

  override var needsPanelToBecomeKey: Bool { false }

  override var isEnabled: Bool {
    didSet { updatePresentation() }
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
    true
  }

  override func mouseDown(with event: NSEvent) {
    pressed = true
    updatePresentation()
    super.mouseDown(with: event)
    pressed = false
    updatePresentation()
  }

  override func resetCursorRects() {
    super.resetCursorRects()
    addCursorRect(bounds, cursor: isEnabled ? .pointingHand : .arrow)
  }

  override func updateTrackingAreas() {
    super.updateTrackingAreas()
    if let pointerTrackingArea {
      removeTrackingArea(pointerTrackingArea)
    }
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.activeAlways, .inVisibleRect, .mouseEnteredAndExited],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    pointerTrackingArea = trackingArea
  }

  override func mouseEntered(with event: NSEvent) {
    pointerInside = true
    window?.invalidateCursorRects(for: self)
    updatePresentation()
  }

  override func mouseExited(with event: NSEvent) {
    pointerInside = false
    window?.invalidateCursorRects(for: self)
    updatePresentation()
  }

  func setActivePresentation(_ isActive: Bool) {
    representsActiveState = isActive
    updatePresentation()
  }

  func setMenuBarIconColor(_ color: NSColor) {
    menuBarIconColor = color
    updatePresentation()
  }

  private func updatePresentation() {
    wantsLayer = true
    contentTintColor = menuBarIconColor
    if !title.isEmpty {
      attributedTitle = NSAttributedString(
        string: title,
        attributes: [
          .font: NSFont.systemFont(ofSize: 11, weight: .semibold),
          .foregroundColor: menuBarIconColor,
        ]
      )
    }
    let resolvedOpacity: CGFloat
    if !isEnabled {
      resolvedOpacity = MenuBarIslandPresentation.disabledIconOpacity
    } else if pressed {
      resolvedOpacity = MenuBarIslandPresentation.pressedIconOpacity
    } else if pointerInside {
      resolvedOpacity = MenuBarIslandPresentation.hoverIconOpacity
    } else if representsActiveState {
      resolvedOpacity = MenuBarIslandPresentation.activeIconOpacity
    } else {
      resolvedOpacity = MenuBarIslandPresentation.inactiveIconOpacity
    }
    alphaValue = resolvedOpacity

    let highlighted = isEnabled && (pointerInside || pressed)
    let scale =
      pressed
      ? MenuBarIslandPresentation.pressedScale
      : highlighted ? MenuBarIslandPresentation.hoverScale : 1
    let duration =
      NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
      ? 0
      : MenuBarIslandPresentation.interactionDuration
    CATransaction.begin()
    CATransaction.setAnimationDuration(duration)
    CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeInEaseOut))
    layer?.cornerRadius = 8
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.borderWidth = 0
    layer?.borderColor = NSColor.clear.cgColor
    layer?.shadowOpacity = 0
    layer?.shadowRadius = 0
    layer?.shadowOffset = .zero
    layer?.transform = CATransform3DMakeScale(scale, scale, 1)
    CATransaction.commit()
  }
}

@MainActor
private final class BrowserControlStatusButton: MenuBarIslandButton {
  private let symbolView = NSImageView()
  private var phase: BrowserControlPhase = .idle
  private var reduceMotionObserver: NSObjectProtocol?
  private var menuBarIconColor = NSColor.labelColor

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configureContents()
    reduceMotionObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.applyAppearance()
      }
    }
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  func update(phase: BrowserControlPhase, copy: RabbisirMenuBarCopy) {
    self.phase = phase
    applyAppearance()
    let label = "\(copy.browserControl), \(copy.browserAccessibilityStatus(phase: phase))"
    toolTip = label
    setAccessibilityLabel(label)
  }

  override func setMenuBarIconColor(_ color: NSColor) {
    menuBarIconColor = color
    super.setMenuBarIconColor(color)
    applyAppearance()
  }

  private func configureContents() {
    imagePosition = .noImage
    title = ""
    symbolView.image = NSImage(
      systemSymbolName: MenuBarIslandPresentation.browserControlSymbolName,
      accessibilityDescription: nil
    )?.withSymbolConfiguration(MenuBarIslandPresentation.symbolConfiguration)
    symbolView.contentTintColor = menuBarIconColor
    symbolView.wantsLayer = true
    symbolView.translatesAutoresizingMaskIntoConstraints = false

    addSubview(symbolView)
    NSLayoutConstraint.activate([
      symbolView.centerYAnchor.constraint(equalTo: centerYAnchor),
      symbolView.centerXAnchor.constraint(equalTo: centerXAnchor),
      symbolView.widthAnchor.constraint(equalToConstant: 14),
      symbolView.heightAnchor.constraint(equalToConstant: 14),
    ])
  }

  private func applyAppearance() {
    symbolView.layer?.removeAnimation(forKey: "browser-control-status")
    symbolView.layer?.opacity = 1

    switch phase {
    case .idle:
      symbolView.contentTintColor = menuBarIconColor
    case .active:
      symbolView.contentTintColor = menuBarIconColor
    case .failed:
      symbolView.contentTintColor = menuBarIconColor
    }

    switch BrowserControlPresentation.motion(
      for: phase,
      reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    ) {
    case .none:
      break
    case .breathe:
      installStatusAnimation(from: 1, to: 0.46, duration: 1.1)
    case .flash:
      installStatusAnimation(from: 1, to: 0.12, duration: 0.18)
    }
  }

  private func installStatusAnimation(from: Float, to: Float, duration: CFTimeInterval) {
    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = from
    animation.toValue = to
    animation.duration = duration
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    symbolView.layer?.add(animation, forKey: "browser-control-status")
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    symbolView.contentTintColor = menuBarIconColor
  }
}

@MainActor
final class MenuBarIslandContentView: NSView {
  private let state: WorkspaceState
  private let browserControlButton = BrowserControlStatusButton()
  private let sidebarButton = MenuBarIslandButton()
  private let detailsButton = MenuBarIslandButton()
  private let workspaceVisibilityButton = MenuBarIslandButton()
  private let isWorkspaceVisible: () -> Bool
  private let setWorkspaceVisible: (Bool) -> Void
  private let localization: RabbisirLocalization
  private var cancellables: Set<AnyCancellable> = []
  private var browserStatusPopover: NSPopover?

  init(
    state: WorkspaceState,
    frame: CGRect,
    localization: RabbisirLocalization,
    isWorkspaceVisible: @escaping () -> Bool,
    setWorkspaceVisible: @escaping (Bool) -> Void
  ) {
    self.state = state
    self.localization = localization
    self.isWorkspaceVisible = isWorkspaceVisible
    self.setWorkspaceVisible = setWorkspaceVisible
    super.init(frame: frame)
    configureView()
    observeState()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var acceptsFirstResponder: Bool { false }

  private func configureView() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor

    configureBrowserControlButton()
    configure(
      sidebarButton,
      symbolName: "sidebar.left",
      action: #selector(toggleSidebar)
    )
    configure(
      detailsButton,
      symbolName: "sidebar.right",
      action: #selector(toggleDetails)
    )
    configureWorkspaceVisibilityButton()

    let controls = NSStackView(
      views: [
        browserControlButton,
        sidebarButton,
        detailsButton,
        workspaceVisibilityButton,
      ]
    )
    controls.orientation = .horizontal
    controls.alignment = .centerY
    controls.distribution = .fill
    controls.spacing = 4
    controls.translatesAutoresizingMaskIntoConstraints = false
    addSubview(controls)

    NSLayoutConstraint.activate([
      controls.centerXAnchor.constraint(equalTo: centerXAnchor),
      controls.centerYAnchor.constraint(equalTo: centerYAnchor),
      controls.widthAnchor.constraint(equalToConstant: MenuBarIslandPresentation.controlsWidth),
      controls.heightAnchor.constraint(equalToConstant: 26),
    ])
  }

  private func configureBrowserControlButton() {
    browserControlButton.bezelStyle = .inline
    browserControlButton.isBordered = false
    browserControlButton.target = self
    browserControlButton.action = #selector(showBrowserControlStatus)
    browserControlButton.focusRingType = .exterior
    browserControlButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      browserControlButton.widthAnchor.constraint(
        equalToConstant: MenuBarIslandPresentation.browserControlWidth
      ),
      browserControlButton.heightAnchor.constraint(equalToConstant: 26),
    ])
  }

  private func configure(_ button: NSButton, symbolName: String, action: Selector) {
    let image = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: nil
    )?.withSymbolConfiguration(MenuBarIslandPresentation.symbolConfiguration)
    image?.isTemplate = true
    button.image = image
    button.title = ""
    button.imagePosition = .imageOnly
    button.bezelStyle = .inline
    button.isBordered = false
    button.target = self
    button.action = action
    button.focusRingType = .exterior
    button.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      button.widthAnchor.constraint(equalToConstant: MenuBarIslandPresentation.panelControlWidth),
      button.heightAnchor.constraint(equalToConstant: 26),
    ])
  }

  private func configureWorkspaceVisibilityButton() {
    workspaceVisibilityButton.bezelStyle = .inline
    workspaceVisibilityButton.isBordered = false
    workspaceVisibilityButton.target = self
    workspaceVisibilityButton.action = #selector(toggleWorkspaceVisibility)
    workspaceVisibilityButton.focusRingType = .exterior
    workspaceVisibilityButton.translatesAutoresizingMaskIntoConstraints = false
    NSLayoutConstraint.activate([
      workspaceVisibilityButton.widthAnchor.constraint(
        equalToConstant: MenuBarIslandPresentation.workspaceVisibilityWidth
      ),
      workspaceVisibilityButton.heightAnchor.constraint(equalToConstant: 26),
    ])
    updateWorkspaceVisibility(isVisible: isWorkspaceVisible())
  }

  func applyMenuBarAppearance(_ appearance: NSAppearance) {
    let color = MenuBarIslandPresentation.iconColor(for: appearance)
    browserControlButton.setMenuBarIconColor(color)
    sidebarButton.setMenuBarIconColor(color)
    detailsButton.setMenuBarIconColor(color)
    workspaceVisibilityButton.setMenuBarIconColor(color)
  }

  func updateWorkspaceVisibility(
    isVisible: Bool,
    language: RabbisirInterfaceLanguage? = nil
  ) {
    let title = MenuBarIslandPresentation.workspaceVisibilityTitle(
      isVisible: isVisible,
      language: language ?? localization.language
    )
    let symbolName = MenuBarIslandPresentation.workspaceVisibilitySymbolName(
      isVisible: isVisible
    )
    let image = NSImage(
      systemSymbolName: symbolName,
      accessibilityDescription: nil
    )?.withSymbolConfiguration(MenuBarIslandPresentation.symbolConfiguration)
    image?.isTemplate = true
    workspaceVisibilityButton.image = image
    workspaceVisibilityButton.title = ""
    workspaceVisibilityButton.imagePosition = .imageOnly
    workspaceVisibilityButton.setActivePresentation(isVisible)
    workspaceVisibilityButton.toolTip = title
    workspaceVisibilityButton.setAccessibilityLabel(title)
    let panelControlsEnabled = MenuBarIslandPresentation.panelControlsEnabled(
      isWorkspaceVisible: isVisible
    )
    sidebarButton.isEnabled = panelControlsEnabled
    detailsButton.isEnabled = panelControlsEnabled
  }

  private func observeState() {
    state.$isSidebarVisible
      .sink { [weak self] isVisible in
        self?.updateSidebarButton(isVisible: isVisible)
      }
      .store(in: &cancellables)
    state.$isDetailsVisible
      .sink { [weak self] isVisible in
        self?.updateDetailsButton(isVisible: isVisible)
      }
      .store(in: &cancellables)
    state.$browserControlPhase
      .sink { [weak self] phase in
        self?.updateBrowserControlButton(phase: phase)
      }
      .store(in: &cancellables)
    localization.$language
      .removeDuplicates()
      .sink { [weak self] language in
        guard let self else { return }
        self.updateSidebarButton(
          isVisible: self.state.isSidebarVisible,
          language: language
        )
        self.updateDetailsButton(
          isVisible: self.state.isDetailsVisible,
          language: language
        )
        self.updateWorkspaceVisibility(
          isVisible: self.isWorkspaceVisible(),
          language: language
        )
        self.updateBrowserControlButton(phase: self.state.browserControlPhase)
      }
      .store(in: &cancellables)
  }

  private func updateSidebarButton(
    isVisible: Bool,
    language: RabbisirInterfaceLanguage? = nil
  ) {
    let title = MenuBarIslandPresentation.sidebarTitle(
      isVisible: isVisible,
      language: language ?? localization.language
    )
    sidebarButton.setActivePresentation(isVisible)
    sidebarButton.toolTip = title
    sidebarButton.setAccessibilityLabel(title)
  }

  private func updateDetailsButton(
    isVisible: Bool,
    language: RabbisirInterfaceLanguage? = nil
  ) {
    let title = MenuBarIslandPresentation.detailsTitle(
      isVisible: isVisible,
      language: language ?? localization.language
    )
    detailsButton.setActivePresentation(isVisible)
    detailsButton.toolTip = title
    detailsButton.setAccessibilityLabel(title)
  }

  private func updateBrowserControlButton(phase: BrowserControlPhase) {
    browserControlButton.update(
      phase: phase, copy: RabbisirCopy(language: localization.language).menuBar)
    if browserStatusPopover?.isShown == true {
      browserStatusPopover?.contentViewController = browserStatusController(for: phase)
    }
  }

  @objc private func toggleSidebar() {
    guard isWorkspaceVisible() else { return }
    state.toggleSidebar()
  }

  @objc private func toggleDetails() {
    guard isWorkspaceVisible() else { return }
    state.toggleDetails()
  }

  @objc private func toggleWorkspaceVisibility() {
    let shouldShow = !isWorkspaceVisible()
    setWorkspaceVisible(shouldShow)
    updateWorkspaceVisibility(isVisible: shouldShow)
  }

  @objc private func showBrowserControlStatus() {
    if browserStatusPopover?.isShown == true {
      browserStatusPopover?.close()
      return
    }

    let popover = NSPopover()
    popover.behavior = .transient
    popover.animates = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    popover.contentViewController = browserStatusController(
      for: state.browserControlPhase
    )
    browserStatusPopover = popover
    popover.show(
      relativeTo: browserControlButton.bounds,
      of: browserControlButton,
      preferredEdge: .minY
    )
  }

  private func browserStatusController(for phase: BrowserControlPhase) -> NSViewController {
    let controller = NSViewController()
    let container = NSView(frame: CGRect(x: 0, y: 0, width: 260, height: 108))

    let copy = RabbisirCopy(language: localization.language).menuBar
    let title = NSTextField(labelWithString: copy.browserControl)
    title.font = .systemFont(ofSize: 13, weight: .semibold)
    title.frame = CGRect(x: 14, y: 78, width: 232, height: 18)

    let status = NSTextField(labelWithString: phase.title(copy: copy))
    status.font = .systemFont(ofSize: 12, weight: .semibold)
    status.textColor = browserControlStatusColor(for: phase)
    status.frame = CGRect(x: 14, y: 53, width: 232, height: 17)

    let detail = NSTextField(wrappingLabelWithString: phase.detail(copy: copy))
    detail.font = .systemFont(ofSize: 11)
    detail.textColor = .secondaryLabelColor
    detail.frame = CGRect(x: 14, y: 12, width: 232, height: 34)

    container.addSubview(title)
    container.addSubview(status)
    container.addSubview(detail)
    container.setAccessibilityLabel(
      "\(copy.browserControl), \(copy.browserAccessibilityStatus(phase: phase)). \(phase.detail(copy: copy))"
    )
    controller.view = container
    controller.preferredContentSize = container.frame.size
    return controller
  }

  private func browserControlStatusColor(
    for phase: BrowserControlPhase
  ) -> NSColor {
    switch phase {
    case .idle:
      .labelColor
    case .active:
      .systemGreen
    case .failed:
      .systemRed
    }
  }
}

@MainActor
final class MenuBarOverlayCoordinator: NSObject {
  private let state: WorkspaceState
  private weak var mainWindow: NSWindow?
  private let panel: MenuBarOverlayPanel
  private let contentView: MenuBarIslandContentView
  private let isWorkspaceVisible: () -> Bool
  private let localization: RabbisirLocalization
  private var localizationCancellable: AnyCancellable?
  private var appearanceSentinel: MenuBarAppearanceSentinel?
  private var mainWindowVisibilityObservation: NSKeyValueObservation?
  private var lastScreen: NSScreen?
  private var observers: [ObservationToken] = []
  private let islandSize = MenuBarIslandPresentation.size

  init(
    state: WorkspaceState,
    mainWindow: NSWindow,
    initiallyHidden: Bool = false,
    localization: RabbisirLocalization = .shared,
    isWorkspaceVisible: @escaping () -> Bool,
    setWorkspaceVisible: @escaping (Bool) -> Void
  ) {
    self.state = state
    self.mainWindow = mainWindow
    self.isWorkspaceVisible = isWorkspaceVisible
    self.localization = localization
    lastScreen = mainWindow.screen ?? NSScreen.main
    contentView = MenuBarIslandContentView(
      state: state,
      frame: CGRect(origin: .zero, size: MenuBarIslandPresentation.size),
      localization: localization,
      isWorkspaceVisible: isWorkspaceVisible,
      setWorkspaceVisible: setWorkspaceVisible
    )
    panel = MenuBarOverlayPanel(
      contentRect: CGRect(origin: .zero, size: islandSize),
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    super.init()

    configurePanel()
    appearanceSentinel = MenuBarAppearanceSentinel { [weak contentView] appearance in
      contentView?.applyMenuBarAppearance(appearance)
    }
    panel.alphaValue = initiallyHidden ? 0 : 1
    installObservers()
    observeLocalization()
    observeMainWindowVisibility()
    repositionAndShowIfPossible()
  }

  deinit {
    mainWindowVisibilityObservation?.invalidate()
    for observer in observers {
      NotificationCenter.default.removeObserver(observer.value)
    }
  }

  func repositionAndShowIfPossible() {
    if let screen = mainWindow?.screen {
      lastScreen = screen
    }
    guard let screen = lastScreen ?? NSScreen.main,
      let frame = MenuBarOverlayPlacement.frame(
        for: MenuBarScreenGeometry(screen: screen),
        islandSize: islandSize,
        horizontalAnchorOffsetX: MenuBarIslandPresentation.visibilityControlsCenterOffsetX
      )
    else {
      panel.orderOut(nil)
      return
    }

    panel.setFrame(frame, display: true)
    panel.orderFrontRegardless()
    appearanceSentinel?.refresh()
  }

  func reveal(duration: TimeInterval) {
    repositionAndShowIfPossible()
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.allowsImplicitAnimation = true
      panel.animator().alphaValue = 1
    }
  }

  var tourTargetFrame: CGRect {
    panel.frame
  }

  private func configurePanel() {
    panel.level = .popUpMenu
    panel.isOpaque = false
    panel.backgroundColor = MenuBarIslandPresentation.containerBackgroundColor
    panel.hasShadow = false
    panel.ignoresMouseEvents = false
    panel.hidesOnDeactivate = false
    panel.becomesKeyOnlyIfNeeded = true
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .ignoresCycle,
    ]
    panel.contentView = contentView
    panel.setAccessibilityLabel(
      RabbisirCopy(language: RabbisirLocalization.shared.language).menuBar.islandAccessibility
    )
  }

  private func observeLocalization() {
    localizationCancellable = localization.$language
      .removeDuplicates()
      .sink { [weak self] language in
        self?.panel.setAccessibilityLabel(
          RabbisirCopy(language: language).menuBar.islandAccessibility
        )
      }
  }

  private func installObservers() {
    let center = NotificationCenter.default
    let applicationNames: [Notification.Name] = [
      NSApplication.didBecomeActiveNotification,
      NSApplication.didResignActiveNotification,
      NSApplication.didChangeScreenParametersNotification,
    ]
    let windowNames: [Notification.Name] = [
      NSWindow.didMoveNotification,
      NSWindow.didResizeNotification,
      NSWindow.didMiniaturizeNotification,
      NSWindow.didDeminiaturizeNotification,
    ]

    func observe(_ name: Notification.Name, object: Any?) -> ObservationToken {
      let observer = center.addObserver(forName: name, object: object, queue: .main) {
        [weak self] _ in
        MainActor.assumeIsolated {
          self?.repositionAndShowIfPossible()
        }
      }
      return ObservationToken(observer)
    }

    observers = applicationNames.map { observe($0, object: nil) }
    observers += windowNames.map { observe($0, object: mainWindow) }
    let spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.repositionAndShowIfPossible()
      }
    }
    observers.append(ObservationToken(spaceObserver))
  }

  private func observeMainWindowVisibility() {
    mainWindowVisibilityObservation = mainWindow?.observe(\.isVisible, options: [.initial, .new]) {
      [weak self] _, change in
      Task { @MainActor [weak self] in
        guard let self else { return }
        self.contentView.updateWorkspaceVisibility(
          isVisible: change.newValue ?? self.isWorkspaceVisible()
        )
        self.repositionAndShowIfPossible()
      }
    }
  }

}
