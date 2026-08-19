import AppKit
import Combine
import QuartzCore
import SwiftUI

enum RabbisirDevelopmentLaunchOptions {
  static let sidebarInspectionDragArgument = "--sidebar-inspection-drag"
  static let firstRunPreviewArgument = "--first-run-preview"
  static let readinessFileArgument = "--dev-readiness-file"
  static let openReadinessFileArgument = "--open-readiness-file"

  static func allowsSidebarInspectionDrag(arguments: [String]) -> Bool {
    arguments.contains(sidebarInspectionDragArgument)
  }

  static func forcesFirstRunPreview(arguments: [String]) -> Bool {
    arguments.contains(firstRunPreviewArgument)
  }

  static func readinessFile(
    arguments: [String],
    temporaryDirectory: URL = FileManager.default.temporaryDirectory
  ) -> URL? {
    let readinessArguments = Set([readinessFileArgument, openReadinessFileArgument])
    let indices = arguments.indices.filter { readinessArguments.contains(arguments[$0]) }
    guard indices.count == 1, let index = indices.first,
      arguments.indices.contains(index + 1)
    else { return nil }
    let value = arguments[index + 1]
    guard value.hasPrefix("/"), !value.contains("\0") else { return nil }
    let root = temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
    let candidate = URL(fileURLWithPath: value).standardizedFileURL
    let parent = candidate.deletingLastPathComponent().resolvingSymlinksInPath().standardizedFileURL
    let supportedPrefix =
      candidate.lastPathComponent.hasPrefix("rabbisir-dev-ready.")
      || candidate.lastPathComponent.hasPrefix("rabbisir-open-ready.")
    guard parent.path == root.path || parent.path.hasPrefix(root.path + "/"), supportedPrefix
    else { return nil }
    return candidate
  }
}

private final class DesktopObservationToken: @unchecked Sendable {
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

private final class LocalEventMonitorToken: @unchecked Sendable {
  private let value: Any

  init(_ value: Any) {
    self.value = value
  }

  func remove() {
    NSEvent.removeMonitor(value)
  }
}

@MainActor
final class SpatialPanelHostingView: NSHostingView<AnyView> {
  override var isOpaque: Bool { false }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    layerContentsRedrawPolicy = .duringViewResize
    layerContentsPlacement = .bottomLeft
  }
}

@MainActor
final class SpatialPanelContentContainer: NSView {
  let slidingContentView: NSView

  override var isOpaque: Bool { false }

  init(rootView: AnyView) {
    slidingContentView = SpatialPanelHostingView(rootView: rootView)
    super.init(frame: .zero)
    wantsLayer = true
    slidingContentView.wantsLayer = true
    layerContentsRedrawPolicy = .duringViewResize
    slidingContentView.layerContentsRedrawPolicy = .duringViewResize
    layerContentsPlacement = .bottomLeft
    slidingContentView.layerContentsPlacement = .bottomLeft
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.masksToBounds = true
    addSubview(slidingContentView)
    slidingContentView.autoresizingMask = []
  }

