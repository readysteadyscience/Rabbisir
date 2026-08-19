import Combine
import Foundation
import OSLog

enum ConversationTransportFailureCategory {
  static func value(for error: any Error) -> String {
    if error is CancellationError { return "cancelled" }
    if let error = error as? URLError { return "network-\(error.code.rawValue)" }
    if let error = error as? UpstreamConversationTransportError {
      switch error {
      case .invalidBaseURL: return "invalid-base-url"
      case .unsupportedWebSocketMessage: return "unsupported-carrier-message"
      case .carrierStatus(let status): return "carrier-status-\(status)"
      case .cancellationRejected: return "cancellation-rejected"
      }
    }
    if let error = error as? UpstreamConversationWireError {
      switch error {
      case .invalidEnvelope: return "invalid-envelope"
      case .rpcIDMismatch: return "rpc-id-mismatch"
      case .server(let rpcError): return "server-\(rpcError.code)"
      }
    }
    if error is DecodingError { return "invalid-response" }
    return "unknown"
  }
}

@MainActor
final class NativeConversationStore: ObservableObject, NativeConversationViewModel {
  @Published private(set) var selectedSessionID: String?
  @Published private(set) var items: [NativeConversationItem] = []
  @Published private(set) var updateRevision: UInt64 = 0
  @Published private(set) var isLoadingInitialHistory = false
  @Published private(set) var isLoadingOlderHistory = false
  @Published private(set) var hasMoreHistory = false
  @Published private(set) var failureMessage: String?
  @Published private(set) var isGenerationRunning = false
  @Published private(set) var isGenerationCancellationPending = false
  @Published private(set) var queueItems: [UpstreamQueueItem] = []
  @Published private(set) var pendingApproval: UpstreamApprovalRequest?
  @Published private(set) var pendingQuestion: UpstreamQuestionRequest?
  @Published private(set) var isInteractionResponsePending = false
  @Published private var attachmentData: [String: Data] = [:]
  private(set) var latestEventSequence: Int?
  private(set) var observedStreamChunkCount = 0

  private static let historyPageMessages = 50

  private let transport: any UpstreamConversationTransporting
  private weak var shellState: WorkspaceState?
  private var sessionWorkingDirectories: [String: String] = [:]
  private var forkHandler: (@MainActor (String) async -> Void)?
  private var reducer = ConversationReducer()
  private var generation = 0
  private var loadedSessionID: String?
  private var oldestEventSequence: Int?
  private var subscribedLastSequence: Int?
  private var bufferedLiveEntries: [Int: UpstreamHistoryEntry] = [:]
  private var initialLoadTask: Task<Void, Never>?
  private var streamTask: Task<Void, Never>?
  private var tailRepairTask: Task<Void, Never>?
  private var upstreamProjectionRevision: UInt64?
  private var upstreamLoadOlderHandler: (@MainActor () async -> Void)?
  private var localizationCancellable: AnyCancellable?

  init(
    transport: any UpstreamConversationTransporting,
    shellState: WorkspaceState? = nil
  ) {
    self.transport = transport
    self.shellState = shellState
    localizationCancellable = RabbisirLocalization.shared.$language
      .removeDuplicates()
      .dropFirst()
      .sink { [weak self] _ in
        self?.publishProjection()
      }
  }

  func updateSessionContexts(_ sessions: [RuntimeNavigationSession]) {
    sessionWorkingDirectories = Dictionary(
      uniqueKeysWithValues: sessions.compactMap { session in
        session.cwd.map { (session.id, $0) }
      }
    )
  }

  func setForkHandler(_ handler: @escaping @MainActor (String) async -> Void) {
    forkHandler = handler
  }

  func setUpstreamLoadOlderHandler(
    _ handler: @escaping @MainActor () async -> Void
  ) {
    upstreamLoadOlderHandler = handler
  }

