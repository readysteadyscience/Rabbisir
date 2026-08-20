import CryptoKit
import Foundation
import Security

struct RuntimePayloadInventory: Codable, Equatable, Sendable {
  static let supportedAlgorithm = "sha256(canonical-path-mode-content-v1)"

  let algorithm: String
  let digest: String
  let fileCount: Int
  let symlinkCount: Int

  static func read(from root: URL, includedTopLevelNames: Set<String>? = nil) throws -> Self {
    let fileManager = FileManager.default
    let canonicalRoot = root.resolvingSymlinksInPath().standardizedFileURL
    var records: [String] = []
    var fileCount = 0
    var symlinkCount = 0

    func visit(_ directory: URL, prefix: String = "") throws {
      try Task.checkCancellation()
      let children = try fileManager.contentsOfDirectory(
        at: directory,
        includingPropertiesForKeys: [.isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey],
        options: []
      ).sorted { $0.lastPathComponent.utf8.lexicographicallyPrecedes($1.lastPathComponent.utf8) }
      for child in children {
        try Task.checkCancellation()
        if prefix.isEmpty,
          let includedTopLevelNames,
          !includedTopLevelNames.contains(child.lastPathComponent)
        {
          continue
        }
        let relativePath = prefix + child.lastPathComponent
        guard !relativePath.contains("\n"), !relativePath.contains("\r") else {
          throw RuntimeProvenanceVerificationError.invalidPayload
        }
        if relativePath == ".rabbisir-runtime-provenance.json"
          || relativePath.hasSuffix("/.rabbisir-runtime-provenance.json")
        {
          continue
        }
        let values = try child.resourceValues(forKeys: [
          .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        ])
        if values.isSymbolicLink == true {
          let destination = child.resolvingSymlinksInPath().standardizedFileURL
          guard
            destination.path == canonicalRoot.path
              || destination.path.hasPrefix(canonicalRoot.path + "/")
          else { throw RuntimeProvenanceVerificationError.invalidPayload }
          let target = try fileManager.destinationOfSymbolicLink(atPath: child.path)
          guard !target.contains("\n"), !target.contains("\r") else {
            throw RuntimeProvenanceVerificationError.invalidPayload
          }
          records.append("link \(target) \(relativePath)\n")
          symlinkCount += 1
        } else if values.isDirectory == true {
          try visit(child, prefix: relativePath + "/")
        } else if values.isRegularFile == true {
          let attributes = try fileManager.attributesOfItem(atPath: child.path)
          let permissions = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
          let mode = permissions & 0o111 == 0 ? "0644" : "0755"
          records.append(
            "file \(mode) \(try RuntimeProvenanceVerifier.sha256(file: child)) \(relativePath)\n"
          )
          fileCount += 1
        } else {
          throw RuntimeProvenanceVerificationError.invalidPayload
        }
      }
    }

    try visit(canonicalRoot)
    records.sort()
    return Self(
      algorithm: supportedAlgorithm,
      digest: RuntimeProvenanceVerifier.sha256(Data(records.joined().utf8)),
      fileCount: fileCount,
      symlinkCount: symlinkCount
    )
  }

  static func readRuntimeCarrier(from root: URL) throws -> Self {
    try read(from: root, includedTopLevelNames: ["bin", "node"])
  }
}

private struct RuntimeProvenanceContract: Decodable {
  struct Manifest: Decodable {
    let schemaVersion: Int
    let rabbisirVersion: String
  }

  struct Upstream: Decodable {
    let commit: String
    let tree: String
    let version: String
  }

  struct Toolchain: Decodable {
    let nodeBinarySHA256: String
  }

  struct Launch: Decodable {
    let executable: String
    let node: String
    let nodeSpawnHelper: String
  }

  struct Output: Decodable {
    struct NativeProjection: Decodable {
      let path: String
      let sha256: String
    }

    let algorithm: String
    let digest: String
    let fileCount: Int
    let symlinkCount: Int
    let nativeProjection: NativeProjection
  }

  let schemaVersion: Int
  let manifest: Manifest
  let upstream: Upstream
  let toolchain: Toolchain
  let launch: Launch
  let output: Output
}

private struct RuntimeProvenanceReceipt: Decodable {
  let schemaVersion: Int
  let contractSHA256: String
  let upstreamCommit: String
  let inventory: RuntimePayloadInventory
}

enum RuntimeProvenanceVerificationError: Error, Equatable {
  case invalidPayload
  case contractMismatch
  case receiptMismatch
  case receiptInventoryMismatch
  case inventoryMismatch
  case nodeMismatch
  case projectionMismatch
  case codeSignatureInvalid
}

struct RuntimeCodeSignatureCheck: Sendable {
  let perform: @Sendable (URL) throws -> Void

