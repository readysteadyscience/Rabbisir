import AppKit
import Foundation
import Testing

@testable import RabbisirCore

@Suite("First-run API configuration")
struct FirstRunConfigurationTests {
  @Test("API key portal is the fixed official DeepSeek Platform destination")
  @MainActor
  func officialAPIKeyPortal() {
    let opener = FirstRunExternalURLOpenerFake()
    let failingOpener = FirstRunExternalURLOpenerFake(result: false)

    #expect(
      DeepSeekAPIKeyPortal.url.absoluteString
        == "https://platform.deepseek.com/api_keys"
    )
    #expect(DeepSeekAPIKeyPortal.open(using: opener))
    #expect(opener.openedURLs == [DeepSeekAPIKeyPortal.url])
    #expect(!DeepSeekAPIKeyPortal.open(using: failingOpener))
    #expect(failingOpener.openedURLs == [DeepSeekAPIKeyPortal.url])
  }

  @Test("API key portal copy is bilingual and identifies the official platform")
  func officialAPIKeyPortalCopy() {
    let chinese = FirstRunConfigurationCopy(language: .chinese)
    let english = FirstRunConfigurationCopy(language: .english)

    #expect(chinese.getAPIKey == "获取 API Key")
    #expect(chinese.getAPIKeyExplanation.contains("DeepSeek 官方平台"))
    #expect(chinese.getAPIKeyFailure.contains("手动粘贴"))
    #expect(english.getAPIKey == "Get API Key")
    #expect(english.getAPIKeyExplanation.contains("official DeepSeek Platform"))
    #expect(english.getAPIKeyFailure.contains("paste"))
  }

  @Test("First-run window hides only its traffic lights and retains native glass")
  @MainActor
  func firstRunWindowPresentation() throws {
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 560, height: 440),
      styleMask: [.titled, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    FirstRunConfigurationWindowPolicy.configure(window)

    #expect(window.standardWindowButton(.closeButton)?.isHidden == true)
    #expect(window.standardWindowButton(.miniaturizeButton)?.isHidden == true)
    #expect(window.standardWindowButton(.zoomButton)?.isHidden == true)
    #expect(window.titlebarAppearsTransparent)
    #expect(!window.isOpaque)
    #expect(window.backgroundColor.alphaComponent == 0)

    let content = NSView()
    let container = FirstRunConfigurationWindowPolicy.makeContainer(contentView: content)
    if #available(macOS 26.0, *) {
      let glass = try #require(
        RabbisirGlassAppKitAdapter.nativeGlassView(in: container) as? NSGlassEffectView
      )
      #expect(RabbisirGlassAppKitAdapter.contentView(in: container) === content)
      #expect(glass.cornerRadius == NativeSettingsMaterialPolicy.cornerRadius)
      #expect(glass.style == .regular)
      #expect(glass.tintColor == nil)
      #expect(container.subviews == [glass])
    } else {
      #expect(RabbisirGlassAppKitAdapter.nativeGlassView(in: container) is NSVisualEffectView)
    }
  }

  @Test("Connection test uses the official read-only models request")
  func officialModelsConnectionTest() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [FirstRunConnectionURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    FirstRunConnectionURLProtocol.reset()
    FirstRunConnectionURLProtocol.handler = { request in
      #expect(request.httpMethod == "GET")
      #expect(request.url?.absoluteString == "https://api.deepseek.com/models")
      #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer test-only")
      #expect(request.httpBody == nil)
      let response = try #require(
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        )
      )
      return (
        response,
        Data(#"{"object":"list","data":[{"id":"deepseek-v4-flash"}]}"#.utf8)
      )
    }
    let tester = DeepSeekConnectionTester(
      endpoint: try #require(URL(string: "https://api.deepseek.com/models")),
      session: session
    )

    #expect(await tester.test(apiKey: "test-only"))
  }

  @Test("Missing configuration routes only to first-run setup")
  func missingConfigurationRequiresSetup() async {
    let transport = FirstRunTransportFake(configured: false)
    let service = FirstRunConfigurationService(
      transport: transport,
      connectionTester: FirstRunConnectionFake(result: true)
    )

    #expect(await service.checkReadiness() == .requiresConfiguration)
  }

  @Test("A configured credential with a usable official model skips setup")
  func existingUsableConfigurationIsReady() async {
    let transport = FirstRunTransportFake(configured: true)
    let service = FirstRunConfigurationService(
      transport: transport,
      connectionTester: FirstRunConnectionFake(result: true)
    )

    #expect(await service.checkReadiness() == .ready)
    #expect(await transport.lastSelectedModelID == nil)
  }

  @Test("A failed official model check never unlocks the workspace")
  func failedModelCheckRemainsInSetup() async {
    let transport = FirstRunTransportFake(
      configured: true,
      modelFailure: "authentication failed"
    )
    let service = FirstRunConfigurationService(
      transport: transport,
      connectionTester: FirstRunConnectionFake(result: true)
    )

    #expect(await service.checkReadiness() == .requiresConfiguration)
    #expect(await transport.lastSelectedModelID == nil)
  }

  @Test("An official catalog without Flash never falls back to Pro")
  func proOnlyCatalogRemainsInSetup() async {
    let transport = FirstRunTransportFake(
      configured: true,
      models: [
        UpstreamSettingsModel(
          id: "costly-model",
          name: "DeepSeek-V4-Pro",
          description: nil,
          reasoning: nil
        )
      ],
      hostModelID: "unavailable-base-model"
    )
    let service = FirstRunConfigurationService(
      transport: transport,
      connectionTester: FirstRunConnectionFake(result: true)
    )

    #expect(await service.checkReadiness() == .requiresConfiguration)
  }

  @Test("An existing explicit Pro selection is preserved rather than treated as a fallback")
  func explicitProSelectionIsPreserved() async {
    let transport = FirstRunTransportFake(
      configured: true,
      models: [
        UpstreamSettingsModel(
          id: "chosen-pro-model",
          name: "DeepSeek-V4-Pro",
          description: nil,
          reasoning: nil
        )
      ],
      explicitModelID: "chosen-pro-model"
    )
    let service = FirstRunConfigurationService(
      transport: transport,
      connectionTester: FirstRunConnectionFake(result: true)
    )

    #expect(await service.checkReadiness() == .ready)
    #expect(await transport.lastSelectedModelID == nil)
  }

  @Test("Saving only unlocks after configured state and model connectivity both succeed")
  func saveAndTestRequiresCompleteSuccess() async {
    let failing = FirstRunTransportFake(configured: false)
    let failingService = FirstRunConfigurationService(
      transport: failing,
      connectionTester: FirstRunConnectionFake(result: false)
    )

    #expect(await failingService.saveAndTest(apiKey: "invalid-secret") == .failed)
    #expect(await failing.lastCredentialWrite == nil)

    let passing = FirstRunTransportFake(configured: false)
    let passingService = FirstRunConfigurationService(
      transport: passing,
      connectionTester: FirstRunConnectionFake(result: true)
    )

    #expect(await passingService.saveAndTest(apiKey: "valid-secret") == .ready)
    #expect(await passing.lastCredentialWrite == "valid-secret")
  }

  @Test("An empty key is rejected without calling the credential transport")
  func emptyKeyNeverWrites() async {
    let transport = FirstRunTransportFake(configured: false)
    let service = FirstRunConfigurationService(
      transport: transport,
      connectionTester: FirstRunConnectionFake(result: true)
    )

    #expect(await service.saveAndTest(apiKey: "  \n") == .emptyKey)
    #expect(await transport.lastCredentialWrite == nil)
  }
}

