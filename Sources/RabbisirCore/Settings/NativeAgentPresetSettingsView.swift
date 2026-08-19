import SwiftUI

struct AgentPresetSettingsView: View {
  @ObservedObject var store: NativeSettingsStore
  @State private var viewedDocument: UpstreamAgentPresetDocument?
  @State private var copySource: UpstreamAgentPresetEntry?
  @State private var deleteCandidate: UpstreamAgentPresetEntry?
  @State private var revealedPaths: [String: String] = [:]
  @Environment(\.rabbisirCopy) private var copy

  var body: some View {
    SettingsPage(
      title: copy.agentPresets.pageTitle,
      subtitle: copy.agentPresets.pageSubtitle
    ) {
      SettingsStatusView(store: store)
      if store.agentPresets.isEmpty {
        SettingsContentGroup {
          Text(copy.agentPresets.none)
            .foregroundStyle(.secondary)
        }
      } else {
        presetGroup(title: copy.agentPresets.builtIn, trust: "system")
        presetGroup(title: copy.agentPresets.custom, trust: "user")
      }
    }
    .sheet(item: $viewedDocument) { document in
      AgentPresetDocumentSheet(document: document) {
        viewedDocument = nil
      }
    }
    .sheet(item: $copySource) { source in
      AgentPresetCopySheet(store: store, source: source) {
        copySource = nil
      }
    }
    .alert(
      copy.agentPresets.deleteTitle,
      isPresented: Binding(
        get: { deleteCandidate != nil },
        set: { if !$0 { deleteCandidate = nil } }
      ),
      presenting: deleteCandidate
    ) { preset in
      Button(copy[.cancel], role: .cancel) { deleteCandidate = nil }
      Button(copy[.delete], role: .destructive) {
        Task {
          if await store.removeAgentPreset(id: preset.id) { deleteCandidate = nil }
        }
      }
    } message: { _ in
      Text(copy.agentPresets.deleteMessage)
    }
  }

  @ViewBuilder
  private func presetGroup(title: String, trust: String) -> some View {
    let rows = store.agentPresets.filter { $0.trust == trust }
    if !rows.isEmpty || trust == "user" {
      SettingsContentGroup {
        Text(title).rabbisirTypography(NativeSettingsTypography.sectionTitle)
        if rows.isEmpty {
          Text(
            store.agentPresetAuthorable
              ? copy.agentPresets.noCustom : copy.agentPresets.cannotCreate
          )
          .rabbisirTypography(NativeSettingsTypography.supporting)
          .foregroundStyle(.secondary)
        }
        ForEach(rows) { preset in
          AgentPresetRow(
            preset: preset,
            authorable: store.agentPresetAuthorable,
            hasDocument: store.agentPresetHasDocument,
            revealedPath: revealedPaths[preset.id],
            setDefault: {
              Task { _ = await store.makeDefaultAgentPreset(id: preset.id) }
            },
            view: { Task { await view(preset) } },
            copy: { copySource = preset },
            open: { Task { await open(preset) } },
            remove: { deleteCandidate = preset }
          )
          if preset.id != rows.last?.id { Divider() }
        }
      }
    }
  }

  private func view(_ preset: UpstreamAgentPresetEntry) async {
    do {
      viewedDocument = try await store.readAgentPreset(id: preset.id)
    } catch {
      // Store actions own the persistent status surface; this sheet remains closed on refusal.
    }
  }

  private func open(_ preset: UpstreamAgentPresetEntry) async {
    do {
      let result = try await store.openAgentPreset(id: preset.id)
      if !result.opened, let path = result.path { revealedPaths[preset.id] = path }
    } catch {
      // The Host is the authority on whether this deployment can reveal the location.
    }
  }
}

private struct AgentPresetRow: View {
  let preset: UpstreamAgentPresetEntry
  let authorable: Bool
  let hasDocument: Bool
  let revealedPath: String?
  let setDefault: () -> Void
  let view: () -> Void
  let copy: () -> Void
  let open: () -> Void
  let remove: () -> Void
  @Environment(\.rabbisirCopy) private var localized