  @discardableResult
  func applyUpstreamProjection(_ projection: RuntimeNativeConversationProjection) -> Bool {
    guard projection.sessionID == selectedSessionID,
      projection.openState == "open",
      upstreamProjectionRevision.map({ projection.revision > $0 }) ?? true
    else { return false }
    guard !projection.rows.isEmpty || items.isEmpty else {
      isGenerationRunning = projection.isRunning
      if !projection.isRunning {
        isGenerationCancellationPending = false
      }
      return false
    }
    upstreamProjectionRevision = projection.revision
    loadedSessionID = projection.sessionID
    isLoadingInitialHistory = false
    isLoadingOlderHistory = projection.isLoadingOlder
    hasMoreHistory = projection.hasMore
    failureMessage = nil
    isGenerationRunning = projection.isRunning
    if !projection.isRunning {
      isGenerationCancellationPending = false
    }
    guard items != projection.rows else { return true }
    items = projection.rows
    updateRevision &+= 1
    return true
  }

  func selectSession(_ sessionID: String?) {
    let normalized = sessionID?.trimmingCharacters(in: .whitespacesAndNewlines)
    let next = normalized?.isEmpty == false ? normalized : nil
    guard selectedSessionID != next else {
      if next != nil, loadedSessionID != next, initialLoadTask == nil {
        startCurrentSession()
      }
      return
    }

    generation &+= 1
    initialLoadTask?.cancel()
    streamTask?.cancel()
    tailRepairTask?.cancel()
    initialLoadTask = nil
    streamTask = nil
    tailRepairTask = nil
    selectedSessionID = next
    loadedSessionID = nil
    items = []
    updateRevision &+= 1
    isLoadingInitialHistory = false
    isLoadingOlderHistory = false
    hasMoreHistory = false
    failureMessage = nil
    isGenerationRunning = false
    isGenerationCancellationPending = false
    queueItems = []
    pendingApproval = nil
    pendingQuestion = nil
    isInteractionResponsePending = false
    attachmentData = [:]
    latestEventSequence = nil
    oldestEventSequence = nil
    subscribedLastSequence = nil
    observedStreamChunkCount = 0
    bufferedLiveEntries = [:]
    reducer = ConversationReducer()
    upstreamProjectionRevision = nil

    guard next != nil else { return }
    startCurrentSession()
  }

  @discardableResult
  func requestGenerationCancellation() async -> Bool {
    guard let selectedSessionID,
      isGenerationRunning,
      !isGenerationCancellationPending
    else { return false }
    isGenerationCancellationPending = true
    do {
      try await transport.cancel(sessionID: selectedSessionID)
      return true
    } catch {
      isGenerationCancellationPending = false
      return false
    }
  }

  func generationCancellationDidNotConverge() {
    isGenerationCancellationPending = false
  }

  @discardableResult
  func updateQueueItem(_ itemID: String, action: UpstreamQueueAction) async -> Bool {
    guard let selectedSessionID,
      queueItems.contains(where: { $0.id == itemID && $0.placement == .queued })
    else { return false }
    do {
      try await transport.updateQueue(
        sessionID: selectedSessionID,
        itemID: itemID,
        action: action
      )
      return true
    } catch {
      failureMessage = currentCopy.conversationOperationFailed(.sync)
      return false
    }
  }

  @discardableResult
  func respondToApproval(_ outcome: UpstreamApprovalOutcome) async -> Bool {
    guard let request = pendingApproval,
      request.sessionID == selectedSessionID,
      !isInteractionResponsePending
    else { return false }
    isInteractionResponsePending = true
    do {
      try await transport.respondToApproval(request, outcome: outcome)
      return true
    } catch {
      isInteractionResponsePending = false
      failureMessage = currentCopy.conversationOperationFailed(.sync)
      return false
    }
  }

