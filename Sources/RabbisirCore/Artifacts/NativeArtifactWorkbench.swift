import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Native adaptation of the original Rabbisir Markdown artifact workbench.
struct NativeArtifactWorkbench: View {
  @ObservedObject var state: WorkspaceState
  let document: UpstreamMarkdownDocument
  @State private var mode: ArtifactWorkbenchMode = .markdown
  @State private var copied = false
  @State private var exportFailure: String?
  @State private var isReloadConfirmationPresented = false
  @Environment(\.rabbisirCopy) private var copy

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      toolbar

      Group {
        switch mode {
        case .editor:
          sourceEditor
        case .plain:
          plainProjection
        case .markdown:
          markdownProjection
        case .document:
          ArtifactPagedDocumentPreview(markdown: draft, style: .document)
        case .pdf:
          ArtifactPagedDocumentPreview(markdown: draft, style: .pdf)
        }
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)

      if let failureMessage {
        Label(failureMessage, systemImage: "exclamationmark.triangle")
          .font(.caption)
          .foregroundStyle(.red)
          .padding(.horizontal, 12)
          .padding(.vertical, 8)
      }
    }
    .alert(
      copy.artifacts.unsavedSwitchTitle,
      isPresented: pendingSwitchPresentation
    ) {
      Button(copy.artifacts.saveAndSwitch) {
        Task { await state.saveDraftAndShowPendingArtifact() }
      }
      Button(copy.artifacts.discardAndSwitch, role: .destructive) {
        state.discardDraftAndShowPendingArtifact()
      }
      Button(copy[.cancel], role: .cancel) {
        state.cancelPendingArtifactSwitch()
      }
    } message: {
      Text(copy.artifacts.unsavedSwitchMessage)
    }
    .alert(
      copy.artifacts.reloadDiscardTitle,
      isPresented: $isReloadConfirmationPresented
    ) {
      Button(copy.artifacts.discardAndReload, role: .destructive) {
        Task { await reload(discardingUnsavedChanges: true) }
      }
      Button(copy[.cancel], role: .cancel) {}
    } message: {
      Text(copy.artifacts.reloadDiscardMessage)
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(copy.artifacts.workspace)
  }

  private var toolbar: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack(alignment: .center, spacing: 8) {
        Picker(copy.artifacts.viewPicker, selection: $mode) {
          ForEach(ArtifactWorkbenchMode.allCases) { mode in
            Text(mode.title(copy: copy.artifacts)).tag(mode)
          }
        }
        .pickerStyle(.segmented)
        .fixedSize()

        Spacer(minLength: 8)
      }

      HStack(alignment: .center, spacing: 8) {
        Button(copied ? copy[.artifactCopied] : copy[.artifactCopy]) { copyVisibleProjection() }
          .disabled(draft.isEmpty)
        Button(state.isArtifactSaving ? copy.artifacts.saving : copy[.artifactSave]) {
          Task { await save() }
        }
        .disabled(!isDirty || state.isArtifactSaving)
        Menu(copy[.artifactExport]) {
          ForEach(ArtifactExportFormat.allCases) { format in
            Button(format.title(copy: copy.artifacts)) { export(format) }
          }
        }
        .disabled(draft.isEmpty)
        Button(state.isArtifactReloading ? copy.artifacts.refreshing : copy[.artifactRefresh]) {
          requestReload()
        }
        .disabled(state.isArtifactReloading)
        Button(copy[.artifactPrint]) { printDocument() }
          .disabled(draft.isEmpty)
        Button(copy[.artifactOpenExternal]) {
          Task { await state.openArtifactExternally() }
        }
        .disabled(state.isArtifactOpeningExternally)
        Spacer(minLength: 0)
      }
      .buttonStyle(.borderless)

      HStack(spacing: 10) {
        Text(URL(fileURLWithPath: document.path).lastPathComponent)
          .font(.caption.weight(.semibold))
          .lineLimit(1)
        Text(ByteCountFormatter.string(fromByteCount: Int64(document.bytes), countStyle: .file))
        Text(Date(timeIntervalSince1970: document.modifiedAt), style: .relative)
      }
      .font(.caption)
      .foregroundStyle(NativePanelContentPalette.secondary)
    }
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
  }

  private var plainProjection: some View {
    ScrollView(.vertical, showsIndicators: false) {
      Text(ArtifactDocumentProjection.plainText(from: draft))
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(16)
    }
    .scrollIndicators(.hidden)
    .accessibilityLabel(copy.artifacts.plainView)
  }

  private var markdownProjection: some View {
    ScrollView(.vertical, showsIndicators: false) {
      Text(markdownPreview)
        .frame(maxWidth: .infinity, alignment: .leading)
        .textSelection(.enabled)
        .padding(16)
    }
    .scrollIndicators(.hidden)
    .accessibilityLabel(copy.artifacts.markdownPreview)
  }

  private var sourceEditor: some View {
    TextEditor(text: artifactDraftBinding)
      .font(.body.monospaced())
      .scrollContentBackground(.hidden)
      .scrollIndicators(.hidden)
      .padding(10)
      .accessibilityLabel(copy.artifacts.editor)
  }

  private var isDirty: Bool {
    state.isArtifactDirty
  }

  private var draft: String { state.artifactDraft }

  private var artifactDraftBinding: Binding<String> {
    Binding(
      get: { state.artifactDraft },
      set: { state.updateArtifactDraft($0) }
    )
  }

  private var pendingSwitchPresentation: Binding<Bool> {
    Binding(
      get: { state.pendingArtifactDocument != nil },
      set: { presented in
        if !presented { state.cancelPendingArtifactSwitch() }
      }
    )
  }

  private var markdownPreview: AttributedString {
    (try? AttributedString(
      markdown: draft,
      options: .init(interpretedSyntax: .full)
    )) ?? AttributedString(draft)
  }

  private var failureMessage: String? {
    state.artifactFailureMessage ?? exportFailure
  }

  private func copyVisibleProjection() {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    let content = ArtifactDocumentProjection.copyContent(
      for: mode,
      markdown: draft
    )
    copied = pasteboard.setString(content, forType: .string)
    guard copied else { return }
    Task { @MainActor in
      try? await Task.sleep(for: .seconds(1.5))
      copied = false
    }
  }

  private func save() async {
    if await state.saveArtifact(content: draft) {
      mode = .markdown
    }
  }

  private func requestReload() {
    if state.isArtifactDirty {
      isReloadConfirmationPresented = true
    } else {
      Task { await reload(discardingUnsavedChanges: false) }
    }
  }

  private func reload(discardingUnsavedChanges: Bool) async {
    _ = await state.reloadArtifact(discardingUnsavedChanges: discardingUnsavedChanges)
  }

  private func export(_ format: ArtifactExportFormat) {
    let ext = format.pathExtension
    let sourceName = URL(fileURLWithPath: document.path)
      .deletingPathExtension()
      .lastPathComponent
    let panel = NSSavePanel()
    panel.nameFieldStringValue = "\(sourceName).\(ext)"
    panel.allowedContentTypes = [UTType(filenameExtension: ext) ?? .data]
    guard panel.runModal() == .OK, let url = panel.url else { return }
    do {
      try ArtifactDocumentExporter.write(markdown: draft, format: format, to: url)
      exportFailure = nil
    } catch {
      exportFailure = copy.artifacts.exportFailed
    }
  }

  private func printDocument() {
    let textView = NSTextView(frame: NSRect(x: 0, y: 0, width: 612, height: 792))
    textView.isEditable = false
    textView.drawsBackground = true
    textView.backgroundColor = .white
    textView.textStorage?.setAttributedString(
      ArtifactRichDocumentRenderer.attributedDocument(markdown: draft)
    )
    let operation = NSPrintOperation(view: textView)
    operation.showsPrintPanel = true
    operation.showsProgressPanel = true
    operation.run()
  }
}
