import Foundation

struct UpstreamSettingsSecretView: Codable, Equatable, Sendable {
  let path: [String]
  let set: Bool
}

struct UpstreamSettingsNamespaceView: Codable, Equatable, Sendable, Identifiable {
  let ns: String
  let schema: UpstreamJSONValue
  let value: UpstreamJSONValue
  let base: UpstreamJSONValue?
  let user: UpstreamJSONValue?
  let applies: String
  let secrets: [UpstreamSettingsSecretView]
  let revision: Int

  var id: String { ns }

  func string(at key: String) -> String? {
    value.objectValue?[key]?.stringValue
  }
}

struct UpstreamSettingsDescription: Codable, Equatable, Sendable {
  let writable: Bool
  let hasDocument: Bool
  let namespaces: [UpstreamSettingsNamespaceView]
}

struct UpstreamHostDescription: Codable, Equatable, Sendable {
  let version: String
  let cwd: String
  let provider: String?
  let model: String?
  let attachedSessions: Int
  let canOpenPath: Bool
}

struct UpstreamCredentialView: Codable, Equatable, Sendable {
  let configured: Bool
  let source: String?
  let writable: Bool
}

struct UpstreamCredentialDescription: Codable, Equatable, Sendable {
  let credentials: [String: UpstreamCredentialView]
}

struct UpstreamModelReasoningEffort: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let name: String
  let description: String?
}

struct UpstreamModelReasoning: Codable, Equatable, Sendable {
  let efforts: [UpstreamModelReasoningEffort]
  let defaultEffort: String?
}

struct UpstreamSettingsModel: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let name: String
  let description: String?
  let reasoning: UpstreamModelReasoning?
}

struct UpstreamSettingsModelGroup: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let name: String
  let models: [UpstreamSettingsModel]
}

struct UpstreamSettingsModelFailure: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let name: String
  let message: String
}

struct UpstreamSettingsModelCatalog: Codable, Equatable, Sendable {
  let groups: [UpstreamSettingsModelGroup]
  let failures: [UpstreamSettingsModelFailure]
}

enum DeepSeekFlashModelPolicy {
  static let officialProviderID = "deepseek-official"

  static func flashModel(in catalog: UpstreamSettingsModelCatalog) -> UpstreamSettingsModel? {
    catalog.groups
      .first(where: { $0.id == officialProviderID })?
      .models
      .first(where: isExplicitlyFlash)
  }

  static func explicitModelID(in settings: UpstreamSettingsDescription) -> String? {
    settings.namespaces
      .first(where: { $0.ns == "agent-default-model" })?
      .user?.objectValue?["model"]?.stringValue
  }

  static func containsOfficialModel(
    id: String,
    in catalog: UpstreamSettingsModelCatalog
  ) -> Bool {
    catalog.groups
      .first(where: { $0.id == officialProviderID })?
      .models
      .contains(where: { $0.id == id }) == true
  }

  private static func isExplicitlyFlash(_ model: UpstreamSettingsModel) -> Bool {
    tokens(in: model.name).contains("flash") || tokens(in: model.id).contains("flash")
  }

  private static func tokens(in value: String) -> [String] {
    value.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber }).map(String.init)
  }
}

struct UpstreamAgentPresetEntry: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let trust: String
  let isDefault: Bool
  let name: String?
  let description: String?
  let broken: String?

  var displayName: String { name ?? id }
}

struct UpstreamAgentPresetList: Codable, Equatable, Sendable {
  let presets: [UpstreamAgentPresetEntry]
  let authorable: Bool
  let hasDocument: Bool
}

struct UpstreamAgentPresetDocument: Codable, Equatable, Sendable, Identifiable {
  let agentPreset: String
  let trust: String
  let content: String
  let name: String?
  let description: String?

  var id: String { agentPreset }
}

struct UpstreamAgentPresetOpenResult: Codable, Equatable, Sendable {
  let opened: Bool
  let path: String?
}

struct UpstreamPluginInventoryEntry: Codable, Equatable, Sendable, Identifiable {
  let entryId: String
  let moduleName: String
  let enabled: Bool
  let fiberPhase: String?

  var id: String { entryId }
}

struct UpstreamPluginInventory: Codable, Equatable, Sendable {
  let entries: [UpstreamPluginInventoryEntry]
}

enum UpstreamSettingsPathOperation: Encodable, Equatable, Sendable {
  case set(path: [String], value: UpstreamJSONValue)
  case unset(path: [String])

  private enum CodingKeys: String, CodingKey {
    case op
    case path
    case value
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .set(let path, let value):
      try container.encode("set", forKey: .op)
      try container.encode(path, forKey: .path)
      try container.encode(value, forKey: .value)
    case .unset(let path):
      try container.encode("unset", forKey: .op)
      try container.encode(path, forKey: .path)
    }
  }
}

