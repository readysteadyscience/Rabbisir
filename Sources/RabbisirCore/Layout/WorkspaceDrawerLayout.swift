import CoreGraphics

struct WorkspaceDrawerLayout: Equatable, Sendable {
  static let addWorkspaceActionHeight: CGFloat = 38
  static let verticalPadding: CGFloat = 12

  let expansionHeight: CGFloat
  let listHeight: CGFloat

  static func addWorkspaceOnly() -> Self {
    Self(
      expansionHeight: addWorkspaceActionHeight + verticalPadding * 2,
      listHeight: 0
    )
  }

  static func expandedInputPanelFrame(
    baseFrame: CGRect,
    expansionHeight: CGFloat
  ) -> CGRect {
    CGRect(
      x: baseFrame.minX,
      y: baseFrame.minY,
      width: baseFrame.width,
      height: baseFrame.height + max(0, expansionHeight)
    )
  }

  static func composerOriginY(
    containerHeight: CGFloat,
    composerHeight: CGFloat
  ) -> CGFloat {
    max(0, containerHeight - composerHeight)
  }

  static func drawerOriginY(
    containerHeight: CGFloat,
    composerHeight: CGFloat,
    drawerHeight: CGFloat
  ) -> CGFloat {
    composerOriginY(
      containerHeight: containerHeight,
      composerHeight: composerHeight
    ) - drawerHeight
  }
}
