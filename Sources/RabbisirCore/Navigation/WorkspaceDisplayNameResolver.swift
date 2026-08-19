enum WorkspaceDisplayNameResolver {
  static func resolve(
    projects: [RuntimeNavigationProject],
    composerWorkspace: String
  ) -> String {
    projects.first(where: \.containsSelectedSession)?.title ?? composerWorkspace
  }
}
