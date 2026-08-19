import Combine
import OSLog
import SwiftUI
import UniformTypeIdentifiers
import WebKit

private final class NativeConversationProjectionMessageHandler: NSObject, WKScriptMessageHandler {
  weak var owner: RuntimeBridgeStore?

  func userContentController(
    _ userContentController: WKUserContentController,
    didReceive message: WKScriptMessage
  ) {
    let body = message.body
    Task { @MainActor [weak owner] in
      owner?.receiveNativeConversationProjection(body)
    }
  }
}

enum SessionLogExportPolicy {
  static func suggestedFilename(_ suggestedFilename: String) -> String {
    guard !suggestedFilename.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return "rabbisir-session-log.zip"
    }
    let safeName = URL(fileURLWithPath: suggestedFilename).lastPathComponent
    guard !safeName.isEmpty else { return "rabbisir-session-log.zip" }
    return URL(fileURLWithPath: safeName)
      .deletingPathExtension()
      .appendingPathExtension("zip")
      .lastPathComponent
  }
}

@MainActor
final class RuntimeBridgeStore:
  NSObject,
  ObservableObject,
  WKNavigationDelegate,
  WKDownloadDelegate,
  WorkspaceAdopting
{
  private var currentCopy: RabbisirCopy {
    RabbisirCopy(language: RabbisirLocalization.shared.language)
  }
  let webView: WKWebView
  let conversation: NativeConversationStore
  @Published private(set) var composerProjection = RuntimeComposerProjection.loading
  @Published private(set) var navigationProjects: [RuntimeNavigationProject] = []
  @Published private(set) var selectedWorkspaceTitle: String?
  @Published private(set) var isNavigationLoading = true
  @Published private(set) var navigationFailure: String?
  @Published private(set) var navigationSelectionRevision: UInt64 = 0
  @Published private(set) var archivedNavigationProjectIDs: Set<String>
  @Published private(set) var isRuntimeTransitionPresented = false
  private var isRefreshingNavigation = false
  private var sessionLogDestinations: [ObjectIdentifier: URL] = [:]
  private var suppressedSessionLogDownloadFailures: Set<ObjectIdentifier> = []
  private var sessionLogProgressAlert: NSAlert?
  private let state: WorkspaceState
  private let url: URL
  private let navigationTransport: any UpstreamNavigationTransporting
  private let navigationProjectPreferences: NavigationProjectPreferencesStore
  private let nativeProjectionMessageHandler = NativeConversationProjectionMessageHandler()
  private var nativeProjectionRevision: UInt64 = 0
  private var hasAttemptedInitialSessionRestore = false
  private var localizationCancellable: AnyCancellable?

  init(state: WorkspaceState, url: URL) {
    self.state = state
    self.url = url
    conversation = NativeConversationStore(
      transport: UpstreamConversationTransport(baseURL: url),
      shellState: state
    )
    navigationTransport = UpstreamNavigationTransport(baseURL: url)
    navigationProjectPreferences = NavigationProjectPreferencesStore()
    archivedNavigationProjectIDs = navigationProjectPreferences.archivedWorkspaceIDs()

    let configuration = WKWebViewConfiguration()
    configuration.websiteDataStore = .nonPersistent()
    configuration.defaultWebpagePreferences.allowsContentJavaScript = true
    configuration.userContentController.addUserScript(
      WKUserScript(
        source: RuntimeComposerBridge.visualExtractionScript,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
      )
    )
    configuration.userContentController.addUserScript(
      WKUserScript(
        source: RuntimeNavigationBridge.settingsPolicyInstallationScript,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
      )
    )
    configuration.userContentController.addUserScript(
      WKUserScript(
        source: RuntimeNavigationBridge.nativeMenuOwnershipInstallationScript,
        injectionTime: .atDocumentEnd,
        forMainFrameOnly: true
      )
    )
    configuration.userContentController.addUserScript(
      WKUserScript(
        source: RuntimeConversationProjectionBridge.channelInstallationScript,
        injectionTime: .atDocumentStart,
        forMainFrameOnly: true
      )
    )
    webView = WKWebView(frame: .zero, configuration: configuration)
    super.init()

    localizationCancellable = RabbisirLocalization.shared.$language
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] language in
        guard let self else { return }
        let copy = RabbisirCopy(language: language)
        if self.conversation.selectedSessionID == nil {
          self.state.conversationTitle = copy.currentConversationTitle
        }
        if self.isNavigationLoading || !self.composerProjection.isAvailable {
          self.composerProjection = .loading(copy: copy)
        }
      }

    nativeProjectionMessageHandler.owner = self
    configuration.userContentController.add(
      nativeProjectionMessageHandler,
      name: RuntimeConversationProjectionBridge.messageHandlerName
    )

    conversation.setForkHandler { [weak self] childID in
      await self?.openForkedSession(childID)
    }
    conversation.setUpstreamLoadOlderHandler { [weak self] in
      await self?.loadOlderUpstreamConversation()
    }
    state.configureArtifactActions(
      save: { [weak conversation] document, content in
        guard let conversation else { throw CancellationError() }
        return try await conversation.saveMarkdownDocument(document, content: content)
      },
      openExternal: { [weak conversation] document in
        guard let conversation else { throw CancellationError() }
        try await conversation.openMarkdownDocumentExternally(document)
      },
      reload: { [weak conversation] document in
        guard let conversation else { throw CancellationError() }
        return try await conversation.reloadMarkdownDocument(document)
      }
    )

    webView.navigationDelegate = self
    webView.underPageBackgroundColor = .clear
    load()
  }

  func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
    Task { @MainActor in
      _ = try? await webView.evaluateJavaScript(
        RuntimeComposerBridge.visualExtractionScript
      )
      await refreshComposerProjection()
      await refreshNavigationProjection()
      await synchronizeNativeConversationSelection()
    }
    state.webStatus = .ready
    RabbisirLog.runtime.info("Embedded runtime bridge loaded")
  }

  func webView(
    _ webView: WKWebView,
    didFail navigation: WKNavigation!,
    withError error: any Error
  ) {
    state.webStatus = .unavailable(Self.diagnostic(for: error))
    RabbisirLog.runtime.error("Navigation failed: \(error.localizedDescription, privacy: .private)")
  }

  func webView(
    _ webView: WKWebView,
    didFailProvisionalNavigation navigation: WKNavigation!,
    withError error: any Error
  ) {
    state.webStatus = .unavailable(Self.diagnostic(for: error))
    RabbisirLog.runtime.error(
      "Provisional navigation failed: \(error.localizedDescription, privacy: .private)"
    )
  }

  func webView(
    _ webView: WKWebView,
    decidePolicyFor navigationAction: WKNavigationAction
  ) async -> WKNavigationActionPolicy {
    navigationAction.shouldPerformDownload ? .download : .allow
  }

  func webView(
    _ webView: WKWebView,
    navigationAction: WKNavigationAction,
    didBecome download: WKDownload
  ) {
    download.delegate = self
  }

  func webView(
    _ webView: WKWebView,
    navigationResponse: WKNavigationResponse,
    didBecome download: WKDownload
  ) {
    download.delegate = self
  }

  func download(
    _ download: WKDownload,
    decideDestinationUsing response: URLResponse,
    suggestedFilename: String
  ) async -> URL? {
    let identifier = ObjectIdentifier(download)
    let panel = NSSavePanel()
    panel.nameFieldStringValue = SessionLogExportPolicy.suggestedFilename(suggestedFilename)
    panel.allowedContentTypes = [.zip]
    panel.canCreateDirectories = true
    panel.title = currentCopy[.sessionLog]
    let response = await presentSavePanel(panel)
    guard response == .OK, let destination = panel.url else {
      suppressedSessionLogDownloadFailures.insert(identifier)
      return nil
    }
    sessionLogDestinations[identifier] = destination
    presentSessionLogProgress()
    return destination
  }

  private func presentSavePanel(_ panel: NSSavePanel) async -> NSApplication.ModalResponse {
    guard let window = webView.window else { return panel.runModal() }
    return await withCheckedContinuation { continuation in
      panel.beginSheetModal(for: window) { response in
        continuation.resume(returning: response)
      }
    }
  }

  func downloadDidFinish(_ download: WKDownload) {
    let identifier = ObjectIdentifier(download)
    let destination = sessionLogDestinations.removeValue(forKey: identifier)
    dismissSessionLogProgress()
    if let destination {
      presentSessionLogResult(
        message: currentCopy.sessionZIPSaved(destination.lastPathComponent),
        detail: nil,
        reveal: destination
      )
    }
  }

  func download(
    _ download: WKDownload,
    didFailWithError error: any Error,
    resumeData: Data?
  ) {
    let identifier = ObjectIdentifier(download)
    let destination = sessionLogDestinations.removeValue(forKey: identifier)
    dismissSessionLogProgress()
    if suppressedSessionLogDownloadFailures.remove(identifier) != nil { return }
    if let destination, FileManager.default.fileExists(atPath: destination.path) {
      try? FileManager.default.removeItem(at: destination)
    }
    let alert = NSAlert()
    alert.messageText = currentCopy.sessionZIPDownloadFailed
    alert.informativeText = RabbisirSafeErrorPresentation.message(
      for: error,
      copy: currentCopy
    )
    if let window = webView.window {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }

  private func presentSessionLogProgress() {
    dismissSessionLogProgress()
    let alert = NSAlert()
    alert.messageText = currentCopy.downloadingSessionZIP
    let progress = NSProgressIndicator(frame: CGRect(x: 0, y: 0, width: 240, height: 18))
    progress.style = .spinning
    progress.controlSize = .small
    progress.startAnimation(nil)
    alert.accessoryView = progress
    sessionLogProgressAlert = alert
    if let window = webView.window {
      alert.beginSheetModal(for: window)
    } else {
      alert.window.orderFront(nil)
    }
  }

  private func dismissSessionLogProgress() {
    guard let alert = sessionLogProgressAlert else { return }
    if let parent = alert.window.sheetParent {
      parent.endSheet(alert.window)
    } else {
      alert.window.orderOut(nil)
    }
    sessionLogProgressAlert = nil
  }

  private func presentSessionLogResult(
    message: String,
    detail: String?,
    reveal: URL? = nil
  ) {
    let alert = NSAlert()
    alert.messageText = message
    if let detail { alert.informativeText = detail }
    if reveal != nil {
      alert.addButton(withTitle: currentCopy[.showInFinder])
    }
    alert.addButton(withTitle: currentCopy.okay)
    if let window = webView.window {
      alert.beginSheetModal(for: window) { response in
        guard response == .alertFirstButtonReturn, let reveal else { return }
        NSWorkspace.shared.activateFileViewerSelecting([reveal])
      }
    } else {
      let response = alert.runModal()
      if response == .alertFirstButtonReturn, let reveal {
        NSWorkspace.shared.activateFileViewerSelecting([reveal])
      }
    }
  }

  func retryLoad() {
    webView.stopLoading()
    state.webStatus = .loading
    composerProjection = .loading
    navigationProjects = []
    selectedWorkspaceTitle = nil
    isNavigationLoading = true
    navigationFailure = nil
    nativeProjectionRevision = 0
    hasAttemptedInitialSessionRestore = false
    conversation.selectSession(nil)
    load()
  }

  func receiveNativeConversationProjection(_ value: Any?) {
    guard let projection = RuntimeNativeConversationProjection.decode(value) else {
      if value != nil, !(value is NSNull) {
        RabbisirLog.runtime.error("Rejected an unsupported semantic envelope")
      }
      return
    }
    if conversation.applyUpstreamProjection(projection) {
      nativeProjectionRevision = max(nativeProjectionRevision, projection.revision)
    }
  }

  func refreshNativeConversationProjection() async {
    guard state.webStatus == .ready else { return }
    do {
      let value = try await webView.evaluateJavaScript(
        RuntimeConversationProjectionBridge.projectionScript(
          afterRevision: nativeProjectionRevision
        )
      )
      receiveNativeConversationProjection(value)
    } catch {
      // The official client may still be installing its semantic face during first paint.
    }
  }

  private func loadOlderUpstreamConversation() async {
    guard state.webStatus == .ready else { return }
    do {
      _ = try await webView.callAsyncJavaScript(
        "return await (\(RuntimeConversationProjectionBridge.loadOlderScript));",
        arguments: [:],
        in: nil,
        contentWorld: .page
      )
      await refreshNativeConversationProjection()
    } catch {
      // The native store retains the current page when official pagination is unavailable.
    }
  }

  func refreshComposerProjection() async {
    guard state.webStatus == .ready else { return }
    do {
      let value = try await webView.evaluateJavaScript(
        RuntimeComposerBridge.projectionScript
      )
      if let next = RuntimeComposerProjection.decode(value), next != composerProjection {
        composerProjection = next
      }
    } catch {
      if composerProjection != .loading {
        composerProjection = .loading
      }
    }
  }

  func activateComposerControl(_ control: RuntimeComposerControl) async -> Bool {
    guard state.webStatus == .ready else { return false }
    webView.window?.makeKeyAndOrderFront(nil)
    do {
      let value = try await webView.evaluateJavaScript(
        RuntimeComposerBridge.activationScript(for: control)
      )
      await refreshComposerProjection()
      return value as? Bool ?? false
    } catch {
      return false
    }
  }

  func composerOptions(for kind: RuntimeComposerChoiceKind) async -> [RuntimeComposerOption] {
    guard state.webStatus == .ready else { return [] }
    do {
      let value = try await webView.callAsyncJavaScript(
        "return await (\(RuntimeComposerBridge.choicesScript(for: kind)));",
        arguments: [:],
        in: nil,
        contentWorld: .page
      )
      let options = RuntimeComposerOption.decode(value) ?? []
      return options
    } catch {
      return []
    }
  }

  func refreshNavigationProjection() async {
    guard state.webStatus == .ready, !isRefreshingNavigation else { return }
    isRefreshingNavigation = true
    defer { isRefreshingNavigation = false }
    isNavigationLoading = navigationProjects.isEmpty
    do {
      let selectedSessionID =
        try await webView.evaluateJavaScript(
          RuntimeNavigationBridge.currentSessionIDScript
        ) as? String
      var snapshot = try await navigationTransport.snapshot(
        selectedSessionID: selectedSessionID
      )
      if !hasAttemptedInitialSessionRestore {
        hasAttemptedInitialSessionRestore = true
        let restorableProjects = snapshot.projects.filter {
          !archivedNavigationProjectIDs.contains($0.id)
        }
        if let restoreSessionID = NavigationSessionRestorePolicy.restoreCandidate(
          savedSessionID: navigationProjectPreferences.lastSelectedSessionID(),
          currentSessionID: snapshot.selectedSessionID,
          projects: restorableProjects
        ) {
          let restored =
            try await webView.callAsyncJavaScript(
              "return await (\(RuntimeNavigationBridge.selectionScript(sessionID: restoreSessionID)));",
              arguments: [:],
              in: nil,
              contentWorld: .page
            ) as? Bool ?? false
          if restored {
            snapshot = try await navigationTransport.snapshot(
              selectedSessionID: restoreSessionID
            )
          }
        }
      }
      navigationProjects = snapshot.projects
      selectedWorkspaceTitle = snapshot.selectedWorkspaceTitle
      conversation.updateSessionContexts(snapshot.projects.flatMap(\.sessions))
      navigationFailure =
        snapshot.projects.isEmpty
        ? currentCopy[.sidebarEmpty]
        : nil
      if let selected = snapshot.projects.lazy
        .flatMap({ $0.sessions })
        .first(where: { $0.isSelected })
      {
        state.conversationTitle = selected.title
      }
      conversation.selectSession(snapshot.selectedSessionID)
      if let selectedSessionID = snapshot.selectedSessionID,
        snapshot.projects.flatMap(\.sessions).contains(where: { $0.id == selectedSessionID })
      {
        navigationProjectPreferences.setLastSelectedSessionID(selectedSessionID)
      }
    } catch {
      navigationFailure = currentCopy.navigationLoadFailed
    }
    isNavigationLoading = false
  }

  func selectNavigationSession(_ session: RuntimeNavigationSession) async -> Bool {
    guard state.webStatus == .ready else { return false }
    do {
      let accepted =
        try await webView.callAsyncJavaScript(
          "return await (\(RuntimeNavigationBridge.selectionScript(sessionID: session.id)));",
          arguments: [:],
          in: nil,
          contentWorld: .page
        ) as? Bool ?? false
      guard accepted else { return false }
      navigationProjects = navigationProjects.map { project in
        RuntimeNavigationProject(
          id: project.id,
          title: project.title,
          sessions: project.sessions.map { candidate in
            RuntimeNavigationSession(
              id: candidate.id,
              title: candidate.title,
              isSelected: candidate.id == session.id,
              updatedAt: candidate.updatedAt,
              cwd: candidate.cwd
            )
          }
        )
      }
      state.conversationTitle = session.title
      conversation.selectSession(session.id)
      navigationProjectPreferences.setLastSelectedSessionID(session.id)
      await refreshNativeConversationProjection()
      navigationSelectionRevision &+= 1
      return true
    } catch {
      return false
    }
  }

  private func openForkedSession(_ sessionID: String) async {
    await refreshNavigationProjection()
    guard
      let session = navigationProjects.lazy
        .flatMap({ $0.sessions })
        .first(where: { $0.id == sessionID })
    else { return }
    _ = await selectNavigationSession(session)
  }

  var activeNavigationProjects: [RuntimeNavigationProject] {
    navigationProjects.filter { !archivedNavigationProjectIDs.contains($0.id) }
  }

  var archivedNavigationProjects: [RuntimeNavigationProject] {
    navigationProjects.filter { archivedNavigationProjectIDs.contains($0.id) }
  }

  var currentWorkspaceDisplayName: String {
    selectedWorkspaceTitle
      ?? WorkspaceDisplayNameResolver.resolve(
        projects: navigationProjects,
        composerWorkspace: composerProjection.workspace
      )
  }

  func pinNavigationProject(_ project: RuntimeNavigationProject) async -> Bool {
    guard project.id != UpstreamNavigationProjection.ungroupedProjectID else { return false }
    let beforeID = navigationProjects.first { candidate in
      candidate.id != project.id
        && candidate.id != UpstreamNavigationProjection.ungroupedProjectID
    }?.id
    do {
      try await navigationTransport.moveWorkspace(
        workspaceID: project.id,
        beforeWorkspaceID: beforeID
      )
      await refreshNavigationProjection()
      return true
    } catch {
      return false
    }
  }

  func renameNavigationProject(
    _ project: RuntimeNavigationProject,
    title: String
  ) async -> Bool {
    guard project.id != UpstreamNavigationProjection.ungroupedProjectID else { return false }
    do {
      try await navigationTransport.renameWorkspace(
        workspaceID: project.id,
        title: title
      )
      await refreshNavigationProjection()
      return true
    } catch {
      return false
    }
  }

  func setNavigationProjectArchived(
    _ project: RuntimeNavigationProject,
    archived: Bool
  ) {
    guard project.id != UpstreamNavigationProjection.ungroupedProjectID else { return }
    navigationProjectPreferences.setArchived(archived, workspaceID: project.id)
    archivedNavigationProjectIDs = navigationProjectPreferences.archivedWorkspaceIDs()
  }

  func deleteNavigationProject(_ project: RuntimeNavigationProject) async -> Bool {
    guard project.id != UpstreamNavigationProjection.ungroupedProjectID else { return false }
    do {
      try await navigationTransport.deleteWorkspace(workspaceID: project.id)
      for session in project.sessions {
        navigationProjectPreferences.clearLastSelectedSessionID(ifMatching: session.id)
      }
      navigationProjectPreferences.remove(workspaceID: project.id)
      archivedNavigationProjectIDs = navigationProjectPreferences.archivedWorkspaceIDs()
      await clearConversationSelectionAfterRemoval()
      await refreshNavigationProjection()
      return true
    } catch {
      return false
    }
  }

  func pinNavigationSession(
    _ session: RuntimeNavigationSession,
    in project: RuntimeNavigationProject
  ) async -> Bool {
    guard project.id != UpstreamNavigationProjection.ungroupedProjectID else { return false }
    let beforeSessionID = project.sessions.first(where: { $0.id != session.id })?.id
    do {
      try await navigationTransport.moveSession(
        sessionID: session.id,
        toWorkspaceID: project.id,
        beforeSessionID: beforeSessionID
      )
      await refreshNavigationProjection()
      return true
    } catch {
      return false
    }
  }

  func renameNavigationSession(
    _ session: RuntimeNavigationSession,
    title: String
  ) async -> Bool {
    do {
      try await navigationTransport.renameSession(sessionID: session.id, title: title)
      await refreshNavigationProjection()
      return true
    } catch {
      return false
    }
  }

  func archiveNavigationSession(_ session: RuntimeNavigationSession) async -> Bool {
    do {
      try await navigationTransport.archiveSession(sessionID: session.id)
      navigationProjectPreferences.clearLastSelectedSessionID(ifMatching: session.id)
      await clearConversationSelectionAfterRemoval()
      await refreshNavigationProjection()
      return true
    } catch {
      return false
    }
  }

  private func clearConversationSelectionAfterRemoval() async {
    conversation.selectSession(nil)
    state.conversationTitle = currentCopy.currentConversationTitle
    navigationProjects = navigationProjects.map { project in
      RuntimeNavigationProject(
        id: project.id,
        title: project.title,
        sessions: project.sessions.map { session in
          RuntimeNavigationSession(
            id: session.id,
            title: session.title,
            isSelected: false,
            updatedAt: session.updatedAt,
            cwd: session.cwd
          )
        }
      )
    }
    _ = try? await webView.callAsyncJavaScript(
      "return await (\(RuntimeNavigationBridge.clearSelectionScript));",
      arguments: [:],
      in: nil,
      contentWorld: .page
    )
    navigationSelectionRevision &+= 1
  }

  func forkNavigationSession(_ session: RuntimeNavigationSession) async -> Bool {
    do {
      let childID = try await navigationTransport.forkSession(sessionID: session.id)
      await refreshNavigationProjection()
      guard
        let child = navigationProjects.lazy
          .flatMap({ $0.sessions })
          .first(where: { $0.id == childID })
      else { return false }
      return await selectNavigationSession(child)
    } catch {
      return false
    }
  }

  func moveNavigationSession(
    _ session: RuntimeNavigationSession,
    to project: RuntimeNavigationProject
  ) async -> Bool {
    guard project.id != UpstreamNavigationProjection.ungroupedProjectID else { return false }
    do {
      try await navigationTransport.moveSession(
        sessionID: session.id,
        toWorkspaceID: project.id,
        beforeSessionID: nil
      )
      await refreshNavigationProjection()
      return true
    } catch {
      return false
    }
  }

  func startNewSession() async -> Bool {
    guard state.webStatus == .ready else { return false }
    do {
      let accepted =
        try await webView.evaluateJavaScript(
          RuntimeNavigationBridge.newSessionActivationScript
        ) as? Bool ?? false
      guard accepted else { return false }
      try? await Task.sleep(for: .milliseconds(250))
      await refreshComposerProjection()
      await refreshNavigationProjection()
      await synchronizeNativeConversationSelection()
      return true
    } catch {
      return false
    }
  }

  func adoptWorkspace(at directory: URL) async -> Bool {
    guard state.webStatus == .ready, directory.isFileURL else { return false }
    do {
      let sessionID = try await navigationTransport.adoptWorkspace(path: directory.path)
      var opened = false
      for _ in 0..<20 where !opened {
        opened =
          try await webView.callAsyncJavaScript(
            "return await (\(RuntimeNavigationBridge.selectionScript(sessionID: sessionID)));",
            arguments: [:],
            in: nil,
            contentWorld: .page
          ) as? Bool ?? false
        if !opened {
          try await Task.sleep(for: .milliseconds(50))
        }
      }
      guard opened else { return false }
      await refreshComposerProjection()
      await refreshNavigationProjection()
      await synchronizeNativeConversationSelection()
      navigationSelectionRevision &+= 1
      return conversation.selectedSessionID == sessionID
    } catch {
      return false
    }
  }

  func openSettings() async -> Bool {
    guard state.webStatus == .ready else { return false }
    webView.window?.makeKeyAndOrderFront(nil)
    do {
      let accepted =
        try await webView.callAsyncJavaScript(
          "return await (\(RuntimeNavigationBridge.settingsActivationScript));",
          arguments: [:],
          in: nil,
          contentWorld: .page
        ) as? Bool ?? false
      if accepted {
        isRuntimeTransitionPresented = true
      }
      return accepted
    } catch {
      return false
    }
  }

  func dismissRuntimeTransition() {
    isRuntimeTransitionPresented = false
  }

  func openSessionLog() async -> Bool {
    guard state.webStatus == .ready else { return false }
    webView.window?.makeKeyAndOrderFront(nil)
    do {
      return try await webView.callAsyncJavaScript(
        "return await (\(RuntimeNavigationBridge.sessionLogActivationScript));",
        arguments: [:],
        in: nil,
        contentWorld: .page
      ) as? Bool ?? false
    } catch {
      return false
    }
  }

  func selectComposerOption(
    _ option: RuntimeComposerOption,
    kind: RuntimeComposerChoiceKind
  ) async -> RuntimeComposerSelectionResult {
    guard state.webStatus == .ready else {
      return RuntimeComposerSelectionResult(
        accepted: false,
        draft: nil,
        requiresUpstreamConfirmation: false
      )
    }
    do {
      let value = try await webView.callAsyncJavaScript(
        "return await (\(RuntimeComposerBridge.selectionScript(kind: kind, optionID: option.id)));",
        arguments: [:],
        in: nil,
        contentWorld: .page
      )
      let result =
        RuntimeComposerSelectionResult.decode(value)
        ?? RuntimeComposerSelectionResult(
          accepted: false,
          draft: nil,
          requiresUpstreamConfirmation: false
        )
      if result.accepted {
        await refreshComposerProjection()
        if kind == .workspace {
          await refreshNavigationProjection()
        }
      }
      return result
    } catch {
      return RuntimeComposerSelectionResult(
        accepted: false,
        draft: nil,
        requiresUpstreamConfirmation: false
      )
    }
  }

  func submitInput(_ text: String, gesture: ComposerSubmitGesture) async -> Bool {
    do {
      let value = try await webView.callAsyncJavaScript(
        RuntimeConversationProjectionBridge.submitScript,
        arguments: ["text": text, "gesture": gesture.rawValue],
        in: nil,
        contentWorld: .page
      )
      let result = RuntimeConversationSubmissionResult.decode(value)
      await refreshComposerProjection()
      await refreshNavigationProjection()
      if result?.accepted == true {
        await synchronizeNativeConversationSelection()
        conversation.refreshAfterUpstreamMutation()
        return true
      }
      return false
    } catch {
      return false
    }
  }

  func cancelCurrentGeneration() async -> Bool {
    guard await conversation.requestGenerationCancellation() else { return false }

    for _ in 0..<100 {
      await refreshNativeConversationProjection()
      if !conversation.isGenerationRunning {
        await refreshComposerProjection()
        return true
      }
      try? await Task.sleep(for: .milliseconds(50))
    }

    conversation.generationCancellationDidNotConverge()
    await refreshComposerProjection()
    return false
  }

  func synchronizeNativeConversationSelection() async {
    guard state.webStatus == .ready else { return }
    do {
      let value = try await webView.evaluateJavaScript(
        RuntimeNavigationBridge.currentSessionIDScript
      )
      conversation.selectSession(value as? String)
      await refreshNativeConversationProjection()
    } catch {
      conversation.selectSession(nil)
    }
  }

  private func load() {
    webView.load(URLRequest(url: url, cachePolicy: .useProtocolCachePolicy))
  }

  private static func diagnostic(for error: any Error) -> String {
    RabbisirCopy(language: RabbisirLocalization.shared.language).internalWorkspaceUnavailable
  }
}

struct RuntimeBridgeView: NSViewRepresentable {
  let store: RuntimeBridgeStore

  func makeNSView(context: Context) -> WKWebView {
    store.webView
  }

  func updateNSView(_ nsView: WKWebView, context: Context) {}
}
