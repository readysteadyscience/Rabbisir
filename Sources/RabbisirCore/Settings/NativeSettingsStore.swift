import Combine
import Foundation

@MainActor
final class NativeSettingsStore: ObservableObject {
  static let deepSeekNamespace = "llm-deepseek"
  static let deepSeekCredentialReference = "DEEPSEEK_API_KEY"

  enum Status: Equatable {
    case idle
    case loading
    case ready
    case failed(String)
  }

  @Published private(set) var status: Status = .idle
  @Published private(set) var writable = false
  @Published private(set) var namespaces: [String: UpstreamSettingsNamespaceView] = [:]
  @Published private(set) var deepSeekCredential: UpstreamCredentialView?
  @Published private(set) var webSearchCredential: UpstreamCredentialView?
  @Published private(set) var modelGroups: [UpstreamSettingsModelGroup] = []
  @Published private(set) var modelFailures: [UpstreamSettingsModelFailure] = []
  @Published private(set) var agentPresets: [UpstreamAgentPresetEntry] = []
  @Published private(set) var agentPresetAuthorable = false
  @Published private(set) var agentPresetHasDocument = false
  @Published private(set) var pluginInventory: [UpstreamPluginInventoryEntry] = []
  @Published private(set) var pluginInventoryFailure: String?
  @Published private(set) var actionMessage: String?
  @Published private(set) var actionMessageIsError = false
  @Published private(set) var isWriting = false

  private let transport: any UpstreamSettingsTransporting
  private var generation = 0

  init(transport: any UpstreamSettingsTransporting) {
    self.transport = transport
  }

  var deepSeekNamespace: UpstreamSettingsNamespaceView? {
    namespaces[Self.deepSeekNamespace]
  }

  var currentDefaultModelID: String? {
    namespaces["agent-default-model"]?.string(at: "model")
  }

  var currentDefaultModel: UpstreamSettingsModel? {
    guard let currentDefaultModelID else { return nil }
    return modelGroups.flatMap(\.models).first { $0.id == currentDefaultModelID }
  }

  var currentDefaultModelIsExplicit: Bool {
    namespaces["agent-default-model"]?.user?.objectValue?["model"]?.stringValue != nil
  }

  func string(namespace: String, key: String) -> String? {
    namespaces[namespace]?.string(at: key)
  }

  func stringOptions(namespace: String, key: String) -> [(id: String, label: String)] {
    guard let schema = namespaces[namespace]?.schema.objectValue,
      let refs = schema["refs"]?.objectValue,
      let rootID = schema["uid"]?.integerValue,
      let root = refs[String(rootID)]?.objectValue,
      let fieldID = root["dict"]?.objectValue?[key]?.integerValue,
      let field = refs[String(fieldID)]?.objectValue
    else { return [] }
    let candidates: [[String: UpstreamJSONValue]]
    if field["type"]?.stringValue == "union" {
      candidates = (field["list"]?.arrayValue ?? []).compactMap { item in
        guard let id = item.integerValue else { return nil }
        return refs[String(id)]?.objectValue
      }
    } else {
      candidates = [field]
    }
    return candidates.compactMap { candidate in
      guard candidate["type"]?.stringValue == "const",
        let id = candidate["value"]?.stringValue
      else { return nil }
      let label = candidate["meta"]?.objectValue?["description"]?.stringValue
      return (id, label?.isEmpty == false ? label! : id)
    }
  }

  func load() async {
    generation &+= 1
    let requestedGeneration = generation
    status = .loading
    actionMessage = nil
    actionMessageIsError = false
    do {
      async let settings = transport.describeSettings()
      async let credentials = transport.describeCredentials(
        references: [Self.deepSeekCredentialReference]
      )
      async let models = transport.listModels()
      async let presets = transport.listAgentPresets()
      let snapshot = try await (settings, credentials, models, presets)
      guard generation == requestedGeneration else { return }
      writable = snapshot.0.writable
      namespaces = Dictionary(uniqueKeysWithValues: snapshot.0.namespaces.map { ($0.ns, $0) })
      deepSeekCredential = snapshot.1.credentials[Self.deepSeekCredentialReference]
      modelGroups = snapshot.2.groups.filter { $0.id == "deepseek-official" }
      modelFailures = snapshot.2.failures.filter { $0.id == "deepseek-official" }
      agentPresets = snapshot.3.presets
      agentPresetAuthorable = snapshot.3.authorable
      agentPresetHasDocument = snapshot.3.hasDocument
      status = .ready
      await reloadWebSearchCredential()
      await reloadPluginInventory()
    } catch {
      guard generation == requestedGeneration else { return }
      status = .failed(Self.message(for: error))
    }
  }

