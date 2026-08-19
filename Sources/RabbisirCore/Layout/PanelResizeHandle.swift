import AppKit

enum PanelResizeHandleMetrics {
  static let width: CGFloat = 18
  static let protrusion: CGFloat = 9
}

enum PanelResizeHandleVariant: Equatable, Sendable {
  case composer
  case details
  case sidebar

  var size: CGSize {
    switch self {
    case .composer:
      CGSize(width: PanelResizeHandleMetrics.width, height: 44)
    case .details:
      CGSize(width: PanelResizeHandleMetrics.width, height: 128)
    case .sidebar:
      CGSize(width: PanelResizeHandleMetrics.width, height: NativeNavigationLayout.projectRowHeight)
    }
  }
}

enum PanelResizeHandleAttachment: Equatable, Sendable {
  case leading
  case trailing
}

enum PanelResizeHandleVerticalAlignment: Equatable, Sendable {
  case center
  case top(inset: CGFloat)
}

enum PanelResizeHandleVisualOwner: Equatable, Sendable {
  case bodySurface
  case handlePanel
}

enum PanelResizeHandlePresentationPolicy {
  static func visualOwner(
    for variant: PanelResizeHandleVariant
  ) -> PanelResizeHandleVisualOwner {
    variant == .composer ? .bodySurface : .handlePanel
  }
}

enum PanelResizeHandlePalette {
  static func gripOpacity(
    isHovered: Bool,
    isActive: Bool,
    isEnabled: Bool = true
  ) -> CGFloat {
    if !isEnabled { return 0.28 }
    if isActive { return 0.92 }
    if isHovered { return 0.74 }
    return 0.56
  }

  static func gripColor(
    appearance: NSAppearance,
    isHovered: Bool,
    isActive: Bool,
    isEnabled: Bool = true
  ) -> NSColor {
    let alpha = gripOpacity(
      isHovered: isHovered,
      isActive: isActive,
      isEnabled: isEnabled
    )
    var color = NSColor.labelColor
    appearance.performAsCurrentDrawingAppearance {
      color = (NSColor.labelColor.usingColorSpace(.deviceRGB) ?? NSColor.labelColor)
        .withAlphaComponent(alpha)
    }
    return color
  }
}

enum PanelResizeHandleGeometry {
  static func sidebarEarPath(in bounds: CGRect) -> CGPath {
    let path = CGMutablePath()
    let earBody = CGRect(
      x: PanelResizeHandleMetrics.protrusion,
      y: bounds.minY,
      width: max(0, bounds.width - PanelResizeHandleMetrics.protrusion),
      height: bounds.height
    )
    path.addRoundedRect(
      in: earBody,
      cornerWidth: min(7, earBody.width / 2),
      cornerHeight: min(7, earBody.height / 2)
    )
    path.addRect(
      CGRect(
        x: bounds.minX,
        y: bounds.midY - 5,
        width: min(PanelResizeHandleMetrics.protrusion + 2, bounds.width),
        height: 10
      )
    )
    return path
  }

  static func gripCenterY(
    in bounds: CGRect,
    variant: PanelResizeHandleVariant,
    attachment: PanelResizeHandleAttachment
  ) -> CGFloat {
    if variant == .composer, attachment == .trailing {
      bounds.midY - 2
    } else {
      bounds.midY
    }
  }

  static func presentationFrame(
    for bodyFrame: CGRect,
    attachment: PanelResizeHandleAttachment
  ) -> CGRect {
    switch attachment {
    case .leading:
      CGRect(
        x: bodyFrame.minX - PanelResizeHandleMetrics.protrusion,
        y: bodyFrame.minY,
        width: bodyFrame.width + PanelResizeHandleMetrics.protrusion,
        height: bodyFrame.height
      )
    case .trailing:
      CGRect(
        x: bodyFrame.minX,
        y: bodyFrame.minY,
        width: bodyFrame.width + PanelResizeHandleMetrics.protrusion,
        height: bodyFrame.height
      )
    }
  }

  static func handleFrame(
    for bodyFrame: CGRect,
    variant: PanelResizeHandleVariant,
    attachment: PanelResizeHandleAttachment,
    verticalAlignment: PanelResizeHandleVerticalAlignment = .center
  ) -> CGRect {
    let size = variant.size
    let x =
      attachment == .leading
      ? bodyFrame.minX - PanelResizeHandleMetrics.protrusion
      : bodyFrame.maxX - PanelResizeHandleMetrics.protrusion
    let y: CGFloat
    switch verticalAlignment {
    case .center:
      y = bodyFrame.midY - size.height / 2
    case .top(let inset):
      y = bodyFrame.maxY - inset - size.height
    }
    return CGRect(
      x: x,
      y: y,
      width: size.width,
      height: size.height
    )
  }