  @discardableResult
  func respondToQuestion(_ answer: UpstreamQuestionAnswer) async -> Bool {
    guard let request = pendingQuestion,
      request.sessionID == selectedSessionID,
      !isInteractionResponsePending
    else { return false }
    isInteractionResponsePending = true
    do {
      try await transport.respondToQuestion(request, answer: answer)
      return true
    } catch {
      isInteractionResponsePending = false
      failureMessage = currentCopy.conversationOperationFailed(.sync)
      return false
    }
  }

  func ensureConversationLoaded() async {
    guard let selectedSessionID else { return }
    if loadedSessionID == selectedSessionID { return }
    if initialLoadTask == nil {
      startCurrentSession()
    }
    await initialLoadTask?.value
  }

  func loadOlderHistory() async {
    if upstreamProjectionRevision != nil {
      guard hasMoreHistory, !isLoadingOlderHistory else { return }
      await upstreamLoadOlderHandler?()
      return
    }
    guard let sessionID = selectedSessionID,
      loadedSessionID == sessionID,
      hasMoreHistory,
      !isLoadingOlderHistory,
      let beforeSequence = oldestEventSequence
    else { return }
    let expectedGeneration = generation
    isLoadingOlderHistory = true
    defer {
      if generation == expectedGeneration {
        isLoadingOlderHistory = false
      }
    }

    do {
      let page = try await transport.history(
        sessionID: sessionID,
        beforeSequence: beforeSequence,
        maxMessages: Self.historyPageMessages
      )
      guard generation == expectedGeneration, selectedSessionID == sessionID else { return }
      reducer.merge(page)
      oldestEventSequence = page.events.first?.event.sequence ?? oldestEventSequence
      hasMoreHistory = page.hasMore
      publishProjection()
    } catch {
      guard generation == expectedGeneration else { return }
      failureMessage = Self.diagnostic(for: error, operation: .loadEarlier)
    }
  }

  func imageData(for attachmentID: String) -> Data? {
    attachmentData[attachmentID]
  }

  func ensureImageLoaded(_ image: UpstreamImageAttachmentReference) async {
    guard attachmentData[image.attachmentID] == nil,
      let sessionID = selectedSessionID
    else { return }
    do {
      let value = try await transport.attachment(
        sessionID: sessionID,
        attachmentID: image.attachmentID
      )
      guard selectedSessionID == sessionID,
        let data = Data(base64Encoded: value.data)
      else { return }
      attachmentData[image.attachmentID] = data
      updateRevision &+= 1
    } catch {
      guard selectedSessionID == sessionID else { return }
      failureMessage = Self.diagnostic(for: error, operation: .loadImage)
    }
  }

  func openProducedFile(_ path: String) async {
    guard let sessionID = selectedSessionID else { return }
    do {
      if path.lowercased().hasSuffix(".md")
        || path.lowercased().hasSuffix(".markdown")
      {
        let value = try await transport.previewMarkdown(
          sessionID: sessionID,
          path: path
        )
        guard selectedSessionID == sessionID else { return }
        shellState?.showArtifact(value.document)
      } else {
        try await transport.openPath(resolvedWorkspacePath(path, sessionID: sessionID))
      }
    } catch {
      guard selectedSessionID == sessionID else { return }
      shellState?.showArtifactFailure(Self.diagnostic(for: error, operation: .openFile))
    }
  }

  func saveMarkdownDocument(
    _ document: UpstreamMarkdownDocument,
    content: String
  ) async throws -> UpstreamMarkdownDocument {
    guard let sessionID = selectedSessionID else { throw CancellationError() }
    let value = try await transport.saveMarkdown(
      sessionID: sessionID,
      path: document.path,
      content: content,
      expectedModifiedAt: document.modifiedAt
    )
    guard selectedSessionID == sessionID else { throw CancellationError() }
    return value.document
  }

  func reloadMarkdownDocument(
    _ document: UpstreamMarkdownDocument
  ) async throws -> UpstreamMarkdownDocument {
    guard let sessionID = selectedSessionID else { throw CancellationError() }
    let value = try await transport.previewMarkdown(
      sessionID: sessionID,
      path: document.path
    )
    guard selectedSessionID == sessionID else { throw CancellationError() }
    return value.document
  }

