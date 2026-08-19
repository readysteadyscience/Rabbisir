import Foundation
import OSLog

struct UpstreamRuntimeManifest: Codable, Equatable, Sendable {
  static let supportedSchemaVersion = 3
  static let fieldNames: Set<String> = [
    "schemaVersion",
    "upstreamVersion",
    "rabbisirVersion",
    "upstreamCommit",
    "upstreamTree",
    "provenanceContractSHA256",
    "runtimeInventorySHA256",
    "executable",
  ]

  let schemaVersion: Int
  let upstreamVersion: String
  let rabbisirVersion: String
  let upstreamCommit: String
  let upstreamTree: String
  let provenanceContractSHA256: String
  let runtimeInventorySHA256: String
  let executable: String

  static func decodeStrictly(from data: Data) throws -> Self {
    guard
      let object = try JSONSerialization.jsonObject(with: data) as? [String: Any],
      Set(object.keys) == fieldNames
    else { throw UpstreamRuntimeResolutionError.manifestInvalid }
    do {
      return try JSONDecoder().decode(Self.self, from: data)
    } catch {
      throw UpstreamRuntimeResolutionError.manifestInvalid
    }
  }
}

struct UpstreamRuntimeLaunchPlan: Equatable, Sendable {
  enum Carrier: Equatable, Sendable {
    case bundled
    case developmentSource
  }

  let carrier: Carrier
  let executableURL: URL
  let argumentsPrefix: [String]
  let workingDirectory: URL
  let manifest: UpstreamRuntimeManifest

  func arguments(port: Int?) -> [String] {
    argumentsPrefix + [
      "web",
      "--host", "127.0.0.1",
      "--port", port.map(String.init) ?? "0",
    ]
  }
}

enum UpstreamRuntimeResolutionError: LocalizedError, Equatable {
  case manifestMissing
  case manifestInvalid
  case unsupportedManifest(Int)
  case componentMissing
  case provenanceInvalid
  case incompatibleVersion(expected: String, actual: String)

  var errorDescription: String? {
    let copy = RabbisirCopy(language: RabbisirInterfaceLanguage.currentPreference())
    return switch self {
    case .manifestMissing:
      copy.runtimeManifestMissing
    case .manifestInvalid:
      copy.runtimeManifestInvalid
    case .unsupportedManifest(let version):
      copy.runtimeManifestUnsupported(version)
    case .componentMissing:
      copy.runtimeComponentMissing
    case .provenanceInvalid:
      copy.runtimeProvenanceInvalid
    case .incompatibleVersion(let expected, let actual):
      copy.runtimeVersionMismatch(expected: expected, actual: actual)
    }
  }
}

struct UpstreamRuntimeResolver: Sendable {
  let resourceRoot: URL
  let environment: [String: String]
  let identity: RabbisirLaunchIdentity
  let applicationSupportComponent: String

  init(
    resourceRoot: URL? = RabbisirResourceBundle.current.resourceURL?.appendingPathComponent(
      "VendorRuntime", isDirectory: true),
    environment: [String: String] = ProcessInfo.processInfo.environment,
    identity: RabbisirLaunchIdentity = .production,
    applicationSupportComponent: String? = nil
  ) {
    self.resourceRoot = resourceRoot ?? URL(fileURLWithPath: "/__rabbisir_missing_runtime__")
    self.environment = environment
    self.identity = identity
    self.applicationSupportComponent =
      applicationSupportComponent ?? identity.applicationSupportComponent
  }

  func resolve() throws -> UpstreamRuntimeLaunchPlan {
    let manifest = try loadManifest()
    guard manifest.schemaVersion == UpstreamRuntimeManifest.supportedSchemaVersion else {
      throw UpstreamRuntimeResolutionError.unsupportedManifest(manifest.schemaVersion)
    }
    guard manifest.upstreamVersion == RabbisirVersion.upstreamCompatibleVersion else {
      throw UpstreamRuntimeResolutionError.incompatibleVersion(
        expected: RabbisirVersion.upstreamCompatibleVersion,
        actual: manifest.upstreamVersion
      )
    }
    guard manifest.upstreamCommit == RabbisirVersion.upstreamCompatibleCommit else {
      throw UpstreamRuntimeResolutionError.manifestInvalid
    }
    guard manifest.rabbisirVersion == RabbisirVersion.displayVersion else {
      throw UpstreamRuntimeResolutionError.manifestInvalid
    }
    let bundledExecutable: URL
    do {
      bundledExecutable = try RuntimeCanonicalPath.resolve(
        manifest.executable,
        under: resourceRoot
      )
    } catch {
      throw UpstreamRuntimeResolutionError.manifestInvalid
    }
    if FileManager.default.isExecutableFile(atPath: bundledExecutable.path) {
      return UpstreamRuntimeLaunchPlan(
        carrier: .bundled,
        executableURL: bundledExecutable,
        argumentsPrefix: [],
        workingDirectory: applicationRuntimeDirectory(),
        manifest: manifest
      )
    }

    #if DEBUG
      return try developmentPlan(manifest: manifest)
    #else
      throw UpstreamRuntimeResolutionError.componentMissing
    #endif
  }

