import AppKit
import Foundation
import Testing

@testable import RabbisirCore

@Suite("Native settings", .serialized)
struct NativeSettingsTests {
  @Test("Settings and model failures never project upstream diagnostics")
  func settingsFailuresAreSafeAndLocalized() {
    let privatePath = "/Use" + "rs/example"
    let raw = "PRIVATE \(privatePath) http://127.0.0.1:3080 stack trace"
    let error = UpstreamConversationWireError.server(
      UpstreamRPCError(code: "unauthorized", message: raw, details: .null)
    )
    for language in RabbisirInterfaceLanguage.allCases {
      let copy = RabbisirCopy(language: language)
      let settings = RabbisirSafeErrorPresentation.message(
        for: error, context: .settings, copy: copy)
      let models = RabbisirSafeErrorPresentation.message(
        category: .serviceUnavailable, context: .modelCatalog, copy: copy)
      for message in [settings, models] {
        #expect(!message.contains(raw))
        #expect(!message.contains(privatePath))
        #expect(!message.contains("127.0.0.1"))
        #expect(!message.contains("3080"))
      }
      #expect(settings.contains(language == .chinese ? "API Key" : "API Key"))
      #expect(models.contains(language == .chinese ? "模型目录" : "model catalog"))
    }
  }

  @Test("Apple owns the material while every existing content surface defaults to regular glass")
  func systemOwnedRegularGlassPolicy() {
    for role in RabbisirGlassSurfaceRole.allCases {
      let configuration = RabbisirGlassMaterialPolicy.configuration(role: role)
      #expect(configuration.isInteractive == (role == .interactiveControl))
    }
  }

  @Test("Settings typography uses native semantic roles without a custom font family")
  func settingsTypographyUsesNativeSemanticRoles() {
    #expect(NativeSettingsTypography.root == .body)
    #expect(NativeSettingsTypography.navigation == .body)
    #expect(NativeSettingsTypography.pageTitle == .pageTitle)
    #expect(NativeSettingsTypography.rowTitle == .headline)
    #expect(NativeSettingsTypography.supporting == .callout)
    #expect(NativeSettingsTypography.caption == .caption)
    #expect(NativeSettingsTypography.identifier == .codeCaption)

    #expect(RabbisirTypographyRole.pageTitle.textStyle == .title)
    #expect(RabbisirTypographyRole.pageTitle.weight == .semibold)
    #expect(RabbisirTypographyRole.body.weight == nil)
    #expect(RabbisirTypographyRole.headline.weight == nil)
    #expect(RabbisirTypographyRole.pageTitle.design == .default)
    #expect(RabbisirTypographyRole.codeCaption.design == .monospaced)
  }

