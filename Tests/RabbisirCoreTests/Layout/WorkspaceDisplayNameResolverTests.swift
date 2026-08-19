import Testing

@testable import RabbisirCore

@Suite("Workspace display name")
struct WorkspaceDisplayNameResolverTests {
  @Test("The selected session's owning project overrides the Composer placeholder")
  func selectedSessionOwnsTheDisplayName() {
    let projects = [
      project(id: "one", title: "项目一", sessionID: "session-1", selected: false),
      project(id: "two", title: "项目二", sessionID: "session-2", selected: true),
    ]

    #expect(
      WorkspaceDisplayNameResolver.resolve(
        projects: projects,
        composerWorkspace: "当前工作区"
      ) == "项目二"
    )
  }

  @Test("Changing the selected session changes the displayed project")
  func sessionSelectionChangesTheDisplayName() {
    let firstSelection = [
      project(id: "one", title: "项目一", sessionID: "session-1", selected: true),
      project(id: "two", title: "项目二", sessionID: "session-2", selected: false),
    ]
    let secondSelection = [
      project(id: "one", title: "项目一", sessionID: "session-1", selected: false),
      project(id: "two", title: "项目二", sessionID: "session-2", selected: true),
    ]

    #expect(
      WorkspaceDisplayNameResolver.resolve(
        projects: firstSelection,
        composerWorkspace: "当前工作区"
      ) == "项目一"
    )
    #expect(
      WorkspaceDisplayNameResolver.resolve(
        projects: secondSelection,
        composerWorkspace: "当前工作区"
      ) == "项目二"
    )
  }

  @Test("A new session without an owning project keeps the Composer workspace")
  func newSessionFallsBackToComposerWorkspace() {
    #expect(
      WorkspaceDisplayNameResolver.resolve(
        projects: [
          project(
            id: "one",
            title: "项目一",
            sessionID: "session-1",
            selected: false
          )
        ],
        composerWorkspace: "新会话工作区"
      ) == "新会话工作区"
    )
  }

  private func project(
    id: String,
    title: String,
    sessionID: String,
    selected: Bool
  ) -> RuntimeNavigationProject {
    RuntimeNavigationProject(
      id: id,
      title: title,
      sessions: [
        RuntimeNavigationSession(
          id: sessionID,
          title: sessionID,
          isSelected: selected,
          updatedAt: 0
        )
      ]
    )
  }
}
