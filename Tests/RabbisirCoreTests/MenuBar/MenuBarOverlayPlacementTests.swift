import AppKit
import CoreGraphics
import Testing

@testable import RabbisirCore

@Suite("Menu bar overlay placement")
struct MenuBarOverlayPlacementTests {
  @Test("External display centers the island")
  func externalDisplayCentersIslandInMenuBarBand() throws {
    let geometry = MenuBarScreenGeometry(
      frame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_050),
      safeInsets: ScreenInsets(top: 0, left: 0, bottom: 0, right: 0)
    )

    let frame = try #require(
      MenuBarOverlayPlacement.frame(
        for: geometry,
        islandSize: MenuBarIslandPresentation.size
      )
    )

    #expect(frame.midX == geometry.frame.midX)
    #expect(frame.maxY == geometry.frame.maxY)
  }

  @Test("Visibility controls, not the appended browser control, own the center anchor")
  func visibilityControlsOwnTheScreenCenter() throws {
    let geometry = MenuBarScreenGeometry(
      frame: CGRect(x: 0, y: 0, width: 3_840, height: 1_080),
      visibleFrame: CGRect(x: 0, y: 0, width: 3_840, height: 1_050),
      safeInsets: ScreenInsets(top: 0, left: 0, bottom: 0, right: 0)
    )
    let offset = MenuBarIslandPresentation.visibilityControlsCenterOffsetX
    let frame = try #require(
      MenuBarOverlayPlacement.frame(
        for: geometry,
        islandSize: MenuBarIslandPresentation.size,
        horizontalAnchorOffsetX: offset
      )
    )

    #expect(frame.midX + offset == geometry.frame.midX)
  }

  @Test("Notched display uses a public auxiliary top area")
  func notchedDisplayPlacesIslandInsideAuxiliaryArea() throws {
    let leftArea = CGRect(x: 0, y: 956, width: 740, height: 44)
    let rightArea = CGRect(x: 1_060, y: 956, width: 740, height: 44)
    let geometry = MenuBarScreenGeometry(
      frame: CGRect(x: 0, y: 0, width: 1_800, height: 1_000),
      visibleFrame: CGRect(x: 0, y: 0, width: 1_800, height: 956),
      safeInsets: ScreenInsets(top: 44, left: 0, bottom: 0, right: 0),
      auxiliaryTopLeftArea: leftArea,
      auxiliaryTopRightArea: rightArea
    )

    let frame = try #require(
      MenuBarOverlayPlacement.frame(
        for: geometry,
        islandSize: MenuBarIslandPresentation.size
      )
    )

    #expect(leftArea.contains(frame) || rightArea.contains(frame))
    #expect(!frame.contains(CGPoint(x: geometry.frame.midX, y: frame.midY)))
  }

  @Test("Unsafe geometry declines to create an overlay")
  func impossibleSafeWidthDeclinesToCreateOverlay() {
    let geometry = MenuBarScreenGeometry(
      frame: CGRect(x: 0, y: 0, width: 70, height: 900),
      visibleFrame: CGRect(x: 0, y: 0, width: 70, height: 870),
      safeInsets: ScreenInsets(top: 30, left: 10, bottom: 0, right: 10)
    )

    #expect(
      MenuBarOverlayPlacement.frame(
        for: geometry,
        islandSize: MenuBarIslandPresentation.size
      ) == nil
    )
  }

  @Test("Island controls expose the action for the current panel state")
  func islandControlTitlesTrackVisibility() {
    #expect(MenuBarIslandPresentation.sidebarTitle(isVisible: true) == "隐藏项目与对话")
    #expect(MenuBarIslandPresentation.sidebarTitle(isVisible: false) == "显示项目与对话")
    #expect(MenuBarIslandPresentation.detailsTitle(isVisible: true) == "隐藏详情")
    #expect(MenuBarIslandPresentation.detailsTitle(isVisible: false) == "显示详情")
    #expect(
      MenuBarIslandPresentation.workspaceVisibilityTitle(
        isVisible: true,
        language: .chinese
      ) == "隐藏"
    )
    #expect(
      MenuBarIslandPresentation.workspaceVisibilityTitle(
        isVisible: false,
        language: .english
      ) == "Show"
    )
    #expect(
      MenuBarIslandPresentation.workspaceVisibilitySymbolName(isVisible: true) == "eye.slash"
    )
    #expect(MenuBarIslandPresentation.workspaceVisibilitySymbolName(isVisible: false) == "eye")
  }

  @Test("Panel controls are disabled while the complete workspace is hidden")
  func hiddenWorkspaceDisablesPanelControls() {
    #expect(MenuBarIslandPresentation.panelControlsEnabled(isWorkspaceVisible: true))
    #expect(!MenuBarIslandPresentation.panelControlsEnabled(isWorkspaceVisible: false))
  }

  @Test("Island container has a permanently clear component-owned background")
  func islandContainerBackgroundIsClear() {
    #expect(MenuBarIslandPresentation.containerBackgroundColor.alphaComponent == 0)
  }

  @Test("Nearby AppKit glass surfaces share one native effect container")
  @MainActor
  func nearbyAppKitGlassSharesNativeContainer() throws {
    let content = NSView()
    let container = RabbisirGlassAppKitAdapter.makeEffectGroup(
      contentView: content,
      spacing: 8
    )
    if #available(macOS 26.0, *) {
      let group = try #require(container as? NSGlassEffectContainerView)
      #expect(group.contentView === content)
      #expect(group.spacing == 8)
    } else {
      #expect(container === content)
    }
  }

  @Test("Island hover feedback never paints a card or border around the hit target")
  func islandHoverLeavesContainerClear() {
    #expect(MenuBarIslandPresentation.hoverFillOpacity == 0)
    #expect(MenuBarIslandPresentation.pressedFillOpacity == 0)
    #expect(MenuBarIslandPresentation.hoverBorderOpacity == 0)
  }

  @Test("Island icons follow the system menu bar appearance")
  func islandIconsUseSystemMenuBarContrast() throws {
    let lightMenuBar = try #require(NSAppearance(named: .vibrantLight))
    let darkMenuBar = try #require(NSAppearance(named: .vibrantDark))
    let darkIcon = try #require(
      MenuBarIslandPresentation.iconColor(for: lightMenuBar).usingColorSpace(.sRGB)
    )
    let lightIcon = try #require(
      MenuBarIslandPresentation.iconColor(for: darkMenuBar).usingColorSpace(.sRGB)
    )
    #expect(darkIcon.brightnessComponent < 0.5)
    #expect(lightIcon.brightnessComponent > 0.5)
    #expect(
      MenuBarIslandPresentation.disabledIconOpacity < MenuBarIslandPresentation.inactiveIconOpacity)
    #expect(
      MenuBarIslandPresentation.inactiveIconOpacity < MenuBarIslandPresentation.activeIconOpacity)
    #expect(
      MenuBarIslandPresentation.activeIconOpacity < MenuBarIslandPresentation.hoverIconOpacity)
  }

  @Test("Preferred language selects the workspace visibility copy")
  func visibilityCopyFollowsPreferredLanguage() {
    #expect(MenuBarInterfaceLanguage.resolve(preferredLanguages: ["zh-Hans"]) == .chinese)
    #expect(MenuBarInterfaceLanguage.resolve(preferredLanguages: ["en-US"]) == .english)
    #expect(MenuBarInterfaceLanguage.resolve(preferredLanguages: []) == .english)
  }

  @Test("Island controls consume the newly published language value immediately")
  @MainActor
  func islandControlsUpdateDuringLanguagePublication() throws {
    let suite = "RabbisirTests.MenuBarLocalization.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    let localization = RabbisirLocalization(
      defaults: defaults,
      preferredLanguages: ["zh-Hans"]
    )
    let view = MenuBarIslandContentView(
      state: WorkspaceState(),
      frame: CGRect(origin: .zero, size: MenuBarIslandPresentation.size),
      localization: localization,
      isWorkspaceVisible: { true },
      setWorkspaceVisible: { _ in }
    )
    let buttons = descendants(of: view).compactMap { $0 as? NSButton }
    let visibilityButton = try #require(buttons.first(where: { $0.toolTip == "隐藏" }))

    localization.select(.english)

    #expect(visibilityButton.title.isEmpty)
    #expect(visibilityButton.toolTip == "Hide")
  }

  @Test("Asymmetric outer controls keep sidebar and details centered")
  func panelVisibilityControlsRemainCentered() {
    #expect(
      MenuBarIslandPresentation.visibilityControlsCenterOffsetX
        == (MenuBarIslandPresentation.browserControlWidth
          - MenuBarIslandPresentation.workspaceVisibilityWidth) / 2
    )
  }

  @Test("Workspace visibility icon keeps the real hide and show action")
  @MainActor
  func workspaceVisibilityIconTogglesWorkspace() throws {
    var isVisible = true
    let view = MenuBarIslandContentView(
      state: WorkspaceState(),
      frame: CGRect(origin: .zero, size: MenuBarIslandPresentation.size),
      localization: RabbisirLocalization.shared,
      isWorkspaceVisible: { isVisible },
      setWorkspaceVisible: { isVisible = $0 }
    )
    let visibilityButton = try #require(
      descendants(of: view).compactMap { $0 as? NSButton }
        .first(where: { $0.toolTip == "隐藏" })
    )

    #expect(visibilityButton.title.isEmpty)
    visibilityButton.performClick(nil)
    #expect(!isVisible)
    #expect(visibilityButton.toolTip == "显示")
    visibilityButton.performClick(nil)
    #expect(isVisible)
    #expect(visibilityButton.toolTip == "隐藏")
  }

  @Test("Browser control uses a neutral system window symbol")
  func browserControlSymbolIsAvailable() {
    #expect(MenuBarIslandPresentation.browserControlSymbolName == "globe")
    #expect(
      NSImage(
        systemSymbolName: MenuBarIslandPresentation.browserControlSymbolName,
        accessibilityDescription: nil
      ) != nil
    )
  }

  @MainActor
  private func descendants(of view: NSView) -> [NSView] {
    view.subviews + view.subviews.flatMap(descendants(of:))
  }
}