  static let live = Self { applicationURL in
    var staticCode: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(
        applicationURL as CFURL,
        SecCSFlags(),
        &staticCode
      ) == errSecSuccess,
      let staticCode
    else { throw RuntimeProvenanceVerificationError.codeSignatureInvalid }
    let flags = SecCSFlags(
      rawValue: UInt32(
        kSecCSCheckAllArchitectures | kSecCSCheckNestedCode | kSecCSStrictValidate
      )
    )
    guard SecStaticCodeCheckValidity(staticCode, flags, nil) == errSecSuccess else {
      throw RuntimeProvenanceVerificationError.codeSignatureInvalid
    }
  }
}

enum RuntimePackagedApplication {
  static func officialProductionApp(containing resourceRoot: URL) -> URL? {
    let resourceBundle = resourceRoot.deletingLastPathComponent()
    let resources = resourceBundle.deletingLastPathComponent()
    let contents = resources.deletingLastPathComponent()
    let application = contents.deletingLastPathComponent()
    guard resourceBundle.pathExtension == "bundle",
      resources.lastPathComponent == "Resources",
      contents.lastPathComponent == "Contents",
      application.pathExtension == "app",
      let data = try? Data(contentsOf: contents.appendingPathComponent("Info.plist")),
      let info = try? PropertyListSerialization.propertyList(
        from: data,
        options: [],
        format: nil
      ) as? [String: Any],
      info["RabbisirProductFlavor"] as? String == "official-production"
    else { return nil }
    return application
  }
}

enum RuntimeCanonicalPath {
  static func resolve(_ value: String, under resourceRoot: URL) throws -> URL {
    guard !value.isEmpty,
      !value.hasPrefix("/"),
      !value.contains("\\"),
      !value.contains("\0"),
      !value.contains("\n"),
      !value.contains("\r")
    else { throw RuntimeProvenanceVerificationError.invalidPayload }
    let components = value.split(separator: "/", omittingEmptySubsequences: false)
    guard components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
      throw RuntimeProvenanceVerificationError.invalidPayload
    }

    let canonicalRoot = resourceRoot.resolvingSymlinksInPath().standardizedFileURL
    let candidate = canonicalRoot.appendingPathComponent(value).standardizedFileURL
    guard isInside(candidate, root: canonicalRoot),
      FileManager.default.fileExists(atPath: candidate.path)
    else { throw RuntimeProvenanceVerificationError.invalidPayload }
    let destination = candidate.resolvingSymlinksInPath().standardizedFileURL
    guard isInside(destination, root: canonicalRoot) else {
      throw RuntimeProvenanceVerificationError.invalidPayload
    }
    return candidate
  }

  private static func isInside(_ candidate: URL, root: URL) -> Bool {
    candidate.path == root.path || candidate.path.hasPrefix(root.path + "/")
  }
}

enum RuntimeProvenanceVerifier {
  private struct VerifiedMetadata {
    let contract: RuntimeProvenanceContract
    let receipt: RuntimeProvenanceReceipt
    let expectedInventory: RuntimePayloadInventory
    let node: URL
  }

