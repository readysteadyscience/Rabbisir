import CoreGraphics

public enum WorkspaceLayoutTier: String, Equatable, Sendable {
  case wide
  case standard
  case compressed
}

public struct WorkspaceLayout: Equatable, Sendable {
  public let centerOriginX: CGFloat
  public let centerWidth: CGFloat
  public let detailOriginX: CGFloat
  public let detailWidth: CGFloat
  public let tier: WorkspaceLayoutTier
}

public enum WorkspaceLayoutPolicy {
  public static let outerPadding: CGFloat = 12
  public static let panelGap: CGFloat = 12
  public static let preferredCenterWidth: CGFloat = 900
  public static let minimumCenterWidth: CGFloat = 520
  public static let preferredDetailWidth: CGFloat = 360
  public static let minimumDetailWidth: CGFloat = 320

  public static func resolve(width: CGFloat, detailsVisible: Bool) -> WorkspaceLayout {
    let usableWidth = max(0, width - outerPadding * 2)
    let baselineCenterWidth = min(preferredCenterWidth, usableWidth)
    let baselineCenterOrigin = (width - baselineCenterWidth) / 2

    guard detailsVisible else {
      return WorkspaceLayout(
        centerOriginX: baselineCenterOrigin,
        centerWidth: baselineCenterWidth,
        detailOriginX: width - outerPadding,
        detailWidth: 0,
        tier: .wide
      )
    }

    let maximumDetailWidth = max(
      minimumDetailWidth,
      usableWidth - minimumCenterWidth - panelGap
    )
    let detailWidth = min(preferredDetailWidth, maximumDetailWidth)
    let detailOrigin = width - outerPadding - detailWidth
    let overlap = max(
      0,
      baselineCenterOrigin + baselineCenterWidth + panelGap - detailOrigin
    )
    let leftWhitespace = max(0, baselineCenterOrigin - outerPadding)
    let shift = min(overlap, leftWhitespace)
    let compression = max(0, overlap - shift)
    let centerWidth = max(minimumCenterWidth, baselineCenterWidth - compression)

    let tier: WorkspaceLayoutTier
    if overlap == 0 {
      tier = .wide
    } else if compression == 0 {
      tier = .standard
    } else {
      tier = .compressed
    }

    return WorkspaceLayout(
      centerOriginX: baselineCenterOrigin - shift,
      centerWidth: centerWidth,
      detailOriginX: detailOrigin,
      detailWidth: detailWidth,
      tier: tier
    )
  }
}

public enum MainWindowPlacement {
  public static func frame(in visibleFrame: CGRect) -> CGRect {
    let width = min(1_440, visibleFrame.width * 0.92)
    let height = min(960, visibleFrame.height * 0.90)
    return CGRect(
      x: visibleFrame.midX - width / 2,
      y: visibleFrame.midY - height / 2,
      width: width,
      height: height
    )
  }
}
