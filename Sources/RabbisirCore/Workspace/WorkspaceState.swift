import Combine
import Foundation

@MainActor
public final class WorkspaceState: ObservableObject {
  public enum DetailKind: String, CaseIterable, Identifiable {
    case artifact
    case sessionLog = "Session Log"

    public var id: Self { self }
  }

  public enum WebStatus: Equatable {
    case loading
    case ready
    case unavailable(String)

    func label(copy: RabbisirCopy) -> String {
      switch self {
      case .loading:
        copy.runtimePreparing
      case .ready:
        copy.runtimeReady
      case .unavailable(let message):
        copy.runtimeUnavailable(message)
      }
    }
  }

  @Published public var isSidebarVisible = true
  @Published public var isDetailsVisible = true
  @Published public var detailKind: DetailKind = .artifact
  @Published public var conversationTitle = RabbisirCopy(
    language: RabbisirLocalization.shared.language
  ).currentConversationTitle
  @Published public var webStatus: WebStatus = .loading
  @Published public var inputDraft = ""
  @Published var artifactDocument: UpstreamMarkdownDocument?
  @Published private(set) var artifactDraft = ""
  @Published private(set) var pendingArtifactDocument: UpstreamMarkdownDocument?
  @Published var artifactFailureMessage: String?
  @Published private(set) var detailFocusRequest = 0
  @Published private(set) var isArtifactSaving = false
  @Published private(set) var isArtifactOpeningExternally = false
  @Published private(set) var isArtifactReloading = false
  @Published private(set) var composerTextHeight = ComposerInputLayout.minimumTextViewportHeight
  @Published public private(set) var browserControlPhase: BrowserControlPhase = .idle
  @Published public private(set) var inputFocusRequest = 0
  @Published private(set) var sidebarHandleHoveredProjectID: String?
  private var artifactSaveHandler:
    ((UpstreamMarkdownDocument, String) async throws -> UpstreamMarkdownDocument)?
  private var artifactOpenExternalHandler: ((UpstreamMarkdownDocument) async throws -> Void)?
  private var artifactReloadHandler:
    ((UpstreamMarkdownDocument) async throws -> UpstreamMarkdownDocument)?

  public init() {}

  var isArtifactDirty: Bool {
    guard let artifactDocument else { return false }
    return artifactDraft != artifactDocument.content
  }

  public func toggleSidebar() {
    isSidebarVisible.toggle()
  }

  public func toggleDetails() {
    isDetailsVisible.toggle()
  }

  public func showDetails(_ kind: DetailKind) {
    detailKind = kind
    isDetailsVisible = true
  }

  func showArtifact(_ document: UpstreamMarkdownDocument) {
    if let current = artifactDocument,
      isArtifactDirty,
      current != document
    {
      pendingArtifactDocument = document
      artifactFailureMessage = nil
      showDetails(.artifact)
      requestDetailsFocus()
      return
    }
    applyArtifact(document)
  }

  func updateArtifactDraft(_ content: String) {
    artifactDraft = content
  }

  func cancelPendingArtifactSwitch() {
    pendingArtifactDocument = nil
  }

  func discardDraftAndShowPendingArtifact() {
    guard let pendingArtifactDocument else { return }
    applyArtifact(pendingArtifactDocument)
  }

  @discardableResult
  func saveDraftAndShowPendingArtifact() async -> Bool {
    guard let pendingArtifactDocument else { return false }
    guard await saveArtifact(content: artifactDraft) else { return false }
    guard self.pendingArtifactDocument == pendingArtifactDocument else { return false }
    applyArtifact(pendingArtifactDocument)
    return true
  }

  private func applyArtifact(_ document: UpstreamMarkdownDocument) {
    artifactDocument = document
    artifactDraft = document.content
    pendingArtifactDocument = nil
    artifactFailureMessage = nil
    showDetails(.artifact)
    requestDetailsFocus()
  }

  func showArtifactFailure(_ message: String) {
    artifactFailureMessage = message
    showDetails(.artifact)
    requestDetailsFocus()
  }

  private func requestDetailsFocus() {
    detailFocusRequest &+= 1
  }

  func configureArtifactActions(
    save: @escaping (UpstreamMarkdownDocument, String) async throws -> UpstreamMarkdownDocument,
    openExternal: @escaping (UpstreamMarkdownDocument) async throws -> Void,
    reload: @escaping (UpstreamMarkdownDocument) async throws -> UpstreamMarkdownDocument
  ) {
    artifactSaveHandler = save
    artifactOpenExternalHandler = openExternal
    artifactReloadHandler = reload
  }

  @discardableResult
  func saveArtifact(content: String) async -> Bool {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    guard let document = artifactDocument, let artifactSaveHandler else {
      artifactFailureMessage = copy.artifactUnavailableToSave
      return false
    }
    guard !isArtifactSaving else { return false }
    isArtifactSaving = true
    artifactFailureMessage = nil
    defer { isArtifactSaving = false }
    do {
      let saved = try await artifactSaveHandler(document, content)
      artifactDocument = saved
      artifactDraft = saved.content
      return true
    } catch is CancellationError {
      return false
    } catch {
      artifactFailureMessage = copy.artifactSaveFailed
      return false
    }
  }

  func openArtifactExternally() async {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    guard let document = artifactDocument, let artifactOpenExternalHandler else {
      artifactFailureMessage = copy.artifactUnavailableToOpen
      return
    }
    guard !isArtifactOpeningExternally else { return }
    isArtifactOpeningExternally = true
    artifactFailureMessage = nil
    defer { isArtifactOpeningExternally = false }
    do {
      try await artifactOpenExternalHandler(document)
    } catch is CancellationError {
      return
    } catch {
      artifactFailureMessage = copy.artifactOpenFailed
    }
  }

  @discardableResult
  func reloadArtifact(discardingUnsavedChanges: Bool = false) async -> Bool {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    guard let document = artifactDocument, let artifactReloadHandler else {
      artifactFailureMessage = copy.artifactUnavailableToRefresh
      return false
    }
    guard !isArtifactDirty || discardingUnsavedChanges else { return false }
    guard !isArtifactReloading else { return false }
    isArtifactReloading = true
    artifactFailureMessage = nil
    defer { isArtifactReloading = false }
    do {
      let reloaded = try await artifactReloadHandler(document)
      artifactDocument = reloaded
      artifactDraft = reloaded.content
      return true
    } catch is CancellationError {
      return false
    } catch {
      artifactFailureMessage = copy.artifactRefreshFailed
      return false
    }
  }

  public func requestInputFocus() {
    inputFocusRequest &+= 1
  }

  func updateComposerTextHeight(_ height: CGFloat) {
    let resolved = max(ComposerInputLayout.minimumTextViewportHeight, height)
    guard abs(resolved - composerTextHeight) > 0.5 else { return }
    composerTextHeight = resolved
  }

  public func browserControlDidBegin() {
    browserControlPhase = .active
  }

  public func browserControlDidFail(reason: String) {
    guard browserControlPhase == .active else { return }
    let trimmedReason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    browserControlPhase = .failed(
      trimmedReason.isEmpty ? copy.unknownBrowserControlError : trimmedReason)
  }

  public func browserControlDidEnd() {
    browserControlPhase = .idle
  }

  func setSidebarHandleHoveredProjectID(_ projectID: String?) {
    guard sidebarHandleHoveredProjectID != projectID else { return }
    sidebarHandleHoveredProjectID = projectID
  }
}