  func setDeepSeekCredential(_ value: String) async -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
      actionMessage = currentCopy.apiKeyEmpty
      actionMessageIsError = true
      return false
    }
    return await performWrite(success: currentCopy.deepSeekKeySaved) {
      try await transport.setCredential(
        reference: Self.deepSeekCredentialReference,
        value: trimmed
      )
      deepSeekCredential = try await transport.describeCredentials(
        references: [Self.deepSeekCredentialReference]
      ).credentials[Self.deepSeekCredentialReference]
    }
  }

  func removeDeepSeekCredential() async -> Bool {
    await performWrite(success: currentCopy.deepSeekKeyDeleted) {
      try await transport.unsetCredential(reference: Self.deepSeekCredentialReference)
      deepSeekCredential = try await transport.describeCredentials(
        references: [Self.deepSeekCredentialReference]
      ).credentials[Self.deepSeekCredentialReference]
    }
  }

  var webSearchCredentialReference: String {
    string(namespace: "web-search-deepseek", key: "apiKeyEnv")
      ?? Self.deepSeekCredentialReference
  }

  func reloadWebSearchCredential() async {
    do {
      webSearchCredential = try await transport.describeCredentials(
        references: [webSearchCredentialReference]
      ).credentials[webSearchCredentialReference]
    } catch {
      webSearchCredential = nil
    }
  }

  func setWebSearchCredential(_ value: String) async -> Bool {
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return true }
    return await performWrite(success: currentCopy.plugins.saved) {
      try await transport.setCredential(reference: webSearchCredentialReference, value: trimmed)
      await reloadWebSearchCredential()
    }
  }

  func setString(namespace: String, key: String, value: String?) async -> Bool {
    await setValue(
      namespace: namespace,
      key: key,
      value: value.map(UpstreamJSONValue.string)
    )
  }

  func setValue(
    namespace: String,
    key: String,
    value: UpstreamJSONValue?
  ) async -> Bool {
    guard let descriptor = namespaces[namespace] else {
      actionMessage = currentCopy[.settingsUnavailable]
      actionMessageIsError = true
      return false
    }
    let operation: UpstreamSettingsPathOperation =
      if let value {
        .set(path: [key], value: value)
      } else {
        .unset(path: [key])
      }
    return await performWrite(success: currentCopy.settingsSaved) {
      let updated = try await transport.mutateSettings(
        namespace: namespace,
        operations: [operation],
        expectedRevision: descriptor.revision
      )
      namespaces[namespace] = updated
    }
  }

  func apply(
    namespace: String,
    operations: [UpstreamSettingsPathOperation],
    success: String? = nil
  ) async -> Bool {
    guard let descriptor = namespaces[namespace] else {
      actionMessage = currentCopy[.settingsUnavailable]
      actionMessageIsError = true
      return false
    }
    guard !operations.isEmpty else { return true }
    return await performWrite(success: success ?? currentCopy.settingsSaved) {
      let updated = try await transport.mutateSettings(
        namespace: namespace,
        operations: operations,
        expectedRevision: descriptor.revision
      )
      namespaces[namespace] = updated
    }
  }

  func reloadAgentPresets() async {
    do {
      let roster = try await transport.listAgentPresets()
      agentPresets = roster.presets
      agentPresetAuthorable = roster.authorable
      agentPresetHasDocument = roster.hasDocument
    } catch {
      actionMessage = currentCopy.agentPresetReadFailed(Self.message(for: error, context: .general))
      actionMessageIsError = true
    }
  }

  func makeDefaultAgentPreset(id: String) async -> Bool {
    let saved = await setString(namespace: "agent-presets", key: "default", value: id)
    if saved { await reloadAgentPresets() }
    return saved
  }

  func readAgentPreset(id: String) async throws -> UpstreamAgentPresetDocument {
    try await transport.readAgentPreset(id: id)
  }

  func copyAgentPreset(from: String, id: String, name: String?) async -> Bool {
    await performWrite(success: currentCopy.agentPresetCreated) {
      try await transport.copyAgentPreset(from: from, id: id, name: name)
      await reloadAgentPresets()
    }
  }

  func openAgentPreset(id: String) async throws -> UpstreamAgentPresetOpenResult {
    try await transport.openAgentPreset(id: id)
  }

  func removeAgentPreset(id: String) async -> Bool {
    await performWrite(success: currentCopy.agentPresetDeleted) {
      try await transport.removeAgentPreset(id: id)
      await reloadAgentPresets()
    }
  }

  func reloadPluginInventory() async {
    pluginInventoryFailure = nil
    do {
      pluginInventory = try await transport.listPlugins().entries
    } catch {
      pluginInventory = []
      pluginInventoryFailure = Self.message(for: error, context: .pluginInventory)
    }
  }

  private func performWrite(
    success: String,
    operation: () async throws -> Void
  ) async -> Bool {
    guard !isWriting else { return false }
    isWriting = true
    defer { isWriting = false }
    actionMessage = nil
    actionMessageIsError = false
    do {
      try await operation()
      actionMessage = success
      actionMessageIsError = false
      return true
    } catch let UpstreamConversationWireError.server(error)
      where error.code == "settings-conflict"
    {
      await load()
      actionMessage = currentCopy.settingsConflict
      actionMessageIsError = true
      return false
    } catch {
      actionMessage = currentCopy.settingsSaveFailed(Self.message(for: error, context: .general))
      actionMessageIsError = true
      return false
    }
  }

  static func message(
    for error: any Error,
    context: RabbisirSafeErrorContext = .settings
  ) -> String {
    RabbisirSafeErrorPresentation.message(
      for: error,
      context: context,
      copy: RabbisirCopy(language: RabbisirLocalization.shared.language)
    )
  }

  var modelCatalogFailureMessage: String {
    RabbisirSafeErrorPresentation.message(
      category: .serviceUnavailable,
      context: .modelCatalog,
      copy: currentCopy
    )
  }

  private var currentCopy: RabbisirCopy {
    RabbisirCopy(language: RabbisirLocalization.shared.language)
  }
}
