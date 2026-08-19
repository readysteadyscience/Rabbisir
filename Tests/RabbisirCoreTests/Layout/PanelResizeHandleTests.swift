import AppKit
import Testing

@testable import RabbisirCore

@MainActor
private final class ResizeHandleOrderingTestWindow: NSWindow {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { true }
}

@Suite("Panel resize handles")
struct PanelResizeHandleTests {
  @Test("Grip dots follow the system semantic foreground in both appearances")
  func gripUsesSemanticForeground() throws {
    let light = try #require(NSAppearance(named: .aqua))
    let dark = try #require(NSAppearance(named: .darkAqua))
    let lightColor = try #require(
      PanelResizeHandlePalette.gripColor(
        appearance: light,
        isHovered: false,
        isActive: false
      ).usingColorSpace(.deviceRGB)
    )
    let darkColor = try #require(
      PanelResizeHandlePalette.gripColor(
        appearance: dark,
        isHovered: false,
        isActive: false
      ).usingColorSpace(.deviceRGB)
    )

    #expect(lightColor.redComponent < 0.5)
    #expect(darkColor.redComponent > 0.5)
  }

  @Test("Composer grip visuals belong to the input surface while its panel keeps the hit area")
  func composerGripVisualOwnership() {
    #expect(
      PanelResizeHandlePresentationPolicy.visualOwner(for: .composer)
        == .bodySurface
    )
    #expect(
      PanelResizeHandlePresentationPolicy.visualOwner(for: .details)
        == .handlePanel
    )
  }

  @Test("Composer hover and press feedback preserve the semantic contrast ordering")
  func composerGripInteractionContrast() {
    let idle = PanelResizeHandlePalette.gripOpacity(
      isHovered: false,
      isActive: false
    )
    let hovered = PanelResizeHandlePalette.gripOpacity(
      isHovered: true,
      isActive: false
    )
    let active = PanelResizeHandlePalette.gripOpacity(
      isHovered: true,
      isActive: true
    )

    #expect(idle < hovered)
    #expect(hovered < active)
  }

  @Test("The visible handle owns its hit area and cannot move its panel")
  @MainActor
  func handleOwnsOnlyItsHitArea() {
    let frame = CGRect(origin: .zero, size: PanelResizeHandleVariant.composer.size)
    let panel = PanelResizeHandlePanel(
      frame: frame,
      accessibilityLabel: "调整宽度",
      identifier: NSUserInterfaceItemIdentifier("Rabbisir.testResizeHandle"),
      variant: .composer,
      attachment: .trailing
    )
    let handle = panel.handleView

    #expect(handle.hitTest(CGPoint(x: frame.midX, y: frame.midY)) === handle)
    #expect(handle.hitTest(CGPoint(x: -1, y: frame.midY)) == nil)
    #expect(!panel.isMovable)
    #expect(!panel.isMovableByWindowBackground)
    #expect(!panel.ignoresMouseEvents)
    #expect(panel.identifier?.rawValue == "Rabbisir.testResizeHandle")
    #expect(handle.accessibilityLabel() == "调整宽度")
  }

  @Test("Composer and detail handles use distinct semantic heights")
  func handleVariantsStayIndependent() {
    #expect(PanelResizeHandleVariant.composer.size.height == 44)
    #expect(PanelResizeHandleVariant.details.size.height == 128)
    #expect(
      PanelResizeHandleVariant.sidebar.size.height
        == NativeNavigationLayout.projectRowHeight
    )
  }

  @Test("Composer handle aligns to the input surface top and joins its trailing edge")
  func composerHandleUsesInputSurfaceTop() {
    let inputFrame = CGRect(x: 600, y: 16, width: 780, height: 129)
    let topInset = InputComposerShape.outerTopInset + InputComposerShape.mainTop
    let handle = PanelResizeHandleGeometry.handleFrame(
      for: inputFrame,
      variant: .composer,
      attachment: .trailing,
      verticalAlignment: .top(inset: topInset)
    )
    let presentation = PanelResizeHandleGeometry.presentationFrame(
      for: inputFrame,
      attachment: .trailing
    )

    #expect(handle.maxY == inputFrame.maxY - topInset)
    #expect(InputComposerShape.outerBottomInset == 0)
    #expect(handle.minX < inputFrame.maxX)
    #expect(handle.maxX == presentation.maxX)
    #expect(presentation.minX == inputFrame.minX)
  }

  @Test("Composer grip dots remain bound to the ear while the workspace drawer grows")
  func composerGripDotsFollowTheEar() {
    let composerHeight = InputComposerShape.collapsedSurfaceHeight
    let collapsedContainerHeight = InputComposerShape.outerTopInset + composerHeight
    let expandedContainerHeight = collapsedContainerHeight + 286

    let collapsedTop = InputComposerShape.resizeGripTopOffset(
      containerHeight: collapsedContainerHeight,
      composerSurfaceHeight: composerHeight
    )
    let expandedTop = InputComposerShape.resizeGripTopOffset(
      containerHeight: expandedContainerHeight,
      composerSurfaceHeight: composerHeight
    )

    #expect(collapsedTop == InputComposerShape.outerTopInset + InputComposerShape.mainTop)
    #expect(expandedTop == collapsedTop + 286)
  }

  @Test("Grip dots use the optical center of each connected contour")
  func gripDotsUseConnectedContourCenter() {
    let composerBounds = CGRect(x: 0, y: 0, width: 18, height: 44)
    let detailsBounds = CGRect(x: 0, y: 0, width: 18, height: 128)

    #expect(
      PanelResizeHandleGeometry.gripCenterY(
        in: composerBounds,
        variant: .composer,
        attachment: .trailing
      ) == composerBounds.midY - 2
    )
    #expect(
      PanelResizeHandleGeometry.gripCenterY(
        in: detailsBounds,
        variant: .details,
        attachment: .leading
      ) == detailsBounds.midY
    )
  }

  @Test("Double-click resets without starting a resize drag")
  @MainActor
  func doubleClickRequestsReset() throws {
    let handle = PanelResizeHandleView(
      frame: CGRect(origin: .zero, size: PanelResizeHandleVariant.composer.size),
      variant: .composer,
      attachment: .trailing
    )
    var resetCount = 0
    var dragCount = 0
    handle.onResetRequested = { resetCount += 1 }
    handle.onDragBegan = { dragCount += 1 }
    let event = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: .zero,
        modifierFlags: [],
        timestamp: 0,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 2,
        pressure: 0
      )
    )

    handle.mouseDown(with: event)

    #expect(resetCount == 1)
    #expect(dragCount == 0)
  }

  @Test("Resize handle remains above its body after the body regains key focus")
  @MainActor
  func handleMaintainsHitOrderAfterBodyFocus() throws {
    let previousKeyWindow = ResizeHandleOrderingTestWindow(
      contentRect: CGRect(x: 80, y: 80, width: 80, height: 80),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    let body = ResizeHandleOrderingTestWindow(
      contentRect: CGRect(x: 120, y: 120, width: 240, height: 120),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    let handle = PanelResizeHandlePanel(
      frame: CGRect(x: 350, y: 150, width: 18, height: 44),
      accessibilityLabel: "调整测试面板宽度",
      identifier: NSUserInterfaceItemIdentifier("Rabbisir.testResizeHandleOrdering"),
      variant: .composer,
      attachment: .trailing
    )
    defer {
      handle.orderOut(nil)
      body.orderOut(nil)
      previousKeyWindow.orderOut(nil)
    }

    previousKeyWindow.makeKeyAndOrderFront(nil)
    body.orderFront(nil)
    handle.order(.above, relativeTo: body.windowNumber)
    body.makeKeyAndOrderFront(nil)

    let windowNumbers = try #require(NSWindow.windowNumbers(options: []))
    let handleIndex = try #require(
      windowNumbers.firstIndex(of: NSNumber(value: handle.windowNumber)))
    let bodyIndex = try #require(windowNumbers.firstIndex(of: NSNumber(value: body.windowNumber)))
    #expect(handleIndex < bodyIndex)
  }

  @Test("Two native single-click events inside the system interval also request reset")
  @MainActor
  func timedNativeClicksRequestReset() throws {
    let handle = PanelResizeHandleView(
      frame: CGRect(origin: .zero, size: PanelResizeHandleVariant.sidebar.size),
      variant: .sidebar,
      attachment: .trailing
    )
    var resetCount = 0
    handle.onResetRequested = { resetCount += 1 }
    let first = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: CGPoint(x: 9, y: 17),
        modifierFlags: [],
        timestamp: 1,
        windowNumber: 0,
        context: nil,
        eventNumber: 0,
        clickCount: 1,
        pressure: 0
      )
    )
    let second = try #require(
      NSEvent.mouseEvent(
        with: .leftMouseDown,
        location: CGPoint(x: 9, y: 17),
        modifierFlags: [],
        timestamp: 1.1,
        windowNumber: 0,
        context: nil,
        eventNumber: 1,
        clickCount: 1,
        pressure: 0
      )
    )

    handle.mouseDown(with: first)
    handle.mouseDown(with: second)

    #expect(resetCount == 1)
  }

  @Test("Composer grip contour is continuously filled across its top join")
  func composerGripContourHasNoJoinGap() {
    let rect = CGRect(x: 0, y: 0, width: 789, height: 121)
    let path = InputComposerShape().path(in: rect)
    let bodyRight = rect.maxX - PanelResizeHandleMetrics.protrusion

    for x in stride(
      from: bodyRight - 1,
      through: rect.maxX - 1 - 4,
      by: 1
    ) {
      #expect(path.contains(CGPoint(x: x, y: InputComposerShape.mainTop + 1)))
    }
    #expect(path.contains(CGPoint(x: rect.maxX - 1, y: InputComposerShape.mainTop + 5)))
  }

  @Test("Grip dots breathe unless Reduce Motion is enabled")
  @MainActor
  func gripDotsRespectReduceMotion() {
    let handle = PanelResizeHandleView(
      frame: CGRect(x: 0, y: 0, width: 18, height: 44),
      variant: .composer,
      attachment: .trailing
    )

    handle.applyMotion(policy: MotionAccessibilityPolicy(reduceMotion: false))
    #expect(handle.hasBreathingAnimation)
    #expect(handle.stableGripOpacity == 1)

    handle.applyMotion(policy: MotionAccessibilityPolicy(reduceMotion: true))
    #expect(!handle.hasBreathingAnimation)
    #expect(handle.stableGripOpacity == 1)
  }

  @Test("Sidebar ear joins through the straight edge without covering row corners")
  func sidebarEarPreservesNavigationCorners() {
    let bounds = CGRect(origin: .zero, size: PanelResizeHandleVariant.sidebar.size)
    let path = PanelResizeHandleGeometry.sidebarEarPath(in: bounds)

    #expect(path.contains(CGPoint(x: bounds.minX + 1, y: bounds.midY)))
    #expect(!path.contains(CGPoint(x: bounds.minX + 1, y: bounds.minY + 1)))
    #expect(!path.contains(CGPoint(x: bounds.minX + 1, y: bounds.maxY - 1)))
  }

  @Test("Detail handle is tall, centered, and joins the panel leading edge")
  func detailHandleJoinsLeadingEdge() {
    let detailsFrame = CGRect(x: 3_120, y: 16, width: 720, height: 1_018)
    let handle = PanelResizeHandleGeometry.handleFrame(
      for: detailsFrame,
      variant: .details,
      attachment: .leading
    )
    let presentation = PanelResizeHandleGeometry.presentationFrame(
      for: detailsFrame,
      attachment: .leading
    )

    #expect(handle.midY == detailsFrame.midY)
    #expect(handle.maxX > detailsFrame.minX)
    #expect(handle.minX == presentation.minX)
    #expect(presentation.maxX == detailsFrame.maxX)
  }

  @Test("Detail width follows the left-edge drag direction")
  func detailResizeDirection() {
    #expect(
      SpatialWorkspaceLayoutPolicy.detailsWidth(
        from: 720,
        horizontalDragDelta: -80
      ) == 800
    )
    #expect(
      SpatialWorkspaceLayoutPolicy.detailsWidth(
        from: 720,
        horizontalDragDelta: 80
      ) == 640
    )
  }
}