  private func loadManifest() throws -> UpstreamRuntimeManifest {
    let url = resourceRoot.appendingPathComponent("manifest.json")
    guard let data = try? Data(contentsOf: url) else {
      throw UpstreamRuntimeResolutionError.manifestMissing
    }
    return try UpstreamRuntimeManifest.decodeStrictly(from: data)
  }

  #if DEBUG
    private func developmentPlan(manifest: UpstreamRuntimeManifest) throws
      -> UpstreamRuntimeLaunchPlan
    {
      guard let override = environment["RABBISIR_RUNTIME_SOURCE_ROOT"], !override.isEmpty else {
        throw UpstreamRuntimeResolutionError.componentMissing
      }
      let root = URL(fileURLWithPath: override, isDirectory: true).standardizedFileURL
      let packageURL = root.appendingPathComponent("apps/cli/package.json")
      guard let data = try? Data(contentsOf: packageURL),
        let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
        let version = object["version"] as? String
      else {
        throw UpstreamRuntimeResolutionError.componentMissing
      }
      guard version == manifest.upstreamVersion else {
        throw UpstreamRuntimeResolutionError.incompatibleVersion(
          expected: manifest.upstreamVersion,
          actual: version
        )
      }
      let entry = root.appendingPathComponent("apps/cli/src/bin.ts")
      guard FileManager.default.fileExists(atPath: entry.path),
        FileManager.default.fileExists(
          atPath: root.appendingPathComponent("node_modules/tsx").path),
        let node = executable(named: "node")
      else {
        throw UpstreamRuntimeResolutionError.componentMissing
      }
      return UpstreamRuntimeLaunchPlan(
        carrier: .developmentSource,
        executableURL: node,
        argumentsPrefix: ["--import", "tsx/esm", entry.path],
        workingDirectory: root,
        manifest: manifest
      )
    }

    private func executable(named name: String) -> URL? {
      for directory in (environment["PATH"] ?? "").split(separator: ":") {
        let candidate = URL(fileURLWithPath: String(directory), isDirectory: true)
          .appendingPathComponent(name)
        if FileManager.default.isExecutableFile(atPath: candidate.path) {
          return candidate.resolvingSymlinksInPath()
        }
      }
      return nil
    }
  #endif

  private func applicationRuntimeDirectory() -> URL {
    let base =
      FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
      ?? FileManager.default.homeDirectoryForCurrentUser
    return base.appendingPathComponent(applicationSupportComponent, isDirectory: true)
      .appendingPathComponent("Runtime", isDirectory: true)
  }
}

enum UpstreamRuntimeReadyLine {
  static func parse(_ line: String) -> URL? {
    let prefix = "dsh web: "
    guard let range = line.range(of: prefix) else { return nil }
    let candidate = line[range.upperBound...].split(whereSeparator: { $0.isWhitespace }).first
    guard let candidate,
      let url = URL(string: String(candidate)),
      url.scheme == "http",
      url.host == "127.0.0.1",
      let port = url.port,
      port != 3080,
      port != 3083
    else { return nil }
    return url
  }
}

enum ManagedUpstreamRuntimeError: LocalizedError, Equatable {
  case failedToLaunch
  case exitedBeforeReady
  case readinessTimedOut
  case healthCheckFailed
  case stopped

  var errorDescription: String? {
    let copy = RabbisirCopy(language: RabbisirInterfaceLanguage.currentPreference())
    return switch self {
    case .failedToLaunch:
      copy.runtimeFailedToLaunch
    case .exitedBeforeReady:
      copy.runtimeExitedBeforeReady
    case .readinessTimedOut:
      copy.runtimeReadinessTimedOut
    case .healthCheckFailed:
      copy.runtimeHealthCheckFailed
    case .stopped:
      copy.runtimeStopped
    }
  }
}

enum ManagedRuntimeChildEnvironment {
  private static let inheritedKeys = [
    "HOME", "LANG", "LC_ALL", "LC_CTYPE", "LOGNAME", "TMPDIR", "USER",
  ]

