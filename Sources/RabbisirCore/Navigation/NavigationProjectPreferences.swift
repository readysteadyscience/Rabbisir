import Foundation

/// Persists Rabbisir-only project presentation state by the official
/// WorkspaceId. The upstream runtime remains the authority for project identity and data.
struct NavigationProjectPreferencesStore {
  private static let archivedKey = "Rabbisir.navigation.archivedWorkspaceIDs"
  private static let lastSelectedSessionKey = "Rabbisir.navigation.lastSelectedSessionID"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  func archivedWorkspaceIDs() -> Set<String> {
    Set(defaults.stringArray(forKey: Self.archivedKey) ?? [])
  }

  func setArchived(_ archived: Bool, workspaceID: String) {
    var ids = archivedWorkspaceIDs()
    if archived {
      ids.insert(workspaceID)
    } else {
      ids.remove(workspaceID)
    }
    defaults.set(ids.sorted(), forKey: Self.archivedKey)
  }

  func remove(workspaceID: String) {
    setArchived(false, workspaceID: workspaceID)
  }

  func lastSelectedSessionID() -> String? {
    guard
      let value = defaults.string(forKey: Self.lastSelectedSessionKey)?
        .trimmingCharacters(in: .whitespacesAndNewlines),
      !value.isEmpty
    else { return nil }
    return value
  }

  func setLastSelectedSessionID(_ sessionID: String) {
    let value = sessionID.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !value.isEmpty else { return }
    defaults.set(value, forKey: Self.lastSelectedSessionKey)
  }

  func clearLastSelectedSessionID(ifMatching sessionID: String) {
    guard lastSelectedSessionID() == sessionID else { return }
    defaults.removeObject(forKey: Self.lastSelectedSessionKey)
  }
}

enum NavigationSessionRestorePolicy {
  static func restoreCandidate(
    savedSessionID: String?,
    currentSessionID: String?,
    projects: [RuntimeNavigationProject]
  ) -> String? {
    let visibleSessionIDs = Set(projects.flatMap(\.sessions).map(\.id))
    if let currentSessionID, visibleSessionIDs.contains(currentSessionID) {
      return nil
    }
    guard let savedSessionID, visibleSessionIDs.contains(savedSessionID) else {
      return nil
    }
    return savedSessionID
  }
}
