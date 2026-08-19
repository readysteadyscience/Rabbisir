import Testing

@testable import RabbisirCore

@Suite("Workspace drawer presentation")
struct WorkspaceDrawerPresentationPolicyTests {
  @Test("The trigger arrow points toward the drawer's next movement")
  func triggerArrowReflectsPresentation() {
    #expect(
      WorkspaceDrawerPresentationPolicy.triggerSymbolName(isPresented: false)
        == "chevron.up"
    )
    #expect(
      WorkspaceDrawerPresentationPolicy.triggerSymbolName(isPresented: true)
        == "chevron.down"
    )
  }

  @Test("Accepted operations inside the drawer preserve its presentation")
  func acceptedInternalOperationsStayOpen() {
    #expect(
      WorkspaceDrawerPresentationPolicy.presentation(
        after: .acceptedInternalOperation,
        currentlyPresented: true
      )
    )
  }

  @Test("Only explicit dismissal actions close the drawer")
  func explicitActionsDismiss() {
    #expect(
      !WorkspaceDrawerPresentationPolicy.presentation(
        after: .toggleTrigger,
        currentlyPresented: true
      )
    )
    #expect(
      !WorkspaceDrawerPresentationPolicy.presentation(
        after: .explicitClose,
        currentlyPresented: true
      )
    )
    #expect(
      !WorkspaceDrawerPresentationPolicy.presentation(
        after: .outsideInteraction(internalOperationActive: false),
        currentlyPresented: true
      )
    )
    #expect(
      WorkspaceDrawerPresentationPolicy.presentation(
        after: .toggleTrigger,
        currentlyPresented: false
      )
    )
  }

  @Test("Outside interactions cannot collapse an active workspace operation")
  func internalOperationProtectsPresentation() {
    #expect(
      WorkspaceDrawerPresentationPolicy.presentation(
        after: .outsideInteraction(internalOperationActive: true),
        currentlyPresented: true
      )
    )
  }
}
