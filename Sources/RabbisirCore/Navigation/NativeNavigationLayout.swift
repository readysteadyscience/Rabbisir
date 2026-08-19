import CoreGraphics

enum NativeNavigationLayout {
  static let projectRowHeight: CGFloat = 34
  static let overflowControlDiameter: CGFloat = 26
  static let overflowControlOuterInset = SpatialWorkspaceLayoutPolicy.inputBottomInset
  static let overflowControlToContentSpacing = projectRowHeight
  static let safeVerticalInset =
    overflowControlOuterInset + overflowControlDiameter + overflowControlToContentSpacing
  static let sessionRowHeight: CGFloat = 32
  static let projectSpacing: CGFloat = 4
  static let childSpacing: CGFloat = 3
  static let trailingRadius: CGFloat = 12
  /// Transparent room owned by a row's hover affordances, outside its title layout.
  static let trailingInteractionReserve: CGFloat = 124
  static let resizeExtensionWidth: CGFloat = 18
  static let hoverActionCount = 4
  static let hoverActionDiameter: CGFloat = 20
  static let hoverActionSpacing: CGFloat = 6

  static var hoverActionSurfaceWidth: CGFloat {
    CGFloat(hoverActionCount) * hoverActionDiameter
      + CGFloat(hoverActionCount - 1) * hoverActionSpacing
  }

  static var initialExpandedProjectIDs: Set<String> { [] }

  static var requiredTrailingInteractionWidth: CGFloat {
    resizeExtensionWidth + 5 + hoverActionSurfaceWidth
  }

  static func childSectionHeight(sessionCount: Int) -> CGFloat {
    guard sessionCount > 0 else { return 0 }
    return CGFloat(sessionCount) * sessionRowHeight
      + CGFloat(sessionCount) * childSpacing
  }

  static func visibleChildSectionHeight(
    sessionCount: Int,
    isExpanded: Bool
  ) -> CGFloat {
    isExpanded ? childSectionHeight(sessionCount: sessionCount) : 0
  }

  static func minimumContentHeight(viewportHeight: CGFloat) -> CGFloat {
    max(0, viewportHeight)
  }

  static func scrollViewportHeight(totalViewportHeight: CGFloat) -> CGFloat {
    max(0, totalViewportHeight - safeVerticalInset * 2)
  }

  static func scrollInteractionBounds(
    viewportSize: CGSize,
    navigationWidth: CGFloat
  ) -> CGRect {
    CGRect(
      x: 0,
      y: safeVerticalInset,
      width: max(0, min(navigationWidth, viewportSize.width)),
      height: scrollViewportHeight(totalViewportHeight: viewportSize.height)
    )
  }

  static func overflowVisibility(
    contentBounds: CGRect,
    viewportHeight: CGFloat,
    tolerance: CGFloat = 1
  ) -> NativeNavigationOverflowVisibility {
    guard !contentBounds.isNull, viewportHeight > 0 else {
      return NativeNavigationOverflowVisibility(hasHiddenAbove: false, hasHiddenBelow: false)
    }
    return NativeNavigationOverflowVisibility(
      hasHiddenAbove: contentBounds.minY < safeVerticalInset - tolerance,
      hasHiddenBelow: contentBounds.maxY > viewportHeight - safeVerticalInset + tolerance
    )
  }

  static func overflowControlCenterY(
    edge: NativeNavigationOverflowEdge,
    viewportHeight: CGFloat
  ) -> CGFloat {
    let inset = overflowControlOuterInset + overflowControlDiameter / 2
    switch edge {
    case .top:
      return inset
    case .bottom:
      return viewportHeight - inset
    }
  }

  static func contentHeight(
    projects: [RuntimeNavigationProject],
    expandedProjectIDs: Set<String>
  ) -> CGFloat {
    guard !projects.isEmpty else { return 0 }
    let projectRows = CGFloat(projects.count) * projectRowHeight
    let projectGaps = CGFloat(max(0, projects.count - 1)) * projectSpacing
    let childRows = projects.reduce(CGFloat.zero) { total, project in
      guard expandedProjectIDs.contains(project.id), !project.sessions.isEmpty else {
        return total
      }
      return total + childSectionHeight(sessionCount: project.sessions.count)
    }
    return projectRows + projectGaps + childRows
  }

  static func expansionNeedsBottomReveal(
    projects: [RuntimeNavigationProject],
    expandedProjectIDs: Set<String>,
    viewportHeight: CGFloat
  ) -> Bool {
    contentHeight(projects: projects, expandedProjectIDs: expandedProjectIDs)
      > minimumContentHeight(viewportHeight: viewportHeight)
  }
}

enum NativeNavigationOverflowEdge {
  case top
  case bottom
}

struct NativeNavigationOverflowVisibility: Equatable {
  let hasHiddenAbove: Bool
  let hasHiddenBelow: Bool
}