  func openMarkdownDocumentExternally(
    _ document: UpstreamMarkdownDocument
  ) async throws {
    guard let sessionID = selectedSessionID else { throw CancellationError() }
    try await transport.openPath(
      resolvedWorkspacePath(document.path, sessionID: sessionID)
    )
    guard selectedSessionID == sessionID else { throw CancellationError() }
  }

  func forkConversation(at sequence: Int) async {
    guard let sessionID = selectedSessionID else { return }
    do {
      let childID = try await transport.fork(
        sessionID: sessionID,
        atSequence: sequence
      )
      guard selectedSessionID == sessionID else { return }
      await forkHandler?(childID)
    } catch {
      guard selectedSessionID == sessionID else { return }
      failureMessage = Self.diagnostic(for: error, operation: .fork)
    }
  }

  func refreshAfterUpstreamMutation() {
    scheduleTailRepair(after: .milliseconds(180))
  }

  private func startCurrentSession() {
    guard let sessionID = selectedSessionID else { return }
    let expectedGeneration = generation
    isLoadingInitialHistory = true
    failureMessage = nil

    streamTask?.cancel()
    streamTask = Task { [weak self] in
      await self?.consumeEventStream(sessionID: sessionID, generation: expectedGeneration)
    }
    initialLoadTask = Task { [weak self] in
      await self?.loadInitialHistory(sessionID: sessionID, generation: expectedGeneration)
    }
  }

  private func loadInitialHistory(sessionID: String, generation expectedGeneration: Int) async {
    do {
      let page = try await transport.history(
        sessionID: sessionID,
        beforeSequence: nil,
        maxMessages: Self.historyPageMessages
      )
      guard generation == expectedGeneration, selectedSessionID == sessionID else { return }

      var nextReducer = ConversationReducer()
      nextReducer.reset(to: page)
      let buffered = bufferedLiveEntries.values.sorted {
        $0.event.sequence < $1.event.sequence
      }
      for entry in buffered {
        nextReducer.ingest(entry)
      }
      bufferedLiveEntries.removeAll(keepingCapacity: true)
      reducer = nextReducer
      oldestEventSequence = page.events.first?.event.sequence
      latestEventSequence = max(
        page.events.last?.event.sequence,
        buffered.last?.event.sequence
      )
      if upstreamProjectionRevision == nil {
        loadedSessionID = sessionID
        hasMoreHistory = page.hasMore
        isLoadingInitialHistory = false
        failureMessage = nil
        publishProjection()
      }
      if let subscribedLastSequence,
        subscribedLastSequence > (latestEventSequence ?? -1)
      {
        scheduleTailRepair()
      }
    } catch {
      guard generation == expectedGeneration, selectedSessionID == sessionID else { return }
      RabbisirLog.runtime.error(
        "Conversation history load failed: \(ConversationTransportFailureCategory.value(for: error), privacy: .public)"
      )
      if upstreamProjectionRevision == nil {
        isLoadingInitialHistory = false
        failureMessage = Self.diagnostic(for: error, operation: .load)
      }
    }
    if generation == expectedGeneration {
      initialLoadTask = nil
    }
  }

