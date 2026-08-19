import Foundation
import Testing

@testable import RabbisirCore

@Suite("Rabbisir launch identity")
struct RabbisirLaunchIdentityTests {
  @Test("Production, DEV, and Open identities cannot share bundle or data identity")
  func identitiesAreIsolated() {
    #expect(RabbisirLaunchIdentity.production.displayName == "Rabbisir")
    #expect(RabbisirLaunchIdentity.development.displayName == "Rabbisir DEV")
    #expect(RabbisirOpenIdentity.displayName == "Rabbisir Open")

    let bundleIdentifiers = Set([
      RabbisirLaunchIdentity.production.bundleIdentifier,
      RabbisirLaunchIdentity.development.bundleIdentifier,
      RabbisirOpenIdentity.bundleIdentifier,
    ])
    let applicationSupportComponents = Set([
      RabbisirLaunchIdentity.production.applicationSupportComponent,
      RabbisirLaunchIdentity.development.applicationSupportComponent,
      RabbisirOpenIdentity.applicationSupportComponent,
    ])
    #expect(bundleIdentifiers.count == 3)
    #expect(applicationSupportComponents.count == 3)
  }

  @Test("Process display identity resolves Open without reclassifying official identities")
  func displayIdentityResolution() {
    #expect(RabbisirAppIdentity.resolve(processName: "Rabbisir") == "Rabbisir")
    #expect(RabbisirAppIdentity.resolve(processName: "Rabbisir DEV") == "Rabbisir DEV")
    #expect(RabbisirAppIdentity.resolve(processName: "Rabbisir Open") == "Rabbisir Open")
    #expect(RabbisirAppIdentity.resolve(processName: "test-runner") == "Rabbisir")
  }

  @Test("Open accepts an isolated home only below the temporary directory")
  func isolatedHomeIsTemporaryAndScoped() {
    let temporaryDirectory = URL(fileURLWithPath: "/tmp/rabbisir-test-tmp", isDirectory: true)
    let valid = "/tmp/rabbisir-test-tmp/open-home"
    #expect(
      RabbisirOpenIdentity.isolatedHome(
        environment: [RabbisirOpenIdentity.isolatedHomeEnvironmentKey: valid],
        temporaryDirectory: temporaryDirectory
      )?.path == valid
    )
    #expect(
      RabbisirOpenIdentity.isolatedHome(
        environment: [RabbisirOpenIdentity.isolatedHomeEnvironmentKey: "/outside/open-home"],
        temporaryDirectory: temporaryDirectory
      ) == nil
    )
  }
}
