import AppKit
import SwiftUI

struct NativeNavigationActionPresentation: Equatable, Sendable {
  let overlayOpacity: Double
  let strokeOpacity: Double
  let foregroundOpacity: Double
  let scale: CGFloat
}

enum NativeNavigationStyle {
  static let foregroundNSColor = NSColor.labelColor
  static let foreground = Color(nsColor: foregroundNSColor)
  /// Idle projects rely on their own neutral glass without an additional tint.
  static let projectSurfaceOpacity = 0.0
  static let hoverOverlayOpacity = 0.07
  static let selectionOverlayOpacity = 0.055
  static let selectionFill = Color(nsColor: .labelColor).opacity(selectionOverlayOpacity)
  static let selectionIndicator = Color.accentColor.opacity(0.78)

  static func interactionFill(for colorScheme: ColorScheme) -> Color {
    colorScheme == .light
      ? Color.white.opacity(0.18)
      : Color.white.opacity(hoverOverlayOpacity)
  }

  /// Hover feedback lives on controls and content, never as a tint over the row glass.
  static func projectRowOverlayOpacity(isHovered: Bool) -> Double {
    0
  }

  static func projectActionPresentation(
    isHovered: Bool,
    isPressed: Bool,
    isEnabled: Bool,
    reduceMotion: Bool
  ) -> NativeNavigationActionPresentation {
    guard isEnabled else {
      return NativeNavigationActionPresentation(
        overlayOpacity: 0,
        strokeOpacity: 0,
        foregroundOpacity: 0.38,
        scale: 1
      )
    }
    if isPressed {
      return NativeNavigationActionPresentation(
        overlayOpacity: 0,
        strokeOpacity: 0,
        foregroundOpacity: 1,
        scale: reduceMotion ? 1 : 0.94
      )
    }
    if isHovered {
      return NativeNavigationActionPresentation(
        overlayOpacity: 0,
        strokeOpacity: 0,
        foregroundOpacity: 1,
        scale: 1
      )
    }
    return NativeNavigationActionPresentation(
      overlayOpacity: 0,
      strokeOpacity: 0,
      foregroundOpacity: 0.78,
      scale: 1
    )
  }

}

enum NativeNavigationMaterialPolicy {
  enum ContainerScope: Equatable, Sendable {
    case none
  }

  enum Grouping: Equatable, Sendable {
    case independentProjectSurfaces
  }

  enum RenderingPath: Equatable, Sendable {
    case stableOpticalCanvas
  }

  /// Each project uses the same direct surface path as the composer and details.
  /// A navigation-only glass container would create a different compositing context.
  static let containerScope = ContainerScope.none
  static let grouping = Grouping.independentProjectSurfaces
  static let opticalReferenceHeight = InputComposerShape.collapsedSurfaceHeight

  /// Project rows reveal one fixed SwiftUI Liquid Glass canvas through an
  /// animatable mask so pointer feedback never replaces its sampling context.
  static let renderingPath = RenderingPath.stableOpticalCanvas
  /// Project action circles are separate hit targets, but their glass must
  /// remain optically identical to the project row during pointer feedback.
  static let projectActionSurfaceRole = RabbisirGlassSurfaceRole.navigation
  static let projectActionIsInteractive = false

  /// The project's mask owns the extension; no second glass surface is added.
  static func projectOwnerExtensionWidth(isHovered: Bool) -> CGFloat {
    isHovered ? NativeNavigationLayout.resizeExtensionWidth : 0
  }

  static func configuration() -> RabbisirGlassMaterialConfiguration {
    RabbisirGlassMaterialPolicy.configuration(
      role: .navigation
    )
  }

  static func projectActionConfiguration() -> RabbisirGlassMaterialConfiguration {
    RabbisirGlassMaterialPolicy.configuration(
      role: projectActionSurfaceRole,
      interactive: projectActionIsInteractive
    )
  }
}

extension View {
  @ViewBuilder
  func nativeNavigationChildGlass() -> some View {
    self
  }
}