  private func consumeEventStream(sessionID: String, generation expectedGeneration: Int) async {
    var retryDelay = Duration.milliseconds(160)
    while !Task.isCancelled,
      generation == expectedGeneration,
      selectedSessionID == sessionID
    {
      queueItems = []
      pendingApproval = nil
      pendingQuestion = nil
      isInteractionResponsePending = false
      do {
        for try await envelope in transport.eventStream() {
          guard !Task.isCancelled,
            generation == expectedGeneration,
            selectedSessionID == sessionID
          else { return }
          handle(envelope.frame, for: sessionID)
          retryDelay = .milliseconds(160)
        }
      } catch {
        guard !Task.isCancelled,
          generation == expectedGeneration,
          selectedSessionID == sessionID
        else { return }
        RabbisirLog.runtime.error(
          "Conversation event stream failed: \(ConversationTransportFailureCategory.value(for: error), privacy: .public)"
        )
        if upstreamProjectionRevision == nil {
          failureMessage =
            items.isEmpty
            ? Self.diagnostic(for: error, operation: .connect)
            : currentCopy.liveConversationInterrupted
        }
      }
      guard !Task.isCancelled else { return }
      try? await Task.sleep(for: retryDelay)
      retryDelay = min(retryDelay * 2, .seconds(2))
    }
  }

  private func handle(_ frame: UpstreamConversationStreamFrame, for sessionID: String) {
    switch frame {
    case .event(let frameSessionID, let entry) where frameSessionID == sessionID:
      acceptLiveEntry(entry)
    case .subscribed(let frameSessionID, let lastSequence) where frameSessionID == sessionID:
      subscribedLastSequence = lastSequence
      failureMessage = nil
      if loadedSessionID == sessionID,
        lastSequence > (latestEventSequence ?? -1)
      {
        scheduleTailRepair()
      }
    case .queue(let frameSessionID, let items) where frameSessionID == sessionID:
      queueItems = items
    case .approvalRequested(let request) where request.sessionID == sessionID:
      pendingApproval = request
    case .approvalResolved(let frameSessionID, let approvalID)
    where frameSessionID == sessionID && pendingApproval?.approvalID == approvalID:
      pendingApproval = nil
      isInteractionResponsePending = false
    case .questionRequested(let request) where request.sessionID == sessionID:
      pendingQuestion = request
    case .questionResolved(let frameSessionID, let questionRPCID)
    where frameSessionID == sessionID && pendingQuestion?.rpcID == questionRPCID:
      pendingQuestion = nil
      isInteractionResponsePending = false
    case .streamError(let error):
      if upstreamProjectionRevision == nil {
        failureMessage = currentCopy.liveConversationError(
          RabbisirSafeErrorPresentation.message(
            category: RabbisirSafeErrorPresentation.category(forRPCCode: error.code),
            copy: currentCopy
          ))
      }
    default:
      break
    }
  }

  private func acceptLiveEntry(_ entry: UpstreamHistoryEntry) {
    let sequence = entry.event.sequence
    if isLoadingInitialHistory || loadedSessionID == nil {
      bufferedLiveEntries[sequence] = entry
      return
    }

    if let latestEventSequence, sequence > latestEventSequence + 1 {
      bufferedLiveEntries[sequence] = entry
      scheduleTailRepair()
      return
    }

    let projectionChanged = reducer.ingest(entry)
    latestEventSequence = max(latestEventSequence, sequence)
    failureMessage = nil
    if entry.event.type == "assistant/chunk" {
      observedStreamChunkCount &+= 1
    }
    if projectionChanged {
      publishProjection()
    }
  }

  private func scheduleTailRepair(after delay: Duration = .zero) {
    guard tailRepairTask == nil,
      let sessionID = selectedSessionID,
      loadedSessionID == sessionID
    else { return }
    let expectedGeneration = generation
    tailRepairTask = Task { [weak self] in
      if delay > .zero {
        try? await Task.sleep(for: delay)
      }
      await self?.repairTail(sessionID: sessionID, generation: expectedGeneration)
    }
  }

