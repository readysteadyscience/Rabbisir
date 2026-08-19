import Combine

@MainActor
final class WorkspaceDrawerModel: ObservableObject {
  @Published private(set) var failureMessage: String?
  @Published var isPresented = false
  @Published private(set) var isContentVisible = false
  private(set) var isPerformingInternalOperation = false

  private let workspaceAdopter: any WorkspaceAdopting
  private let directoryPicker: any WorkspaceDirectoryPicking

  convenience init(runtimeBridge: RuntimeBridgeStore) {
    self.init(
      workspaceAdopter: runtimeBridge,
      directoryPicker: AppKitWorkspaceDirectoryPicker()
    )
  }

  init(
    workspaceAdopter: any WorkspaceAdopting,
    directoryPicker: any WorkspaceDirectoryPicking
  ) {
    self.workspaceAdopter = workspaceAdopter
    self.directoryPicker = directoryPicker
  }

  func toggle() {
    let next = WorkspaceDrawerPresentationPolicy.presentation(
      after: .toggleTrigger,
      currentlyPresented: isPresented
    )
    if next {
      isContentVisible = true
      isPresented = true
    } else {
      dismiss()
    }
  }

  func dismiss() {
    isPresented = WorkspaceDrawerPresentationPolicy.presentation(
      after: .explicitClose,
      currentlyPresented: isPresented
    )
    failureMessage = nil
  }

  func dismissFromOutsideInteraction() {
    let consumedExternalOperation = isPerformingInternalOperation
    isPresented = WorkspaceDrawerPresentationPolicy.presentation(
      after: .outsideInteraction(
        internalOperationActive: consumedExternalOperation
      ),
      currentlyPresented: isPresented
    )
    if consumedExternalOperation {
      isPerformingInternalOperation = false
    }
    failureMessage = nil
  }

  func finishDismissal() {
    guard !isPresented else { return }
    isContentVisible = false
  }

  func createWorkspace() {
    guard !isPerformingInternalOperation else { return }
    isPerformingInternalOperation = true
    failureMessage = nil
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard let directory = await directoryPicker.pickDirectory() else {
        isPerformingInternalOperation = false
        return
      }
      let accepted = await workspaceAdopter.adoptWorkspace(at: directory)
      isPerformingInternalOperation = false
      guard accepted else {
        failureMessage =
          RabbisirCopy(language: RabbisirLocalization.shared.language)[
            .newWorkspaceFailure
          ]
        return
      }
      failureMessage = nil
      isPresented = WorkspaceDrawerPresentationPolicy.presentation(
        after: .acceptedInternalOperation,
        currentlyPresented: isPresented
      )
    }
  }
}