  override func layout() {
    super.layout()
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    slidingContentView.frame = bounds
    CATransaction.commit()
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    if let editor = firstDescendant(of: ComposerTextView.self, beneath: slidingContentView) {
      let editorPoint = editor.convert(point, from: self)
      if editor.bounds.contains(editorPoint) {
        return editor.hitTest(editorPoint) ?? editor
      }
    }
    return super.hitTest(point) ?? (bounds.contains(point) ? self : nil)
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  private func firstDescendant<T: NSView>(of type: T.Type, beneath root: NSView) -> T? {
    if let match = root as? T { return match }
    for child in root.subviews {
      if let match = firstDescendant(of: type, beneath: child) {
        return match
      }
    }
    return nil
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@MainActor
final class SpatialPanel: NSPanel {
  private let acceptsKeyWindow: Bool
  private(set) var slidingContentView: NSView?
  var acceptsScrollWheelAtLocation: ((NSPoint, CGRect) -> Bool)?

  init(frame: CGRect, acceptsKeyWindow: Bool) {
    self.acceptsKeyWindow = acceptsKeyWindow
    super.init(
      contentRect: frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    becomesKeyOnlyIfNeeded = !acceptsKeyWindow
  }

  override var canBecomeKey: Bool { acceptsKeyWindow }
  override var canBecomeMain: Bool { acceptsKeyWindow }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .scrollWheel, let acceptsScrollWheelAtLocation,
      let contentView, let contentBounds = self.contentView?.bounds
    {
      guard acceptsScrollWheelAtLocation(event.locationInWindow, contentBounds) else { return }
      if let scrollView = firstScrollView(beneath: contentView) {
        scrollView.scrollWheel(with: event)
        return
      }
    }
    super.sendEvent(event)
  }

  private func firstScrollView(beneath root: NSView) -> NSScrollView? {
    if let scrollView = root as? NSScrollView { return scrollView }
    for child in root.subviews {
      if let scrollView = firstScrollView(beneath: child) { return scrollView }
    }
    return nil
  }

  @discardableResult
  func forwardScrollWheelToContent(_ event: NSEvent) -> Bool {
    guard let contentView, let scrollView = firstScrollView(beneath: contentView) else {
      return false
    }
    scrollView.scrollWheel(with: event)
    return true
  }

  func install(rootView: AnyView) {
    let container = SpatialPanelContentContainer(
      rootView: AnyView(
        RabbisirLocalizedRoot {
          RabbisirApplicationActiveRoot {
            rootView
          }
        }
      )
    )
    contentView = container
    slidingContentView = container.slidingContentView
    container.slidingContentView.frame = PanelTransitionPolicy.visibleContentFrame(
      in: container.bounds
    )
  }
}

@MainActor
private final class SpatialMainWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

/// Mouse routing for the native conversation workspace.
///
/// The transparent visual background remains part of Rabbisir's interactive
/// column so scrolling works across the full message viewport. Individual
/// text, link, and copy controls continue to own their more specific hit areas.
enum ConversationWorkspaceHitPolicy {
  static let ignoresMouseEvents = false
}

@MainActor
final class SpatialWorkspaceCoordinator: NSObject, NSWindowDelegate {
  let mainWindow: NSWindow

  private let state: WorkspaceState
  private let runtimeBridge: RuntimeBridgeStore
  private let workspaceDrawerModel: WorkspaceDrawerModel
  private let interfacePreferences: RabbisirInterfacePreferencesStore
  private var targetScreen: NSScreen
  private let sidebarPanel: SpatialPanel
  private let inputPanel: SpatialPanel
  private let composerResizeGripVisualState = ComposerResizeGripVisualState()
  private var detailsPanel: SpatialPanel?
  private var isTourDetailsPreviewVisible = false
  private var sidebarResizeHandlePanel: PanelResizeHandlePanel?
  private var conversationResizeHandlePanel: PanelResizeHandlePanel?
  private var detailsResizeHandlePanel: PanelResizeHandlePanel?
  private let sidebarTransition = PanelTransitionCoordinator()
  private let detailsTransition = PanelTransitionCoordinator()
  private var sidebarTransitionGeneration: UInt64 = 0
  private var detailsTransitionGeneration: UInt64 = 0
  private var preferredConversationWidth: CGFloat?
  private var preferredDetailsWidth = SpatialWorkspaceLayoutPolicy.detailsWidth
  private var preferredSidebarWidth: CGFloat?
  private var composerTextHeight = ComposerInputLayout.minimumTextViewportHeight
  private var workspaceDrawerHeight: CGFloat = 0
  private var workspaceDrawerTransitionGeneration: UInt64 = 0
  private let inputPanelResizeTransition = PanelResizeTransitionCoordinator()
  private let workspaceWidthResetTransition = PanelResizeTransitionCoordinator()
  private let tourPanelResizeTransition = PanelResizeTransitionCoordinator()
  private let workspaceVisibilityTransition = WorkspaceVisibilityTransitionCoordinator()
  private var tourPanelDemonstrationTask: Task<Void, Never>?
  private var tourPanelDemonstrationSnapshot: RabbisirWorkspaceWidthPreferences?
  private var conversationResizeStartWidth: CGFloat?
  private var detailsResizeStartWidth: CGFloat?
  private var sidebarResizeStartWidth: CGFloat?
  private var hoveredSidebarProjectRowFrame: CGRect?
  private var sidebarHoverHandleState = NavigationHoverHandleState()
  private var hoveredSidebarProjectID: String?
  private var sidebarResizeHandleDismissTask: Task<Void, Never>?
  private var sidebarResizeHandleVisibilityGeneration: UInt64 = 0
  private var cancellables: Set<AnyCancellable> = []
  private var observers: [DesktopObservationToken] = []
  private var outsideInteractionMonitor: LocalEventMonitorToken?
  private var outsideGlobalInteractionMonitor: LocalEventMonitorToken?
  private var sidebarScrollMonitor: LocalEventMonitorToken?
  private(set) var isWorkspaceVisible = false

  init(
    state: WorkspaceState,
    runtimeBridge: RuntimeBridgeStore,
    launchScreen: NSScreen,
    interfacePreferences: RabbisirInterfacePreferencesStore = RabbisirInterfacePreferencesStore()
  ) {
    self.state = state
    self.runtimeBridge = runtimeBridge
    self.interfacePreferences = interfacePreferences
    workspaceDrawerModel = WorkspaceDrawerModel(runtimeBridge: runtimeBridge)
    targetScreen = launchScreen
    let restoredWidths = interfacePreferences.workspaceWidths
    preferredSidebarWidth = restoredWidths.sidebar
    preferredConversationWidth = restoredWidths.conversation
    preferredDetailsWidth = restoredWidths.details ?? SpatialWorkspaceLayoutPolicy.detailsWidth

    let layout = Self.workspaceLayout(
      for: launchScreen,
      detailsVisible: false,
      preferredSidebarWidth: restoredWidths.sidebar,
      preferredConversationWidth: restoredWidths.conversation,
      preferredDetailsWidth: restoredWidths.details
    )
    mainWindow = SpatialMainWindow(
      contentRect: layout.mainFrame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false,
      screen: launchScreen
    )
    sidebarPanel = SpatialPanel(
      frame: Self.sidebarPanelFrame(for: layout),
      acceptsKeyWindow: false
    )
    sidebarPanel.acceptsScrollWheelAtLocation = { location, contentBounds in
      let navigationWidth = max(
        0,
        contentBounds.width - NativeNavigationLayout.trailingInteractionReserve
      )
      return NativeNavigationLayout.scrollInteractionBounds(
        viewportSize: contentBounds.size,
        navigationWidth: navigationWidth
      ).contains(location)
    }
    inputPanel = SpatialPanel(
      frame: Self.inputPanelFrame(for: layout),
      acceptsKeyWindow: true
    )
    super.init()

    configureMainWindow(frame: layout.mainFrame)
    configurePanel(
      sidebarPanel,
      frame: Self.sidebarPanelFrame(for: layout),
      identifier: "RabbisirApp.sidebar",
      movableByWindowBackground:
        RabbisirDevelopmentLaunchOptions.allowsSidebarInspectionDrag(
          arguments: ProcessInfo.processInfo.arguments
        ),
      rootView: AnyView(
        SpatialSidebarView(
          state: state,
          runtimeBridge: runtimeBridge,
          onProjectRowHover: { [weak self] projectID, hovering, frame in
            self?.setSidebarProjectRowHover(projectID, hovering: hovering, frame: frame)
          }
        )
      )
    )
    configurePanel(
      inputPanel,
      frame: Self.inputPanelFrame(for: layout),
      identifier: "RabbisirApp.input",
      movableByWindowBackground: false,
      rootView: AnyView(
        SpatialInputView(
          state: state,
          runtimeBridge: runtimeBridge,
          conversation: runtimeBridge.conversation,
          workspaceDrawer: workspaceDrawerModel,
          resizeGripVisualState: composerResizeGripVisualState
        )
      )
    )
    inputPanel.ignoresMouseEvents = false
    installSidebarResizeHandle(layout: layout)
    installConversationResizeHandle(layout: layout)
    installSidebarScrollRouting()
    observeState()
    observeLocalization()
    observeDesktopChanges()
  }

  deinit {
    tourPanelDemonstrationTask?.cancel()
    sidebarResizeHandleDismissTask?.cancel()
    outsideInteractionMonitor?.remove()
    outsideGlobalInteractionMonitor?.remove()
    sidebarScrollMonitor?.remove()
    for observer in observers {
      observer.remove()
    }
  }

  private func installSidebarScrollRouting() {
    guard sidebarScrollMonitor == nil,
      let monitor = NSEvent.addLocalMonitorForEvents(
        matching: .scrollWheel,
        handler: {
          [weak self] event in
          guard let self, self.isWorkspaceVisible, self.state.isSidebarVisible else {
            return event
          }
          let screenPoint = NSEvent.mouseLocation
          guard self.sidebarPanel.frame.contains(screenPoint) else { return event }
          let localPoint = NSPoint(
            x: screenPoint.x - self.sidebarPanel.frame.minX,
            y: screenPoint.y - self.sidebarPanel.frame.minY
          )
          let contentBounds = self.sidebarPanel.contentView?.bounds ?? .zero
          let navigationWidth = max(
            0,
            contentBounds.width - NativeNavigationLayout.trailingInteractionReserve
          )
          let interactionBounds = NativeNavigationLayout.scrollInteractionBounds(
            viewportSize: contentBounds.size,
            navigationWidth: navigationWidth
          )
          guard interactionBounds.contains(localPoint) else { return nil }
          _ = self.sidebarPanel.forwardScrollWheelToContent(event)
          return nil
        })
    else { return }
    sidebarScrollMonitor = LocalEventMonitorToken(monitor)
  }

  func showAll(focusInput: Bool = false) {
    let startAlpha = mainWindow.isVisible ? mainWindow.alphaValue : 0
    let layout = workspaceLayout(detailsVisible: state.isDetailsVisible)
    mainWindow.setFrame(layout.mainFrame, display: true)
    sidebarPanel.setFrame(Self.sidebarPanelFrame(for: layout), display: true)
    inputPanel.setFrame(inputPanelFrame(for: layout), display: true)

    mainWindow.makeKeyAndOrderFront(nil)
    if state.isSidebarVisible {
      sidebarTransition.cancel(contentView: sidebarPanel.slidingContentView)
      setPanelContent(sidebarPanel, visible: true, edge: .leading)
      sidebarPanel.orderFront(nil)
      showSidebarResizeHandle(for: layout)
    } else {
      sidebarResizeHandlePanel?.orderOut(nil)
      sidebarPanel.orderOut(nil)
    }
    inputPanel.orderFront(nil)
    showConversationResizeHandle(for: layout)
    if state.isDetailsVisible {
      presentDetails(animated: false)
    }
    isWorkspaceVisible = true
    setWorkspaceAlpha(startAlpha)
    workspaceVisibilityTransition.transition(
      from: startAlpha,
      to: 1,
      spec: RabbisirMotionToken.workspaceVisibilityFade,
      apply: { [weak self] alpha in
        self?.setWorkspaceAlpha(alpha)
      },
      completion: {}
    )
    NSApp.activate(ignoringOtherApps: true)
    if focusInput {
      focusNativeInput()
    }
  }

  func prepareForLaunch() {
    let layout = workspaceLayout(detailsVisible: state.isDetailsVisible)
    mainWindow.setFrame(layout.mainFrame, display: true)
    sidebarPanel.setFrame(Self.sidebarPanelFrame(for: layout), display: true)
    positionSidebarResizeHandle(for: layout)
    inputPanel.setFrame(inputPanelFrame(for: layout), display: true)

    setWorkspaceAlpha(0)
  }

  func revealAll(duration: TimeInterval) {
    if state.isDetailsVisible, detailsPanel == nil {
      presentDetails(animated: false)
      detailsPanel?.alphaValue = 0
    }
    mainWindow.makeKeyAndOrderFront(nil)
    if state.isSidebarVisible {
      sidebarPanel.orderFront(nil)
      showSidebarResizeHandle(for: workspaceLayout(detailsVisible: state.isDetailsVisible))
    }
    inputPanel.orderFront(nil)
    showConversationResizeHandle(for: workspaceLayout(detailsVisible: state.isDetailsVisible))
    if state.isDetailsVisible {
      detailsPanel?.orderFront(nil)
      if let detailsPanel {
        detailsResizeHandlePanel?.order(
          .above,
          relativeTo: detailsPanel.windowNumber
        )
      }
    }

    isWorkspaceVisible = true
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.allowsImplicitAnimation = true
      self.mainWindow.animator().alphaValue = 1
      if self.state.isSidebarVisible {
        self.sidebarPanel.animator().alphaValue = 1
        self.sidebarResizeHandlePanel?.animator().alphaValue = 1
      }
      self.inputPanel.animator().alphaValue = 1
      self.conversationResizeHandlePanel?.animator().alphaValue = 1
      self.detailsPanel?.animator().alphaValue = 1
      self.detailsResizeHandlePanel?.animator().alphaValue = 1
    }
    NSApp.activate(ignoringOtherApps: true)
  }

  func hideAll() {
    cancelTourPanelDemonstration()
    workspaceWidthResetTransition.cancel()
    sidebarTransition.cancel(contentView: sidebarPanel.slidingContentView)
    detailsTransition.cancel(contentView: detailsPanel?.slidingContentView)
    isWorkspaceVisible = false
    workspaceVisibilityTransition.transition(
      from: mainWindow.alphaValue,
      to: 0,
      spec: RabbisirMotionToken.workspaceVisibilityFade,
      apply: { [weak self] alpha in
        self?.setWorkspaceAlpha(alpha)
      },
      completion: { [weak self] in
        guard let self, !self.isWorkspaceVisible else { return }
        self.sidebarResizeHandlePanel?.orderOut(nil)
        self.conversationResizeHandlePanel?.orderOut(nil)
        self.detailsResizeHandlePanel?.orderOut(nil)
        self.detailsPanel?.orderOut(nil)
        self.inputPanel.orderOut(nil)
        self.sidebarPanel.orderOut(nil)
        self.mainWindow.orderOut(nil)
      }
    )
  }

  func toggleFromGlobalShortcut() {
    if isWorkspaceVisible {
      hideAll()
    } else {
      showAll(focusInput: true)
    }
  }

  func tourTargetFrame(for step: WorkspaceTourStep) -> CGRect? {
    switch step {
    case .sidebar:
      return sidebarPanel.frame
    case .conversation:
      return mainWindow.frame.union(inputPanel.frame)
    case .details:
      if let detailsPanel { return detailsPanel.frame }
      guard let bodyFrame = workspaceLayout(detailsVisible: true).detailsFrame else {
        return nil
      }
      let frame = Self.detailsPanelFrame(for: bodyFrame)
      let panel = SpatialPanel(frame: frame, acceptsKeyWindow: false)
      configurePanel(
        panel,
        frame: frame,
        identifier: "RabbisirApp.details.tourPreview",
        movableByWindowBackground: false,
        rootView: AnyView(SpatialDetailsView(state: state))
      )
      panel.orderFront(nil)
      detailsPanel = panel
      isTourDetailsPreviewVisible = true
      return frame
    case .island:
      return nil
    }
  }

  func finishTourDetailsPreview() {
    guard isTourDetailsPreviewVisible else { return }
    detailsPanel?.orderOut(nil)
    detailsPanel = nil
    isTourDetailsPreviewVisible = false
  }

  func startTourPanelDemonstration(
    for step: WorkspaceTourStep,
    policy: MotionAccessibilityPolicy = .current
  ) {
    cancelTourPanelDemonstration()
    let stages = WorkspaceTourPanelDemonstrationPlan.stages(
      for: step,
      reduceMotion: policy.reduceMotion
    )
    guard !stages.isEmpty else { return }

    let snapshot = RabbisirWorkspaceWidthPreferences(
      sidebar: preferredSidebarWidth,
      conversation: preferredConversationWidth,
      details: preferredDetailsWidth
    )
    tourPanelDemonstrationSnapshot = snapshot
    let detailsVisible = state.isDetailsVisible || isTourDetailsPreviewVisible
    let visibleFrame = targetScreen.visibleFrame
    let navigationBottomY = navigationBarBottomY(for: targetScreen)

    tourPanelDemonstrationTask = Task { @MainActor [weak self] in
      guard let self else { return }
      for stage in stages {
        guard !Task.isCancelled else { return }
        let layout = WorkspaceTourPanelDemonstrationPlan.layout(
          for: stage,
          visibleFrame: visibleFrame,
          navigationBarBottomY: navigationBottomY,
          snapshot: snapshot,
          detailsVisible: detailsVisible
        )
        applyTourPanelLayout(layout, policy: policy)
        do {
          try await Task.sleep(for: .milliseconds(570))
        } catch {
          return
        }
      }
      guard !Task.isCancelled else { return }
      tourPanelDemonstrationTask = nil
      tourPanelDemonstrationSnapshot = nil
    }
  }

  func cancelTourPanelDemonstration() {
    tourPanelDemonstrationTask?.cancel()
    tourPanelDemonstrationTask = nil
    tourPanelResizeTransition.cancel()
    guard let snapshot = tourPanelDemonstrationSnapshot else { return }
    tourPanelDemonstrationSnapshot = nil
    preferredSidebarWidth = snapshot.sidebar
    preferredConversationWidth = snapshot.conversation
    preferredDetailsWidth = snapshot.details ?? SpatialWorkspaceLayoutPolicy.detailsWidth
    let layout = WorkspaceTourPanelDemonstrationPlan.layout(
      for: .restored,
      visibleFrame: targetScreen.visibleFrame,
      navigationBarBottomY: navigationBarBottomY(for: targetScreen),
      snapshot: snapshot,
      detailsVisible: state.isDetailsVisible
    )
    applyTourPanelLayout(
      layout,
      policy: MotionAccessibilityPolicy(reduceMotion: true)
    )
  }

  func showAndFocusInput() {
    if !isWorkspaceVisible {
      showAll(focusInput: true)
    } else {
      focusNativeInput()
    }
  }

  func windowWillClose(_ notification: Notification) {
    guard notification.object as? NSWindow === mainWindow else { return }
    hideAll()
    NSApp.terminate(nil)
  }

  private func configureMainWindow(frame: CGRect) {
    mainWindow.identifier = NSUserInterfaceItemIdentifier("RabbisirApp.main")
    mainWindow.title = RabbisirWindowTitle.main(displayName: RabbisirAppIdentity.displayName)
    mainWindow.isOpaque = false
    mainWindow.backgroundColor = .clear
    mainWindow.hasShadow = false
    mainWindow.ignoresMouseEvents = ConversationWorkspaceHitPolicy.ignoresMouseEvents
    mainWindow.level = .normal
    mainWindow.minSize = NSSize(width: 620, height: 520)
    mainWindow.isReleasedWhenClosed = false
    mainWindow.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
    ]
    mainWindow.isMovable = false
    mainWindow.isMovableByWindowBackground = false
    mainWindow.delegate = self
    mainWindow.contentViewController = NSHostingController(
      rootView: RabbisirLocalizedRoot {
        RabbisirApplicationActiveRoot {
          SpatialMainView(
            state: state,
            runtimeBridge: runtimeBridge
          )
        }
      }
    )
    mainWindow.setFrame(frame, display: false)
  }

  private func configurePanel(
    _ panel: SpatialPanel,
    frame: CGRect,
    identifier: String,
    movableByWindowBackground: Bool = true,
    rootView: AnyView
  ) {
    panel.identifier = NSUserInterfaceItemIdentifier(identifier)
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.animationBehavior = .none
    panel.isFloatingPanel = false
    panel.hidesOnDeactivate = false
    panel.level = .normal
    panel.collectionBehavior = [
      .canJoinAllSpaces,
      .fullScreenAuxiliary,
      .ignoresCycle,
    ]
    panel.isReleasedWhenClosed = false
    panel.isMovable = movableByWindowBackground
    panel.isMovableByWindowBackground = movableByWindowBackground
    panel.install(rootView: rootView)
    panel.setFrame(frame, display: false)
    panel.slidingContentView?.frame = PanelTransitionPolicy.visibleContentFrame(
      in: panel.contentView?.bounds ?? .zero
    )
  }

  private func observeState() {
    state.$isSidebarVisible
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] visible in
        self?.cancelTourPanelDemonstration()
        self?.setSidebarVisible(visible)
      }
      .store(in: &cancellables)

