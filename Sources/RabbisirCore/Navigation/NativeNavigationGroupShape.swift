import SwiftUI

struct NativeNavigationGroupShape: Shape {
  let trailingRadius: CGFloat
  var projectRowHeight: CGFloat = 0
  var projectExtensionWidth: CGFloat = 0
  var baseWidth: CGFloat?
  var reservedTrailingWidth: CGFloat = 0

  var animatableData: CGFloat {
    get { projectExtensionWidth }
    set { projectExtensionWidth = newValue }
  }

  func resolvingBaseWidth(_ width: CGFloat) -> Self {
    var copy = self
    copy.baseWidth = width
    return copy
  }

  func path(in rect: CGRect) -> Path {
    let inferredBaseWidth = rect.width - max(0, reservedTrailingWidth)
    let resolvedBaseWidth = min(max(0, baseWidth ?? inferredBaseWidth), rect.width)
    let baseMaxX = rect.minX + resolvedBaseWidth
    let radius = min(trailingRadius, resolvedBaseWidth, rect.height / 2)
    let extensionWidth = max(0, projectExtensionWidth)
    let extendedMaxX = baseMaxX + extensionWidth
    let extendsOnlyProjectRow = extensionWidth > 0 && rect.height > projectRowHeight + 0.5
    let topRightX = extensionWidth > 0 ? extendedMaxX : baseMaxX
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: topRightX - radius, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: topRightX, y: rect.minY + radius),
      control: CGPoint(x: topRightX, y: rect.minY)
    )
    if extendsOnlyProjectRow {
      let joinRadius = min(4, extensionWidth / 2, projectRowHeight / 4)
      path.addLine(to: CGPoint(x: topRightX, y: rect.minY + projectRowHeight - joinRadius))
      path.addQuadCurve(
        to: CGPoint(x: topRightX - joinRadius, y: rect.minY + projectRowHeight),
        control: CGPoint(x: topRightX, y: rect.minY + projectRowHeight)
      )
      path.addLine(to: CGPoint(x: baseMaxX + joinRadius, y: rect.minY + projectRowHeight))
      path.addQuadCurve(
        to: CGPoint(x: baseMaxX, y: rect.minY + projectRowHeight + joinRadius),
        control: CGPoint(x: baseMaxX, y: rect.minY + projectRowHeight)
      )
    }
    let lowerRightX = extendsOnlyProjectRow ? baseMaxX : topRightX
    path.addLine(to: CGPoint(x: lowerRightX, y: rect.maxY - radius))
    path.addQuadCurve(
      to: CGPoint(x: lowerRightX - radius, y: rect.maxY),
      control: CGPoint(x: lowerRightX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}
