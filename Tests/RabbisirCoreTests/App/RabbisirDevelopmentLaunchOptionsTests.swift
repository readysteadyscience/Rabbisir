import Foundation
import Testing

@testable import RabbisirCore

@Suite("Rabbisir development launch options")
struct RabbisirDevelopmentLaunchOptionsTests {
  @Test("Sidebar inspection drag is opt-in and never affects ordinary launches")
  func sidebarInspectionDragIsExplicit() {
    #expect(
      !RabbisirDevelopmentLaunchOptions.allowsSidebarInspectionDrag(
        arguments: ["Rabbisir"]
      )
    )
    #expect(
      RabbisirDevelopmentLaunchOptions.allowsSidebarInspectionDrag(
        arguments: ["Rabbisir", "--sidebar-inspection-drag"]
      )
    )
  }

  @Test("First-run preview is explicit and absent from ordinary DEV launches")
  func firstRunPreviewIsExplicit() {
    #expect(
      !RabbisirDevelopmentLaunchOptions.forcesFirstRunPreview(
        arguments: ["Rabbisir DEV"]
      )
    )
    #expect(
      RabbisirDevelopmentLaunchOptions.forcesFirstRunPreview(
        arguments: ["Rabbisir DEV", "--first-run-preview"]
      )
    )
  }

  @Test("DEV readiness accepts only one scoped temporary status file")
  func readinessFileIsScopedToTemporaryDirectory() {
    let temporaryDirectory = FileManager.default.temporaryDirectory
    let valid =
      temporaryDirectory
      .appendingPathComponent("rabbisir-dev-ready.fixture")
      .path
    #expect(
      RabbisirDevelopmentLaunchOptions.readinessFile(
        arguments: ["Rabbisir DEV", "--dev-readiness-file", valid],
        temporaryDirectory: temporaryDirectory
      )?.path == valid
    )
    let open =
      temporaryDirectory
      .appendingPathComponent("rabbisir-open-ready.fixture")
      .path
    #expect(
      RabbisirDevelopmentLaunchOptions.readinessFile(
        arguments: ["Rabbisir Open", "--open-readiness-file", open],
        temporaryDirectory: temporaryDirectory
      )?.path == open
    )
    #expect(
      RabbisirDevelopmentLaunchOptions.readinessFile(
        arguments: ["Rabbisir DEV", "--dev-readiness-file", "/outside/status"],
        temporaryDirectory: temporaryDirectory
      ) == nil
    )
    #expect(
      RabbisirDevelopmentLaunchOptions.readinessFile(
        arguments: [
          "Rabbisir Open", "--open-readiness-file", open,
          "--dev-readiness-file", valid,
        ],
        temporaryDirectory: temporaryDirectory
      ) == nil
    )
    #expect(
      RabbisirDevelopmentLaunchOptions.readinessFile(
        arguments: [
          "Rabbisir DEV", "--dev-readiness-file", valid,
          "--dev-readiness-file", valid,
        ],
        temporaryDirectory: temporaryDirectory
      ) == nil
    )
  }
}