  /// Places the sidebar grip inside the row-owned extension as that extension grows.
  static func sidebarHandleFrame(
    for bodyFrame: CGRect,
    revealProgress: CGFloat
  ) -> CGRect {
    let size = PanelResizeHandleVariant.sidebar.size
    let progress = min(max(revealProgress, 0), 1)
    let hiddenX = bodyFrame.maxX - size.width / 2
    let visibleX = bodyFrame.maxX
    return CGRect(
      x: hiddenX + (visibleX - hiddenX) * progress,
      y: bodyFrame.midY - size.height / 2,
      width: size.width,
      height: size.height
    )
  }
}

@MainActor
final class PanelResizeGripDotsView: NSView {
  private let stableDotsLayer = CAShapeLayer()
  private let pulseDotsLayer = CAShapeLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    stableDotsLayer.zPosition = 1
    pulseDotsLayer.zPosition = 2
    layer?.addSublayer(stableDotsLayer)
    layer?.addSublayer(pulseDotsLayer)
    setAccessibilityElement(false)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func hitTest(_ point: NSPoint) -> NSView? { nil }

  override func layout() {
    super.layout()
    stableDotsLayer.frame = bounds
    pulseDotsLayer.frame = bounds
  }

  func update(
    color: NSColor,
    center: CGPoint
  ) {
    let path = CGMutablePath()
    for offset in [-8, 0, 8] as [CGFloat] {
      path.addEllipse(
        in: CGRect(
          x: center.x - 1.5,
          y: center.y + offset - 1.5,
          width: 3,
          height: 3
        )
      )
    }
    stableDotsLayer.path = path
    stableDotsLayer.fillColor = color.cgColor
    stableDotsLayer.opacity = 1
    pulseDotsLayer.path = path
    pulseDotsLayer.fillColor = color.cgColor
  }

  func applyMotion(policy: MotionAccessibilityPolicy) {
    let key = "Rabbisir.handleGripBreath"
    pulseDotsLayer.removeAnimation(forKey: key)
    pulseDotsLayer.opacity = 0
    guard !policy.reduceMotion else { return }

    let animation = CABasicAnimation(keyPath: "opacity")
    animation.fromValue = 0.08
    animation.toValue = 0.42
    animation.duration = RabbisirMotionToken.handleGripBreath.duration
    animation.autoreverses = true
    animation.repeatCount = .infinity
    animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
    pulseDotsLayer.add(animation, forKey: key)
  }

  var hasBreathingAnimation: Bool {
    pulseDotsLayer.animation(forKey: "Rabbisir.handleGripBreath") != nil
  }

  var stableDotsOpacity: Float { stableDotsLayer.opacity }
}

@MainActor
final class PanelResizeHandleView: NSView {
  var onDragBegan: (() -> Void)?
  var onDragChanged: ((CGFloat) -> Void)?
  var onDragEnded: (() -> Void)?
  var onResetRequested: (() -> Void)?
  var onHoverChanged: ((Bool) -> Void)?

  private var trackingAreaReference: NSTrackingArea?
  private var dragStartX: CGFloat?
  private var previousMouseDown: (timestamp: TimeInterval, location: CGPoint)?
  private var isHovered = false
  private var isActive = false
  private let attachment: PanelResizeHandleAttachment
  private let variant: PanelResizeHandleVariant
  private let gripDotsView = PanelResizeGripDotsView(frame: .zero)

