import AppKit
import CoreGraphics
import Testing

@testable import RabbisirCore

@Suite("Workspace layout")
struct WorkspaceLayoutTests {
  @Test("The complete first workspace opens with details visible")
  @MainActor
  func workspaceDefaultsToVisibleDetails() {
    #expect(WorkspaceState().isDetailsVisible)
  }

  @Test("Rabbisir display version appends its increment to the upstream version")
  func versionTracksTheCompatibleUpstreamBaseline() {
    #expect(RabbisirVersion.upstreamCompatibleVersion == "0.1.0-rc.5")
    #expect(RabbisirVersion.displayVersion == "0.1.0")
    #expect(RabbisirVersion.appleShortVersion == "0.1.0")
    #expect(RabbisirVersion.appleBuildVersion == "1")
  }

  @Test("Wide detail uses trailing whitespace without moving the center")
  func wideLayoutKeepsCenterFrameUnchangedWhenDetailsOpen() {
    let closed = WorkspaceLayoutPolicy.resolve(width: 1_700, detailsVisible: false)
    let open = WorkspaceLayoutPolicy.resolve(width: 1_700, detailsVisible: true)

    #expect(open.tier == .wide)
    #expect(open.centerOriginX == closed.centerOriginX)
    #expect(open.centerWidth == closed.centerWidth)
  }

  @Test("Standard detail shifts before compressing")
  func standardLayoutMovesCenterLeftBeforeCompressingIt() {
    let closed = WorkspaceLayoutPolicy.resolve(width: 1_300, detailsVisible: false)
    let open = WorkspaceLayoutPolicy.resolve(width: 1_300, detailsVisible: true)

    #expect(open.tier == .standard)
    #expect(open.centerOriginX < closed.centerOriginX)
    #expect(open.centerWidth == closed.centerWidth)
  }

