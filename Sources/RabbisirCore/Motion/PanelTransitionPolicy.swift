import CoreGraphics

enum PanelTransitionEdge: Equatable, Sendable {
  case leading
  case trailing
}

enum PanelTransitionPolicy {
  static func visibleContentFrame(in bounds: CGRect) -> CGRect {
    CGRect(origin: bounds.origin, size: bounds.size)
  }

  static func hiddenContentFrame(
    in bounds: CGRect,
    edge: PanelTransitionEdge
  ) -> CGRect {
    CGRect(
      x: edge == .leading ? -bounds.width : bounds.width,
      y: bounds.minY,
      width: bounds.width,
      height: bounds.height
    )
  }

  static func isStrictHorizontalTransition(from: CGRect, to: CGRect) -> Bool {
    from.minY == to.minY && from.size == to.size
  }
}
