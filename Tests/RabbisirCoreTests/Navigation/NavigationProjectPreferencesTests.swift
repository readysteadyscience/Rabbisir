import Foundation
import Testing

@testable import RabbisirCore

@Suite("Navigation project preferences")
struct NavigationProjectPreferencesTests {
  @Test("Project archive state persists by official WorkspaceId and is reversible")
  func archiveRoundTrip() throws {
    let suiteName = "RabbisirTests.NavigationProjectPreferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = NavigationProjectPreferencesStore(defaults: defaults)
    first.setArchived(true, workspaceID: "workspace-real")

    let reopened = NavigationProjectPreferencesStore(defaults: defaults)
    #expect(reopened.archivedWorkspaceIDs() == ["workspace-real"])

    reopened.setArchived(false, workspaceID: "workspace-real")
    #expect(reopened.archivedWorkspaceIDs().isEmpty)
  }

  @Test("Last explicit session selection persists without storing conversation content")
  func sessionSelectionRoundTrip() throws {
    let suiteName = "RabbisirTests.NavigationSessionPreferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suiteName))
    defer { defaults.removePersistentDomain(forName: suiteName) }

    let first = NavigationProjectPreferencesStore(defaults: defaults)
    first.setLastSelectedSessionID("session-explicit")

    let reopened = NavigationProjectPreferencesStore(defaults: defaults)
    #expect(reopened.lastSelectedSessionID() == "session-explicit")

    reopened.clearLastSelectedSessionID(ifMatching: "session-other")
    #expect(reopened.lastSelectedSessionID() == "session-explicit")
    reopened.clearLastSelectedSessionID(ifMatching: "session-explicit")
    #expect(reopened.lastSelectedSessionID() == nil)
  }

  @Test("Cold-start restore replaces only an unlisted transient selection")
  func coldStartRestorePolicy() {
    let projects = [
      RuntimeNavigationProject(
        id: "workspace-real",
        title: "Workspace",
        sessions: [
          RuntimeNavigationSession(
            id: "session-saved",
            title: "Saved",
            isSelected: false,
            updatedAt: 2,
            cwd: nil
          ),
          RuntimeNavigationSession(
            id: "session-current",
            title: "Current",
            isSelected: true,
            updatedAt: 1,
            cwd: nil
          ),
        ]
      )
    ]

    #expect(
      NavigationSessionRestorePolicy.restoreCandidate(
        savedSessionID: "session-saved",
        currentSessionID: "session-transient-blank",
        projects: projects
      ) == "session-saved"
    )
    #expect(
      NavigationSessionRestorePolicy.restoreCandidate(
        savedSessionID: "session-saved",
        currentSessionID: "session-current",
        projects: projects
      ) == nil
    )
    #expect(
      NavigationSessionRestorePolicy.restoreCandidate(
        savedSessionID: "session-missing",
        currentSessionID: "session-transient-blank",
        projects: projects
      ) == nil
    )
  }
}