@MainActor
private final class FirstRunExternalURLOpenerFake: RabbisirExternalURLOpening {
  private let result: Bool
  private(set) var openedURLs: [URL] = []

  init(result: Bool = true) {
    self.result = result
  }

  func open(_ url: URL) -> Bool {
    openedURLs.append(url)
    return result
  }
}

private final class FirstRunConnectionURLProtocol: URLProtocol, @unchecked Sendable {
  typealias Handler = @Sendable (URLRequest) throws -> (HTTPURLResponse, Data)
  private static let lock = NSLock()
  nonisolated(unsafe) static var handler: Handler?

  static func reset() {
    lock.withLock { handler = nil }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      let handler = try #require(Self.lock.withLock { Self.handler })
      let (response, data) = try handler(request)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}
}

private struct FirstRunConnectionFake: DeepSeekConnectionTesting {
  let result: Bool

  func test(apiKey: String) async -> Bool { result }
}

private actor FirstRunTransportFake: FirstRunConfigurationTransporting {
  private var configured: Bool
  private let modelFailure: String?
  private let models: [UpstreamSettingsModel]
  private var effectiveModelID: String?
  private(set) var lastCredentialWrite: String?
  private(set) var lastSelectedModelID: String?

  init(
    configured: Bool,
    modelFailure: String? = nil,
    models: [UpstreamSettingsModel] = [
      UpstreamSettingsModel(
        id: "current-flash-model",
        name: "DeepSeek-V4-Flash",
        description: nil,
        reasoning: nil
      )
    ],
    explicitModelID: String? = nil,
    effectiveModelID: String? = nil,
    hostModelID: String = "current-flash-model"
  ) {
    self.configured = configured
    self.modelFailure = modelFailure
    self.models = models
    self.effectiveModelID = effectiveModelID ?? explicitModelID ?? hostModelID
  }

  func describeCredentials(references: [String]) async throws -> UpstreamCredentialDescription {
    UpstreamCredentialDescription(
      credentials: Dictionary(
        uniqueKeysWithValues: references.map {
          ($0, UpstreamCredentialView(configured: configured, source: nil, writable: true))
        }
      )
    )
  }

  func setCredential(reference: String, value: String) async throws {
    lastCredentialWrite = value
    configured = true
  }

  func describeHost() async throws -> UpstreamHostDescription {
    UpstreamHostDescription(
      version: "0.1.0-rc.5",
      cwd: "/tmp/first-run-fixture",
      provider: DeepSeekFlashModelPolicy.officialProviderID,
      model: effectiveModelID,
      attachedSessions: 0,
      canOpenPath: true
    )
  }

  func listModels() async throws -> UpstreamSettingsModelCatalog {
    if let modelFailure {
      return UpstreamSettingsModelCatalog(
        groups: [],
        failures: [
          UpstreamSettingsModelFailure(
            id: "deepseek-official",
            name: "DeepSeek",
            message: modelFailure
          )
        ]
      )
    }
    return UpstreamSettingsModelCatalog(
      groups: [
        UpstreamSettingsModelGroup(
          id: "deepseek-official",
          name: "DeepSeek",
          models: models
        )
      ],
      failures: []
    )
  }
}
