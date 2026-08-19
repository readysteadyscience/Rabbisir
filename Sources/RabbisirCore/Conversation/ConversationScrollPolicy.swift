import CoreGraphics

enum ConversationScrollAction: Equatable, Sendable {
  case none
  case followTail(animated: Bool)
  case preserveAnchor(id: String)
}

struct ConversationScrollPolicy: Equatable, Sendable {
  static let bottomProximity: CGFloat = 44
  static let historyBoundaryProximity: CGFloat = 28

  private(set) var isFollowingTail = true
  private(set) var hasPositionedInitialContent = false
  private var hasLeftHistoryBoundary = false
  private var wasNearHistoryBoundary = true

  mutating func resetForSession() {
    self = ConversationScrollPolicy()
  }

  mutating func contentDidChange(
    previousIDs: [String],
    currentIDs: [String]
  ) -> ConversationScrollAction {
    guard !currentIDs.isEmpty else { return .none }

    guard hasPositionedInitialContent else {
      hasPositionedInitialContent = true
      return .followTail(animated: false)
    }

    if let anchorID = prependedAnchor(previousIDs: previousIDs, currentIDs: currentIDs) {
      return .preserveAnchor(id: anchorID)
    }

    return isFollowingTail ? .followTail(animated: true) : .none
  }

  mutating func viewportDidUpdate(
    distanceFromBottom: CGFloat,
    contentTopOffset: CGFloat
  ) -> Bool {
    isFollowingTail = distanceFromBottom <= Self.bottomProximity

    let isNearHistoryBoundary = contentTopOffset >= -Self.historyBoundaryProximity
    let shouldLoadOlder =
      isNearHistoryBoundary
      && !wasNearHistoryBoundary
      && hasLeftHistoryBoundary

    if !isNearHistoryBoundary {
      hasLeftHistoryBoundary = true
    }
    wasNearHistoryBoundary = isNearHistoryBoundary
    return shouldLoadOlder
  }

  private func prependedAnchor(
    previousIDs: [String],
    currentIDs: [String]
  ) -> String? {
    guard
      let previousFirstID = previousIDs.first,
      let startIndex = currentIDs.firstIndex(of: previousFirstID),
      startIndex > currentIDs.startIndex,
      currentIDs.count - startIndex >= previousIDs.count
    else {
      return nil
    }

    let preservedRange = currentIDs[startIndex..<startIndex + previousIDs.count]
    guard preservedRange.elementsEqual(previousIDs) else { return nil }
    return previousFirstID
  }
}