  init(
    frame frameRect: NSRect,
    variant: PanelResizeHandleVariant,
    attachment: PanelResizeHandleAttachment
  ) {
    self.attachment = attachment
    self.variant = variant
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.masksToBounds = false
    gripDotsView.frame = bounds
    gripDotsView.autoresizingMask = [.width, .height]
    gripDotsView.isHidden =
      PanelResizeHandlePresentationPolicy.visualOwner(for: variant) == .bodySurface
    addSubview(gripDotsView)
    setAccessibilityRole(.splitter)
    updateAccessibility(copy: RabbisirCopy(language: RabbisirLocalization.shared.language))
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(accessibilityDisplayOptionsDidChange(_:)),
      name: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
      object: nil
    )
    applyMotion(policy: .current)
  }

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    refreshAppearance()
    applyMotion(policy: .current)
  }

  override func viewDidChangeEffectiveAppearance() {
    super.viewDidChangeEffectiveAppearance()
    refreshAppearance()
  }

  override func updateTrackingAreas() {
    if let trackingAreaReference {
      removeTrackingArea(trackingAreaReference)
    }
    let area = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(area)
    trackingAreaReference = area
    super.updateTrackingAreas()
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .resizeLeftRight)
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    onHoverChanged?(true)
    refreshAppearance()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    onHoverChanged?(false)
    refreshAppearance()
  }

  override func mouseDown(with event: NSEvent) {
    let location = event.locationInWindow
    let isTimedDoubleClick =
      previousMouseDown.map { previous in
        event.timestamp - previous.timestamp <= NSEvent.doubleClickInterval
          && hypot(location.x - previous.location.x, location.y - previous.location.y) <= 4
      } ?? false
    previousMouseDown = (event.timestamp, location)
    if event.clickCount >= 2 || isTimedDoubleClick {
      dragStartX = nil
      isActive = false
      refreshAppearance()
      onResetRequested?()
      return
    }
    dragStartX = NSEvent.mouseLocation.x
    isActive = true
    refreshAppearance()
    onDragBegan?()
  }

  override func mouseDragged(with event: NSEvent) {
    guard let dragStartX else { return }
    onDragChanged?(NSEvent.mouseLocation.x - dragStartX)
  }

  override func mouseUp(with event: NSEvent) {
    guard dragStartX != nil else { return }
    dragStartX = nil
    isActive = false
    refreshAppearance()
    onDragEnded?()
  }

  override func layout() {
    super.layout()
    gripDotsView.frame = bounds
    updateGripDots()
  }

  private func updateGripDots() {
    let dotColor = PanelResizeHandlePalette.gripColor(
      appearance: effectiveAppearance,
      isHovered: isHovered,
      isActive: isActive
    )
    let gripCenterX: CGFloat
    if variant == .sidebar {
      gripCenterX = bounds.midX
    } else {
      gripCenterX = attachment == .leading ? bounds.midX - 2 : bounds.midX + 2
    }
    let gripCenterY = PanelResizeHandleGeometry.gripCenterY(
      in: bounds,
      variant: variant,
      attachment: attachment
    )
    gripDotsView.update(
      color: dotColor,
      center: CGPoint(x: gripCenterX, y: gripCenterY)
    )
  }

  private func refreshAppearance() {
    updateGripDots()
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    setAccessibilityValue(isActive ? copy.resizeInProgress : copy.resizeAvailable)
  }

  func updateAccessibility(copy: RabbisirCopy) {
    setAccessibilityLabel(copy.resizePanelWidth)
    setAccessibilityHelp(copy.resizePanelWidthHelp)
    setAccessibilityValue(isActive ? copy.resizeInProgress : copy.resizeAvailable)
  }

  func applyMotion(policy: MotionAccessibilityPolicy) {
    gripDotsView.applyMotion(policy: policy)
  }

  var hasBreathingAnimation: Bool {
    gripDotsView.hasBreathingAnimation
  }

  var stableGripOpacity: Float { gripDotsView.stableDotsOpacity }

  @objc private func accessibilityDisplayOptionsDidChange(_ notification: Notification) {
    applyMotion(policy: .current)
  }
}

@MainActor
private final class SidebarResizeHandleGlassContainer: NSView {
  private let handleView: PanelResizeHandleView

  init(handleView: PanelResizeHandleView) {
    self.handleView = handleView
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    addSubview(handleView)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layout() {
    super.layout()
    handleView.frame = bounds
  }
}

@MainActor
final class PanelResizeHandlePanel: NSPanel {
  let handleView: PanelResizeHandleView
  private let variant: PanelResizeHandleVariant

  init(
    frame: CGRect,
    accessibilityLabel: String,
    identifier: NSUserInterfaceItemIdentifier,
    variant: PanelResizeHandleVariant,
    attachment: PanelResizeHandleAttachment
  ) {
    self.variant = variant
    handleView = PanelResizeHandleView(
      frame: .zero,
      variant: variant,
      attachment: attachment
    )
    super.init(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    isOpaque = false
    backgroundColor = .clear
    ignoresMouseEvents = false
    hasShadow = false
    isFloatingPanel = false
    hidesOnDeactivate = false
    level = .normal
    collectionBehavior = [.ignoresCycle]
    isReleasedWhenClosed = false
    isExcludedFromWindowsMenu = true
    title = accessibilityLabel
    self.identifier = identifier
    setAccessibilityLabel(accessibilityLabel)
    isMovable = false
    isMovableByWindowBackground = false
    becomesKeyOnlyIfNeeded = true
    handleView.frame = CGRect(origin: .zero, size: frame.size)
    handleView.setAccessibilityLabel(accessibilityLabel)
    handleView.setAccessibilityIdentifier(identifier.rawValue)
    if variant == .sidebar {
      let container = SidebarResizeHandleGlassContainer(handleView: handleView)
      container.frame = CGRect(origin: .zero, size: frame.size)
      contentView = container
    } else {
      contentView = handleView
    }
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  func updateAccessibility(label: String, copy: RabbisirCopy) {
    title = label
    setAccessibilityLabel(label)
    handleView.setAccessibilityLabel(label)
    handleView.updateAccessibility(copy: copy)
    handleView.setAccessibilityLabel(label)
  }

  override func order(_ place: NSWindow.OrderingMode, relativeTo otherWin: Int) {
    // The Composer hit island belongs to the input panel's ordering lifecycle.
    if variant == .composer, place == .above,
      let owner = NSApp.windows.first(where: { $0.windowNumber == otherWin })
    {
      if parent !== owner {
        parent?.removeChildWindow(self)
        owner.addChildWindow(self, ordered: .above)
      } else {
        super.order(place, relativeTo: otherWin)
      }
      return
    }
    super.order(place, relativeTo: otherWin)
  }
}
