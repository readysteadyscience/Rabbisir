import CoreGraphics

public enum SpatialWorkspaceTier: String, Equatable, Sendable {
  case wide
  case standard
  case compressed
}

public struct SpatialWorkspaceLayout: Equatable, Sendable {
  public let sidebarFrame: CGRect
  public let mainFrame: CGRect
  public let inputFrame: CGRect
  public let detailsFrame: CGRect?
  public let canonicalConversationCenterX: CGFloat
  public let tier: SpatialWorkspaceTier
}

public enum SpatialWorkspaceLayoutPolicy {
  public static let outerMargin: CGFloat = 24
  public static let panelGap: CGFloat = 16
  public static let conversationDetailClearance: CGFloat = 24
  public static let sidebarWidth: CGFloat = 264
  public static let minimumSidebarWidth: CGFloat = 196
  public static let maximumSidebarWidth: CGFloat = 440
  public static let preferredInputWidth: CGFloat = 780
  public static let minimumInputWidth: CGFloat = 520
  public static let maximumConversationWidth: CGFloat = 1_200
  public static let inputWidthRatio: CGFloat = 0.18
  public static let inputBottomInset: CGFloat = 10
  public static let inputHeight: CGFloat = 129
  public static let detailsWidth: CGFloat = 720
  public static let minimumDetailsWidth: CGFloat = 420
  public static let maximumStoredDetailsWidth: CGFloat = 10_000

  public static func resolve(
    visibleFrame: CGRect,
    detailsVisible: Bool,
    navigationBarBottomY: CGFloat? = nil,
    preferredSidebarWidth: CGFloat? = nil,
    preferredConversationWidth: CGFloat? = nil,
    preferredDetailsWidth: CGFloat? = nil
  ) -> SpatialWorkspaceLayout {
    let preferredResolvedSidebarWidth = min(
      max(preferredSidebarWidth ?? sidebarWidth, minimumSidebarWidth),
      min(maximumSidebarWidth, max(minimumSidebarWidth, visibleFrame.width * 0.32))
    )
    let canonicalCenterX = visibleFrame.midX
    let preferredConversationMinimumX =
      visibleFrame.minX + preferredResolvedSidebarWidth + panelGap
    let maximumCenteredWidth = max(
      minimumInputWidth,
      2 * (canonicalCenterX - preferredConversationMinimumX)
    )
    let screenConversationMaximum = max(
      minimumInputWidth,
      min(
        maximumConversationWidth,
        maximumCenteredWidth,
        visibleFrame.width - outerMargin * 2
      )
    )
    let automaticConversationWidth = min(
      preferredInputWidth,
      screenConversationMaximum,
      max(minimumInputWidth, visibleFrame.width * inputWidthRatio)
    )

    let inputY = visibleFrame.minY + inputBottomInset
    let mainMaxY = visibleFrame.maxY - outerMargin
    let requestedDetailsWidth = preferredDetailsWidth ?? detailsWidth
    let resolvedDetailsWidth = constrainedDetailsWidth(
      requestedDetailsWidth,
      visibleFrame: visibleFrame
    )
    let sharedInset = inputY - visibleFrame.minY
    let navigationBottom = min(
      navigationBarBottomY ?? visibleFrame.maxY,
      visibleFrame.maxY
    )
    let detailTopY = max(inputY, navigationBottom - sharedInset)
    let details =
      detailsVisible
      ? CGRect(
        x: visibleFrame.maxX - resolvedDetailsWidth,
        y: inputY,
        width: resolvedDetailsWidth,
        height: max(0, detailTopY - inputY)
      )
      : nil

    let requestedConversationWidth =
      preferredConversationWidth
      ?? automaticConversationWidth
    var conversationWidth = min(
      max(requestedConversationWidth, minimumInputWidth),
      screenConversationMaximum
    )
    let canonicalOriginX = canonicalCenterX - conversationWidth / 2
    var resolvedSidebarWidth = preferredResolvedSidebarWidth
    var effectiveOriginX = canonicalOriginX

    if let details {
      let availableConversationMaxX = details.minX - conversationDetailClearance
      if canonicalOriginX + conversationWidth > availableConversationMaxX {
        let shiftedOriginX = availableConversationMaxX - conversationWidth
        if shiftedOriginX >= preferredConversationMinimumX {
          effectiveOriginX = shiftedOriginX
        } else {
          resolvedSidebarWidth = min(
            preferredResolvedSidebarWidth,
            max(
              minimumSidebarWidth,
              availableConversationMaxX
                - conversationWidth
                - panelGap
                - visibleFrame.minX
            )
          )
          effectiveOriginX = visibleFrame.minX + resolvedSidebarWidth + panelGap
          conversationWidth = max(
            minimumInputWidth,
            min(conversationWidth, availableConversationMaxX - effectiveOriginX)
          )
        }
      }
    }

    let sidebar = CGRect(
      x: visibleFrame.minX,
      y: visibleFrame.minY,
      width: resolvedSidebarWidth,
      height: max(420, visibleFrame.height)
    )
    let input = CGRect(
      x: effectiveOriginX,
      y: inputY,
      width: conversationWidth,
      height: inputHeight
    )
    let main = CGRect(
      x: effectiveOriginX,
      y: input.maxY,
      width: conversationWidth,
      height: max(0, mainMaxY - input.maxY)
    )

    let tier: SpatialWorkspaceTier
    if conversationWidth < requestedConversationWidth
      || resolvedSidebarWidth < preferredResolvedSidebarWidth
    {
      tier = .compressed
    } else if effectiveOriginX < canonicalOriginX {
      tier = .standard
    } else {
      tier = .wide
    }

    return SpatialWorkspaceLayout(
      sidebarFrame: sidebar,
      mainFrame: main,
      inputFrame: input,
      detailsFrame: details,
      canonicalConversationCenterX: canonicalCenterX,
      tier: tier
    )
  }

  public static func conversationWidth(
    from preferredWidth: CGFloat,
    horizontalDragDelta: CGFloat
  ) -> CGFloat {
    preferredWidth + 2 * horizontalDragDelta
  }

  public static func sidebarWidth(
    from preferredWidth: CGFloat,
    horizontalDragDelta: CGFloat
  ) -> CGFloat {
    preferredWidth + horizontalDragDelta
  }

  public static func detailsWidth(
    from preferredWidth: CGFloat,
    horizontalDragDelta: CGFloat
  ) -> CGFloat {
    preferredWidth - horizontalDragDelta
  }

  private static func constrainedDetailsWidth(
    _ requestedWidth: CGFloat,
    visibleFrame: CGRect
  ) -> CGFloat {
    let availableWidth = max(
      minimumDetailsWidth,
      visibleFrame.width
        - minimumSidebarWidth
        - panelGap
        - minimumInputWidth
        - conversationDetailClearance
    )
    return min(max(requestedWidth, minimumDetailsWidth), availableWidth)
  }
}
