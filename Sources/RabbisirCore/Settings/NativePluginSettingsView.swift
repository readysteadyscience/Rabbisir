import SwiftUI

struct PluginSettingsView: View {
  @ObservedObject var store: NativeSettingsStore
  @State private var tab: PluginSettingsTab = .configuration
  @Environment(\.rabbisirCopy) private var copy

  var body: some View {
    SettingsPage(
      title: copy.plugins.pageTitle,
      subtitle: copy.plugins.pageSubtitle
    ) {
      SettingsStatusView(store: store)
      Picker(copy.plugins.viewLabel, selection: $tab) {
        ForEach(PluginSettingsTab.allCases) { tab in Text(tab.title(copy: copy.plugins)).tag(tab) }
      }
      .pickerStyle(.segmented)
      .labelsHidden()
      .accessibilityLabel(copy.plugins.viewLabel)

      switch tab {
      case .configuration:
        pluginConfiguration
      case .inventory:
        PluginInventoryView(store: store)
      }
    }
  }

  @ViewBuilder
  private var pluginConfiguration: some View {
    let cards = PluginCardDefinition.official(copy: copy.plugins).filter {
      store.namespaces[$0.namespace] != nil
    }
    if cards.isEmpty {
      SettingsContentGroup {
        Text(copy.plugins.noEditableSettings)
          .foregroundStyle(.secondary)
      }
    } else {
      ForEach(cards) { definition in
        if let descriptor = store.namespaces[definition.namespace] {
          PluginConfigurationCard(
            store: store,
            descriptor: descriptor,
            definition: definition
          )
          .id("\(definition.namespace).\(descriptor.revision)")
        }
      }
    }
  }
}

private enum PluginSettingsTab: String, CaseIterable, Identifiable {
  case configuration
  case inventory

  var id: String { rawValue }
  func title(copy: RabbisirPluginCopy) -> String {
    self == .configuration ? copy.configuration : copy.inventory
  }
}

private struct PluginCardDefinition: Identifiable {
  enum ValueKind { case number, text }
  struct Field: Identifiable {
    let key: String
    let label: String
    let hint: String
    let kind: ValueKind
    var id: String { key }
  }

  let namespace: String
  let title: String
  let description: String
  let fields: [Field]
  let includesCredential: Bool
  var id: String { namespace }

  static func official(copy: RabbisirPluginCopy) -> [Self] {
    [
      PluginCardDefinition(
        namespace: "shell",
        title: copy.terminalTitle,
        description: copy.terminalDescription,
        fields: [
          Field(key: "timeoutMs", label: copy.timeoutLabel, hint: copy.timeoutHint, kind: .number),
          Field(
            key: "maxOutputBytes", label: copy.outputLimitLabel, hint: copy.outputLimitHint,
            kind: .number),
        ],
        includesCredential: false
      ),
      PluginCardDefinition(
        namespace: "agent-loop",
        title: copy.agentLoopTitle,
        description: copy.agentLoopDescription,
        fields: [
          Field(
            key: "maxParallelToolCalls", label: copy.parallelCallsLabel,
            hint: copy.parallelCallsHint, kind: .number)
        ],
        includesCredential: false
      ),
      PluginCardDefinition(
        namespace: "web-search-deepseek",
        title: copy.webSearchTitle,
        description: copy.webSearchDescription,
        fields: [
          Field(key: "baseURL", label: copy.baseURLLabel, hint: copy.baseURLHint, kind: .text),
          Field(key: "maxUses", label: copy.maxUsesLabel, hint: copy.maxUsesHint, kind: .number),
        ],
        includesCredential: true
      ),
    ]
  }
}

private struct PluginConfigurationCard: View {
  @ObservedObject var store: NativeSettingsStore
  let descriptor: UpstreamSettingsNamespaceView
  let definition: PluginCardDefinition
  @State private var expanded = false
  @State private var drafts: [String: String]
  @State private var cleared: Set<String> = []
  @State private var credentialDraft = ""
  @Environment(\.rabbisirCopy) private var copy

  init(
    store: NativeSettingsStore,
    descriptor: UpstreamSettingsNamespaceView,
    definition: PluginCardDefinition
  ) {
    self.store = store
    self.descriptor = descriptor
    self.definition = definition
    let values = descriptor.value.objectValue ?? [:]
    _drafts = State(
      initialValue: Dictionary(
        uniqueKeysWithValues: definition.fields.map {
          ($0.key, Self.text(values[$0.key]))
        }))
  }

