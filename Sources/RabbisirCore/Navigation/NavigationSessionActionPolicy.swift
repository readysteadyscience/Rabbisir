/// A native session operation whose availability is derived from the upstream runtime API.
enum NavigationSessionAction: Equatable, Sendable {
  case pin
  case rename
  case archive
  case delete
  case fork
  case moveToWorkspace(workspaceID: String)
  case showInFinder
  case copyWorkingDirectory
  case copySessionID
}

/// One stable hover position and whether the official API can perform it.
struct NavigationSessionHoverAction: Equatable, Sendable {
  let kind: NavigationSessionAction
  let isEnabled: Bool
}

/// Keeps hover positions stable while exposing only capabilities with a real implementation.
enum NavigationSessionActionPolicy {
  static func hoverActions(
    belongsToDurableWorkspace: Bool
  ) -> [NavigationSessionHoverAction] {
    [
      NavigationSessionHoverAction(kind: .pin, isEnabled: belongsToDurableWorkspace),
      NavigationSessionHoverAction(kind: .rename, isEnabled: true),
      NavigationSessionHoverAction(kind: .archive, isEnabled: true),
      // The current upstream runtime RPC map has no session deletion operation.
      NavigationSessionHoverAction(kind: .delete, isEnabled: false),
    ]
  }

  static func contextMenuActions(
    hasWorkingDirectory: Bool,
    movableWorkspaceIDs: [String]
  ) -> [NavigationSessionAction] {
    var actions: [NavigationSessionAction] = [.fork]
    actions.append(
      contentsOf: movableWorkspaceIDs.map {
        .moveToWorkspace(workspaceID: $0)
      }
    )
    if hasWorkingDirectory {
      actions.append(.showInFinder)
      actions.append(.copyWorkingDirectory)
    }
    actions.append(.copySessionID)
    return actions
  }
}
