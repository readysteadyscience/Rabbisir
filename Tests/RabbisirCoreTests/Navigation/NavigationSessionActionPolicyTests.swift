import Testing

@testable import RabbisirCore

@Suite("Navigation session actions")
struct NavigationSessionActionPolicyTests {
  @Test("Hover keeps four stable positions while unsupported deletion stays disabled")
  func hoverActions() {
    let actions = NavigationSessionActionPolicy.hoverActions(
      belongsToDurableWorkspace: true
    )

    #expect(actions.map(\.kind) == [.pin, .rename, .archive, .delete])
    #expect(actions.map(\.isEnabled) == [true, true, true, false])
  }

  @Test("Ungrouped sessions cannot claim durable pinning")
  func ungroupedPinning() {
    let actions = NavigationSessionActionPolicy.hoverActions(
      belongsToDurableWorkspace: false
    )

    #expect(actions[0].kind == .pin)
    #expect(!actions[0].isEnabled)
  }

  @Test("Context menu omits every hover duplicate and exposes only truthful capabilities")
  func contextMenuCapabilities() {
    let actions = NavigationSessionActionPolicy.contextMenuActions(
      hasWorkingDirectory: true,
      movableWorkspaceIDs: ["workspace-other"]
    )

    #expect(
      actions == [
        .fork,
        .moveToWorkspace(workspaceID: "workspace-other"),
        .showInFinder,
        .copyWorkingDirectory,
        .copySessionID,
      ])
    #expect(!actions.contains(.pin))
    #expect(!actions.contains(.rename))
    #expect(!actions.contains(.archive))
    #expect(!actions.contains(.delete))
  }

  @Test("Context menu removes filesystem actions when no working directory exists")
  func missingWorkingDirectory() {
    let actions = NavigationSessionActionPolicy.contextMenuActions(
      hasWorkingDirectory: false,
      movableWorkspaceIDs: []
    )

    #expect(actions == [.fork, .copySessionID])
  }
}
