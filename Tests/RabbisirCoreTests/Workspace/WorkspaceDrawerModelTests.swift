import Foundation
import Testing

@testable import RabbisirCore

@Suite("Workspace drawer model")
struct WorkspaceDrawerModelTests {
  @Test("Cancelling the native picker preserves the current workspace")
  @MainActor
  func cancelPreservesSelection() async {
    let picker = WorkspaceDirectoryPickerStub(result: nil)
    let adopter = WorkspaceAdopterStub(result: true)
    let model = WorkspaceDrawerModel(
      workspaceAdopter: adopter,
      directoryPicker: picker
    )
    model.isPresented = true

    model.createWorkspace()
    await waitUntilIdle(model)

    #expect(picker.pickCount == 1)
    #expect(adopter.adoptedURLs.isEmpty)
    #expect(model.isPresented)
    #expect(model.failureMessage == nil)
  }

  @Test("A selected temporary directory is adopted without losing drawer state")
  @MainActor
  func selectedDirectoryIsAdopted() async {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let picker = WorkspaceDirectoryPickerStub(result: directory)
    let adopter = WorkspaceAdopterStub(result: true)
    let model = WorkspaceDrawerModel(
      workspaceAdopter: adopter,
      directoryPicker: picker
    )
    model.isPresented = true

    model.createWorkspace()
    await waitUntilIdle(model)

    #expect(adopter.adoptedURLs == [directory])
    #expect(model.isPresented)
    #expect(model.failureMessage == nil)
  }

  @Test("A failed adoption reports failure without changing the selected workspace")
  @MainActor
  func adoptionFailureRemainsRecoverable() async {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    let picker = WorkspaceDirectoryPickerStub(result: directory)
    let adopter = WorkspaceAdopterStub(result: false)
    let model = WorkspaceDrawerModel(
      workspaceAdopter: adopter,
      directoryPicker: picker
    )
    model.isPresented = true

    model.createWorkspace()
    await waitUntilIdle(model)

    #expect(adopter.adoptedURLs == [directory])
    #expect(model.isPresented)
    #expect(model.failureMessage != nil)
  }

  @MainActor
  private func waitUntilIdle(_ model: WorkspaceDrawerModel) async {
    let deadline = ContinuousClock.now + .seconds(1)
    while model.isPerformingInternalOperation, ContinuousClock.now < deadline {
      await Task.yield()
    }
  }
}

@MainActor
private final class WorkspaceDirectoryPickerStub: WorkspaceDirectoryPicking {
  private let result: URL?
  private(set) var pickCount = 0

  init(result: URL?) {
    self.result = result
  }

  func pickDirectory() async -> URL? {
    pickCount += 1
    return result
  }
}

@MainActor
private final class WorkspaceAdopterStub: WorkspaceAdopting {
  private let result: Bool
  private(set) var adoptedURLs: [URL] = []

  init(result: Bool) {
    self.result = result
  }

  func adoptWorkspace(at directory: URL) async -> Bool {
    adoptedURLs.append(directory)
    return result
  }
}