protocol UpstreamSettingsTransporting: Sendable {
  func describeHost() async throws -> UpstreamHostDescription
  func describeSettings() async throws -> UpstreamSettingsDescription
  func mutateSettings(
    namespace: String,
    operations: [UpstreamSettingsPathOperation],
    expectedRevision: Int
  ) async throws -> UpstreamSettingsNamespaceView
  func describeCredentials(references: [String]) async throws -> UpstreamCredentialDescription
  func setCredential(reference: String, value: String) async throws
  func unsetCredential(reference: String) async throws
  func listModels() async throws -> UpstreamSettingsModelCatalog
  func listAgentPresets() async throws -> UpstreamAgentPresetList
  func readAgentPreset(id: String) async throws -> UpstreamAgentPresetDocument
  func copyAgentPreset(from: String, id: String, name: String?) async throws
  func openAgentPreset(id: String) async throws -> UpstreamAgentPresetOpenResult
  func removeAgentPreset(id: String) async throws
  func listPlugins() async throws -> UpstreamPluginInventory
}

enum UpstreamSettingsTransportError: Error, Equatable, Sendable {
  case invalidBaseURL
  case carrierStatus(Int)
}

final class UpstreamSettingsTransport: UpstreamSettingsTransporting, @unchecked Sendable {
  private let baseURL: URL
  private let session: URLSession

  init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
  }

  func describeHost() async throws -> UpstreamHostDescription {
    try await call(method: "host.describe", payload: EmptyRequest())
  }

  func describeSettings() async throws -> UpstreamSettingsDescription {
    try await call(method: "settings.describe", payload: EmptyRequest())
  }

  func mutateSettings(
    namespace: String,
    operations: [UpstreamSettingsPathOperation],
    expectedRevision: Int
  ) async throws -> UpstreamSettingsNamespaceView {
    try await call(
      method: "settings.mutate",
      payload: SettingsMutationRequest(
        ns: namespace,
        ops: operations,
        expectedRevision: expectedRevision
      )
    )
  }

  func describeCredentials(references: [String]) async throws -> UpstreamCredentialDescription {
    try await call(
      method: "credentials.describe",
      payload: CredentialsDescriptionRequest(refs: references)
    )
  }

  func setCredential(reference: String, value: String) async throws {
    let _: EmptyResponse = try await call(
      method: "credentials.set",
      payload: CredentialSetRequest(ref: reference, value: value)
    )
  }

  func unsetCredential(reference: String) async throws {
    let _: EmptyResponse = try await call(
      method: "credentials.unset",
      payload: CredentialReferenceRequest(ref: reference)
    )
  }

  func listModels() async throws -> UpstreamSettingsModelCatalog {
    try await call(method: "llm.models", payload: EmptyRequest())
  }

  func listAgentPresets() async throws -> UpstreamAgentPresetList {
    try await call(method: "agentPreset.list", payload: EmptyRequest())
  }

  func readAgentPreset(id: String) async throws -> UpstreamAgentPresetDocument {
    try await call(method: "agentPreset.read", payload: AgentPresetRequest(agentPreset: id))
  }

  func copyAgentPreset(from: String, id: String, name: String?) async throws {
    let _: AgentPresetCopyResponse = try await call(
      method: "agentPreset.copy",
      payload: AgentPresetCopyRequest(from: from, agentPreset: id, name: name)
    )
  }

  func openAgentPreset(id: String) async throws -> UpstreamAgentPresetOpenResult {
    try await call(method: "agentPreset.openDocument", payload: AgentPresetRequest(agentPreset: id))
  }

  func removeAgentPreset(id: String) async throws {
    let _: EmptyResponse = try await call(
      method: "agentPreset.remove",
      payload: AgentPresetRequest(agentPreset: id)
    )
  }

  func listPlugins() async throws -> UpstreamPluginInventory {
    try await call(
      method: "pluginInventory/list", payload: RemoteArgumentsRequest(args: EmptyRequest()))
  }

  private func call<Request: Encodable, Value: Decodable>(
    method: String,
    payload: Request
  ) async throws -> Value {
    let rpcID = UUID().uuidString
    let body = try UpstreamConversationWire.encodeRequest(
      method: method,
      rpcID: rpcID,
      payload: payload
    )
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw UpstreamSettingsTransportError.invalidBaseURL
    }
    components.path = "/api/\(method)"
    components.query = nil
    components.fragment = nil
    guard let endpoint = components.url else {
      throw UpstreamSettingsTransportError.invalidBaseURL
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw UpstreamSettingsTransportError.carrierStatus(
        (response as? HTTPURLResponse)?.statusCode ?? -1
      )
    }
    return try UpstreamConversationWire.decodeResponse(
      data,
      expectedRPCID: rpcID,
      as: Value.self
    )
  }
}

private struct EmptyRequest: Encodable {}
private struct EmptyResponse: Decodable {}

private struct SettingsMutationRequest: Encodable {
  let ns: String
  let ops: [UpstreamSettingsPathOperation]
  let expectedRevision: Int
}

private struct CredentialsDescriptionRequest: Encodable {
  let refs: [String]
}

private struct CredentialSetRequest: Encodable {
  let ref: String
  let value: String
}

private struct CredentialReferenceRequest: Encodable {
  let ref: String
}

private struct AgentPresetRequest: Encodable {
  let agentPreset: String
}

private struct AgentPresetCopyRequest: Encodable {
  let from: String
  let agentPreset: String
  let name: String?
}

private struct AgentPresetCopyResponse: Decodable {
  let agentPreset: String
}

private struct RemoteArgumentsRequest<Arguments: Encodable>: Encodable {
  let args: Arguments
}
