import Foundation

enum NavigationProjectHoverSource: Hashable, Sendable {
  case row
  case resizeHandle
  case actionSlots
}

/// Tracks the independently entered surfaces that make up one project row's
/// hover affordance. A leave from one surface cannot dismiss the affordance
/// while the pointer remains over another surface owned by the same row.
struct NavigationProjectHoverState: Equatable, Sendable {
  private(set) var sources: Set<NavigationProjectHoverSource> = []

  var isActive: Bool { !sources.isEmpty }

  mutating func set(
    _ source: NavigationProjectHoverSource,
    hovering: Bool
  ) {
    if hovering {
      sources.insert(source)
    } else {
      sources.remove(source)
    }
  }

  mutating func reset() {
    sources.removeAll()
  }
}

/// Owns the single project row whose expensive hover material is visible.
/// Delayed leave callbacks from a previous row cannot clear a newer owner.
struct NavigationProjectHoverPresentationState: Equatable, Sendable {
  private(set) var activeProjectID: String?

  mutating func set(projectID: String, hovering: Bool) {
    if hovering {
      activeProjectID = projectID
    } else if activeProjectID == projectID {
      activeProjectID = nil
    }
  }

  func isPresented(for projectID: String) -> Bool {
    activeProjectID == projectID
  }
}

/// Owns the single session row whose hover actions are visible. Delayed leave
/// callbacks from a reused or previously hovered row cannot dismiss the
/// current row's actions.
struct NavigationSessionHoverPresentationState: Equatable, Sendable {
  private(set) var activeSessionID: String?

  mutating func set(sessionID: String, hovering: Bool) {
    if hovering {
      activeSessionID = sessionID
    } else if activeSessionID == sessionID {
      activeSessionID = nil
    }
  }

  func isPresented(for sessionID: String) -> Bool {
    activeSessionID == sessionID
  }
}

struct NavigationHoverHandleState: Equatable, Sendable {
  var isRowHovered = false
  var isHandleHovered = false
  var isDragging = false

  var shouldRemainVisible: Bool {
    isRowHovered || isHandleHovered || isDragging
  }

  mutating func apply(_ event: NavigationHoverHandleEvent) {
    switch event {
    case .rowHover(let hovering):
      isRowHovered = hovering
    case .handleHover(let hovering):
      isHandleHovered = hovering
    case .drag(let dragging):
      isDragging = dragging
    }
  }
}

enum NavigationHoverHandleEvent: Equatable, Sendable {
  case rowHover(Bool)
  case handleHover(Bool)
  case drag(Bool)
}

/// Orders hover exit so the grip is gone before its owning row retracts.
enum NavigationHoverExitPolicy {
  static let boundaryGraceDuration = 0.06

  static func gripDismissDuration(reduceMotion: Bool) -> TimeInterval {
    reduceMotion
      ? 0
      : RabbisirMotionToken.navigationRowHandleReveal.duration
  }
}

enum NavigationHoverOwnershipPolicy {
  static func acceptsLeave(
    activeProjectID: String?,
    leavingProjectID: String
  ) -> Bool {
    activeProjectID == leavingProjectID
  }

  static func isProjectTransfer(
    activeProjectID: String?,
    incomingProjectID: String
  ) -> Bool {
    guard let activeProjectID else { return false }
    return activeProjectID != incomingProjectID
  }
}