  private func repairTail(sessionID: String, generation expectedGeneration: Int) async {
    defer {
      if generation == expectedGeneration {
        tailRepairTask = nil
      }
    }
    guard !Task.isCancelled else { return }
    do {
      let page = try await transport.history(
        sessionID: sessionID,
        beforeSequence: nil,
        maxMessages: Self.historyPageMessages
      )
      guard generation == expectedGeneration, selectedSessionID == sessionID else { return }
      reducer.merge(page)
      let buffered = bufferedLiveEntries.values.sorted {
        $0.event.sequence < $1.event.sequence
      }
      for entry in buffered {
        reducer.ingest(entry)
      }
      bufferedLiveEntries.removeAll(keepingCapacity: true)
      latestEventSequence = max(
        latestEventSequence,
        max(page.events.last?.event.sequence, buffered.last?.event.sequence)
      )
      failureMessage = nil
      publishProjection()
    } catch {
      guard generation == expectedGeneration else { return }
      if upstreamProjectionRevision == nil {
        failureMessage =
          items.isEmpty
          ? Self.diagnostic(for: error, operation: .sync)
          : currentCopy.liveConversationSyncUnavailable
      }
    }
  }

  private func publishProjection() {
    guard upstreamProjectionRevision == nil else { return }
    let projection = reducer.projection(
      copy: RabbisirCopy(language: RabbisirLocalization.shared.language)
    )
    let nextItems = projection.rows.map { row in
      Self.nativeItem(row, turns: projection.turns)
    }
    guard items != nextItems else { return }
    items = nextItems
    updateRevision &+= 1
  }

  private static func nativeItem(
    _ row: UpstreamConversationRow,
    turns: [Int: UpstreamConversationTurn]
  ) -> NativeConversationItem {
    let kind: NativeConversationItem.Kind =
      switch row.kind {
      case .user: .user
      case .assistant: .assistant
      case .image: .image
      case .tool: .tool
      case .command: .command
      case .compaction: .compaction
      case .notice: .notice
      case .error: .error
      case .turnTail: .turnTail
      }
    return NativeConversationItem(
      id: row.id,
      kind: kind,
      text: row.text,
      detail: row.detail,
      images: row.images,
      isStreaming: row.isStreaming,
      turn: row.turn,
      turnStartedAt: row.turn.flatMap { turns[$0]?.startTime },
      turnEndedAt: row.turn.flatMap { turns[$0]?.endTime },
      copyText: row.copyText,
      allowsCopy: row.copyText != nil,
      tool: row.tool.map {
        NativeConversationItem.Tool(title: $0.title, summary: $0.summary, state: $0.state)
      },
      turnTail: row.turnTail.map {
        NativeConversationItem.TurnTail(
          durationMilliseconds: $0.durationMilliseconds,
          firstTokenLatencyMilliseconds: $0.firstTokenLatencyMilliseconds,
          tokensPerSecond: $0.tokensPerSecond,
          producedFiles: $0.producedFiles,
          branchSequence: $0.branchSequence,
          isBranchUnavailable: $0.isBranchUnavailable
        )
      }
    )
  }

  private var currentCopy: RabbisirCopy {
    RabbisirCopy(language: RabbisirLocalization.shared.language)
  }

  static func diagnostic(
    for error: any Error,
    operation: RabbisirCopy.ConversationOperation
  ) -> String {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    let reason = RabbisirSafeErrorPresentation.message(for: error, copy: copy)
    return copy.conversationOperationFailed(operation, reason: reason)
  }

  private func resolvedWorkspacePath(_ path: String, sessionID: String) -> String {
    if path.hasPrefix("/")
      || path.range(of: #"^[A-Za-z]:[/\\]"#, options: .regularExpression) != nil
      || path.hasPrefix(#"\\"#)
    {
      return path
    }
    guard let cwd = sessionWorkingDirectories[sessionID], !cwd.isEmpty else {
      return path
    }
    return cwd.replacingOccurrences(
      of: #"[/\\]+$"#,
      with: "",
      options: .regularExpression
    )
      + "/"
      + path.trimmingCharacters(in: CharacterSet(charactersIn: "/\\"))
  }

}

private func max(_ left: Int?, _ right: Int?) -> Int? {
  switch (left, right) {
  case (let left?, let right?): Swift.max(left, right)
  case (let left?, nil): left
  case (nil, let right?): right
  case (nil, nil): nil
  }
}