    state.$isDetailsVisible
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] visible in
        self?.cancelTourPanelDemonstration()
        if visible {
          self?.presentDetails(animated: true)
        } else {
          self?.dismissDetails(animated: true)
        }
      }
      .store(in: &cancellables)

    state.$detailFocusRequest
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] _ in
        self?.focusDetailsPanel()
      }
      .store(in: &cancellables)

    runtimeBridge.$isRuntimeTransitionPresented
      .removeDuplicates()
      .sink { [weak self] isPresented in
        guard let self else { return }
        self.mainWindow.ignoresMouseEvents = ConversationWorkspaceHitPolicy.ignoresMouseEvents
      }
      .store(in: &cancellables)

    workspaceDrawerModel.$isPresented
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] isPresented in
        guard let self else { return }
        self.setWorkspaceDrawerHeight(
          isPresented ? self.currentWorkspaceDrawerLayout.expansionHeight : 0,
          animated: true
        )
      }
      .store(in: &cancellables)

    let monitor = NSEvent.addLocalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] event in
      MainActor.assumeIsolated {
        guard let self,
          self.workspaceDrawerModel.isPresented,
          event.window !== self.inputPanel,
          !(event.window is NSOpenPanel)
        else { return }
        self.workspaceDrawerModel.dismissFromOutsideInteraction()
      }
      return event
    }
    if let monitor {
      outsideInteractionMonitor = LocalEventMonitorToken(monitor)
    }
    let globalMonitor = NSEvent.addGlobalMonitorForEvents(
      matching: [.leftMouseDown, .rightMouseDown]
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        guard let self,
          self.workspaceDrawerModel.isPresented,
          !self.hasVisibleOpenPanel
        else { return }
        self.workspaceDrawerModel.dismissFromOutsideInteraction()
      }
    }
    if let globalMonitor {
      outsideGlobalInteractionMonitor = LocalEventMonitorToken(globalMonitor)
    }

    state.$composerTextHeight
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] height in
        self?.setComposerTextHeight(height, animated: true)
      }
      .store(in: &cancellables)
  }

  private func observeLocalization() {
    RabbisirLocalization.shared.$language
      .removeDuplicates()
      .sink { [weak self] language in
        self?.updateLocalizedWindowAccessibility(
          copy: RabbisirCopy(language: language)
        )
      }
      .store(in: &cancellables)
  }

  private func updateLocalizedWindowAccessibility(copy: RabbisirCopy) {
    sidebarResizeHandlePanel?.updateAccessibility(
      label: copy.resizeSidebarWidth,
      copy: copy
    )
    conversationResizeHandlePanel?.updateAccessibility(
      label: copy.resizeConversationWidth,
      copy: copy
    )
    detailsResizeHandlePanel?.updateAccessibility(
      label: copy.resizeDetailsWidth,
      copy: copy
    )
  }

  private func setSidebarVisible(_ visible: Bool) {
    sidebarTransitionGeneration &+= 1
    let generation = sidebarTransitionGeneration
    let layout = workspaceLayout(detailsVisible: state.isDetailsVisible)
    sidebarPanel.setFrame(Self.sidebarPanelFrame(for: layout), display: true)
    positionSidebarResizeHandle(for: layout)
    sidebarPanel.alphaValue = 1
    guard let contentView = sidebarPanel.slidingContentView,
      let bounds = sidebarPanel.contentView?.bounds
    else { return }

    guard isWorkspaceVisible else {
      contentView.frame =
        visible
        ? PanelTransitionPolicy.visibleContentFrame(in: bounds)
        : PanelTransitionPolicy.hiddenContentFrame(in: bounds, edge: .leading)
      sidebarPanel.orderOut(nil)
      sidebarResizeHandlePanel?.orderOut(nil)
      return
    }

    if visible {
      sidebarPanel.orderFront(nil)
      showSidebarResizeHandle(for: layout)
    } else {
      sidebarResizeHandlePanel?.orderOut(nil)
    }
    let target =
      visible
      ? PanelTransitionPolicy.visibleContentFrame(in: bounds)
      : PanelTransitionPolicy.hiddenContentFrame(in: bounds, edge: .leading)
    sidebarTransition.transition(contentView: contentView, to: target) { [weak self] in
      guard let self,
        self.sidebarTransitionGeneration == generation,
        !self.state.isSidebarVisible
      else { return }
      self.sidebarPanel.orderOut(nil)
    }
  }

  private func presentDetails(animated: Bool) {
    workspaceWidthResetTransition.cancel()
    isTourDetailsPreviewVisible = false
    let layout = workspaceLayout(detailsVisible: true)
    guard let targetBodyFrame = layout.detailsFrame else { return }
    let targetFrame = Self.detailsPanelFrame(for: targetBodyFrame)

    let panel: SpatialPanel
    let isNewPanel: Bool
    if let detailsPanel {
      panel = detailsPanel
      isNewPanel = false
    } else {
      panel = SpatialPanel(frame: targetFrame, acceptsKeyWindow: true)
      configurePanel(
        panel,
        frame: targetFrame,
        identifier: "RabbisirApp.details",
        movableByWindowBackground: false,
        rootView: AnyView(SpatialDetailsView(state: state))
      )
      detailsPanel = panel
      isNewPanel = true
    }

    detailsTransitionGeneration &+= 1
    let generation = detailsTransitionGeneration
    panel.setFrame(targetFrame, display: false)
    panel.layoutIfNeeded()
    guard let contentView = panel.slidingContentView,
      let bounds = panel.contentView?.bounds
    else { return }
    if isNewPanel {
      contentView.frame =
        animated
        ? PanelTransitionPolicy.hiddenContentFrame(in: bounds, edge: .trailing)
        : PanelTransitionPolicy.visibleContentFrame(in: bounds)
    }
    panel.alphaValue = 1
    panel.orderFront(nil)
    installDetailsResizeHandleIfNeeded(layout: layout)
    let detailsHandleTarget = detailsResizeHandleFrame(for: layout)
    if let detailsResizeHandlePanel, let detailsHandleTarget {
      if isNewPanel && animated {
        detailsResizeHandlePanel.setFrame(
          CGRect(
            x: targetFrame.maxX,
            y: detailsHandleTarget.minY,
            width: detailsHandleTarget.width,
            height: detailsHandleTarget.height
          ),
          display: false
        )
      } else {
        detailsResizeHandlePanel.setFrame(detailsHandleTarget, display: false)
      }
      detailsResizeHandlePanel.order(.above, relativeTo: panel.windowNumber)
    }

    let target = PanelTransitionPolicy.visibleContentFrame(in: bounds)
    let policy = MotionAccessibilityPolicy(
      reduceMotion: !animated || MotionAccessibilityPolicy.current.reduceMotion
    )
    var windowTargets: [(window: NSWindow, frame: CGRect)] = [
      (mainWindow, layout.mainFrame),
      (inputPanel, inputPanelFrame(for: layout)),
    ]
    if let conversationResizeHandlePanel {
      windowTargets.append(
        (conversationResizeHandlePanel, conversationResizeHandleFrame(for: layout))
      )
    }
    if let detailsResizeHandlePanel, let detailsHandleTarget {
      windowTargets.append((detailsResizeHandlePanel, detailsHandleTarget))
    }
    detailsTransition.transition(
      contentView: contentView,
      to: target,
      windowTargets: windowTargets,
      policy: policy
    ) { [weak self] in
      guard let self,
        self.detailsTransitionGeneration == generation,
        self.state.isDetailsVisible,
        self.detailsPanel === panel
      else { return }
    }
  }

  private func focusDetailsPanel() {
    guard isWorkspaceVisible else { return }
    if detailsPanel == nil {
      presentDetails(animated: false)
    }
    detailsPanel?.makeKeyAndOrderFront(nil)
  }

  private func dismissDetails(animated: Bool) {
    workspaceWidthResetTransition.cancel()
    let layout = workspaceLayout(detailsVisible: false)
    guard let panel = detailsPanel else {
      mainWindow.setFrame(layout.mainFrame, display: true)
      inputPanel.setFrame(inputPanelFrame(for: layout), display: true)
      return
    }

    detailsTransitionGeneration &+= 1
    let generation = detailsTransitionGeneration
    guard let contentView = panel.slidingContentView,
      let bounds = panel.contentView?.bounds
    else { return }
    let target = PanelTransitionPolicy.hiddenContentFrame(in: bounds, edge: .trailing)
    let policy = MotionAccessibilityPolicy(
      reduceMotion: !animated || MotionAccessibilityPolicy.current.reduceMotion
    )
    var windowTargets: [(window: NSWindow, frame: CGRect)] = [
      (mainWindow, layout.mainFrame),
      (inputPanel, inputPanelFrame(for: layout)),
    ]
    if let conversationResizeHandlePanel {
      windowTargets.append(
        (conversationResizeHandlePanel, conversationResizeHandleFrame(for: layout))
      )
    }
    if let detailsResizeHandlePanel {
      let hiddenHandleFrame = CGRect(
        x: panel.frame.maxX,
        y: detailsResizeHandlePanel.frame.minY,
        width: detailsResizeHandlePanel.frame.width,
        height: detailsResizeHandlePanel.frame.height
      )
      windowTargets.append((detailsResizeHandlePanel, hiddenHandleFrame))
    }
    detailsTransition.transition(
      contentView: contentView,
      to: target,
      windowTargets: windowTargets,
      policy: policy
    ) { [weak self] in
      guard let self,
        self.detailsTransitionGeneration == generation,
        !self.state.isDetailsVisible,
        self.detailsPanel === panel
      else { return }
      self.detailsResizeHandlePanel?.orderOut(nil)
      panel.orderOut(nil)
      self.detailsPanel = nil
    }
  }

  private func animate(duration: TimeInterval, changes: @escaping () -> Void) {
    NSAnimationContext.runAnimationGroup { context in
      context.duration =
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        ? min(duration, 0.12)
        : duration
      context.allowsImplicitAnimation = duration > 0
      changes()
    }
  }

  private func setWorkspaceAlpha(_ alpha: CGFloat) {
    mainWindow.alphaValue = alpha
    sidebarPanel.alphaValue = alpha
    sidebarResizeHandlePanel?.alphaValue = alpha
    inputPanel.alphaValue = alpha
    conversationResizeHandlePanel?.alphaValue = alpha
    detailsPanel?.alphaValue = alpha
    detailsResizeHandlePanel?.alphaValue = alpha
  }

  private func focusNativeInput() {
    NSApp.activate(ignoringOtherApps: true)
    inputPanel.makeKeyAndOrderFront(nil)
    state.requestInputFocus()
  }

  private func observeDesktopChanges() {
    let screenObserver = NotificationCenter.default.addObserver(
      forName: NSApplication.didChangeScreenParametersNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.restoreAfterDisplayChange()
      }
    }
    let spaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
      forName: NSWorkspace.activeSpaceDidChangeNotification,
      object: nil,
      queue: .main
    ) { [weak self] _ in
      MainActor.assumeIsolated {
        self?.restoreVisiblePanelsWithoutActivation()
      }
    }
    observers = [
      DesktopObservationToken(
        center: NotificationCenter.default,
        value: screenObserver
      ),
      DesktopObservationToken(
        center: NSWorkspace.shared.notificationCenter,
        value: spaceObserver
      ),
    ]
  }

  private var hasVisibleOpenPanel: Bool {
    NSApp.windows.contains { window in
      window is NSOpenPanel && window.isVisible
    }
  }

  private func restoreAfterDisplayChange() {
    let targetIdentifier = targetScreen.rabbisirDisplayIdentifier
    guard
      let screen = NSScreen.screens.first(where: {
        $0.rabbisirDisplayIdentifier == targetIdentifier
      }) ?? RabbisirPrimaryScreen.current
    else { return }
    move(to: screen)
  }

  func move(to screen: NSScreen) {
    cancelTourPanelDemonstration()
    workspaceWidthResetTransition.cancel()
    sidebarTransition.cancel(contentView: sidebarPanel.slidingContentView)
    detailsTransition.cancel(contentView: detailsPanel?.slidingContentView)
    targetScreen = screen
    let layout = workspaceLayout(detailsVisible: state.isDetailsVisible)
    mainWindow.setFrame(layout.mainFrame, display: isWorkspaceVisible)
    sidebarPanel.setFrame(
      Self.sidebarPanelFrame(for: layout),
      display: isWorkspaceVisible
    )
    positionSidebarResizeHandle(for: layout)
    inputPanel.setFrame(
      inputPanelFrame(for: layout),
      display: isWorkspaceVisible
    )
    setPanelContent(inputPanel, visible: true, edge: .leading)
    positionConversationResizeHandle(for: layout)
    if let detailsFrame = layout.detailsFrame {
      detailsPanel?.setFrame(
        Self.detailsPanelFrame(for: detailsFrame),
        display: isWorkspaceVisible
      )
      if let detailsPanel {
        setPanelContent(detailsPanel, visible: true, edge: .trailing)
      }
      positionDetailsResizeHandle(for: layout)
    }
    restoreVisiblePanelsWithoutActivation()
  }

  private func restoreVisiblePanelsWithoutActivation() {
    guard isWorkspaceVisible else { return }
    mainWindow.orderFront(nil)
    if state.isSidebarVisible {
      sidebarPanel.orderFront(nil)
      if let sidebarResizeHandlePanel, sidebarResizeHandlePanel.isVisible {
        sidebarResizeHandlePanel.order(
          .above,
          relativeTo: sidebarPanel.windowNumber
        )
      }
    }
    inputPanel.orderFront(nil)
    conversationResizeHandlePanel?.order(
      .above,
      relativeTo: inputPanel.windowNumber
    )
    if state.isDetailsVisible {
      detailsPanel?.orderFront(nil)
      if let detailsPanel {
        detailsResizeHandlePanel?.order(
          .above,
          relativeTo: detailsPanel.windowNumber
        )
      }
    }
  }

  private func setPanelContent(
    _ panel: SpatialPanel,
    visible: Bool,
    edge: PanelTransitionEdge
  ) {
    panel.layoutIfNeeded()
    guard let contentView = panel.slidingContentView,
      let bounds = panel.contentView?.bounds
    else { return }
    contentView.frame =
      visible
      ? PanelTransitionPolicy.visibleContentFrame(in: bounds)
      : PanelTransitionPolicy.hiddenContentFrame(in: bounds, edge: edge)
  }

  private func installSidebarResizeHandle(layout: SpatialWorkspaceLayout) {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    let panel = PanelResizeHandlePanel(
      frame: .zero,
      accessibilityLabel: copy.resizeSidebarWidth,
      identifier: NSUserInterfaceItemIdentifier("Rabbisir.sidebarResizeHandle"),
      variant: .sidebar,
      attachment: .trailing
    )
    panel.handleView.onDragBegan = { [weak self] in
      guard let self else { return }
      self.cancelTourPanelDemonstration()
      self.sidebarHoverHandleState.apply(.drag(true))
      self.workspaceWidthResetTransition.cancel()
      self.sidebarResizeStartWidth =
        self.sidebarPanel.frame.width - NativeNavigationLayout.trailingInteractionReserve
    }
    panel.handleView.onDragChanged = { [weak self] deltaX in
      guard let self, let startWidth = self.sidebarResizeStartWidth else { return }
      self.workspaceWidthResetTransition.cancel()
      self.preferredSidebarWidth = SpatialWorkspaceLayoutPolicy.sidebarWidth(
        from: startWidth,
        horizontalDragDelta: deltaX
      )
      self.interfacePreferences.setSidebarWidth(self.preferredSidebarWidth)
      self.applyLiveResizeLayout()
    }
    panel.handleView.onDragEnded = { [weak self] in
      guard let self else { return }
      self.preferredSidebarWidth =
        self.sidebarPanel.frame.width - NativeNavigationLayout.trailingInteractionReserve
      self.interfacePreferences.setSidebarWidth(self.preferredSidebarWidth)
      self.sidebarResizeStartWidth = nil
      self.sidebarHoverHandleState.apply(.drag(false))
      self.scheduleSidebarResizeHandleDismissalIfNeeded()
    }
    panel.handleView.onResetRequested = { [weak self] in
      guard let self else { return }
      self.sidebarResizeStartWidth = nil
      self.preferredSidebarWidth = nil
      self.interfacePreferences.setSidebarWidth(nil)
      self.animateWidthReset()
    }
    panel.handleView.onHoverChanged = { [weak self] hovering in
      guard let self else { return }
      self.sidebarHoverHandleState.apply(.handleHover(hovering))
      self.state.setSidebarHandleHoveredProjectID(
        hovering ? self.hoveredSidebarProjectID : nil
      )
      if hovering {
        self.sidebarResizeHandleDismissTask?.cancel()
      } else {
        self.scheduleSidebarResizeHandleDismissalIfNeeded()
      }
    }
    sidebarResizeHandlePanel = panel
    panel.orderOut(nil)
  }

  private func installConversationResizeHandle(layout: SpatialWorkspaceLayout) {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    let panel = PanelResizeHandlePanel(
      frame: conversationResizeHandleFrame(for: layout),
      accessibilityLabel: copy.resizeConversationWidth,
      identifier: NSUserInterfaceItemIdentifier("Rabbisir.conversationResizeHandle"),
      variant: .composer,
      attachment: .trailing
    )
    panel.handleView.onDragBegan = { [weak self] in
      guard let self else { return }
      self.cancelTourPanelDemonstration()
      self.composerResizeGripVisualState.setActive(true)
      self.workspaceWidthResetTransition.cancel()
      self.conversationResizeStartWidth =
        self.inputPanel.frame.width - PanelResizeHandleMetrics.protrusion
    }
    panel.handleView.onDragChanged = { [weak self] deltaX in
      guard let self, let startWidth = self.conversationResizeStartWidth else { return }
      self.workspaceWidthResetTransition.cancel()
      self.preferredConversationWidth = SpatialWorkspaceLayoutPolicy.conversationWidth(
        from: startWidth,
        horizontalDragDelta: deltaX
      )
      self.interfacePreferences.setConversationWidth(self.preferredConversationWidth)
      self.applyLiveResizeLayout()
    }
    panel.handleView.onDragEnded = { [weak self] in
      guard let self else { return }
      self.composerResizeGripVisualState.setActive(false)
      self.preferredConversationWidth =
        self.inputPanel.frame.width - PanelResizeHandleMetrics.protrusion
      self.interfacePreferences.setConversationWidth(self.preferredConversationWidth)
      self.conversationResizeStartWidth = nil
    }
    panel.handleView.onResetRequested = { [weak self] in
      guard let self else { return }
      self.composerResizeGripVisualState.setActive(false)
      self.conversationResizeStartWidth = nil
      self.preferredConversationWidth = nil
      self.interfacePreferences.setConversationWidth(nil)
      self.animateWidthReset()
    }
    panel.handleView.onHoverChanged = { [weak self] hovering in
      self?.composerResizeGripVisualState.setHovered(hovering)
    }
    conversationResizeHandlePanel = panel
  }

  private func installDetailsResizeHandleIfNeeded(layout: SpatialWorkspaceLayout) {
    guard detailsResizeHandlePanel == nil,
      let frame = detailsResizeHandleFrame(for: layout)
    else { return }
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    let panel = PanelResizeHandlePanel(
      frame: frame,
      accessibilityLabel: copy.resizeDetailsWidth,
      identifier: NSUserInterfaceItemIdentifier("Rabbisir.detailsResizeHandle"),
      variant: .details,
      attachment: .leading
    )
    panel.handleView.onDragBegan = { [weak self] in
      guard let self else { return }
      self.cancelTourPanelDemonstration()
      self.workspaceWidthResetTransition.cancel()
      self.detailsTransition.cancel(contentView: self.detailsPanel?.slidingContentView)
      self.detailsResizeStartWidth = self.detailsPanel.map {
        $0.frame.width - PanelResizeHandleMetrics.protrusion
      }
    }
    panel.handleView.onDragChanged = { [weak self] deltaX in
      guard let self, let startWidth = self.detailsResizeStartWidth else { return }
      self.workspaceWidthResetTransition.cancel()
      self.preferredDetailsWidth = SpatialWorkspaceLayoutPolicy.detailsWidth(
        from: startWidth,
        horizontalDragDelta: deltaX
      )
      self.interfacePreferences.setDetailsWidth(self.preferredDetailsWidth)
      self.applyLiveResizeLayout()
    }
    panel.handleView.onDragEnded = { [weak self] in
      guard let self else { return }
      if let width = self.detailsPanel?.frame.width {
        self.preferredDetailsWidth = width - PanelResizeHandleMetrics.protrusion
        self.interfacePreferences.setDetailsWidth(self.preferredDetailsWidth)
      }
      self.detailsResizeStartWidth = nil
    }
    panel.handleView.onResetRequested = { [weak self] in
      guard let self else { return }
      self.detailsTransition.cancel(contentView: self.detailsPanel?.slidingContentView)
      self.detailsResizeStartWidth = nil
      self.preferredDetailsWidth = SpatialWorkspaceLayoutPolicy.detailsWidth
      self.interfacePreferences.setDetailsWidth(nil)
      self.animateWidthReset()
    }
    detailsResizeHandlePanel = panel
  }

  private func applyLiveResizeLayout() {
    workspaceWidthResetTransition.cancel()
    let layout = workspaceLayout(detailsVisible: state.isDetailsVisible)
    sidebarPanel.setFrame(Self.sidebarPanelFrame(for: layout), display: true)
    setPanelContent(sidebarPanel, visible: true, edge: .leading)
    positionSidebarResizeHandle(for: layout)
    mainWindow.setFrame(layout.mainFrame, display: true)
    inputPanel.setFrame(inputPanelFrame(for: layout), display: true)
    setPanelContent(inputPanel, visible: true, edge: .leading)
    positionConversationResizeHandle(for: layout)
    if let detailsFrame = layout.detailsFrame, let detailsPanel {
      detailsPanel.setFrame(Self.detailsPanelFrame(for: detailsFrame), display: true)
      setPanelContent(detailsPanel, visible: true, edge: .trailing)
      positionDetailsResizeHandle(for: layout)
    }
  }

  private func applyTourPanelLayout(
    _ layout: SpatialWorkspaceLayout,
    policy: MotionAccessibilityPolicy
  ) {
    workspaceWidthResetTransition.cancel()
    inputPanelResizeTransition.cancel()
    var targets: [(window: NSWindow, frame: CGRect)] = [
      (sidebarPanel, Self.sidebarPanelFrame(for: layout)),
      (mainWindow, layout.mainFrame),
      (inputPanel, inputPanelFrame(for: layout)),
    ]
    if let sidebarResizeHandlePanel,
      let frame = sidebarResizeHandleFrame(for: layout)
    {
      targets.append((sidebarResizeHandlePanel, frame))
    }
    if let conversationResizeHandlePanel {
      targets.append((conversationResizeHandlePanel, conversationResizeHandleFrame(for: layout)))
    }
    if let detailsFrame = layout.detailsFrame, let detailsPanel {
      targets.append((detailsPanel, Self.detailsPanelFrame(for: detailsFrame)))
      if let detailsResizeHandlePanel,
        let frame = detailsResizeHandleFrame(for: layout)
      {
        targets.append((detailsResizeHandlePanel, frame))
      }
    }
    tourPanelResizeTransition.transition(
      windowTargets: targets,
      spec: RabbisirMotionToken.panelWidthReset,
      policy: policy
    ) { [weak self] in
      guard let self else { return }
      self.setPanelContent(self.sidebarPanel, visible: true, edge: .leading)
      self.setPanelContent(self.inputPanel, visible: true, edge: .leading)
      if let detailsPanel = self.detailsPanel {
        self.setPanelContent(detailsPanel, visible: true, edge: .trailing)
      }
    }
  }

  private func animateWidthReset() {
    inputPanelResizeTransition.cancel()
    let layout = workspaceLayout(detailsVisible: state.isDetailsVisible)
    var targets: [(window: NSWindow, frame: CGRect)] = [
      (sidebarPanel, Self.sidebarPanelFrame(for: layout)),
      (mainWindow, layout.mainFrame),
      (inputPanel, inputPanelFrame(for: layout)),
    ]
    if let sidebarResizeHandlePanel,
      let sidebarResizeHandleFrame = sidebarResizeHandleFrame(for: layout)
    {
      targets.append((sidebarResizeHandlePanel, sidebarResizeHandleFrame))
    }
    if let conversationResizeHandlePanel {
      targets.append(
        (conversationResizeHandlePanel, conversationResizeHandleFrame(for: layout))
      )
    }
    if let detailsFrame = layout.detailsFrame, let detailsPanel {
      targets.append((detailsPanel, Self.detailsPanelFrame(for: detailsFrame)))
      if let detailsResizeHandlePanel,
        let handleFrame = detailsResizeHandleFrame(for: layout)
      {
        targets.append((detailsResizeHandlePanel, handleFrame))
      }
    }
    workspaceWidthResetTransition.transition(
      windowTargets: targets,
      spec: RabbisirMotionToken.panelWidthReset
    ) { [weak self] in
      guard let self else { return }
      self.setPanelContent(self.sidebarPanel, visible: true, edge: .leading)
      self.setPanelContent(self.inputPanel, visible: true, edge: .leading)
      if let detailsPanel = self.detailsPanel {
        self.setPanelContent(detailsPanel, visible: true, edge: .trailing)
      }
    }
  }

  private func setWorkspaceDrawerHeight(_ requestedHeight: CGFloat, animated: Bool) {
    cancelTourPanelDemonstration()
    workspaceWidthResetTransition.cancel()
    let height = max(0, requestedHeight)
    guard abs(height - workspaceDrawerHeight) > 0.5 else {
      if height == 0 {
        workspaceDrawerModel.finishDismissal()
      }
      return
    }

    workspaceDrawerHeight = height
    workspaceDrawerTransitionGeneration &+= 1
    let generation = workspaceDrawerTransitionGeneration
    let layout = workspaceLayout(detailsVisible: state.isDetailsVisible)
    let targetFrame = inputPanelFrame(for: layout)

    guard isWorkspaceVisible else {
      inputPanelResizeTransition.cancel()
      inputPanel.setFrame(targetFrame, display: false)
      if height == 0 {
        workspaceDrawerModel.finishDismissal()
      }
      return
    }

    let policy = MotionAccessibilityPolicy.current
    guard animated, policy.allowsSpatialTransitions else {
      inputPanelResizeTransition.cancel()
      inputPanel.setFrame(targetFrame, display: true)
      if height == 0 {
        workspaceDrawerModel.finishDismissal()
      }
      return
    }

    let spec = RabbisirMotionToken.sidebarShowHide
    inputPanelResizeTransition.transition(
      window: inputPanel,
      to: targetFrame,
      spec: spec,
      policy: policy
    ) { [weak self] in
      guard let self, self.workspaceDrawerTransitionGeneration == generation else { return }
      if height == 0 {
        self.workspaceDrawerModel.finishDismissal()
      }
    }
  }

  private func setComposerTextHeight(_ requestedHeight: CGFloat, animated: Bool) {
    cancelTourPanelDemonstration()
    workspaceWidthResetTransition.cancel()
    let height = max(ComposerInputLayout.minimumTextViewportHeight, requestedHeight)
    guard abs(height - composerTextHeight) > 0.5 else { return }
    composerTextHeight = height
    workspaceDrawerTransitionGeneration &+= 1
    let targetFrame = inputPanelFrame(
      for: workspaceLayout(detailsVisible: state.isDetailsVisible)
    )
    let policy = MotionAccessibilityPolicy.current
    guard isWorkspaceVisible, animated, policy.allowsSpatialTransitions else {
      inputPanelResizeTransition.cancel()
      inputPanel.setFrame(targetFrame, display: isWorkspaceVisible)
      return
    }

    let spec = RabbisirMotionToken.composerContentResize
    inputPanelResizeTransition.transition(
      window: inputPanel,
      to: targetFrame,
      spec: spec,
      policy: policy
    ) { [weak self] in
      guard let self else { return }
      if self.workspaceDrawerHeight == 0 {
        self.workspaceDrawerModel.finishDismissal()
      }
    }
  }

  private var currentWorkspaceDrawerLayout: WorkspaceDrawerLayout {
    WorkspaceDrawerLayout.addWorkspaceOnly()
  }

  private func setSidebarProjectRowHover(
    _ projectID: String,
    hovering: Bool,
    frame: CGRect
  ) {
    if hovering {
      let resetsVerticalAnchor = NavigationHoverOwnershipPolicy.isProjectTransfer(
        activeProjectID: hoveredSidebarProjectID,
        incomingProjectID: projectID
      )
      sidebarHoverHandleState.apply(.rowHover(true))
      hoveredSidebarProjectID = projectID
      hoveredSidebarProjectRowFrame = frame
      sidebarResizeHandleDismissTask?.cancel()
      showSidebarResizeHandle(
        for: workspaceLayout(detailsVisible: state.isDetailsVisible),
        resettingAnchor: resetsVerticalAnchor
      )
    } else {
      // A delayed leave from a previous row cannot dismiss a handle that has
      // already transferred to another project.
      guard
        NavigationHoverOwnershipPolicy.acceptsLeave(
          activeProjectID: hoveredSidebarProjectID,
          leavingProjectID: projectID
        )
      else { return }
      sidebarHoverHandleState.apply(.rowHover(false))
      scheduleSidebarResizeHandleDismissalIfNeeded()
    }
  }

  private func scheduleSidebarResizeHandleDismissalIfNeeded() {
    guard !sidebarHoverHandleState.shouldRemainVisible else { return }
    sidebarResizeHandleDismissTask?.cancel()
    sidebarResizeHandleVisibilityGeneration &+= 1
    let generation = sidebarResizeHandleVisibilityGeneration
    hideSidebarResizeHandle(generation: generation)
  }

  private func hideSidebarResizeHandle(generation: UInt64) {
    guard let panel = sidebarResizeHandlePanel else { return }
    panel.ignoresMouseEvents = true
    let duration =
      MotionAccessibilityPolicy.current.reduceMotion
      ? 0
      : RabbisirMotionToken.navigationRowHandleReveal.duration
    NSAnimationContext.runAnimationGroup { context in
      context.duration = duration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().alphaValue = 0
      if let hiddenFrame = self.sidebarResizeHandleFrame(
        for: self.workspaceLayout(detailsVisible: self.state.isDetailsVisible),
        revealProgress: 0
      ) {
        panel.animator().setFrame(hiddenFrame, display: true)
      }
    } completionHandler: { [weak self, weak panel] in
      Task { @MainActor in
        guard let self, let panel,
          generation == self.sidebarResizeHandleVisibilityGeneration,
          !self.sidebarHoverHandleState.shouldRemainVisible
        else { return }
        panel.orderOut(nil)
        self.hoveredSidebarProjectID = nil
        self.state.setSidebarHandleHoveredProjectID(nil)
      }
    }
  }

  private func showSidebarResizeHandle(
    for layout: SpatialWorkspaceLayout,
    resettingAnchor: Bool = false
  ) {
    guard isWorkspaceVisible,
      state.isSidebarVisible,
      let panel = sidebarResizeHandlePanel,
      let frame = sidebarResizeHandleFrame(for: layout, revealProgress: 1)
    else {
      sidebarResizeHandlePanel?.orderOut(nil)
      return
    }
    sidebarResizeHandleVisibilityGeneration &+= 1
    sidebarResizeHandleDismissTask?.cancel()
    panel.ignoresMouseEvents = false
    panel.level = sidebarPanel.level
    panel.collectionBehavior = sidebarPanel.collectionBehavior.union(.ignoresCycle)
    panel.appearance = sidebarPanel.effectiveAppearance
    let wasVisible = panel.isVisible
    if !wasVisible || resettingAnchor {
      // Moving between rows is a new horizontal reveal at the target row. The
      // target Y is installed without animation so pointer direction can never
      // become part of the grip's entrance transition.
      panel.setFrame(
        sidebarResizeHandleFrame(for: layout, revealProgress: 0) ?? frame,
        display: true
      )
      panel.alphaValue = MotionAccessibilityPolicy.current.reduceMotion ? 1 : 0
    } else if panel.alphaValue < 1 {
      panel.alphaValue = 1
    }
    panel.order(.above, relativeTo: sidebarPanel.windowNumber)
    NSAnimationContext.runAnimationGroup { context in
      context.duration = RabbisirMotionToken.navigationRowHandleReveal.duration
      context.timingFunction = CAMediaTimingFunction(name: .easeOut)
      panel.animator().setFrame(frame, display: true)
      panel.animator().alphaValue = 1
    }
  }

  private func positionSidebarResizeHandle(for layout: SpatialWorkspaceLayout) {
    guard let frame = sidebarResizeHandleFrame(for: layout, revealProgress: 1) else {
      sidebarResizeHandlePanel?.orderOut(nil)
      return
    }
    sidebarResizeHandlePanel?.setFrame(frame, display: isWorkspaceVisible)
  }

  private func showConversationResizeHandle(for layout: SpatialWorkspaceLayout) {
    guard let panel = conversationResizeHandlePanel else { return }
    panel.level = inputPanel.level
    panel.collectionBehavior = inputPanel.collectionBehavior.union(.ignoresCycle)
    panel.setFrame(conversationResizeHandleFrame(for: layout), display: true)
    panel.order(.above, relativeTo: inputPanel.windowNumber)
  }

  private func positionConversationResizeHandle(for layout: SpatialWorkspaceLayout) {
    conversationResizeHandlePanel?.setFrame(
      conversationResizeHandleFrame(for: layout),
      display: isWorkspaceVisible
    )
  }

  private func positionDetailsResizeHandle(for layout: SpatialWorkspaceLayout) {
    guard let frame = detailsResizeHandleFrame(for: layout),
      let detailsResizeHandlePanel
    else { return }
    detailsResizeHandlePanel.setFrame(frame, display: isWorkspaceVisible)
  }

  private func conversationResizeHandleFrame(for layout: SpatialWorkspaceLayout) -> CGRect {
    PanelResizeHandleGeometry.handleFrame(
      for: layout.inputFrame,
      variant: .composer,
      attachment: .trailing,
      verticalAlignment: .top(
        inset: InputComposerShape.outerTopInset + InputComposerShape.mainTop
      )
    )
  }

  private func sidebarResizeHandleFrame(
    for layout: SpatialWorkspaceLayout,
    revealProgress: CGFloat = 1
  ) -> CGRect? {
    guard let rowFrame = hoveredSidebarProjectRowFrame else { return nil }
    let rowBodyFrame = CGRect(
      x: layout.sidebarFrame.minX,
      y: sidebarPanel.frame.maxY - rowFrame.maxY,
      width: layout.sidebarFrame.width,
      height: rowFrame.height
    )
    return PanelResizeHandleGeometry.sidebarHandleFrame(
      for: rowBodyFrame,
      revealProgress: revealProgress
    )
  }

  private func detailsResizeHandleFrame(for layout: SpatialWorkspaceLayout) -> CGRect? {
    guard let detailsFrame = layout.detailsFrame else { return nil }
    return PanelResizeHandleGeometry.handleFrame(
      for: detailsFrame,
      variant: .details,
      attachment: .leading
    )
  }

  private static func inputPanelFrame(for layout: SpatialWorkspaceLayout) -> CGRect {
    return WorkspaceDrawerLayout.expandedInputPanelFrame(
      baseFrame: PanelResizeHandleGeometry.presentationFrame(
        for: layout.inputFrame,
        attachment: .trailing
      ),
      expansionHeight: 0
    )
  }

  private static func sidebarPanelFrame(for layout: SpatialWorkspaceLayout) -> CGRect {
    CGRect(
      x: layout.sidebarFrame.minX,
      y: layout.sidebarFrame.minY,
      width: layout.sidebarFrame.width + NativeNavigationLayout.trailingInteractionReserve,
      height: layout.sidebarFrame.height
    )
  }

  private func inputPanelFrame(for layout: SpatialWorkspaceLayout) -> CGRect {
    let composerLayout = ComposerInputLayout.resolve(
      measuredTextHeight: composerTextHeight,
      visibleHeight: targetScreen.visibleFrame.height
    )
    return WorkspaceDrawerLayout.expandedInputPanelFrame(
      baseFrame: PanelResizeHandleGeometry.presentationFrame(
        for: layout.inputFrame,
        attachment: .trailing
      ),
      expansionHeight: workspaceDrawerHeight + composerLayout.panelExpansionHeight
    )
  }

  private static func detailsPanelFrame(for bodyFrame: CGRect) -> CGRect {
    PanelResizeHandleGeometry.presentationFrame(
      for: bodyFrame,
      attachment: .leading
    )
  }

  private func workspaceLayout(detailsVisible: Bool) -> SpatialWorkspaceLayout {
    Self.workspaceLayout(
      for: targetScreen,
      detailsVisible: detailsVisible,
      preferredSidebarWidth: preferredSidebarWidth,
      preferredConversationWidth: preferredConversationWidth,
      preferredDetailsWidth: preferredDetailsWidth
    )
  }

  private static func workspaceLayout(
    for screen: NSScreen,
    detailsVisible: Bool,
    preferredSidebarWidth: CGFloat? = nil,
    preferredConversationWidth: CGFloat? = nil,
    preferredDetailsWidth: CGFloat? = nil
  ) -> SpatialWorkspaceLayout {
    return SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: screen.visibleFrame,
      detailsVisible: detailsVisible,
      navigationBarBottomY: navigationBarBottomY(for: screen),
      preferredSidebarWidth: preferredSidebarWidth,
      preferredConversationWidth: preferredConversationWidth,
      preferredDetailsWidth: preferredDetailsWidth
    )
  }

  private static func navigationBarBottomY(for screen: NSScreen) -> CGFloat {
    let navigationFrame = MenuBarOverlayPlacement.frame(
      for: MenuBarScreenGeometry(screen: screen),
      islandSize: MenuBarIslandPresentation.size
    )
    return navigationFrame?.minY ?? screen.visibleFrame.maxY
  }

  private func navigationBarBottomY(for screen: NSScreen) -> CGFloat {
    Self.navigationBarBottomY(for: screen)
  }

  private static let panelGap: CGFloat = 16
}
