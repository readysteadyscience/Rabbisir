import CoreGraphics

struct ComposerInputLayout: Equatable, Sendable {
  static let minimumTextViewportHeight: CGFloat = 20
  static let maximumTextViewportHeight: CGFloat = 260
  static let maximumScreenHeightRatio: CGFloat = 0.30
  static let controlRowOffsetY: CGFloat = 8

  let textViewportHeight: CGFloat
  let surfaceHeight: CGFloat

  var panelExpansionHeight: CGFloat {
    surfaceHeight - InputComposerShape.collapsedSurfaceHeight
  }

  static func resolve(measuredTextHeight: CGFloat, visibleHeight: CGFloat) -> Self {
    let maximum = max(
      minimumTextViewportHeight,
      min(maximumTextViewportHeight, visibleHeight * maximumScreenHeightRatio)
    )
    let viewport = min(max(measuredTextHeight, minimumTextViewportHeight), maximum)
    return Self(
      textViewportHeight: viewport,
      surfaceHeight: InputComposerShape.collapsedSurfaceHeight
        + viewport - minimumTextViewportHeight
    )
  }
}
