import SwiftUI

enum NativeSettingsTypography {
  static let root: RabbisirTypographyRole = .body
  static let navigation: RabbisirTypographyRole = .body
  static let pageTitle: RabbisirTypographyRole = .pageTitle
  static let sectionTitle: RabbisirTypographyRole = .sectionTitle
  static let rowTitle: RabbisirTypographyRole = .headline
  static let body: RabbisirTypographyRole = .body
  static let supporting: RabbisirTypographyRole = .callout
  static let caption: RabbisirTypographyRole = .caption
  static let badge: RabbisirTypographyRole = .badge
  static let identifier: RabbisirTypographyRole = .codeCaption
  static let codeBody: RabbisirTypographyRole = .codeBody
  static let sheetTitle: RabbisirTypographyRole = .sheetTitle
}

enum NativeSettingsSection: String, CaseIterable, Identifiable {
  case general
  case models
  case plugins
  case agentPresets

  var id: String { rawValue }

  func title(copy: RabbisirCopy) -> String {
    switch self {
    case .general: copy[.settingsGeneral]
    case .models: copy[.settingsModels]
    case .plugins: copy[.settingsPlugins]
    case .agentPresets: copy[.settingsAgentPresets]
    }
  }

  var symbol: String {
    switch self {
    case .general: "gearshape"
    case .models: "cpu"
    case .plugins: "puzzlepiece.extension"
    case .agentPresets: "person.crop.rectangle.stack"
    }
  }
}

struct NativeSettingsRootView: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var store: NativeSettingsStore
  let close: () -> Void
  @State private var selection: NativeSettingsSection = .general

  var body: some View {
    HStack(spacing: 0) {
      ScrollView {
        VStack(spacing: 4) {
          ForEach(NativeSettingsSection.allCases) { section in
            NativeSettingsNavigationRow(
              section: section,
              isSelected: selection == section,
              select: { selection = section }
            )
          }
        }
        .padding(10)
      }
      .frame(width: 220)

      Divider()
        .opacity(0.34)

      Group {
        switch selection {
        case .general:
          GeneralSettingsView(store: store)
        case .models:
          ModelSettingsView(store: store)
        case .plugins:
          PluginSettingsView(store: store)
        case .agentPresets:
          AgentPresetSettingsView(store: store)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.clear)
    }
    .frame(minWidth: 880, minHeight: 620)
    .rabbisirTypography(NativeSettingsTypography.root)
    .background(Color.clear)
    .toolbar {
      ToolbarItem(placement: .primaryAction) {
        Button(copy[.done], action: close)
          .keyboardShortcut(.defaultAction)
      }
    }
    .task {
      if store.status == .idle { await store.load() }
    }
    .overlay {
      if store.status == .loading {
        ProgressView(copy[.settingsLoading])
          .padding(22)
          .rabbisirGlassSurface(cornerRadius: 18)
      }
    }
  }
}

private struct NativeSettingsNavigationRow: View {
  @Environment(\.rabbisirCopy) private var copy
  private enum Metrics {
    static let horizontalPadding: CGFloat = 10
    static let iconSize: CGFloat = 15
    static let iconSlotWidth: CGFloat = 18
    static let rowHeight: CGFloat = 32
    static let spacing: CGFloat = 7
  }

  let section: NativeSettingsSection
  let isSelected: Bool
  let select: () -> Void
  @State private var isHovered = false

  var body: some View {
    Button(action: select) {
      HStack(alignment: .center, spacing: Metrics.spacing) {
        Image(systemName: section.symbol)
          .font(.system(size: Metrics.iconSize, weight: .regular))
          .frame(width: Metrics.iconSlotWidth, height: Metrics.rowHeight, alignment: .center)
        Text(section.title(copy: copy))
          .rabbisirTypography(NativeSettingsTypography.navigation)
          .lineLimit(1)
        Spacer(minLength: 0)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Metrics.horizontalPadding)
      .frame(height: Metrics.rowHeight)
      .contentShape(Rectangle())
      .background {
        RoundedRectangle(cornerRadius: 8, style: .continuous)
          .fill(
            Color.primary.opacity(
              isSelected ? 0.12 : (isHovered ? 0.065 : 0)
            )
          )
      }
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

struct SettingsPage<Content: View>: View {
  let title: String
  let subtitle: String?
  @ViewBuilder let content: () -> Content

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: 22) {
        VStack(alignment: .leading, spacing: 5) {
          Text(title).rabbisirTypography(NativeSettingsTypography.pageTitle)
          if let subtitle {
            Text(subtitle)
              .rabbisirTypography(NativeSettingsTypography.supporting)
              .foregroundStyle(.secondary)
          }
        }
        content()
      }
      .frame(maxWidth: 720, alignment: .leading)
      .padding(32)
      .frame(maxWidth: .infinity, alignment: .topLeading)
    }
    .background(Color.clear)
  }
}