  static func verify(resourceRoot: URL, manifest: UpstreamRuntimeManifest) throws {
    do {
      let metadata = try verifiedMetadata(resourceRoot: resourceRoot, manifest: manifest)
      let inventory = try RuntimePayloadInventory.readRuntimeCarrier(from: resourceRoot)
      guard metadata.receipt.inventory == inventory else {
        throw RuntimeProvenanceVerificationError.receiptInventoryMismatch
      }
      guard
        inventory == metadata.expectedInventory,
        inventory.algorithm == RuntimePayloadInventory.supportedAlgorithm
      else { throw RuntimeProvenanceVerificationError.inventoryMismatch }
      guard
        try sha256(file: metadata.node)
          == metadata.contract.toolchain.nodeBinarySHA256
      else { throw RuntimeProvenanceVerificationError.nodeMismatch }
    } catch let error as RuntimeProvenanceVerificationError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw RuntimeProvenanceVerificationError.invalidPayload
    }
  }

  static func verifySignedPackage(
    resourceRoot: URL,
    manifest: UpstreamRuntimeManifest,
    applicationURL: URL,
    codeSignatureCheck: RuntimeCodeSignatureCheck = .live
  ) throws {
    do {
      _ = try verifiedMetadata(resourceRoot: resourceRoot, manifest: manifest)
    } catch let error as RuntimeProvenanceVerificationError {
      throw error
    } catch is CancellationError {
      throw CancellationError()
    } catch {
      throw RuntimeProvenanceVerificationError.invalidPayload
    }
    do {
      try codeSignatureCheck.perform(applicationURL)
    } catch {
      throw RuntimeProvenanceVerificationError.codeSignatureInvalid
    }
  }

  private static func verifiedMetadata(
    resourceRoot: URL,
    manifest: UpstreamRuntimeManifest
  ) throws -> VerifiedMetadata {
    let contractData = try Data(
      contentsOf: resourceRoot.appendingPathComponent("provenance-contract.json"))
    let contract = try JSONDecoder().decode(RuntimeProvenanceContract.self, from: contractData)
    let storedManifestData = try Data(
      contentsOf: resourceRoot.appendingPathComponent("manifest.json"))
    let storedManifest = try UpstreamRuntimeManifest.decodeStrictly(from: storedManifestData)
    let receiptData = try Data(
      contentsOf: resourceRoot.appendingPathComponent(
        ".rabbisir-runtime-provenance.json"))
    let receipt = try JSONDecoder().decode(RuntimeProvenanceReceipt.self, from: receiptData)
    let expectedInventory = RuntimePayloadInventory(
      algorithm: contract.output.algorithm,
      digest: contract.output.digest,
      fileCount: contract.output.fileCount,
      symlinkCount: contract.output.symlinkCount
    )
    let contractDigest = sha256(contractData)
    guard contract.schemaVersion == 3,
      storedManifest == manifest,
      manifest.schemaVersion == contract.manifest.schemaVersion,
      manifest.upstreamVersion == contract.upstream.version,
      manifest.rabbisirVersion == contract.manifest.rabbisirVersion,
      manifest.upstreamCommit == contract.upstream.commit,
      manifest.upstreamTree == contract.upstream.tree,
      manifest.provenanceContractSHA256 == contractDigest,
      manifest.runtimeInventorySHA256 == contract.output.digest,
      manifest.executable == contract.launch.executable
    else { throw RuntimeProvenanceVerificationError.contractMismatch }
    guard receipt.schemaVersion == 3,
      receipt.contractSHA256 == contractDigest,
      receipt.upstreamCommit == contract.upstream.commit
    else { throw RuntimeProvenanceVerificationError.receiptMismatch }
    guard receipt.inventory == expectedInventory,
      expectedInventory.algorithm == RuntimePayloadInventory.supportedAlgorithm
    else { throw RuntimeProvenanceVerificationError.receiptInventoryMismatch }
    let launcher = try RuntimeCanonicalPath.resolve(
      contract.launch.executable, under: resourceRoot)
    let node = try RuntimeCanonicalPath.resolve(contract.launch.node, under: resourceRoot)
    let spawnHelper = try RuntimeCanonicalPath.resolve(
      contract.launch.nodeSpawnHelper,
      under: resourceRoot
    )
    guard FileManager.default.isExecutableFile(atPath: launcher.path),
      FileManager.default.isExecutableFile(atPath: node.path),
      FileManager.default.isExecutableFile(atPath: spawnHelper.path)
    else { throw RuntimeProvenanceVerificationError.invalidPayload }
    guard
      try sha256(
        file: try RuntimeCanonicalPath.resolve(
          contract.output.nativeProjection.path,
          under: resourceRoot
        )) == contract.output.nativeProjection.sha256
    else { throw RuntimeProvenanceVerificationError.projectionMismatch }
    return VerifiedMetadata(
      contract: contract,
      receipt: receipt,
      expectedInventory: expectedInventory,
      node: node
    )
  }

  static func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  static func sha256(file: URL) throws -> String {
    sha256(try Data(contentsOf: file, options: .mappedIfSafe))
  }
}

struct RuntimeProvenanceCheck: Sendable {
  let perform: @Sendable (URL, UpstreamRuntimeManifest) throws -> Void

  static let live = live()

  static func live(
    codeSignatureCheck: RuntimeCodeSignatureCheck = .live
  ) -> Self {
    Self { resourceRoot, manifest in
      if let applicationURL = RuntimePackagedApplication.officialProductionApp(
        containing: resourceRoot
      ) {
        try RuntimeProvenanceVerifier.verifySignedPackage(
          resourceRoot: resourceRoot,
          manifest: manifest,
          applicationURL: applicationURL,
          codeSignatureCheck: codeSignatureCheck
        )
      } else {
        try RuntimeProvenanceVerifier.verify(resourceRoot: resourceRoot, manifest: manifest)
      }
    }
  }
}

actor RuntimeProvenanceValidationSession {
  private struct Key: Hashable {
    let resourceRoot: String
    let manifestSHA256: String
    let contractSHA256: String
    let inventorySHA256: String
  }

  private let check: RuntimeProvenanceCheck
  private var verifiedKeys: Set<Key> = []

  init(check: RuntimeProvenanceCheck = .live) {
    self.check = check
  }

  func validate(resourceRoot: URL, manifest: UpstreamRuntimeManifest) async throws {
    let manifestData = try Data(contentsOf: resourceRoot.appendingPathComponent("manifest.json"))
    _ = try UpstreamRuntimeManifest.decodeStrictly(from: manifestData)
    let key = Key(
      resourceRoot: resourceRoot.resolvingSymlinksInPath().standardizedFileURL.path,
      manifestSHA256: RuntimeProvenanceVerifier.sha256(manifestData),
      contractSHA256: manifest.provenanceContractSHA256,
      inventorySHA256: manifest.runtimeInventorySHA256
    )
    if verifiedKeys.contains(key) { return }

    let check = check
    let worker = Task.detached(priority: .userInitiated) {
      try Task.checkCancellation()
      try check.perform(resourceRoot, manifest)
      try Task.checkCancellation()
    }
    do {
      try await withTaskCancellationHandler {
        try await worker.value
      } onCancel: {
        worker.cancel()
      }
      verifiedKeys.insert(key)
    } catch {
      worker.cancel()
      throw error
    }
  }
}