  @Test("Narrow detail respects the minimum readable center")
  func narrowLayoutCompressesOnlyAfterWhitespaceIsConsumed() {
    let open = WorkspaceLayoutPolicy.resolve(width: 930, detailsVisible: true)

    #expect(open.tier == .compressed)
    #expect(open.centerWidth >= WorkspaceLayoutPolicy.minimumCenterWidth)
    #expect(
      open.centerOriginX + open.centerWidth + WorkspaceLayoutPolicy.panelGap
        <= open.detailOriginX
    )
  }

  @Test("Main window is centered inside the system primary visible frame")
  func mainWindowPlacementStaysInsideMainVisibleFrame() {
    let visible = CGRect(x: 1_920, y: 40, width: 1_728, height: 1_056)
    let frame = MainWindowPlacement.frame(in: visible)

    #expect(visible.contains(frame))
    #expect(frame.midX == visible.midX)
    #expect(frame.midY == visible.midY)
  }

  @Test("Spatial wide details leave the conversation and input fixed")
  func spatialWideDetailsKeepConversationAndInputFixed() throws {
    let visible = CGRect(x: 0, y: 0, width: 3_840, height: 1_050)
    let closed = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: false
    )
    let open = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true
    )

    #expect(open.tier == .wide)
    #expect(open.mainFrame == closed.mainFrame)
    #expect(open.inputFrame == closed.inputFrame)
    #expect(open.detailsFrame != nil)
    let details = try #require(open.detailsFrame)
    #expect(details.width == 720)
    #expect(details.width == CGFloat(360 * 2))
    #expect(details.maxX == visible.maxX)
    #expect(details.minY == open.inputFrame.minY)
    #expect(details.maxY == visible.maxY - SpatialWorkspaceLayoutPolicy.inputBottomInset)
    #expect(open.sidebarFrame.minY == visible.minY)
    #expect(open.sidebarFrame.maxY == visible.maxY)
  }

  @Test(
    "Trailing detail uses equal top and bottom insets at different screen heights",
    arguments: [CGFloat(900), CGFloat(1_050), CGFloat(1_440)]
  )
  func trailingDetailUsesDynamicVerticalAnchors(screenHeight: CGFloat) throws {
    let visible = CGRect(x: 800, y: 36, width: 2_400, height: screenHeight)
    let navigationBottomY = visible.maxY - 6
    let layout = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      navigationBarBottomY: navigationBottomY
    )
    let details = try #require(layout.detailsFrame)
    let bottomInset = layout.inputFrame.minY - visible.minY

    #expect(details.minY == layout.inputFrame.minY)
    #expect(details.minY == visible.minY + bottomInset)
    #expect(details.maxY == navigationBottomY - bottomInset)
    #expect(details.maxX == visible.maxX)
  }

  @Test("Trailing detail shape rounds only its leading corners")
  func trailingDetailShapeCorners() {
    #expect(TrailingEdgePanelShapeMetrics.topLeadingRadius > 0)
    #expect(TrailingEdgePanelShapeMetrics.bottomLeadingRadius > 0)
    #expect(TrailingEdgePanelShapeMetrics.topTrailingRadius == 0)
    #expect(TrailingEdgePanelShapeMetrics.bottomTrailingRadius == 0)
  }

  @Test("Spatial standard details shift conversation and input together")
  func spatialStandardDetailsShiftConversationAndInputTogether() {
    let visible = CGRect(x: 0, y: 0, width: 1_700, height: 1_050)
    let closed = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: false
    )
    let open = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true
    )

    #expect(open.tier == .standard)
    #expect(open.mainFrame.minX < closed.mainFrame.minX)
    #expect(open.inputFrame.midX == open.mainFrame.midX)
    #expect(open.sidebarFrame == closed.sidebarFrame)
  }

  @Test("Spatial narrow details compress navigation before conversation")
  func spatialNarrowDetailsUseAdaptiveCompressionOrder() {
    let visible = CGRect(x: 0, y: 0, width: 1_440, height: 900)
    let closed = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: false
    )
    let open = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true
    )

    #expect(open.tier == .compressed)
    #expect(open.sidebarFrame.width == SpatialWorkspaceLayoutPolicy.minimumSidebarWidth)
    #expect(open.inputFrame.width == SpatialWorkspaceLayoutPolicy.minimumInputWidth)
    #expect(open.sidebarFrame.width < closed.sidebarFrame.width)
    #expect(open.inputFrame.midX == open.mainFrame.midX)
  }

  @Test("Sidebar width preference is bounded and remains flush with the screen edge")
  func sidebarWidthUsesOneConstrainedPreference() {
    let visible = CGRect(x: 120, y: 36, width: 3_840, height: 1_044)
    let narrow = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: false,
      preferredSidebarWidth: 80
    )
    let wide = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: false,
      preferredSidebarWidth: 900
    )

    #expect(narrow.sidebarFrame.minX == visible.minX)
    #expect(wide.sidebarFrame.minX == visible.minX)
    #expect(narrow.sidebarFrame.width == SpatialWorkspaceLayoutPolicy.minimumSidebarWidth)
    #expect(wide.sidebarFrame.width == SpatialWorkspaceLayoutPolicy.maximumSidebarWidth)
  }

  @Test("Sidebar handle stays at the navigation viewport center")
  func sidebarHandleUsesNavigationFrameCenter() {
    let layout = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: CGRect(x: 0, y: 36, width: 3_840, height: 1_044),
      detailsVisible: false,
      preferredSidebarWidth: 336
    )
    let handle = PanelResizeHandleGeometry.handleFrame(
      for: layout.sidebarFrame,
      variant: .sidebar,
      attachment: .trailing
    )

    #expect(handle.midY == layout.sidebarFrame.midY)
    #expect(handle.height == NativeNavigationLayout.projectRowHeight)
    #expect(handle.minX < layout.sidebarFrame.maxX)
    #expect(handle.maxX > layout.sidebarFrame.maxX)
  }

  @Test(
    "Spatial conversation display exactly matches and touches the input panel",
    arguments: [
      CGRect(x: 0, y: 0, width: 3_840, height: 1_050),
      CGRect(x: 0, y: 36, width: 1_700, height: 1_014),
      CGRect(x: 200, y: 40, width: 1_440, height: 860),
    ],
    [false, true]
  )
  func spatialConversationAndInputShareOneColumn(
    visible: CGRect,
    detailsVisible: Bool
  ) {
    let layout = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: detailsVisible
    )

    #expect(layout.mainFrame.minX == layout.inputFrame.minX)
    #expect(layout.mainFrame.width == layout.inputFrame.width)
    #expect(layout.mainFrame.minY == layout.inputFrame.maxY)
  }

  @Test("Spatial input follows the bottom inset and Guanlan-style width strategy")
  func spatialInputUsesBottomInsetAndRatio() {
    let visible = CGRect(x: 0, y: 36, width: 3_840, height: 1_044)
    let layout = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: false
    )

    #expect(
      layout.inputFrame.minY
        == visible.minY + SpatialWorkspaceLayoutPolicy.inputBottomInset
    )
    #expect(layout.inputFrame.width == 3_840 * SpatialWorkspaceLayoutPolicy.inputWidthRatio)
    #expect(layout.inputFrame.midX == layout.mainFrame.midX)
  }

  @Test("Conversation width changes symmetrically around its canonical center")
  func conversationResizeUsesSymmetricDelta() {
    #expect(
      SpatialWorkspaceLayoutPolicy.conversationWidth(
        from: 700,
        horizontalDragDelta: 40
      ) == 780
    )
    #expect(
      SpatialWorkspaceLayoutPolicy.conversationWidth(
        from: 700,
        horizontalDragDelta: -40
      ) == 620
    )
  }

  @Test("One layout solver centers, avoids details, and returns without overshooting")
  func resizablePanelsShareCollisionSolver() throws {
    let visible = CGRect(x: 0, y: 0, width: 2_400, height: 1_050)
    let centered = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: false,
      preferredConversationWidth: 800
    )
    let pressured = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      preferredConversationWidth: 800,
      preferredDetailsWidth: 900
    )
    let released = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      preferredConversationWidth: 800,
      preferredDetailsWidth: 520
    )
    let pressuredDetails = try #require(pressured.detailsFrame)

    #expect(centered.inputFrame.midX == centered.canonicalConversationCenterX)
    #expect(pressured.inputFrame.minX < centered.inputFrame.minX)
    #expect(
      pressured.inputFrame.maxX
        + SpatialWorkspaceLayoutPolicy.conversationDetailClearance
        <= pressuredDetails.minX
    )
    #expect(released.inputFrame.midX == released.canonicalConversationCenterX)
    #expect(released.inputFrame.midX <= released.canonicalConversationCenterX)
  }

  @Test("Conversation and details widths clamp independently")
  func independentWidthLimits() throws {
    let visible = CGRect(x: 0, y: 0, width: 3_840, height: 1_050)
    let minimum = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      preferredConversationWidth: 40,
      preferredDetailsWidth: 40
    )
    let maximum = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      preferredConversationWidth: 8_000,
      preferredDetailsWidth: 8_000
    )

    #expect(minimum.inputFrame.width == SpatialWorkspaceLayoutPolicy.minimumInputWidth)
    #expect(
      try #require(minimum.detailsFrame).width
        == SpatialWorkspaceLayoutPolicy.minimumDetailsWidth
    )
    #expect(maximum.inputFrame.width <= SpatialWorkspaceLayoutPolicy.maximumConversationWidth)
    let maximumDetails = try #require(maximum.detailsFrame)
    #expect(
      maximumDetails.width
        == visible.width
        - SpatialWorkspaceLayoutPolicy.minimumSidebarWidth
        - SpatialWorkspaceLayoutPolicy.panelGap
        - SpatialWorkspaceLayoutPolicy.minimumInputWidth
        - SpatialWorkspaceLayoutPolicy.conversationDetailClearance
    )
  }

  @Test("Details expansion shifts center, then compresses sidebar, then conversation")
  func detailsExpansionUsesEveryAdaptiveWidthStage() throws {
    let visible = CGRect(x: 0, y: 0, width: 2_400, height: 1_050)
    let shifted = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      preferredSidebarWidth: 320,
      preferredConversationWidth: 780,
      preferredDetailsWidth: 900
    )
    let sidebarCompressed = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      preferredSidebarWidth: 320,
      preferredConversationWidth: 780,
      preferredDetailsWidth: 1_350
    )
    let fullyCompressed = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      preferredSidebarWidth: 320,
      preferredConversationWidth: 780,
      preferredDetailsWidth: 8_000
    )
    let fullyCompressedDetails = try #require(fullyCompressed.detailsFrame)

    #expect(shifted.sidebarFrame.width == 320)
    #expect(shifted.inputFrame.width == 780)
    #expect(shifted.inputFrame.midX < shifted.canonicalConversationCenterX)

    #expect(sidebarCompressed.sidebarFrame.width < 320)
    #expect(
      sidebarCompressed.sidebarFrame.width >= SpatialWorkspaceLayoutPolicy.minimumSidebarWidth)
    #expect(sidebarCompressed.inputFrame.width == 780)

    #expect(
      fullyCompressed.sidebarFrame.width
        == SpatialWorkspaceLayoutPolicy.minimumSidebarWidth
    )
    #expect(
      fullyCompressed.inputFrame.width
        == SpatialWorkspaceLayoutPolicy.minimumInputWidth
    )
    #expect(
      fullyCompressed.inputFrame.maxX
        + SpatialWorkspaceLayoutPolicy.conversationDetailClearance
        == fullyCompressedDetails.minX
    )
  }

  @Test("Details maximum adapts to each display width")
  func detailsMaximumUsesTheCurrentVisibleFrame() throws {
    for width: CGFloat in [1_440, 2_400, 3_840] {
      let visible = CGRect(x: 100, y: 20, width: width, height: 1_050)
      let layout = SpatialWorkspaceLayoutPolicy.resolve(
        visibleFrame: visible,
        detailsVisible: true,
        preferredSidebarWidth: 440,
        preferredConversationWidth: 1_200,
        preferredDetailsWidth: 20_000
      )
      let details = try #require(layout.detailsFrame)

      #expect(layout.sidebarFrame.width == SpatialWorkspaceLayoutPolicy.minimumSidebarWidth)
      #expect(layout.inputFrame.width == SpatialWorkspaceLayoutPolicy.minimumInputWidth)
      #expect(details.maxX == visible.maxX)
      #expect(
        details.width
          == width
          - SpatialWorkspaceLayoutPolicy.minimumSidebarWidth
          - SpatialWorkspaceLayoutPolicy.panelGap
          - SpatialWorkspaceLayoutPolicy.minimumInputWidth
          - SpatialWorkspaceLayoutPolicy.conversationDetailClearance
      )
    }
  }

  @Test("Embedded composer bridge targets the shipped composer instead of a native protocol")
  func runtimeComposerBridgeUsesTheEmbeddedComposerActions() {
    #expect(RuntimeComposerBridge.projectionScript.contains("[data-composer-card]"))
    #expect(RuntimeComposerBridge.projectionScript.contains("aria-haspopup') === 'menu'"))
    #expect(RuntimeComposerBridge.projectionScript.contains("model?.title"))
    #expect(
      RuntimeComposerBridge.projectionScript
        .contains("primaryLabel === '发送消息' || primaryLabel === 'Send message'")
    )
    #expect(
      RuntimeComposerBridge.projectionScript
        .contains("button.getAttribute('aria-label')")
    )
    #expect(
      RuntimeComposerBridge.activationScript(for: .permission)
        .contains("const target = permission")
    )
    #expect(
      RuntimeComposerBridge.activationScript(for: .commands)
        .contains("const target = commands")
    )
    let submission = RuntimeComposerBridge.submissionScript(jsonText: "\"hello\"")
    #expect(submission.contains("new InputEvent('input'"))
    #expect(submission.contains("label === '发送消息' || label === 'Send message'"))
    #expect(submission.contains("primary.click()"))
    #expect(submission.contains("resolve(true, 'composer-cleared')"))
    #expect(submission.contains("resolve(false, 'no-runtime-transition')"))
    #expect(!submission.contains("fetch("))
    #expect(!submission.contains("WebSocket"))
    #expect(!submission.contains("new KeyboardEvent"))
    #expect(
      RuntimeComposerBridge.visualExtractionScript
        .contains("[data-composer-card]")
    )
    #expect(
      RuntimeComposerBridge.visualExtractionScript
        .contains("display: none !important")
    )
  }

  @Test("Native upward pickers project and invoke official composer options")
  func composerOptionsRemainOwnedByTheEmbeddedComposer() {
    for kind in RuntimeComposerChoiceKind.allCases {
      let choices = RuntimeComposerBridge.choicesScript(for: kind)
      let selection = RuntimeComposerBridge.selectionScript(
        kind: kind,
        optionID: "\(kind.rawValue):0"
      )

      #expect(choices.contains("[data-composer-card]"))
      #expect(choices.contains("input.getAttribute('aria-haspopup') !== 'menu'"))
      #expect(selection.contains("[data-composer-card]"))
      #expect(selection.contains("input.getAttribute('aria-haspopup') !== 'menu'"))
      #expect(selection.contains("option.click()") || selection.contains("MouseEvent('mousedown'"))
      #expect(!selection.contains("fetch("))
      #expect(!selection.contains("WebSocket"))
    }

    #expect(
      RuntimeComposerBridge.choicesScript(for: .model)
        .contains("button[role=\"menuitemradio\"]")
    )
    #expect(
      RuntimeComposerBridge.choicesScript(for: .reasoning)
        .contains("kind === 'model' ? 0 : 1")
    )
    #expect(
      RuntimeComposerBridge.choicesScript(for: .permission)
        .contains("[role=\"menuitem\"]")
    )
    #expect(
      RuntimeComposerBridge.choicesScript(for: .commands)
        .contains("[role=\"option\"]")
    )
    let workspaceSelection = RuntimeComposerBridge.selectionScript(
      kind: .workspace,
      optionID: "workspace:2"
    )
    #expect(workspaceSelection.contains("const openMenuFor = trigger"))
    #expect(workspaceSelection.contains("trigger.getAttribute('aria-controls')"))
    #expect(workspaceSelection.contains("menu.getClientRects().length > 0"))
  }

  @Test("Native navigation persists the official SessionId instead of a DOM row index")
  func upstreamNavigationSelectionUsesStableSessionID() {
    let selection = RuntimeNavigationBridge.selectionScript(sessionID: "session-real-42")
    #expect(selection.contains("session-real-42"))
    #expect(selection.contains("projection.openSession(requestedID)"))
    #expect(!selection.contains("dsh.sessions.current"))
    #expect(!selection.contains("localStorage"))
    #expect(!selection.contains("window.location.reload()"))
    #expect(
      RuntimeNavigationBridge.currentSessionIDScript.contains("projection.currentSessionID()"))
    #expect(!selection.contains("row.click()"))
    #expect(!selection.contains("querySelectorAll('[role=\"tree\"]')"))
    #expect(!selection.contains("WebSocket"))
    #expect(RuntimeNavigationBridge.clearSelectionScript.contains("projection.clearSelection()"))
    #expect(!RuntimeNavigationBridge.clearSelectionScript.contains("localStorage.removeItem"))
    #expect(
      RuntimeNavigationBridge.settingsActivationScript
        .contains("data-rabbisir-model-policy', 'deepseek-only")
    )
    #expect(
      RuntimeNavigationBridge.settingsActivationScript
        .contains("添加自定义提供方")
    )
    #expect(
      RuntimeNavigationBridge.settingsPolicyInstallationScript
        .contains("MutationObserver")
    )
    #expect(
      RuntimeNavigationBridge.settingsPolicyInstallationScript
        .contains("[class*=\"addActions\"]")
    )
    #expect(
      RuntimeNavigationBridge.settingsPolicyInstallationScript
        .contains("style.setProperty('display', 'none', 'important')")
    )
    #expect(
      RuntimeNavigationBridge.nativeMenuOwnershipInstallationScript
        .contains("data-rabbisir-native-menu-owned")
    )
    #expect(
      RuntimeNavigationBridge.nativeMenuOwnershipInstallationScript
        .contains("/^Session log$/i")
    )
    #expect(
      RuntimeNavigationBridge.nativeMenuOwnershipInstallationScript
        .contains("button[aria-haspopup=\"dialog\"]")
    )
    #expect(
      RuntimeNavigationBridge.sessionLogActivationScript
        .contains("/^(Session log|会话日志)$/i")
    )
    #expect(
      RuntimeNavigationBridge.sessionLogActivationScript
        .contains("trigger.click()")
    )
    #expect(
      RuntimeNavigationBridge.sessionLogActivationScript
        .contains("trigger.getAttribute('aria-busy') === 'true'")
    )
    #expect(!RuntimeNavigationBridge.sessionLogActivationScript.contains("fetch("))
  }

  @Test("App menu owns the single settings and Session Log entry")
  @MainActor
  func appMenuUsesStandardBrandAndCapabilityTitles() throws {
    let menu = ApplicationMenu.make(target: NSObject())
    let appMenu = try #require(menu.items.first?.submenu)
    let actionableTitles = appMenu.items.filter { !$0.isSeparatorItem }.map(\.title)

    #expect(
      actionableTitles == [
        "关于 Rabbisir",
        "设置…",
        "会话日志",
        "重新打开界面导览",
        "显示主窗口",
        "隐藏完整工作台",
        "聚焦输入（⌃⌥Return）",
        "退出 Rabbisir",
      ])
    #expect(appMenu.items.first?.title == "关于 Rabbisir")
    #expect(!appMenu.items.first!.title.contains(RabbisirVersion.displayVersion))
    let focusInputItem = try #require(
      appMenu.items.first(where: { $0.title.hasPrefix("聚焦输入") })
    )
    #expect(focusInputItem.keyEquivalent == "\r")
    #expect(focusInputItem.keyEquivalentModifierMask == [.control, .option])

    let editMenu = try #require(menu.items.first(where: { $0.title == "编辑" })?.submenu)
    let keyCommands = Dictionary(
      uniqueKeysWithValues: editMenu.items.compactMap { item in
        item.keyEquivalent.isEmpty ? nil : (item.keyEquivalent, item.action)
      }
    )
    #expect(keyCommands["a"] == #selector(NSText.selectAll(_:)))
    #expect(keyCommands["c"] == #selector(NSText.copy(_:)))
    #expect(keyCommands["x"] == #selector(NSText.cut(_:)))
    #expect(keyCommands["v"] == #selector(NSText.paste(_:)))
    #expect(keyCommands["z"] == Selector(("undo:")))
  }

  @Test("System menu bar exposes the native two-choice language menu")
  @MainActor
  func appMenuIncludesLanguageChoices() throws {
    let menu = ApplicationMenu.make(target: NSObject())
    let languageMenu = try #require(
      menu.items.first(where: { $0.title == "Language" })?.submenu
    )

    #expect(languageMenu.items.map(\.title) == ["中文", "English"])
    #expect(languageMenu.items.filter { $0.state == .on }.count == 1)
  }

  @Test("About version reads bundle metadata and keeps the locked fallback")
  func aboutVersionUsesBundleFields() {
    let bundleVersion = RabbisirBundleVersion.resolve(infoDictionary: [
      "CFBundleShortVersionString": "2.4.0",
      "CFBundleVersion": "87",
    ])
    let fallback = RabbisirBundleVersion.resolve(infoDictionary: nil)

    #expect(bundleVersion.displayText == "Version 2.4.0 · Build 87")
    #expect(fallback.shortVersion == RabbisirVersion.appleShortVersion)
    #expect(fallback.buildVersion == RabbisirVersion.appleBuildVersion)
  }

  @Test("Session Log export suggests a safe ZIP name without choosing a user path")
  func sessionLogExportSuggestionIsSafe() {
    #expect(
      SessionLogExportPolicy.suggestedFilename("dsh-session-real.zip") == "dsh-session-real.zip")
    #expect(SessionLogExportPolicy.suggestedFilename("../private-name.txt") == "private-name.zip")
    #expect(SessionLogExportPolicy.suggestedFilename("") == "rabbisir-session-log.zip")
  }

  @Test("Global shortcuts are fixed application commands without event content capture")
  func globalHotKeysExposeOnlyWindowCommands() {
    #expect(RabbisirGlobalHotKeyCommand.allCases == [.toggleWorkspace, .focusInput])
    #expect(RabbisirGlobalHotKeyCommand.toggleWorkspace.displayName == "⌃⌥Space")
    #expect(RabbisirGlobalHotKeyCommand.focusInput.displayName == "⌃⌥Return")
    #expect(
      RabbisirGlobalHotKeyCommand.toggleWorkspace.modifiers
        == RabbisirGlobalHotKeyCommand.focusInput.modifiers
    )
  }

  @Test("Model submenus stay scroll-constrained inside small and large displays")
  func modelPickerSubmenuHeightStaysSafe() {
    #expect(
      ModelPickerPresentationMetrics.submenuHeight(
        optionCount: 3,
        visibleHeight: 1_050
      ) == 138
    )
    #expect(
      ModelPickerPresentationMetrics.submenuHeight(
        optionCount: 20,
        visibleHeight: 1_050
      ) == 189
    )
    let compactHeight = ModelPickerPresentationMetrics.submenuHeight(
      optionCount: 20,
      visibleHeight: 640
    )
    #expect(abs(compactHeight - 115.2) < 0.001)
  }

  @Test("The native editor distinguishes official Enter submission gestures")
  func nativeComposerReturnPolicy() {
    #expect(
      ComposerTextKeyPolicy.gesture(keyCode: 36, modifiers: [], isRepeat: false)
        == .enter
    )
    #expect(
      ComposerTextKeyPolicy.gesture(keyCode: 76, modifiers: .command, isRepeat: false)
        == .accelerated
    )
    #expect(
      ComposerTextKeyPolicy.gesture(keyCode: 36, modifiers: .control, isRepeat: false)
        == .accelerated
    )
    #expect(
      ComposerTextKeyPolicy.gesture(keyCode: 36, modifiers: .option, isRepeat: false)
        == .enter
    )
    #expect(ComposerTextKeyPolicy.gesture(keyCode: 36, modifiers: .shift, isRepeat: false) == nil)
    #expect(ComposerTextKeyPolicy.gesture(keyCode: 36, modifiers: [], isRepeat: true) == nil)
    #expect(ComposerTextKeyPolicy.gesture(keyCode: 49, modifiers: [], isRepeat: false) == nil)
  }

  @Test("The full composer viewport resolves to its single native editor")
  @MainActor
  func composerOwnsContinuousHitSurface() throws {
    let scrollView = ComposerTextView.scrollableTextView()
    scrollView.frame = CGRect(x: 0, y: 0, width: 320, height: 120)
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    let editor = try #require(scrollView.documentView as? ComposerTextView)
    editor.frame = scrollView.contentView.bounds
    editor.autoresizingMask = [.width, .height]
    scrollView.layoutSubtreeIfNeeded()

    for point in [
      CGPoint(x: 8, y: 8),
      CGPoint(x: 160, y: 60),
      CGPoint(x: 300, y: 105),
    ] {
      let scrollPoint = editor.convert(point, to: scrollView)
      #expect(scrollView.hitTest(scrollPoint) === editor)
    }
    #expect(editor.acceptsFirstMouse(for: nil))
  }

  @Test("Browser control lifecycle drives idle active failure and reset states")
  @MainActor
  func browserControlLifecycleUsesOnlyObservedEvents() {
    let state = WorkspaceState()

    #expect(state.browserControlPhase == .idle)
    state.browserControlDidFail(reason: "没有发起控制")
    #expect(state.browserControlPhase == .idle)

    state.browserControlDidBegin()
    #expect(state.browserControlPhase == .active)

    state.browserControlDidFail(reason: "权限不可用")
    #expect(state.browserControlPhase == .failed("权限不可用"))

    state.browserControlDidEnd()
    #expect(state.browserControlPhase == .idle)

    #expect(BrowserControlPresentation.motion(for: .idle, reduceMotion: false) == .none)
    #expect(BrowserControlPresentation.motion(for: .active, reduceMotion: false) == .breathe)
    #expect(
      BrowserControlPresentation.motion(
        for: .failed("不可用"),
        reduceMotion: false
      ) == .flash
    )
    #expect(BrowserControlPresentation.motion(for: .active, reduceMotion: true) == .none)
    #expect(
      BrowserControlPresentation.motion(
        for: .failed("不可用"),
        reduceMotion: true
      ) == .none
    )
  }

}