  @Test("Transport uses the official settings RPC endpoint and envelope")
  func upstreamRPCEnvelope() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SettingsURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    SettingsURLProtocol.reset()
    SettingsURLProtocol.handler = { request, body in
      let envelope = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
      )
      let rpcID = try #require(envelope["rpcId"] as? String)
      #expect(envelope["method"] as? String == "settings.describe")
      #expect(request.url?.path == "/api/settings.describe")
      let response = try #require(
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        ))
      return (
        response,
        Data(
          """
          {"type":"server-response","rpcId":"\(rpcID)","result":{"ok":true,"value":{
          "writable":true,"hasDocument":true,"namespaces":[]}}}
          """.utf8)
      )
    }
    let transport = UpstreamSettingsTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )

    let description = try await transport.describeSettings()

    #expect(description.writable)
    #expect(description.hasDocument)
  }

  @Test("Transport uses the generated plugin inventory endpoint and named arguments")
  func pluginInventoryEnvelope() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SettingsURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    SettingsURLProtocol.reset()
    SettingsURLProtocol.handler = { request, body in
      let envelope = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      let payload = try #require(envelope["payload"] as? [String: Any])
      let args = try #require(payload["args"] as? [String: Any])
      #expect(args.isEmpty)
      #expect(envelope["method"] as? String == "pluginInventory/list")
      #expect(request.url?.path == "/api/pluginInventory/list")
      let rpcID = try #require(envelope["rpcId"] as? String)
      let response = try #require(
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        ))
      return (
        response,
        Data(
          """
          {"type":"server-response","rpcId":"\(rpcID)","result":{"ok":true,"value":{"entries":[]}}}
          """.utf8)
      )
    }
    let transport = UpstreamSettingsTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )

    #expect(try await transport.listPlugins().entries.isEmpty)
  }

  @Test("Agent preset authoring calls the official host methods without composition text")
  func agentPresetAuthoringEnvelope() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SettingsURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    SettingsURLProtocol.reset()
    SettingsURLProtocol.handler = { request, body in
      let envelope = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      let payload = try #require(envelope["payload"] as? [String: Any])
      #expect(envelope["method"] as? String == "agentPreset.copy")
      #expect(request.url?.path == "/api/agentPreset.copy")
      #expect(payload["from"] as? String == "standard")
      #expect(payload["agentPreset"] as? String == "mine")
      #expect(payload["name"] as? String == "我的预设")
      #expect(payload["content"] == nil)
      let rpcID = try #require(envelope["rpcId"] as? String)
      let response = try #require(
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        ))
      return (
        response,
        Data(
          """
          {"type":"server-response","rpcId":"\(rpcID)","result":{"ok":true,"value":{"agentPreset":"mine"}}}
          """.utf8)
      )
    }
    let transport = UpstreamSettingsTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )

    try await transport.copyAgentPreset(from: "standard", id: "mine", name: "我的预设")
  }

  @Test("Agent preset management uses every official host endpoint")
  func agentPresetManagementEnvelopes() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SettingsURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    SettingsURLProtocol.reset()
    SettingsURLProtocol.handler = { request, body in
      let envelope = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])
      let method = try #require(envelope["method"] as? String)
      let payload = try #require(envelope["payload"] as? [String: Any])
      #expect(request.url?.path == "/api/\(method)")
      let rpcID = try #require(envelope["rpcId"] as? String)
      let value: String
      switch method {
      case "agentPreset.list":
        #expect(payload.isEmpty)
        value = #"{"presets":[],"authorable":true,"hasDocument":true}"#
      case "agentPreset.read":
        #expect(payload["agentPreset"] as? String == "standard")
        value =
          #"{"agentPreset":"standard","trust":"system","content":"preset","name":null,"description":null}"#
      case "agentPreset.openDocument":
        #expect(payload["agentPreset"] as? String == "standard")
        value = #"{"opened":false,"path":"/preset/standard"}"#
      case "agentPreset.remove":
        #expect(payload["agentPreset"] as? String == "mine")
        value = "{}"
      default:
        Issue.record("Unexpected method: \(method)")
        value = "{}"
      }
      let response = try #require(
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil
        ))
      return (
        response,
        Data(
          """
          {"type":"server-response","rpcId":"\(rpcID)","result":{"ok":true,"value":\(value)}}
          """.utf8)
      )
    }
    let transport = UpstreamSettingsTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )

    #expect(try await transport.listAgentPresets().authorable)
    #expect(try await transport.readAgentPreset(id: "standard").content == "preset")
    #expect(try await transport.openAgentPreset(id: "standard").path == "/preset/standard")
    try await transport.removeAgentPreset(id: "mine")
  }

  @Test("Permission choices come from the official serialized schema")
  @MainActor
  func schemaDrivenPermissionChoices() async {
    let fake = SettingsFakeTransport()
    let store = NativeSettingsStore(transport: fake)

    await store.load()

    #expect(store.string(namespace: "permission", key: "defaultPreset") == "workspace-write")
    #expect(
      store.stringOptions(namespace: "permission", key: "defaultPreset").map(\.id) == [
        "workspace-write", "danger-full-access",
      ])
  }

  @Test("Writes carry the official namespace revision and accept the returned view")
  @MainActor
  func revisionBoundWrite() async {
    let fake = SettingsFakeTransport()
    let store = NativeSettingsStore(transport: fake)
    await store.load()

    let saved = await store.setString(
      namespace: "ui-theme",
      key: "preference",
      value: "dark"
    )

    #expect(saved)
    #expect(store.string(namespace: "ui-theme", key: "preference") == "dark")
    let mutation = await fake.lastMutation
    #expect(mutation?.namespace == "ui-theme")
    #expect(mutation?.revision == 3)
    #expect(
      mutation?.operations == [
        .set(path: ["preference"], value: .string("dark"))
      ])
  }

  @Test("Credential writes are one-way and refresh only configured state")
  @MainActor
  func credentialWriteOnly() async {
    let fake = SettingsFakeTransport()
    let store = NativeSettingsStore(transport: fake)
    await store.load()

    #expect(store.deepSeekCredential?.configured == false)
    #expect(await store.setDeepSeekCredential("secret-value"))
    #expect(store.deepSeekCredential?.configured == true)
    #expect(await fake.lastCredentialWrite == "secret-value")
    #expect(await store.removeDeepSeekCredential())
    #expect(store.deepSeekCredential?.configured == false)
  }

  @Test("Only the official DeepSeek model group is projected")
  @MainActor
  func upstreamDeepSeekOnly() async {
    let fake = SettingsFakeTransport()
    let store = NativeSettingsStore(transport: fake)

    await store.load()

    #expect(store.modelGroups.map(\.id) == ["deepseek-official"])
    #expect(store.modelGroups.flatMap(\.models).map(\.id) == ["deepseek-v4-flash"])
    #expect(store.currentDefaultModelID == "deepseek-v4-flash")
    #expect(store.currentDefaultModel?.name == "DeepSeek-V4-Flash")
    #expect(!store.currentDefaultModelIsExplicit)
  }

  @Test("General choice values localize without changing their upstream identifiers")
  func localizedGeneralChoiceValues() {
    let chinese = RabbisirCopy(language: .chinese)
    let english = RabbisirCopy(language: .english)

    #expect(
      RabbisirSettingsOptionLocalization.label(
        namespace: "ui-conversation",
        id: "queue",
        upstreamLabel: "queue",
        copy: chinese
      ) == "排队"
    )
    #expect(
      RabbisirSettingsOptionLocalization.label(
        namespace: "ui-conversation",
        id: "steer",
        upstreamLabel: "steer",
        copy: chinese
      ) == "引导当前轮次"
    )
    #expect(
      RabbisirSettingsOptionLocalization.label(
        namespace: "ui-conversation",
        id: "queue",
        upstreamLabel: "排队",
        copy: english
      ) == "Queue"
    )
    #expect(
      RabbisirSettingsOptionLocalization.label(
        namespace: "ui-conversation",
        id: "steer",
        upstreamLabel: "引导",
        copy: english
      ) == "Steer Current Turn"
    )
  }

  @Test("One native regular material registry owns every themed panel role")
  func centralizedPanelMaterialRegistry() {
    for role in RabbisirGlassSurfaceRole.allCases {
      let configuration = RabbisirGlassMaterialPolicy.configuration(role: role)
      #expect(configuration.isInteractive == (role == .interactiveControl))
    }
  }

  @Test("Settings uses public regular glass without an app-owned backing layer")
  @MainActor
  func settingsWindowGlassComposition() throws {
    let window = NSWindow(
      contentRect: CGRect(x: 0, y: 0, width: 900, height: 640),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false
    )
    NativeSettingsMaterialPolicy.configure(window)

    #expect(!window.isOpaque)
    #expect(window.backgroundColor.alphaComponent == 0)
    #expect(window.titlebarAppearsTransparent)
    #expect(window.styleMask.contains(.fullSizeContentView))
    #expect(!window.hasShadow)

    let content = NSView()
    let container = NativeSettingsMaterialPolicy.makeContainer(contentView: content)
    if #available(macOS 26.0, *) {
      let glass = RabbisirGlassAppKitAdapter.nativeGlassView(in: container) as? NSGlassEffectView
      #expect(glass?.style == .regular)
      #expect(RabbisirGlassAppKitAdapter.contentView(in: container) === content)
      #expect(glass?.cornerRadius == NativeSettingsMaterialPolicy.cornerRadius)
      #expect(glass?.tintColor == nil)
      #expect(container !== glass)
      #expect(container.subviews.count == 1)
      #expect(container.subviews.first === glass)
    } else {
      let glass = RabbisirGlassAppKitAdapter.nativeGlassView(in: container) as? NSVisualEffectView
      #expect(glass?.material == .underWindowBackground)
      #expect(glass?.blendingMode == .behindWindow)
      #expect(glass?.state == .active)
    }
  }
}