  var body: some View {
    SettingsContentGroup {
      Button {
        expanded.toggle()
      } label: {
        HStack(spacing: 12) {
          VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 7) {
              Text(definition.title).rabbisirTypography(NativeSettingsTypography.rowTitle)
              if isDirty {
                Text(copy.plugins.unsaved)
                  .rabbisirTypography(NativeSettingsTypography.badge)
                  .foregroundStyle(.orange)
              }
            }
            Text(definition.description)
              .rabbisirTypography(NativeSettingsTypography.supporting)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Image(systemName: "chevron.down")
            .rotationEffect(.degrees(expanded ? 180 : 0))
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(
        "\(expanded ? copy.plugins.collapse : copy.plugins.expand): \(definition.title)")

      if expanded {
        if !store.writable {
          Text(copy.plugins.readOnly)
            .rabbisirTypography(NativeSettingsTypography.supporting)
            .foregroundStyle(.secondary)
        }
        if definition.includesCredential { credentialField }
        ForEach(definition.fields) { field in
          Divider()
          pluginField(field)
        }
        HStack {
          Spacer()
          Button(copy.plugins.discardChanges, action: discard)
            .disabled(!isDirty || store.isWriting)
          Button(store.isWriting ? copy.plugins.saving : copy[.save]) { Task { await save() } }
            .disabled(!isDirty || isInvalid || store.isWriting)
        }
      }
    }
  }

  private var credentialField: some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text("API Key").rabbisirTypography(NativeSettingsTypography.body)
        Spacer()
        Text(
          store.webSearchCredential?.configured == true
            ? copy.plugins.configured : copy.plugins.notConfigured
        )
        .rabbisirTypography(NativeSettingsTypography.caption)
        .foregroundStyle(.secondary)
      }
      SecureField(copy.plugins.enterAPIKey, text: $credentialDraft)
        .textFieldStyle(.roundedBorder)
        .disabled(store.webSearchCredential?.writable == false)
      Text(copy.plugins.credentialNote)
        .rabbisirTypography(NativeSettingsTypography.caption)
        .foregroundStyle(.secondary)
    }
  }

  private func pluginField(_ field: PluginCardDefinition.Field) -> some View {
    VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(field.label).rabbisirTypography(NativeSettingsTypography.body)
        if descriptor.user?.objectValue?[field.key] != nil, !cleared.contains(field.key) {
          Text(copy.plugins.overridden)
            .rabbisirTypography(NativeSettingsTypography.badge)
            .foregroundStyle(.secondary)
        }
        Spacer()
        Button(copy.plugins.restoreDefault) { reset(field) }
          .controlSize(.small)
          .disabled(!store.writable)
      }
      TextField(
        field.label,
        text: Binding(
          get: { drafts[field.key] ?? "" },
          set: {
            drafts[field.key] = $0
            cleared.remove(field.key)
          }
        )
      )
      .textFieldStyle(.roundedBorder)
      .disabled(!store.writable)
      Text(field.hint)
        .rabbisirTypography(NativeSettingsTypography.caption)
        .foregroundStyle(.secondary)
      if field.kind == .number, !isValidNumber(drafts[field.key] ?? "") {
        Text(copy.plugins.numberValidation)
          .rabbisirTypography(NativeSettingsTypography.caption)
          .foregroundStyle(.red)
      }
    }
  }

  private var isDirty: Bool {
    if !credentialDraft.isEmpty || !cleared.isEmpty { return true }
    return definition.fields.contains { field in
      drafts[field.key, default: ""] != Self.text(descriptor.value.objectValue?[field.key])
    }
  }

  private var isInvalid: Bool {
    definition.fields.contains { field in
      field.kind == .number && !isValidNumber(drafts[field.key] ?? "")
    }
  }

  private func isValidNumber(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    if trimmed.isEmpty { return true }
    guard let value = Double(trimmed) else { return false }
    return value.isFinite
  }

  private func reset(_ field: PluginCardDefinition.Field) {
    drafts[field.key] = Self.text(descriptor.base?.objectValue?[field.key])
    cleared.insert(field.key)
  }

  private func discard() {
    let values = descriptor.value.objectValue ?? [:]
    drafts = Dictionary(
      uniqueKeysWithValues: definition.fields.map {
        ($0.key, Self.text(values[$0.key]))
      })
    cleared = []
    credentialDraft = ""
  }

  private func save() async {
    var operations: [UpstreamSettingsPathOperation] = []
    for field in definition.fields {
      if cleared.contains(field.key) {
        operations.append(.unset(path: [field.key]))
        continue
      }
      let text = drafts[field.key, default: ""].trimmingCharacters(in: .whitespacesAndNewlines)
      guard text != Self.text(descriptor.value.objectValue?[field.key]) else { continue }
      if text.isEmpty {
        operations.append(.unset(path: [field.key]))
      } else if field.kind == .number, let value = Double(text) {
        if value.rounded() == value {
          operations.append(.set(path: [field.key], value: .integer(Int64(value))))
        } else {
          operations.append(.set(path: [field.key], value: .number(value)))
        }
      } else {
        operations.append(.set(path: [field.key], value: .string(text)))
      }
    }
    var saved = await store.apply(
      namespace: definition.namespace, operations: operations, success: copy.plugins.saved)
    if definition.includesCredential, !credentialDraft.isEmpty {
      saved = await store.setWebSearchCredential(credentialDraft) && saved
    }
    if saved { discard() }
  }

  private static func text(_ value: UpstreamJSONValue?) -> String {
    switch value {
    case .string(let value): value
    case .integer(let value): String(value)
    case .number(let value): String(value)
    default: ""
    }
  }
}

