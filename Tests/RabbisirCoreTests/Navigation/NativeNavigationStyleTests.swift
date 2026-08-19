import AppKit
import Testing

@testable import RabbisirCore

@Suite("Native navigation style")
struct NativeNavigationStyleTests {
  @Test("Navigation foreground resolves dark in Aqua and light in Dark Aqua")
  func semanticForegroundFollowsAppearance() throws {
    let aqua = try #require(NSAppearance(named: .aqua))
    let darkAqua = try #require(NSAppearance(named: .darkAqua))

    let lightValue = try whiteValue(in: aqua)
    let darkValue = try whiteValue(in: darkAqua)

    #expect(lightValue < 0.25)
    #expect(darkValue > 0.75)
  }

  @Test("Project hover never retints the regular glass surface")
  func projectHoverPreservesGlassDepth() {
    #expect(NativeNavigationStyle.projectRowOverlayOpacity(isHovered: false) == 0)
    #expect(NativeNavigationStyle.projectRowOverlayOpacity(isHovered: true) == 0)
  }

  @Test("Project action circles inherit the owning row glass without hover retint")
  func projectActionGlassMatchesOwningRow() {
    let row = NativeNavigationMaterialPolicy.configuration()
    let action = NativeNavigationMaterialPolicy.projectActionConfiguration()

    #expect(action == row)
    #expect(!action.isInteractive)
  }

  @Test("Idle project rows add no tint above their independent glass")
  func projectSurfaceKeepsRowsDistinct() {
    #expect(NativeNavigationStyle.projectSurfaceOpacity == 0)
  }

  @Test("Project action feedback changes only content, never the glass base")
  func projectActionFeedback() {
    let idle = NativeNavigationStyle.projectActionPresentation(
      isHovered: false,
      isPressed: false,
      isEnabled: true,
      reduceMotion: false
    )
    let hovered = NativeNavigationStyle.projectActionPresentation(
      isHovered: true,
      isPressed: false,
      isEnabled: true,
      reduceMotion: false
    )
    let pressed = NativeNavigationStyle.projectActionPresentation(
      isHovered: true,
      isPressed: true,
      isEnabled: true,
      reduceMotion: false
    )

    #expect(idle.overlayOpacity == 0)
    #expect(hovered.overlayOpacity == 0)
    #expect(pressed.overlayOpacity == 0)
    #expect(idle.strokeOpacity == 0)
    #expect(hovered.strokeOpacity == 0)
    #expect(pressed.strokeOpacity == 0)
    #expect(hovered.foregroundOpacity > idle.foregroundOpacity)
    #expect(hovered.scale == 1)
    #expect(pressed.scale < hovered.scale)
  }

  @Test("Reduced motion and disabled actions keep static semantic feedback")
  func accessibleProjectActionFeedback() {
    let reducedMotionPressed = NativeNavigationStyle.projectActionPresentation(
      isHovered: true,
      isPressed: true,
      isEnabled: true,
      reduceMotion: true
    )
    let disabled = NativeNavigationStyle.projectActionPresentation(
      isHovered: true,
      isPressed: false,
      isEnabled: false,
      reduceMotion: false
    )

    #expect(reducedMotionPressed.scale == 1)
    #expect(reducedMotionPressed.overlayOpacity == 0)
    #expect(disabled.foregroundOpacity < 1)
    #expect(disabled.overlayOpacity == 0)
  }

  @Test("Project glass keeps one stable optical owner while its mask grows")
  func projectGlassComposition() {
    #expect(NativeNavigationMaterialPolicy.containerScope == .none)
    #expect(NativeNavigationMaterialPolicy.grouping == .independentProjectSurfaces)
    #expect(NativeNavigationMaterialPolicy.renderingPath == .stableOpticalCanvas)
    #expect(
      NativeNavigationMaterialPolicy.opticalReferenceHeight
        == InputComposerShape.collapsedSurfaceHeight
    )
    #expect(NativeNavigationMaterialPolicy.projectOwnerExtensionWidth(isHovered: false) == 0)
    #expect(
      NativeNavigationMaterialPolicy.projectOwnerExtensionWidth(isHovered: true)
        == NativeNavigationLayout.resizeExtensionWidth
    )
    #expect(!NavigationHoverActionSurfaceStyle.project.ownsGlassContainer)
    #expect(!NavigationHoverActionSurfaceStyle.session.ownsGlassContainer)
    #expect(NavigationHoverActionSurfaceStyle.project.usesOwnerGlassSurface)
    #expect(!NavigationHoverActionSurfaceStyle.session.usesOwnerGlassSurface)
    #expect(!NavigationHoverActionSurfaceStyle.project.includesExtensionSurface)
    #expect(!NavigationHoverActionSurfaceStyle.session.includesExtensionSurface)
  }

  @Test("Navigation uses system regular glass without a custom backing range")
  func navigationGlassUsesTheSystemMaterial() {
    let configuration = NativeNavigationMaterialPolicy.configuration()

    #expect(!configuration.isInteractive)
  }

  private func whiteValue(in appearance: NSAppearance) throws -> CGFloat {
    var resolvedColor: NSColor?
    appearance.performAsCurrentDrawingAppearance {
      resolvedColor = NativeNavigationStyle.foregroundNSColor.usingColorSpace(.sRGB)
    }
    let rgb = try #require(resolvedColor)
    var red: CGFloat = 0
    var green: CGFloat = 0
    var blue: CGFloat = 0
    var alpha: CGFloat = 0
    rgb.getRed(&red, green: &green, blue: &blue, alpha: &alpha)
    return red * 0.2126 + green * 0.7152 + blue * 0.0722
  }

}