  static func make(
    from parent: [String: String],
    isolatedHomeDirectory: URL? = nil
  ) -> [String: String] {
    var result = ["PATH": "/usr/bin:/bin:/usr/sbin:/sbin"]
    for key in inheritedKeys {
      if let value = parent[key], !value.isEmpty, !value.contains("\0") {
        result[key] = value
      }
    }
    if let isolatedHomeDirectory {
      result["HOME"] = isolatedHomeDirectory.path
      result["TMPDIR"] =
        isolatedHomeDirectory.appendingPathComponent(
          "tmp", isDirectory: true
        ).path
    }
    return result
  }
}

@MainActor
final class ManagedUpstreamRuntime {
  enum State: Equatable {
    case idle
    case validating
    case starting
    case ready
    case failed(String)
    case stopping
  }

  private let resolver: UpstreamRuntimeResolver
  private let provenanceValidation: RuntimeProvenanceValidationSession
  private let session: URLSession
  private let readinessTimeout: Duration
  private let isolatedHomeDirectory: URL?
  private var process: Process?
  private var outputPipe: Pipe?
  private var errorPipe: Pipe?
  private var outputBuffer = ""
  private var continuation: CheckedContinuation<URL, any Error>?
  private var timeoutTask: Task<Void, Never>?
  private var healthTask: Task<Void, Never>?
  private var validationTask: Task<Void, any Error>?
  private var readyURL: URL?
  private var preferredPort: Int?
  private var isHealthChecking = false
  private var requestedStop = false

  private(set) var state: State = .idle

  var onUnexpectedExit: (() -> Void)?

  init(
    resolver: UpstreamRuntimeResolver = UpstreamRuntimeResolver(),
    session: URLSession = .shared,
    readinessTimeout: Duration = .seconds(30),
    identity: RabbisirLaunchIdentity? = nil,
    applicationSupportComponent: String? = nil,
    isolatedHomeDirectory: URL? = nil,
    provenanceValidation: RuntimeProvenanceValidationSession = RuntimeProvenanceValidationSession()
  ) {
    self.resolver =
      identity.map {
        UpstreamRuntimeResolver(
          identity: $0,
          applicationSupportComponent: applicationSupportComponent
        )
      } ?? resolver
    self.session = session
    self.readinessTimeout = readinessTimeout
    self.isolatedHomeDirectory = isolatedHomeDirectory
    self.provenanceValidation = provenanceValidation
  }

  func start() async throws -> URL {
    stop()
    let plan = try resolver.resolve()
    state = .validating
    let validationTask = Task { [provenanceValidation, resourceRoot = resolver.resourceRoot] in
      try await provenanceValidation.validate(
        resourceRoot: resourceRoot,
        manifest: plan.manifest
      )
    }
    self.validationTask = validationTask
    do {
      try await validationTask.value
      self.validationTask = nil
    } catch is CancellationError {
      self.validationTask = nil
      state = .idle
      throw CancellationError()
    } catch {
      self.validationTask = nil
      state = .failed(UpstreamRuntimeResolutionError.provenanceInvalid.localizedDescription)
      throw UpstreamRuntimeResolutionError.provenanceInvalid
    }
    try Task.checkCancellation()
    try FileManager.default.createDirectory(
      at: plan.workingDirectory,
      withIntermediateDirectories: true
    )
    let child = Process()
    let stdout = Pipe()
    let stderr = Pipe()
    child.executableURL = plan.executableURL
    child.arguments = plan.arguments(port: preferredPort)
    child.currentDirectoryURL = plan.workingDirectory
    child.environment = ManagedRuntimeChildEnvironment.make(
      from: ProcessInfo.processInfo.environment,
      isolatedHomeDirectory: isolatedHomeDirectory
    )
    child.standardOutput = stdout
    child.standardError = stderr
    child.standardInput = Pipe()
    process = child
    outputPipe = stdout
    errorPipe = stderr
    outputBuffer = ""
    readyURL = nil
    isHealthChecking = false
    requestedStop = false
    state = .starting

    stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
      let data = handle.availableData
      guard !data.isEmpty else { return }
      Task { @MainActor [weak self] in self?.consumeStandardOutput(data) }
    }
    stderr.fileHandleForReading.readabilityHandler = { handle in
      _ = handle.availableData
    }
    child.terminationHandler = { [weak self] exitedProcess in
      Task { @MainActor [weak self] in self?.processDidExit(exitedProcess) }
    }

