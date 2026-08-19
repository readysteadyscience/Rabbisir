import CoreGraphics

enum ConversationBackdropLayout {
  static let topComfort: CGFloat = 32

  static func height(
    visibleMessageCount: Int,
    measuredContentHeight: CGFloat,
    viewportHeight: CGFloat
  ) -> CGFloat {
    guard visibleMessageCount > 0, viewportHeight > 0 else { return 0 }
    return min(
      viewportHeight,
      max(0, measuredContentHeight) + topComfort
    )
  }
}