private struct PluginInventoryView: View {
  @ObservedObject var store: NativeSettingsStore
  @State private var query = ""
  @State private var expanded: String?
  @Environment(\.rabbisirCopy) private var copy

  var body: some View {
    SettingsContentGroup {
      HStack {
        Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
        TextField(copy.plugins.search, text: $query)
          .textFieldStyle(.roundedBorder)
      }
      HStack {
        Text(copy.plugins.inventory)
          .rabbisirTypography(NativeSettingsTypography.sectionTitle)
        Spacer()
        Text("\(filtered.count)").foregroundStyle(.secondary).monospacedDigit()
      }
      if let failure = store.pluginInventoryFailure {
        Text("\(copy.plugins.readFailurePrefix) \(failure)").foregroundStyle(.red)
        Button(copy[.retry]) { Task { await store.reloadPluginInventory() } }
      } else if store.pluginInventory.isEmpty {
        Text(copy.plugins.none).foregroundStyle(.secondary)
      } else if filtered.isEmpty {
        Text(copy.plugins.noMatches).foregroundStyle(.secondary)
      } else {
        ForEach(filtered) { entry in
          Divider()
          Button {
            expanded = expanded == entry.id ? nil : entry.id
          } label: {
            HStack {
              Text(shortName(entry.moduleName))
                .rabbisirTypography(NativeSettingsTypography.body)
              Spacer()
              if entry.enabled {
                Circle().fill(phaseColor(entry.fiberPhase)).frame(width: 7, height: 7)
              }
              Text(entry.enabled ? copy.plugins.enabled : copy.plugins.disabled)
                .rabbisirTypography(NativeSettingsTypography.caption)
                .foregroundStyle(.secondary)
              Image(systemName: "chevron.down")
                .rotationEffect(.degrees(expanded == entry.id ? 180 : 0))
            }
            .contentShape(Rectangle())
          }
          .buttonStyle(.plain)
          .accessibilityLabel(
            "\(shortName(entry.moduleName)), \(entry.enabled ? phaseLabel(entry.fiberPhase) : copy.plugins.disabled)"
          )
          if expanded == entry.id {
            Text(entry.entryId)
              .rabbisirTypography(NativeSettingsTypography.identifier)
              .textSelection(.enabled)
            LabeledContent(
              copy.plugins.configurationStatus,
              value: entry.enabled ? copy.plugins.enabled : copy.plugins.disabled)
            if entry.enabled {
              LabeledContent(copy.plugins.cordisStatus, value: phaseLabel(entry.fiberPhase))
            }
          }
        }
      }
    }
  }

  private var filtered: [UpstreamPluginInventoryEntry] {
    let term = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    guard !term.isEmpty else { return store.pluginInventory }
    return store.pluginInventory.filter {
      $0.entryId.lowercased().contains(term) || $0.moduleName.lowercased().contains(term)
    }
  }

  private func shortName(_ value: String) -> String {
    var name = value
    if name.hasPrefix("@"), let slash = name.firstIndex(of: "/") {
      name = String(name[name.index(after: slash)...])
    }
    for prefix in ["cordis:", "cordis-plugin-", "dsh-host-", "dsh-client-", "dsh-"] {
      if name.hasPrefix(prefix) {
        name.removeFirst(prefix.count)
        break
      }
    }
    return name
  }

  private func phaseLabel(_ phase: String?) -> String {
    switch phase {
    case "pending": copy.plugins.pending
    case "loading": copy.plugins.loading
    case "active": copy.plugins.active
    case "failed": copy.plugins.failed
    case "unloading": copy.plugins.unloading
    default: copy.plugins.unmounted
    }
  }

  private func phaseColor(_ phase: String?) -> Color {
    switch phase {
    case "active": .green
    case "failed": .red
    case "loading", "unloading": .orange
    default: .secondary
    }
  }
}