private final class SettingsURLProtocol: URLProtocol, @unchecked Sendable {
  typealias Handler = @Sendable (URLRequest, Data) throws -> (HTTPURLResponse, Data)
  private static let lock = NSLock()
  nonisolated(unsafe) static var handler: Handler?

  static func reset() {
    lock.withLock { handler = nil }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    do {
      let body = try bodyData()
      let handler = try #require(Self.lock.withLock { Self.handler })
      let (response, data) = try handler(request, body)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}

  private func bodyData() throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
      if count == 0 { break }
      result.append(buffer, count: count)
    }
    return result
  }
}

private actor SettingsFakeTransport: UpstreamSettingsTransporting {
  struct Mutation: Equatable, Sendable {
    let namespace: String
    let operations: [UpstreamSettingsPathOperation]
    let revision: Int
  }

  private(set) var lastMutation: Mutation?
  private(set) var lastCredentialWrite: String?
  private var credentialConfigured = false
  private var views: [UpstreamSettingsNamespaceView]

  init() {
    views = SettingsFakeTransport.initialViews
  }

  func describeHost() async throws -> UpstreamHostDescription {
    UpstreamHostDescription(
      version: "0.1.0-rc.5",
      cwd: "/tmp/settings-fixture",
      provider: "deepseek-official",
      model: "deepseek-v4-flash",
      attachedSessions: 0,
      canOpenPath: true
    )
  }

  func describeSettings() async throws -> UpstreamSettingsDescription {
    UpstreamSettingsDescription(writable: true, hasDocument: true, namespaces: views)
  }

  func mutateSettings(
    namespace: String,
    operations: [UpstreamSettingsPathOperation],
    expectedRevision: Int
  ) async throws -> UpstreamSettingsNamespaceView {
    lastMutation = Mutation(
      namespace: namespace,
      operations: operations,
      revision: expectedRevision
    )
    let index = views.firstIndex { $0.ns == namespace }!
    let existing = views[index]
    var object = existing.value.objectValue ?? [:]
    for operation in operations {
      switch operation {
      case .set(let path, let value) where path.count == 1:
        object[path[0]] = value
      case .unset(let path) where path.count == 1:
        object.removeValue(forKey: path[0])
      default:
        break
      }
    }
    let updated = UpstreamSettingsNamespaceView(
      ns: existing.ns,
      schema: existing.schema,
      value: .object(object),
      base: existing.base,
      user: .object(object),
      applies: existing.applies,
      secrets: existing.secrets,
      revision: existing.revision + 1
    )
    views[index] = updated
    return updated
  }

  func describeCredentials(references: [String]) async throws -> UpstreamCredentialDescription {
    UpstreamCredentialDescription(
      credentials: Dictionary(
        uniqueKeysWithValues: references.map {
          (
            $0,
            UpstreamCredentialView(configured: credentialConfigured, source: nil, writable: true)
          )
        }
      ))
  }

  func setCredential(reference: String, value: String) async throws {
    lastCredentialWrite = value
    credentialConfigured = true
  }

  func unsetCredential(reference: String) async throws {
    credentialConfigured = false
  }

  func listModels() async throws -> UpstreamSettingsModelCatalog {
    UpstreamSettingsModelCatalog(
      groups: [
        UpstreamSettingsModelGroup(
          id: "deepseek-official",
          name: "DeepSeek",
          models: [
            UpstreamSettingsModel(
              id: "deepseek-v4-flash",
              name: "DeepSeek-V4-Flash",
              description: nil,
              reasoning: nil
            )
          ]
        ),
        UpstreamSettingsModelGroup(
          id: "third-party",
          name: "Third Party",
          models: []
        ),
      ],
      failures: []
    )
  }

  func listAgentPresets() async throws -> UpstreamAgentPresetList {
    UpstreamAgentPresetList(
      presets: [
        UpstreamAgentPresetEntry(
          id: "coding",
          trust: "system",
          isDefault: true,
          name: "Coding",
          description: nil,
          broken: nil
        )
      ],
      authorable: true,
      hasDocument: true
    )
  }

  func readAgentPreset(id: String) async throws -> UpstreamAgentPresetDocument {
    UpstreamAgentPresetDocument(
      agentPreset: id,
      trust: "system",
      content: "plugins: []",
      name: "Coding",
      description: nil
    )
  }

  func copyAgentPreset(from: String, id: String, name: String?) async throws {}

  func openAgentPreset(id: String) async throws -> UpstreamAgentPresetOpenResult {
    UpstreamAgentPresetOpenResult(opened: true, path: nil)
  }

  func removeAgentPreset(id: String) async throws {}

  func listPlugins() async throws -> UpstreamPluginInventory {
    UpstreamPluginInventory(entries: [])
  }

  private static let permissionSchema: UpstreamJSONValue = .object([
    "uid": .integer(4),
    "refs": .object([
      "1": .object([
        "type": .string("const"),
        "value": .string("workspace-write"),
        "meta": .object(["description": .string("Workspace Write")]),
      ]),
      "2": .object([
        "type": .string("const"),
        "value": .string("danger-full-access"),
      ]),
      "3": .object([
        "type": .string("union"),
        "list": .array([.integer(1), .integer(2)]),
      ]),
      "4": .object([
        "type": .string("object"),
        "dict": .object(["defaultPreset": .integer(3)]),
      ]),
    ]),
  ])

  private static let initialViews: [UpstreamSettingsNamespaceView] = [
    UpstreamSettingsNamespaceView(
      ns: "agent-default-model",
      schema: .object([:]),
      value: .object([
        "provider": .string("deepseek-official"),
        "model": .string("deepseek-v4-flash"),
      ]),
      base: .object([
        "provider": .string("deepseek-official"),
        "model": .string("deepseek-v4-flash"),
      ]),
      user: nil,
      applies: "next-session",
      secrets: [],
      revision: 1
    ),
    UpstreamSettingsNamespaceView(
      ns: "permission",
      schema: permissionSchema,
      value: .object(["defaultPreset": .string("workspace-write")]),
      base: nil,
      user: nil,
      applies: "live",
      secrets: [],
      revision: 1
    ),
    UpstreamSettingsNamespaceView(
      ns: "ui-theme",
      schema: .object([:]),
      value: .object(["preference": .string("system")]),
      base: nil,
      user: nil,
      applies: "live",
      secrets: [],
      revision: 3
    ),
    UpstreamSettingsNamespaceView(
      ns: "llm-deepseek",
      schema: .object([:]),
      value: .object(["apiKeyEnv": .string("DEEPSEEK_API_KEY")]),
      base: nil,
      user: nil,
      applies: "live",
      secrets: [],
      revision: 2
    ),
  ]
}