struct SettingsContentGroup<Content: View>: View {
  @ViewBuilder let content: () -> Content

  var body: some View {
    VStack(alignment: .leading, spacing: 14, content: content)
      .padding(.vertical, 12)
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .bottom) {
        Divider().opacity(0.42)
      }
  }
}

struct SettingsStatusView: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var store: NativeSettingsStore

  var body: some View {
    if case .failed(let message) = store.status {
      SettingsContentGroup {
        Label(copy[.settingsLoadFailed], systemImage: "exclamationmark.triangle.fill")
          .foregroundStyle(.red)
        Text(message)
          .rabbisirTypography(NativeSettingsTypography.supporting)
          .textSelection(.enabled)
        Button(copy[.retry]) { Task { await store.load() } }
      }
    } else if let message = store.actionMessage {
      Label(message, systemImage: store.actionMessageIsError ? "xmark.circle" : "checkmark.circle")
        .rabbisirTypography(NativeSettingsTypography.supporting)
        .foregroundStyle(store.actionMessageIsError ? .red : .secondary)
        .accessibilityLabel(message)
    }
  }
}

private struct GeneralSettingsView: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var store: NativeSettingsStore

  var body: some View {
    SettingsPage(
      title: copy[.settingsGeneral],
      subtitle: nil
    ) {
      SettingsStatusView(store: store)
      SettingsChoiceRow(
        store: store,
        title: copy[.settingsEnterBehavior],
        subtitle: copy[.settingsEnterBehaviorDescription],
        namespace: "ui-conversation",
        key: "busyEnter",
        fallbackOptions: [("queue", copy[.settingsQueue]), ("steer", copy[.settingsSteer])]
      )
      SettingsChoiceRow(
        store: store,
        title: copy[.settingsDefaultPermission],
        subtitle: copy[.settingsDefaultPermissionDescription],
        namespace: "permission",
        key: "defaultPreset",
        fallbackOptions: []
      )
    }
  }

}

enum RabbisirSettingsOptionLocalization {
  static func label(
    namespace: String,
    id: String,
    upstreamLabel: String,
    copy: RabbisirCopy
  ) -> String {
    switch (namespace, id) {
    case ("ui-conversation", "queue"):
      copy[.settingsQueue]
    case ("ui-conversation", "steer"):
      copy[.settingsSteer]
    case ("permission", _):
      copy.composerPermissionName(upstreamLabel)
    default:
      upstreamLabel
    }
  }
}

private struct SettingsChoiceRow: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var store: NativeSettingsStore
  let title: String
  let subtitle: String
  let namespace: String
  let key: String
  let fallbackOptions: [(String, String)]

  var body: some View {
    let advertised = store.stringOptions(namespace: namespace, key: key)
    let options =
      advertised.isEmpty
      ? fallbackOptions.map { (id: $0.0, label: $0.1) }
      : advertised
    let current = store.string(namespace: namespace, key: key) ?? ""
    SettingsContentGroup {
      HStack(alignment: .center, spacing: 24) {
        VStack(alignment: .leading, spacing: 4) {
          Text(title).rabbisirTypography(NativeSettingsTypography.rowTitle)
          Text(subtitle)
            .rabbisirTypography(NativeSettingsTypography.supporting)
            .foregroundStyle(.secondary)
          if store.namespaces[namespace] == nil {
            Text(copy[.settingsUnavailable])
              .rabbisirTypography(NativeSettingsTypography.supporting)
              .foregroundStyle(.secondary)
          }
        }
        Spacer(minLength: 16)
        if store.namespaces[namespace] != nil {
          Picker(
            title,
            selection: Binding(
              get: { current },
              set: { value in
                Task {
                  _ = await store.setString(
                    namespace: namespace,
                    key: key,
                    value: value.isEmpty ? nil : value
                  )
                }
              }
            )
          ) {
            ForEach(options, id: \.id) { option in
              Text(optionLabel(option)).tag(option.id)
            }
          }
          .labelsHidden()
          .disabled(!store.writable || store.isWriting)
          .frame(width: 210, alignment: .trailing)
        }
      }
    }
  }

  private func optionLabel(_ option: (id: String, label: String)) -> String {
    RabbisirSettingsOptionLocalization.label(
      namespace: namespace,
      id: option.id,
      upstreamLabel: option.label,
      copy: copy
    )
  }
}