    do {
      try child.run()
    } catch {
      cleanupProcessHandles()
      process = nil
      state = .failed(ManagedUpstreamRuntimeError.failedToLaunch.localizedDescription)
      throw ManagedUpstreamRuntimeError.failedToLaunch
    }
    let carrierName =
      switch plan.carrier {
      case .bundled: "bundled"
      case .developmentSource: "development-source"
      }
    RabbisirLog.runtime.info(
      "Child started with carrier \(carrierName, privacy: .public), upstream version \(plan.manifest.upstreamVersion, privacy: .public)"
    )
    let timeout = readinessTimeout
    timeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: timeout)
      guard let self, !Task.isCancelled, state == .starting else { return }
      failStartup(ManagedUpstreamRuntimeError.readinessTimedOut)
    }
    return try await withCheckedThrowingContinuation { continuation in
      if let readyURL {
        continuation.resume(returning: readyURL)
      } else if case .failed(let message) = state {
        continuation.resume(
          throwing: NSError(
            domain: "Rabbisir.ManagedUpstreamRuntime",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: message]
          ))
      } else {
        self.continuation = continuation
      }
    }
  }

  func restart() async throws -> URL {
    stop()
    return try await start()
  }

  func stop() {
    validationTask?.cancel()
    validationTask = nil
    timeoutTask?.cancel()
    timeoutTask = nil
    healthTask?.cancel()
    healthTask = nil
    isHealthChecking = false
    requestedStop = true
    if let continuation {
      self.continuation = nil
      continuation.resume(throwing: ManagedUpstreamRuntimeError.stopped)
    }
    guard let process else {
      cleanupProcessHandles()
      state = .idle
      return
    }
    state = .stopping
    cleanupProcessHandles()
    if process.isRunning { process.terminate() }
    self.process = nil
    readyURL = nil
    state = .idle
    RabbisirLog.runtime.info("Child stop requested")
  }

  private func consumeStandardOutput(_ data: Data) {
    guard let chunk = String(data: data, encoding: .utf8) else { return }
    outputBuffer += chunk
    while let newline = outputBuffer.firstIndex(of: "\n") {
      let line = String(outputBuffer[..<newline])
      outputBuffer.removeSubrange(...newline)
      if let url = UpstreamRuntimeReadyLine.parse(line) {
        beginHealthCheck(url)
      }
    }
    if outputBuffer.count > 8_192 {
      outputBuffer = String(outputBuffer.suffix(8_192))
    }
  }

  private func beginHealthCheck(_ url: URL) {
    guard state == .starting, !isHealthChecking else { return }
    isHealthChecking = true
    preferredPort = url.port
    healthTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        request.cachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        let (_, response) = try await session.data(for: request)
        guard let response = response as? HTTPURLResponse,
          (200..<400).contains(response.statusCode)
        else {
          throw ManagedUpstreamRuntimeError.healthCheckFailed
        }
        completeStartup(url)
      } catch is CancellationError {
        return
      } catch {
        failStartup(ManagedUpstreamRuntimeError.healthCheckFailed)
      }
    }
  }

  private func completeStartup(_ url: URL) {
    guard state == .starting else { return }
    timeoutTask?.cancel()
    timeoutTask = nil
    healthTask = nil
    readyURL = url
    state = .ready
    let continuation = continuation
    self.continuation = nil
    continuation?.resume(returning: url)
    RabbisirLog.runtime.info("Child health check passed")
  }

  private func failStartup(_ error: ManagedUpstreamRuntimeError) {
    guard state == .starting else { return }
    timeoutTask?.cancel()
    timeoutTask = nil
    healthTask?.cancel()
    healthTask = nil
    let continuation = continuation
    self.continuation = nil
    state = .failed(error.localizedDescription)
    if process?.isRunning == true { process?.terminate() }
    continuation?.resume(throwing: error)
  }

  private func processDidExit(_ exitedProcess: Process) {
    guard process === exitedProcess else { return }
    let wasReady = state == .ready
    let intentional = requestedStop || state == .stopping || state == .idle
    cleanupProcessHandles()
    process = nil
    readyURL = nil
    if state == .starting {
      let continuation = continuation
      self.continuation = nil
      timeoutTask?.cancel()
      timeoutTask = nil
      state = .failed(ManagedUpstreamRuntimeError.exitedBeforeReady.localizedDescription)
      continuation?.resume(throwing: ManagedUpstreamRuntimeError.exitedBeforeReady)
    } else if wasReady && !intentional {
      let copy = RabbisirCopy(language: RabbisirInterfaceLanguage.currentPreference())
      state = .failed(copy.runtimeStoppedUnexpectedly)
      onUnexpectedExit?()
    } else if intentional {
      state = .idle
    }
  }

  private func cleanupProcessHandles() {
    outputPipe?.fileHandleForReading.readabilityHandler = nil
    errorPipe?.fileHandleForReading.readabilityHandler = nil
    outputPipe = nil
    errorPipe = nil
  }
}