  var body: some View {
    VStack(alignment: .leading, spacing: 9) {
      Button(action: setDefault) {
        HStack(alignment: .top, spacing: 12) {
          VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 7) {
              Text(displayName).rabbisirTypography(NativeSettingsTypography.rowTitle)
              badge(
                preset.trust == "system"
                  ? localized.agentPresets.builtIn : localized.agentPresets.custom)
              if preset.isDefault { badge(localized.agentPresets.current) }
              if preset.broken != nil { badge(localized.agentPresets.loadFailed, color: .red) }
            }
            Text(displayDescription)
              .rabbisirTypography(NativeSettingsTypography.supporting)
              .foregroundStyle(.secondary)
            Text(preset.id)
              .rabbisirTypography(NativeSettingsTypography.identifier)
              .foregroundStyle(.secondary)
            if preset.broken != nil {
              Text(localized.agentPresets.loadFailed)
                .rabbisirTypography(NativeSettingsTypography.caption)
                .foregroundStyle(.red)
            }
          }
          Spacer(minLength: 8)
          if preset.isDefault { Image(systemName: "checkmark.circle.fill").foregroundStyle(.green) }
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .disabled(preset.isDefault || preset.broken != nil)
      .accessibilityLabel(
        "\(preset.isDefault ? localized.agentPresets.current : localized.agentPresets.setDefault): \(displayName)"
      )

      HStack(spacing: 10) {
        if preset.trust == "system", preset.broken == nil {
          Button(localized.agentPresets.view, systemImage: "doc.text.magnifyingglass", action: view)
        }
        if preset.trust == "user" {
          Button(
            hasDocument ? localized.agentPresets.openDirectory : localized.agentPresets.viewPath,
            systemImage: "folder", action: open)
        }
        Button(localized[.copy], systemImage: "doc.on.doc", action: copy)
          .disabled(!authorable || preset.broken != nil)
        if preset.trust == "user" {
          Button(localized[.delete], systemImage: "trash", role: .destructive, action: remove)
        }
      }
      .labelStyle(.titleAndIcon)
      .controlSize(.small)
      if let revealedPath {
        Text("\(localized.agentPresets.presetFilePrefix)\(revealedPath)")
          .rabbisirTypography(NativeSettingsTypography.identifier)
          .textSelection(.enabled)
      }
    }
    .padding(.vertical, 4)
  }

  private var displayName: String {
    guard preset.trust == "system" else { return preset.displayName }
    return localized.agentPresets.builtInName(id: preset.id, fallback: preset.displayName)
  }

  private var displayDescription: String {
    if let description = preset.description, !description.isEmpty {
      guard preset.trust == "system" else { return description }
      return localized.agentPresets.builtInDescription(id: preset.id, fallback: description)
    }
    return localized.agentPresets.noDescription
  }

  private func badge(_ text: String, color: Color = .secondary) -> some View {
    Text(text)
      .rabbisirTypography(NativeSettingsTypography.badge)
      .foregroundStyle(color)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(color.opacity(0.1), in: Capsule())
  }
}

private struct AgentPresetDocumentSheet: View {
  let document: UpstreamAgentPresetDocument
  let close: () -> Void
  @Environment(\.rabbisirCopy) private var copy

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("\(copy.agentPresets.view) · \(documentTitle)")
        .rabbisirTypography(NativeSettingsTypography.sheetTitle)
      Text(copy.agentPresets.assembly).foregroundStyle(.secondary)
      ScrollView {
        Text(document.content)
          .rabbisirTypography(NativeSettingsTypography.codeBody)
          .textSelection(.enabled)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack {
        Spacer()
        Button(copy[.close], action: close).keyboardShortcut(.defaultAction)
      }
    }
    .padding(24)
    .frame(width: 660, height: 520)
  }

  private var documentTitle: String {
    copy.agentPresets.builtInName(
      id: document.agentPreset,
      fallback: document.name ?? document.agentPreset
    )
  }
}

private struct AgentPresetCopySheet: View {
  @ObservedObject var store: NativeSettingsStore
  let source: UpstreamAgentPresetEntry
  let close: () -> Void
  @State private var id = ""
  @State private var name = ""
  @Environment(\.rabbisirCopy) private var copy

  var body: some View {
    VStack(alignment: .leading, spacing: 16) {
      Text("\(copy.agentPresets.copyTitlePrefix)\(sourceTitle)")
        .rabbisirTypography(NativeSettingsTypography.sheetTitle)
      Text(copy.agentPresets.copyDescription)
        .foregroundStyle(.secondary)
      TextField(copy.agentPresets.identifierPlaceholder, text: $id)
      TextField(copy.agentPresets.namePlaceholder, text: $name)
      if let validationMessage {
        Text(validationMessage)
          .rabbisirTypography(NativeSettingsTypography.supporting)
          .foregroundStyle(.red)
      }
      HStack {
        Spacer()
        Button(copy[.cancel], role: .cancel, action: close)
        Button(copy[.create]) {
          Task {
            let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
            if await store.copyAgentPreset(
              from: source.id,
              id: id,
              name: trimmedName.isEmpty ? nil : trimmedName
            ) {
              close()
            }
          }
        }
        .keyboardShortcut(.defaultAction)
        .disabled(validationMessage != nil || store.isWriting)
      }
    }
    .padding(24)
    .frame(width: 480)
  }

  private var sourceTitle: String {
    guard source.trust == "system" else { return source.displayName }
    return copy.agentPresets.builtInName(id: source.id, fallback: source.displayName)
  }

  private var validationMessage: String? {
    if id.isEmpty { return copy.agentPresets.identifierRequired }
    if id.range(of: "^[a-z0-9][a-z0-9-]*$", options: .regularExpression) == nil {
      return copy.agentPresets.identifierInvalid
    }
    if store.agentPresets.contains(where: { $0.id == id }) {
      return copy.agentPresets.identifierUsed
    }
    return nil
  }
}
