import Foundation
import Testing

@testable import RabbisirCore

@Suite("Rabbisir-owned upstream runtime")
struct ManagedUpstreamRuntimeTests {
  @Test("Full provenance work leaves the main actor responsive")
  @MainActor
  func provenanceValidationDoesNotBlockMainActor() async throws {
    enum ProbeError: Error { case ranOnMainThread }
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeManifest(to: root)
    let session = RuntimeProvenanceValidationSession(
      check: RuntimeProvenanceCheck { _, _ in
        if Thread.isMainThread { throw ProbeError.ranOnMainThread }
        Thread.sleep(forTimeInterval: 0.2)
      }
    )
    let validation = Task {
      try await session.validate(
        resourceRoot: root,
        manifest: manifest
      )
    }
    await Task.yield()
    try await validation.value
  }

  @Test("A successful receipt is hashed once per validation session")
  func successfulValidationIsCachedWithinOneProcessSession() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let counter = root.appendingPathComponent("counter")
    try writeManifest(to: root)
    let session = RuntimeProvenanceValidationSession(
      check: RuntimeProvenanceCheck { _, _ in
        let old = (try? Data(contentsOf: counter)) ?? Data()
        try (old + Data([1])).write(to: counter, options: .atomic)
      }
    )

    try await session.validate(resourceRoot: root, manifest: manifest)
    try await session.validate(resourceRoot: root, manifest: manifest)
    #expect(try Data(contentsOf: counter).count == 1)
  }

  @Test("Cancelling startup cancels provenance work and restores an idle state")
  @MainActor
  func cancellingValidationStopsStartup() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let session = RuntimeProvenanceValidationSession(
      check: RuntimeProvenanceCheck { _, _ in
        while true {
          try Task.checkCancellation()
          Thread.sleep(forTimeInterval: 0.01)
        }
      }
    )
    let runtime = ManagedUpstreamRuntime(
      resolver: UpstreamRuntimeResolver(resourceRoot: root, environment: [:]),
      readinessTimeout: .seconds(1),
      provenanceValidation: session
    )
    let startup = Task { try await runtime.start() }
    while runtime.state != .validating { await Task.yield() }
    runtime.stop()
    await #expect(throws: CancellationError.self) {
      try await startup.value
    }
    #expect(runtime.state == .idle)
  }

  @Test("A failed provenance check is fail-closed and is never cached")
  @MainActor
  func failedValidationIsFailClosed() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let session = RuntimeProvenanceValidationSession(
      check: RuntimeProvenanceCheck { _, _ in
        throw RuntimeProvenanceVerificationError.inventoryMismatch
      }
    )
    let runtime = ManagedUpstreamRuntime(
      resolver: UpstreamRuntimeResolver(resourceRoot: root, environment: [:]),
      readinessTimeout: .seconds(1),
      provenanceValidation: session
    )

    await #expect(throws: UpstreamRuntimeResolutionError.provenanceInvalid) {
      try await runtime.start()
    }
    guard case .failed(let message) = runtime.state else {
      Issue.record("A failed provenance check must leave a visible failed state")
      return
    }
    #expect(!message.contains(root.path))
  }

  @Test("The packaged runtime passes full consumer-side provenance verification")
  func packagedRuntimePassesConsumerVerification() async throws {
    let plan = try UpstreamRuntimeResolver(identity: .development).resolve()
    try await RuntimeProvenanceValidationSession().validate(
      resourceRoot: UpstreamRuntimeResolver(identity: .development).resourceRoot,
      manifest: plan.manifest
    )
    #expect(plan.carrier == .bundled)
    #expect(plan.manifest.runtimeInventorySHA256 == manifest.runtimeInventorySHA256)
  }

  @Test("Open runtime data uses the explicit Open application-support component")
  func openRuntimeDataRootIsIndependent() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)

    let plan = try UpstreamRuntimeResolver(
      resourceRoot: root,
      environment: [:],
      identity: .development,
      applicationSupportComponent: RabbisirOpenIdentity.applicationSupportComponent
    ).resolve()
    #expect(plan.workingDirectory.lastPathComponent == "Runtime")
    #expect(plan.workingDirectory.deletingLastPathComponent().lastPathComponent == "Rabbisir Open")
  }

  @Test("Only private ephemeral loopback readiness lines are accepted")
  func readinessLineValidation() {
    #expect(UpstreamRuntimeReadyLine.parse("dsh web: http://127.0.0.1:49172")?.port == 49172)
    #expect(UpstreamRuntimeReadyLine.parse("dsh web: http://127.0.0.1:3080") == nil)
    #expect(UpstreamRuntimeReadyLine.parse("dsh web: http://127.0.0.1:3083") == nil)
    #expect(UpstreamRuntimeReadyLine.parse("dsh web: http://0.0.0.0:49172") == nil)
    #expect(UpstreamRuntimeReadyLine.parse("dsh web: https://127.0.0.1:49172") == nil)
  }

  @Test("Launch arguments bind loopback and never name a legacy product port")
  func launchArguments() {
    let plan = UpstreamRuntimeLaunchPlan(
      carrier: .bundled,
      executableURL: URL(fileURLWithPath: "/runtime"),
      argumentsPrefix: [],
      workingDirectory: URL(fileURLWithPath: "/work"),
      manifest: manifest
    )
    #expect(plan.arguments(port: nil) == ["web", "--host", "127.0.0.1", "--port", "0"])
    #expect(plan.arguments(port: 49172) == ["web", "--host", "127.0.0.1", "--port", "49172"])
    #expect(!plan.arguments(port: nil).contains("3080"))
    #expect(!plan.arguments(port: nil).contains("3083"))
  }

  @Test("Runtime child inherits only the minimal non-secret environment")
  func childEnvironmentIsAllowlisted() {
    let child = ManagedRuntimeChildEnvironment.make(from: [
      "HOME": "/home/example",
      "TMPDIR": "/tmp/example",
      "LANG": "en_US.UTF-8",
      "DEEPSEEK_API_KEY": "must-not-leak",
      "HTTP_PROXY": "must-not-leak",
      "UNRELATED": "must-not-leak",
    ])

    #expect(child["HOME"] == "/home/example")
    #expect(child["TMPDIR"] == "/tmp/example")
    #expect(child["LANG"] == "en_US.UTF-8")
    #expect(child["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
    #expect(child["DEEPSEEK_API_KEY"] == nil)
    #expect(child["HTTP_PROXY"] == nil)
    #expect(child["UNRELATED"] == nil)

    let isolatedHome = URL(fileURLWithPath: "/tmp/rabbisir-open/home", isDirectory: true)
    let isolated = ManagedRuntimeChildEnvironment.make(
      from: ["HOME": "/home/example", "TMPDIR": "/tmp/example"],
      isolatedHomeDirectory: isolatedHome
    )
    #expect(isolated["HOME"] == "/tmp/rabbisir-open/home")
    #expect(isolated["TMPDIR"] == "/tmp/rabbisir-open/home/tmp")
  }

  @Test("The bundled carrier wins over every development fallback")
  func bundledCarrierWins() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let executable = root.appendingPathComponent(manifest.executable)

    let plan = try UpstreamRuntimeResolver(
      resourceRoot: root,
      environment: [:]
    ).resolve()
    try await RuntimeProvenanceValidationSession().validate(
      resourceRoot: root,
      manifest: plan.manifest
    )
    #expect(plan.carrier == .bundled)
    #expect(plan.executableURL == executable)
    #expect(plan.manifest.upstreamVersion == "0.1.0-rc.5")
  }

  @Test("A bundled runtime whose manifest names another upstream commit is rejected")
  func mismatchedUpstreamCommitIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let mismatched = UpstreamRuntimeManifest(
      schemaVersion: 3,
      upstreamVersion: manifest.upstreamVersion,
      rabbisirVersion: manifest.rabbisirVersion,
      upstreamCommit: "0000000000000000000000000000000000000000",
      upstreamTree: manifest.upstreamTree,
      provenanceContractSHA256: manifest.provenanceContractSHA256,
      runtimeInventorySHA256: manifest.runtimeInventorySHA256,
      executable: manifest.executable
    )
    try JSONEncoder().encode(mismatched).write(to: root.appendingPathComponent("manifest.json"))
    let executable = root.appendingPathComponent(mismatched.executable)
    try FileManager.default.createDirectory(
      at: executable.deletingLastPathComponent(),
      withIntermediateDirectories: true
    )
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)

    #expect(throws: UpstreamRuntimeResolutionError.self) {
      try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
    }
  }

  @Test("Bundled consumption rejects a payload changed after its provenance receipt")
  func tamperedBundledPayloadIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)

    _ = try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()

    try Data("tampered\n".utf8).write(
      to: root.appendingPathComponent("node/lib/runtime.js"),
      options: .atomic
    )
    #expect(throws: RuntimeProvenanceVerificationError.self) {
      try RuntimeProvenanceVerifier.verify(
        resourceRoot: root,
        manifest: try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
          .manifest
      )
    }
  }

  @Test("Bundled consumption rejects a launcher changed after its provenance receipt")
  func tamperedBundledLauncherIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)

    try Data("#!/bin/sh\nexit 7\n".utf8).write(
      to: root.appendingPathComponent(manifest.executable),
      options: .atomic
    )
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: root.appendingPathComponent(manifest.executable).path
    )

    #expect(throws: RuntimeProvenanceVerificationError.self) {
      try RuntimeProvenanceVerifier.verify(
        resourceRoot: root,
        manifest: try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
          .manifest
      )
    }
  }

  @Test("Bundled consumption rejects a Node spawn helper changed after its provenance receipt")
  func tamperedSpawnHelperIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)

    try Data("tampered helper\n".utf8).write(
      to: root.appendingPathComponent("bin/node-spawn-helper"),
      options: .atomic
    )

    #expect(throws: RuntimeProvenanceVerificationError.self) {
      try RuntimeProvenanceVerifier.verify(
        resourceRoot: root,
        manifest: try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
          .manifest
      )
    }
  }

  @Test(
    "A signed official package uses the system code signature after signing changes Mach-O bytes"
  )
  func signedOfficialPackageUsesSystemIntegrity() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let application = root.appendingPathComponent("Rabbisir.app", isDirectory: true)
    let runtime = application.appendingPathComponent(
      "Contents/Resources/Rabbisir_RabbisirCore.bundle/VendorRuntime",
      isDirectory: true
    )
    try writeReceiptedRuntime(to: runtime)
    try writeProductFlavor("official-production", to: application)
    let plan = try UpstreamRuntimeResolver(resourceRoot: runtime, environment: [:]).resolve()
    let signedNode = runtime.appendingPathComponent("bin/node")
    try Data("developer-id-signed-node\n".utf8).write(to: signedNode)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: signedNode.path
    )
    let marker = root.appendingPathComponent("signature-checked")

    try RuntimeProvenanceCheck.live(
      codeSignatureCheck: RuntimeCodeSignatureCheck { checkedApplication in
        guard checkedApplication == application else {
          throw RuntimeProvenanceVerificationError.codeSignatureInvalid
        }
        try Data().write(to: marker)
      }
    ).perform(runtime, plan.manifest)

    #expect(FileManager.default.fileExists(atPath: marker.path))
  }

  @Test("A failed official App signature remains fail-closed")
  func invalidOfficialSignatureIsRejected() throws {
    enum ProbeError: Error { case invalidSignature }
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let application = root.appendingPathComponent("Rabbisir.app", isDirectory: true)
    let runtime = application.appendingPathComponent(
      "Contents/Resources/Rabbisir_RabbisirCore.bundle/VendorRuntime",
      isDirectory: true
    )
    try writeReceiptedRuntime(to: runtime)
    try writeProductFlavor("official-production", to: application)
    let plan = try UpstreamRuntimeResolver(resourceRoot: runtime, environment: [:]).resolve()
    let signedNode = runtime.appendingPathComponent("bin/node")
    try Data("developer-id-signed-node\n".utf8).write(to: signedNode)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: signedNode.path
    )

    #expect(throws: RuntimeProvenanceVerificationError.codeSignatureInvalid) {
      try RuntimeProvenanceCheck.live(
        codeSignatureCheck: RuntimeCodeSignatureCheck { _ in
          throw ProbeError.invalidSignature
        }
      ).perform(runtime, plan.manifest)
    }
  }

  @Test("Signing fallback never applies to DEV or source runtime carriers")
  func developmentCarrierStillRequiresSourceBytes() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let application = root.appendingPathComponent("Rabbisir DEV.app", isDirectory: true)
    let runtime = application.appendingPathComponent(
      "Contents/Resources/Rabbisir_RabbisirCore.bundle/VendorRuntime",
      isDirectory: true
    )
    try writeReceiptedRuntime(to: runtime)
    try writeProductFlavor("official-development", to: application)
    let plan = try UpstreamRuntimeResolver(resourceRoot: runtime, environment: [:]).resolve()
    try Data("changed DEV node\n".utf8).write(to: runtime.appendingPathComponent("bin/node"))
    let marker = root.appendingPathComponent("signature-checked")

    #expect(throws: RuntimeProvenanceVerificationError.self) {
      try RuntimeProvenanceCheck.live(
        codeSignatureCheck: RuntimeCodeSignatureCheck { _ in
          try Data().write(to: marker)
        }
      ).perform(runtime, plan.manifest)
    }
    #expect(!FileManager.default.fileExists(atPath: marker.path))
  }

  @Test("A valid App signature cannot hide changed source metadata")
  func signedPackageStillRejectsMetadataTampering() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let application = root.appendingPathComponent("Rabbisir.app", isDirectory: true)
    let runtime = application.appendingPathComponent(
      "Contents/Resources/Rabbisir_RabbisirCore.bundle/VendorRuntime",
      isDirectory: true
    )
    try writeReceiptedRuntime(to: runtime)
    try writeProductFlavor("official-production", to: application)
    let plan = try UpstreamRuntimeResolver(resourceRoot: runtime, environment: [:]).resolve()
    try Data("changed projection\n".utf8).write(
      to: runtime.appendingPathComponent("node/lib/native-projection.js")
    )

    #expect(throws: RuntimeProvenanceVerificationError.projectionMismatch) {
      try RuntimeProvenanceCheck.live(
        codeSignatureCheck: RuntimeCodeSignatureCheck { _ in }
      ).perform(runtime, plan.manifest)
    }
  }

  @Test("Manifest executable traversal is rejected before a launch plan is produced")
  func manifestExecutableTraversalIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let receiptedManifest = try JSONDecoder().decode(
      UpstreamRuntimeManifest.self,
      from: Data(contentsOf: root.appendingPathComponent("manifest.json"))
    )
    let invalid = UpstreamRuntimeManifest(
      schemaVersion: receiptedManifest.schemaVersion,
      upstreamVersion: receiptedManifest.upstreamVersion,
      rabbisirVersion: receiptedManifest.rabbisirVersion,
      upstreamCommit: receiptedManifest.upstreamCommit,
      upstreamTree: receiptedManifest.upstreamTree,
      provenanceContractSHA256: receiptedManifest.provenanceContractSHA256,
      runtimeInventorySHA256: receiptedManifest.runtimeInventorySHA256,
      executable: "../../../../../../usr/bin/true"
    )
    try JSONEncoder().encode(invalid).write(to: root.appendingPathComponent("manifest.json"))

    #expect(throws: UpstreamRuntimeResolutionError.manifestInvalid) {
      try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
    }
  }

  @Test("Manifest executable symlinks cannot escape the receipted runtime root")
  func manifestExecutableSymlinkEscapeIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let executable = root.appendingPathComponent(manifest.executable)
    try FileManager.default.removeItem(at: executable)
    try FileManager.default.createSymbolicLink(
      at: executable,
      withDestinationURL: URL(fileURLWithPath: "/usr/bin/true")
    )

    #expect(throws: UpstreamRuntimeResolutionError.self) {
      try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
    }
  }

  @Test("Bundled consumption rejects a changed Rabbisir manifest version")
  func tamperedRabbisirVersionIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let plan = try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
    let manifestURL = root.appendingPathComponent("manifest.json")
    var object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
    )
    object["rabbisirVersion"] = "tampered-review-value"
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(
      to: manifestURL)

    #expect(throws: RuntimeProvenanceVerificationError.self) {
      try RuntimeProvenanceVerifier.verify(resourceRoot: root, manifest: plan.manifest)
    }
  }

  @Test("A manifest with an unknown key is rejected before launch planning")
  func unknownManifestKeyIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let manifestURL = root.appendingPathComponent("manifest.json")
    var object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
    )
    object["unreviewedField"] = true
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(
      to: manifestURL)

    #expect(throws: UpstreamRuntimeResolutionError.manifestInvalid) {
      try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
    }
  }

  @Test(
    "Every canonical manifest field is enforced by resolution or provenance",
    arguments: UpstreamRuntimeManifest.fieldNames.sorted()
  )
  func everyManifestFieldIsEnforced(field: String) throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let manifestURL = root.appendingPathComponent("manifest.json")
    var object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
    )
    object[field] = field == "schemaVersion" ? 999 : "tampered-review-value"
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(
      to: manifestURL)

    do {
      let plan = try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
      #expect(throws: RuntimeProvenanceVerificationError.self) {
        try RuntimeProvenanceVerifier.verify(resourceRoot: root, manifest: plan.manifest)
      }
    } catch is UpstreamRuntimeResolutionError {
      // Structural fields fail before a launch plan; provenance fields fail in the full verifier.
    }
  }

  @Test("A successful validation cache cannot hide a later manifest change")
  func cachedValidationRechecksChangedManifest() async throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let plan = try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()
    let session = RuntimeProvenanceValidationSession()
    try await session.validate(resourceRoot: root, manifest: plan.manifest)

    let manifestURL = root.appendingPathComponent("manifest.json")
    var object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: manifestURL)) as? [String: Any]
    )
    object["rabbisirVersion"] = "tampered-review-value"
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(
      to: manifestURL)

    await #expect(throws: RuntimeProvenanceVerificationError.self) {
      try await session.validate(resourceRoot: root, manifest: plan.manifest)
    }
  }

  @Test("A schema 2 receipt is rejected after the manifest integrity upgrade")
  func legacyReceiptIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    let receiptURL = root.appendingPathComponent(".rabbisir-runtime-provenance.json")
    var object = try #require(
      JSONSerialization.jsonObject(with: Data(contentsOf: receiptURL)) as? [String: Any]
    )
    object["schemaVersion"] = 2
    try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]).write(
      to: receiptURL)
    let plan = try UpstreamRuntimeResolver(resourceRoot: root, environment: [:]).resolve()

    #expect(throws: RuntimeProvenanceVerificationError.receiptMismatch) {
      try RuntimeProvenanceVerifier.verify(resourceRoot: root, manifest: plan.manifest)
    }
  }

  @Test("Bundled consumption rejects contract, receipt, inventory, and tree disagreement")
  func provenanceMetadataDisagreementIsRejected() throws {
    let root = try temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    try writeReceiptedRuntime(to: root)
    var invalid = manifest
    invalid = UpstreamRuntimeManifest(
      schemaVersion: invalid.schemaVersion,
      upstreamVersion: invalid.upstreamVersion,
      rabbisirVersion: invalid.rabbisirVersion,
      upstreamCommit: invalid.upstreamCommit,
      upstreamTree: "0000000000000000000000000000000000000000",
      provenanceContractSHA256: invalid.provenanceContractSHA256,
      runtimeInventorySHA256: invalid.runtimeInventorySHA256,
      executable: invalid.executable
    )
    try JSONEncoder().encode(invalid).write(to: root.appendingPathComponent("manifest.json"))

    #expect(throws: RuntimeProvenanceVerificationError.self) {
      try RuntimeProvenanceVerifier.verify(
        resourceRoot: root,
        manifest: invalid
      )
    }
  }

  @Test("A release-safe diagnostic never exposes an internal URL or port")
  func diagnosticPrivacy() {
    let descriptions = [
      ManagedUpstreamRuntimeError.failedToLaunch.localizedDescription,
      ManagedUpstreamRuntimeError.exitedBeforeReady.localizedDescription,
      ManagedUpstreamRuntimeError.readinessTimedOut.localizedDescription,
      ManagedUpstreamRuntimeError.healthCheckFailed.localizedDescription,
      UpstreamRuntimeResolutionError.componentMissing.localizedDescription,
    ]
    for description in descriptions {
      #expect(!description.contains("127.0.0.1"))
      #expect(!description.contains("localhost"))
      #expect(!description.contains("3080"))
      #expect(!description.contains("3083"))
    }
  }

  private var manifest: UpstreamRuntimeManifest {
    UpstreamRuntimeManifest(
      schemaVersion: 3,
      upstreamVersion: "0.1.0-rc.5",
      rabbisirVersion: "0.1.0",
      upstreamCommit: "47f943859bef60e4160492346772ded9b24f765a",
      upstreamTree: "f904efab9ef435201d6ba4da88a34d6366568272",
      provenanceContractSHA256: "78e79b284b60dd67ab3e5363d264259bdec3a7e4d5de72073f6dfbde713685de",
      runtimeInventorySHA256: "1d13cdad0d1751f9a861caae704fd378e552c512fa32ef8a74a7295e23afa1ed",
      executable: "bin/rabbisir-runtime"
    )
  }

  private func temporaryDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("rabbisir-runtime-tests-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
  }

  private func writeManifest(to root: URL) throws {
    let data = try JSONEncoder().encode(manifest)
    try data.write(to: root.appendingPathComponent("manifest.json"))
  }

  private func writeProductFlavor(_ flavor: String, to application: URL) throws {
    let contents = application.appendingPathComponent("Contents", isDirectory: true)
    try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
    let data = try PropertyListSerialization.data(
      fromPropertyList: [
        "CFBundlePackageType": "APPL",
        "RabbisirProductFlavor": flavor,
      ],
      format: .xml,
      options: 0
    )
    try data.write(to: contents.appendingPathComponent("Info.plist"))
  }

  private func writeReceiptedRuntime(to root: URL) throws {
    let nodeRoot = root.appendingPathComponent("node", isDirectory: true)
    let runtimeFile = nodeRoot.appendingPathComponent("lib/runtime.js")
    let projectionFile = nodeRoot.appendingPathComponent("lib/native-projection.js")
    let nodeBinary = root.appendingPathComponent("bin/node")
    let spawnHelper = root.appendingPathComponent("bin/node-spawn-helper")
    let executable = root.appendingPathComponent(manifest.executable)
    try FileManager.default.createDirectory(
      at: runtimeFile.deletingLastPathComponent(), withIntermediateDirectories: true)
    try FileManager.default.createDirectory(
      at: nodeBinary.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("runtime\n".utf8).write(to: runtimeFile)
    try Data("projection\n".utf8).write(to: projectionFile)
    try Data("node\n".utf8).write(to: nodeBinary)
    try Data("spawn helper\n".utf8).write(to: spawnHelper)
    try Data("#!/bin/sh\nexit 0\n".utf8).write(to: executable)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: executable.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: nodeBinary.path)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755], ofItemAtPath: spawnHelper.path)

    let inventory = try RuntimePayloadInventory.readRuntimeCarrier(from: root)
    let contractObject: [String: Any] = [
      "schemaVersion": 3,
      "manifest": [
        "schemaVersion": 3,
        "rabbisirVersion": manifest.rabbisirVersion,
      ],
      "upstream": [
        "commit": RabbisirVersion.upstreamCompatibleCommit,
        "tree": manifest.upstreamTree,
        "version": RabbisirVersion.upstreamCompatibleVersion,
      ],
      "toolchain": [
        "nodeBinarySHA256": RuntimeProvenanceVerifier.sha256(try Data(contentsOf: nodeBinary))
      ],
      "launch": [
        "executable": manifest.executable,
        "node": "bin/node",
        "nodeSpawnHelper": "bin/node-spawn-helper",
      ],
      "output": [
        "algorithm": inventory.algorithm,
        "digest": inventory.digest,
        "fileCount": inventory.fileCount,
        "symlinkCount": inventory.symlinkCount,
        "nativeProjection": [
          "path": "node/lib/native-projection.js",
          "sha256": RuntimeProvenanceVerifier.sha256(try Data(contentsOf: projectionFile)),
        ],
      ],
    ]
    let contractData = try JSONSerialization.data(
      withJSONObject: contractObject, options: [.sortedKeys])
    try contractData.write(to: root.appendingPathComponent("provenance-contract.json"))
    let receiptObject: [String: Any] = [
      "schemaVersion": 3,
      "contractSHA256": RuntimeProvenanceVerifier.sha256(contractData),
      "upstreamCommit": RabbisirVersion.upstreamCompatibleCommit,
      "inventory": [
        "algorithm": inventory.algorithm,
        "digest": inventory.digest,
        "fileCount": inventory.fileCount,
        "symlinkCount": inventory.symlinkCount,
      ],
    ]
    try JSONSerialization.data(withJSONObject: receiptObject, options: [.sortedKeys]).write(
      to: root.appendingPathComponent(".rabbisir-runtime-provenance.json"))
    let resolvedManifest = UpstreamRuntimeManifest(
      schemaVersion: 3,
      upstreamVersion: RabbisirVersion.upstreamCompatibleVersion,
      rabbisirVersion: manifest.rabbisirVersion,
      upstreamCommit: RabbisirVersion.upstreamCompatibleCommit,
      upstreamTree: manifest.upstreamTree,
      provenanceContractSHA256: RuntimeProvenanceVerifier.sha256(contractData),
      runtimeInventorySHA256: inventory.digest,
      executable: manifest.executable
    )
    try JSONEncoder().encode(resolvedManifest).write(
      to: root.appendingPathComponent("manifest.json"))
    try RuntimeProvenanceVerifier.verify(resourceRoot: root, manifest: resolvedManifest)
  }
}
