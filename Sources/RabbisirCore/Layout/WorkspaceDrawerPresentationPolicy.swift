enum WorkspaceDrawerPresentationAction: Equatable, Sendable {
  case toggleTrigger
  case explicitClose
  case outsideInteraction(internalOperationActive: Bool)
  case acceptedInternalOperation
}

enum WorkspaceDrawerPresentationPolicy {
  static func triggerSymbolName(isPresented: Bool) -> String {
    isPresented ? "chevron.down" : "chevron.up"
  }

  static func presentation(
    after action: WorkspaceDrawerPresentationAction,
    currentlyPresented: Bool
  ) -> Bool {
    switch action {
    case .toggleTrigger:
      !currentlyPresented
    case .explicitClose:
      false
    case .outsideInteraction(let internalOperationActive):
      internalOperationActive ? currentlyPresented : false
    case .acceptedInternalOperation:
      currentlyPresented
    }
  }
}
