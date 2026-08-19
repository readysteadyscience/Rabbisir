import CoreGraphics
import Testing

@testable import RabbisirCore

@Suite("Navigation hover resize handle")
struct NavigationHoverHandlePolicyTests {
  @Test("Each surface independently retains one project affordance")
  func compositeProjectHoverSources() {
    var state = NavigationProjectHoverState()
    state.set(.row, hovering: true)
    #expect(state.isActive)

    state.set(.actionSlots, hovering: true)
    state.set(.row, hovering: false)
    #expect(state.isActive)

    state.set(.resizeHandle, hovering: true)
    state.set(.actionSlots, hovering: false)
    #expect(state.isActive)

    state.set(.resizeHandle, hovering: false)
    #expect(!state.isActive)
  }

  @Test("Row reuse clears every stale project hover source")
  func compositeProjectHoverReset() {
    var state = NavigationProjectHoverState()
    state.set(.row, hovering: true)
    state.set(.actionSlots, hovering: true)
    state.reset()
    #expect(!state.isActive)
  }

  @Test("A stale leave cannot dismiss a newly hovered project")
  func staleProjectLeaveIsRejected() {
    #expect(
      !NavigationHoverOwnershipPolicy.acceptsLeave(
        activeProjectID: "project-b",
        leavingProjectID: "project-a"
      )
    )
    #expect(
      NavigationHoverOwnershipPolicy.acceptsLeave(
        activeProjectID: "project-b",
        leavingProjectID: "project-b"
      )
    )
  }

  @Test("Only the current project owns the visible hover affordance")
  func singleProjectPresentationOwner() {
    var state = NavigationProjectHoverPresentationState()

    state.set(projectID: "project-a", hovering: true)
    #expect(state.isPresented(for: "project-a"))
    #expect(!state.isPresented(for: "project-b"))

    state.set(projectID: "project-b", hovering: true)
    #expect(!state.isPresented(for: "project-a"))
    #expect(state.isPresented(for: "project-b"))

    state.set(projectID: "project-a", hovering: false)
    #expect(state.isPresented(for: "project-b"))

    state.set(projectID: "project-b", hovering: false)
    #expect(state.activeProjectID == nil)
  }

  @Test("Only the current session owns the visible hover actions")
  func singleSessionPresentationOwner() {
    var state = NavigationSessionHoverPresentationState()

    state.set(sessionID: "session-a", hovering: true)
    #expect(state.isPresented(for: "session-a"))
    #expect(!state.isPresented(for: "session-b"))

    state.set(sessionID: "session-b", hovering: true)
    #expect(!state.isPresented(for: "session-a"))
    #expect(state.isPresented(for: "session-b"))

    state.set(sessionID: "session-a", hovering: false)
    #expect(state.isPresented(for: "session-b"))

    state.set(sessionID: "session-b", hovering: false)
    #expect(state.activeSessionID == nil)
  }

  @Test("Changing rows starts a new horizontal reveal at the target row")
  func projectTransferResetsItsAnchor() {
    #expect(
      NavigationHoverOwnershipPolicy.isProjectTransfer(
        activeProjectID: "project-a",
        incomingProjectID: "project-b"
      )
    )
    #expect(
      !NavigationHoverOwnershipPolicy.isProjectTransfer(
        activeProjectID: "project-a",
        incomingProjectID: "project-a"
      )
    )
    #expect(
      !NavigationHoverOwnershipPolicy.isProjectTransfer(
        activeProjectID: nil,
        incomingProjectID: "project-a"
      )
    )
  }

  @Test("Crossing from a project row into its handle never hides the handle")
  func rowToHandleHandoff() {
    var state = NavigationHoverHandleState()
    state.apply(.rowHover(true))
    #expect(state.shouldRemainVisible)

    state.apply(.handleHover(true))
    state.apply(.rowHover(false))
    #expect(state.shouldRemainVisible)

    state.apply(.handleHover(false))
    #expect(!state.shouldRemainVisible)
  }

  @Test("An active drag retains the handle after both hover regions are left")
  func dragRetainsVisibility() {
    var state = NavigationHoverHandleState()
    state.apply(.rowHover(true))
    state.apply(.drag(true))
    state.apply(.rowHover(false))
    #expect(state.shouldRemainVisible)

    state.apply(.drag(false))
    #expect(!state.shouldRemainVisible)
  }

  @Test("Grip dismissal completes before the row is allowed to retract")
  func exitOrder() {
    #expect(NavigationHoverExitPolicy.boundaryGraceDuration > 0)
    #expect(
      NavigationHoverExitPolicy.gripDismissDuration(reduceMotion: false)
        <= RabbisirMotionToken.navigationRowHandleReveal.duration
    )
    #expect(NavigationHoverExitPolicy.gripDismissDuration(reduceMotion: true) == 0)
  }

  @Test("Sidebar grip tracks the growing edge instead of appearing at its final point")
  func gripTracksGrowth() {
    let body = CGRect(x: 20, y: 30, width: 240, height: 34)
    let hidden = PanelResizeHandleGeometry.sidebarHandleFrame(
      for: body,
      revealProgress: 0
    )
    let halfway = PanelResizeHandleGeometry.sidebarHandleFrame(
      for: body,
      revealProgress: 0.5
    )
    let visible = PanelResizeHandleGeometry.sidebarHandleFrame(
      for: body,
      revealProgress: 1
    )

    #expect(hidden.midX == body.maxX)
    #expect(halfway.midX > hidden.midX)
    #expect(halfway.midX < visible.midX)
    #expect(visible.minX == body.maxX)
    #expect(hidden.midY == body.midY)
    #expect(visible.midY == body.midY)
  }
}