private struct ModelSettingsView: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var store: NativeSettingsStore
  @State private var apiKey = ""
  @State private var confirmingRemoval = false

  var body: some View {
    SettingsPage(
      title: copy[.settingsModels],
      subtitle: copy[.settingsModelDescription]
    ) {
      SettingsStatusView(store: store)
      SettingsContentGroup {
        HStack {
          VStack(alignment: .leading, spacing: 4) {
            Text("DeepSeek API Key").rabbisirTypography(NativeSettingsTypography.rowTitle)
            Text(credentialDescription)
              .rabbisirTypography(NativeSettingsTypography.supporting)
              .foregroundStyle(.secondary)
          }
          Spacer()
          Circle()
            .fill(store.deepSeekCredential?.configured == true ? .green : .secondary)
            .frame(width: 8, height: 8)
            .accessibilityLabel(
              store.deepSeekCredential?.configured == true
                ? copy[.settingsConfigured]
                : copy[.settingsNotConfigured]
            )
        }
        SecureField(copy[.settingsEnterAPIKey], text: $apiKey)
          .textFieldStyle(.roundedBorder)
          .disabled(store.deepSeekCredential?.writable == false || store.isWriting)
        HStack {
          Button(copy[.save]) {
            Task {
              if await store.setDeepSeekCredential(apiKey) { apiKey = "" }
            }
          }
          .disabled(
            apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isWriting)
          if store.deepSeekCredential?.configured == true {
            Button(copy[.settingsDeleteKey], role: .destructive) { confirmingRemoval = true }
              .disabled(store.deepSeekCredential?.writable == false || store.isWriting)
          }
        }
      }
      if let modelID = store.currentDefaultModelID {
        SettingsContentGroup {
          Text(copy[.settingsCurrentModel])
            .rabbisirTypography(NativeSettingsTypography.rowTitle)
          Text(store.currentDefaultModel?.name ?? modelID)
            .rabbisirTypography(NativeSettingsTypography.body)
          Text(modelID)
            .rabbisirTypography(NativeSettingsTypography.identifier)
            .foregroundStyle(.secondary)
          Text(copy[.settingsCurrentModelDescription])
            .rabbisirTypography(NativeSettingsTypography.supporting)
            .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(
          "\(copy[.settingsCurrentModel])：\(store.currentDefaultModel?.name ?? modelID)"
        )
      }
      ForEach(store.modelGroups) { group in
        SettingsContentGroup {
          Text(group.name).rabbisirTypography(NativeSettingsTypography.rowTitle)
          ForEach(group.models) { model in
            VStack(alignment: .leading, spacing: 5) {
              Text(model.name).rabbisirTypography(NativeSettingsTypography.body)
              Text(model.id)
                .rabbisirTypography(NativeSettingsTypography.identifier)
                .foregroundStyle(.secondary)
              if let efforts = model.reasoning?.efforts, !efforts.isEmpty {
                Text(
                  "\(copy[.settingsReasoningLevel])：\(efforts.map(\.name).joined(separator: " · "))"
                )
                .rabbisirTypography(NativeSettingsTypography.caption)
                .foregroundStyle(.secondary)
              }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if model.id != group.models.last?.id { Divider() }
          }
        }
      }
      if store.modelGroups.isEmpty, store.status == .ready {
        SettingsContentGroup {
          Text(copy[.settingsNoModels])
          if !store.modelFailures.isEmpty {
            Text(store.modelCatalogFailureMessage)
              .rabbisirTypography(NativeSettingsTypography.caption)
              .foregroundStyle(.red)
          }
        }
      }
    }
    .alert(copy[.settingsDeleteKeyTitle], isPresented: $confirmingRemoval) {
      Button(copy[.cancel], role: .cancel) {}
      Button(copy[.delete], role: .destructive) {
        Task { _ = await store.removeDeepSeekCredential() }
      }
    } message: {
      Text(copy[.settingsDeleteKeyMessage])
    }
  }

  private var credentialDescription: String {
    guard let credential = store.deepSeekCredential else {
      return copy[.settingsReadingConfiguration]
    }
    return credential.configured
      ? copy[.settingsConfiguredInRabbisir]
      : copy[.settingsConfigureAPIKey]
  }
}
