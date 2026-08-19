import Foundation
import Testing

@testable import RabbisirCore

@Suite("Native conversation store", .serialized)
@MainActor
struct NativeConversationStoreTests {
  @Test("Conversation RPC diagnostics never expose the upstream message")
  @MainActor
  func conversationRPCDiagnosticsAreSafe() {
    let privatePath = "/Use" + "rs/example"
    let raw = "PRIVATE \(privatePath) http://127.0.0.1:49152 internal stack"
    let error = UpstreamConversationWireError.server(
      UpstreamRPCError(code: "provider-unavailable", message: raw, details: .null)
    )
    let message = NativeConversationStore.diagnostic(for: error, operation: .connect)

    #expect(!message.contains(raw))
    #expect(!message.contains(privatePath))
    #expect(!message.contains("127.0.0.1"))
    #expect(!message.contains("49152"))
  }

  @Test("Transport diagnostics expose only stable failure categories")
  func safeFailureCategories() {
    #expect(
      ConversationTransportFailureCategory.value(
        for: UpstreamConversationTransportError.carrierStatus(503)
      ) == "carrier-status-503"
    )
    #expect(
      ConversationTransportFailureCategory.value(
        for: UpstreamConversationWireError.server(
          UpstreamRPCError(code: "session-not-found", message: "/private/path", details: .null)
        )
      ) == "server-session-not-found"
    )
    #expect(
      !ConversationTransportFailureCategory.value(
        for: UpstreamConversationWireError.server(
          UpstreamRPCError(code: "session-not-found", message: "/private/path", details: .null)
        )
      ).contains("private")
    )
  }

  @Test("A superseded session cannot publish stale history or live events")
  func sessionGenerationIsolation() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-old")
    try await requireEventually("old session history request") {
      await transport.historyCallCount == 1
    }
    store.selectSession("session-new")
    try await requireEventually("new session history request") {
      await transport.historyCallCount == 2
    }
    try await requireEventually("replacement event stream") {
      await transport.streamCount >= 2
    }

    await transport.emit(
      eventEnvelope(
        sessionID: "session-old",
        entry: userEntry(sequence: 30, id: "stale-live", text: "stale live")
      ),
      onStream: 1
    )
    try await transport.resolveHistory(
      call: 1,
      with: page([userEntry(sequence: 4, id: "new", text: "new history")])
    )
    await store.ensureConversationLoaded()

    try await transport.resolveHistory(
      call: 0,
      with: page([userEntry(sequence: 2, id: "stale", text: "stale history")])
    )
    await settleTasks()

    #expect(store.selectedSessionID == "session-new")
    #expect(store.items.map(\.id) == ["user:new"])
    #expect(store.items.map(\.text) == ["new history"])
    #expect(store.latestEventSequence == 4)
  }

  @Test("History and live delivery merge once by official event sequence")
  func historyAndLiveDeduplication() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-dedup")
    try await requireEventually("history and stream start") {
      let historyCallCount = await transport.historyCallCount
      let streamCount = await transport.streamCount
      return historyCallCount == 1 && streamCount == 1
    }
    let first = userEntry(sequence: 1, id: "first", text: "first")
    try await transport.resolveHistory(call: 0, with: page([first]))
    await store.ensureConversationLoaded()

    await transport.emit(eventEnvelope(sessionID: "session-dedup", entry: first))
    await transport.emit(
      eventEnvelope(
        sessionID: "session-dedup",
        entry: userEntry(sequence: 2, id: "second", text: "second")
      )
    )
    try await requireEventually("deduplicated live projection") {
      store.items.count == 2 && store.latestEventSequence == 2
    }

    #expect(store.items.map(\.id) == ["user:first", "user:second"])
    #expect(store.items.map(\.text) == ["first", "second"])
  }

  @Test("Streaming chunks and the final assistant event retain one stable row")
  func partialToFinalKeepsStableRow() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-streaming")
    try await requireEventually("history and stream start") {
      let historyCallCount = await transport.historyCallCount
      let streamCount = await transport.streamCount
      return historyCallCount == 1 && streamCount == 1
    }
    try await transport.resolveHistory(call: 0, with: page([]))
    await store.ensureConversationLoaded()

    await transport.emit(
      eventEnvelope(
        sessionID: "session-streaming",
        entry: assistantChunkEntry(
          sequence: 1,
          chunk: .object([
            "type": .string("block-start"),
            "index": .integer(0),
            "blockType": .string("text"),
          ])
        )
      )
    )
    await transport.emit(
      eventEnvelope(
        sessionID: "session-streaming",
        entry: assistantChunkEntry(
          sequence: 2,
          chunk: .object([
            "type": .string("text-delta"),
            "index": .integer(0),
            "text": .string("partial"),
          ])
        )
      )
    )
    try await requireEventually("streaming row") {
      store.items.first?.text == "partial"
    }
    let partial = try #require(store.items.first)

    await transport.emit(
      eventEnvelope(
        sessionID: "session-streaming",
        entry: assistantFinalEntry(sequence: 3, text: "final reply")
      )
    )
    try await requireEventually("final assistant row") {
      store.items.first?.isStreaming == false
        && store.items.first?.text == "final reply"
    }
    let final = try #require(store.items.first)

    #expect(store.items.count == 1)
    #expect(partial.id == "assistant:1:1")
    #expect(final.id == partial.id)
    #expect(partial.isStreaming)
    #expect(!final.isStreaming)
    #expect(store.observedStreamChunkCount == 2)
  }

  @Test("Published items exclude reasoning, context, and raw tool payloads")
  func storePublishesSafeConversationProjection() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-privacy")
    try await requireEventually("privacy history request") {
      await transport.historyCallCount == 1
    }
    try await transport.resolveHistory(
      call: 0,
      with: page([
        internalContextEntry(sequence: 1, text: "INTERNAL_CONTEXT_FIXTURE"),
        toolResultEntry(sequence: 2, text: "INTERNAL_TOOL_FIXTURE"),
        userEntry(sequence: 3, id: "human", text: "visible human"),
        mixedAssistantEntry(sequence: 4, text: "visible assistant"),
      ])
    )
    await store.ensureConversationLoaded()

    #expect(store.items.map(\.kind) == [.user, .assistant])
    #expect(
      store.items.map(\.text) == [
        "visible human", "visible assistant",
      ])
    #expect(!String(describing: store.items).contains("visible model reasoning"))
    #expect(store.items.allSatisfy { !$0.text.contains("INTERNAL_ARGUMENTS_FIXTURE") })
  }

  @Test("Upstream semantic projection becomes the current session authority")
  func upstreamProjectionIsAuthoritative() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-official")
    try await requireEventually("official history request") {
      await transport.historyCallCount == 1
    }
    try await transport.resolveHistory(
      call: 0,
      with: page([userEntry(sequence: 1, id: "fallback", text: "fallback")], hasMore: true)
    )
    await store.ensureConversationLoaded()

    var nativeOlderLoads = 0
    store.setUpstreamLoadOlderHandler { nativeOlderLoads += 1 }
    store.applyUpstreamProjection(
      RuntimeNativeConversationProjection(
        version: 1,
        revision: 9,
        sessionID: "session-official",
        openState: "open",
        hasMore: true,
        isLoadingOlder: false,
        isRunning: false,
        rows: [
          NativeConversationItem(
            id: "official-user",
            kind: .user,
            text: "official semantic row"
          )
        ]
      )
    )
    #expect(store.items.map(\.text) == ["official semantic row"])

    await transport.emit(
      eventEnvelope(
        sessionID: "session-official",
        entry: userEntry(sequence: 2, id: "raw", text: "raw event must not replace")
      )
    )
    await settleTasks()
    #expect(store.items.map(\.text) == ["official semantic row"])

    await store.loadOlderHistory()
    #expect(nativeOlderLoads == 1)
    #expect(await transport.historyCallCount == 1)
  }

  @Test("A loading upstream projection cannot erase restored native history")
  func loadingUpstreamProjectionPreservesRestoredHistory() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-restored")
    try await requireEventually("restored history request") {
      await transport.historyCallCount == 1
    }
    try await transport.resolveHistory(
      call: 0,
      with: page([
        userEntry(sequence: 1, id: "restored", text: "restored history")
      ])
    )
    await store.ensureConversationLoaded()

    let accepted = store.applyUpstreamProjection(
      RuntimeNativeConversationProjection(
        version: 1,
        revision: 1,
        sessionID: "session-restored",
        openState: "loading",
        hasMore: false,
        isLoadingOlder: false,
        isRunning: false,
        rows: []
      )
    )

    #expect(!accepted)
    #expect(store.items.map(\.text) == ["restored history"])
  }

  @Test("An empty open projection cannot erase matching restored history")
  func emptyOpenProjectionPreservesRestoredHistory() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-restored")
    try await requireEventually("restored history request") {
      await transport.historyCallCount == 1
    }
    try await transport.resolveHistory(
      call: 0,
      with: page([
        userEntry(sequence: 1, id: "restored", text: "restored history")
      ])
    )
    await store.ensureConversationLoaded()

    let accepted = store.applyUpstreamProjection(
      RuntimeNativeConversationProjection(
        version: 1,
        revision: 1,
        sessionID: "session-restored",
        openState: "open",
        hasMore: false,
        isLoadingOlder: false,
        isRunning: false,
        rows: []
      )
    )

    #expect(!accepted)
    #expect(store.items.map(\.text) == ["restored history"])
  }

  @Test("Generation cancellation is available only while running and coalesces repeats")
  func generationCancellationState() async {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    store.selectSession("session-cancel")
    defer { store.selectSession(nil) }

    #expect(!(await store.requestGenerationCancellation()))
    #expect(await transport.cancelCallCount == 0)

    store.applyUpstreamProjection(
      RuntimeNativeConversationProjection(
        version: 1,
        revision: 1,
        sessionID: "session-cancel",
        openState: "open",
        hasMore: false,
        isLoadingOlder: false,
        isRunning: true,
        rows: []
      )
    )
    #expect(store.isGenerationRunning)
    #expect(await store.requestGenerationCancellation())
    #expect(store.isGenerationCancellationPending)
    #expect(!(await store.requestGenerationCancellation()))
    #expect(await transport.cancelCallCount == 1)
    #expect(await transport.lastCancelledSessionID == "session-cancel")

    store.applyUpstreamProjection(
      RuntimeNativeConversationProjection(
        version: 1,
        revision: 2,
        sessionID: "session-cancel",
        openState: "open",
        hasMore: false,
        isLoadingOlder: false,
        isRunning: false,
        rows: []
      )
    )
    #expect(!store.isGenerationRunning)
    #expect(!store.isGenerationCancellationPending)
  }

  @Test("A rejected cancellation restores the actionable running state")
  func rejectedGenerationCancellation() async {
    let transport = ControllableConversationTransport()
    await transport.rejectCancellation()
    let store = NativeConversationStore(transport: transport)
    store.selectSession("session-rejected-cancel")
    defer { store.selectSession(nil) }
    store.applyUpstreamProjection(
      RuntimeNativeConversationProjection(
        version: 1,
        revision: 1,
        sessionID: "session-rejected-cancel",
        openState: "open",
        hasMore: false,
        isLoadingOlder: false,
        isRunning: true,
        rows: []
      )
    )

    #expect(!(await store.requestGenerationCancellation()))
    #expect(store.isGenerationRunning)
    #expect(!store.isGenerationCancellationPending)
    #expect(await transport.cancelCallCount == 1)
  }

  @Test("Queue snapshots and interaction requests stay scoped to the selected session")
  func queueAndInteractionState() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    store.selectSession("session-interactions")
    defer { store.selectSession(nil) }
    try await requireEventually("interaction stream") {
      let streamCount = await transport.streamCount
      let historyCallCount = await transport.historyCallCount
      return streamCount == 1 && historyCallCount == 1
    }
    try await transport.resolveHistory(call: 0, with: page([]))
    await store.ensureConversationLoaded()

    let queued = UpstreamQueueItem(
      id: "queued-1",
      placement: .queued,
      message: .object([
        "content": .array([
          .object(["type": .string("text"), "text": .string("follow up")])
        ])
      ])
    )
    await transport.emit(
      UpstreamConversationStreamEnvelope(
        rpcID: "queue-push",
        frame: .queue(sessionID: "session-interactions", items: [queued])
      )
    )
    try await requireEventually("queue projection") { store.queueItems == [queued] }

    #expect(await store.updateQueueItem("queued-1", action: .steer))
    #expect(await transport.queueActions.count == 1)

    let approval = UpstreamApprovalRequest(
      rpcID: "approval-rpc",
      sessionID: "session-interactions",
      approvalID: "approval-1",
      toolName: "bash",
      callID: nil,
      reason: "Run command"
    )
    await transport.emit(
      UpstreamConversationStreamEnvelope(
        rpcID: approval.rpcID,
        frame: .approvalRequested(approval)
      )
    )
    try await requireEventually("approval projection") { store.pendingApproval == approval }
    #expect(await store.respondToApproval(.rejected))
    #expect(store.pendingApproval == approval)
    #expect(await transport.approvalResponses == [.rejected])
    await transport.emit(
      UpstreamConversationStreamEnvelope(
        rpcID: "approval-resolved",
        frame: .approvalResolved(
          sessionID: "session-interactions",
          approvalID: "approval-1"
        )
      )
    )
    try await requireEventually("approval resolution") { store.pendingApproval == nil }

    let question = UpstreamQuestionRequest(
      rpcID: "question-rpc",
      sessionID: "session-interactions",
      questions: [
        UpstreamQuestionItem(
          id: "decision",
          question: "Continue?",
          detail: nil,
          header: "Decision",
          options: [UpstreamQuestionOption(label: "Yes", description: nil)],
          multiSelect: false,
          intent: nil
        )
      ]
    )
    await transport.emit(
      UpstreamConversationStreamEnvelope(
        rpcID: question.rpcID,
        frame: .questionRequested(question)
      )
    )
    try await requireEventually("question projection") { store.pendingQuestion == question }
    let answer = UpstreamQuestionAnswer(
      answers: [UpstreamQuestionAnswerItem(id: "decision", selected: ["Yes"], custom: nil)]
    )
    #expect(await store.respondToQuestion(answer))
    #expect(await transport.questionResponses == [answer])
  }

  @Test("Loading an older page prepends rows and keeps the tail")
  func olderHistoryPrepends() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-long")
    try await requireEventually("initial history request") {
      await transport.historyCallCount == 1
    }
    try await transport.resolveHistory(
      call: 0,
      with: page(
        [
          userEntry(sequence: 11, id: "eleven", text: "eleven"),
          userEntry(sequence: 12, id: "twelve", text: "twelve"),
        ], hasMore: true)
    )
    await store.ensureConversationLoaded()

    let load = Task { await store.loadOlderHistory() }
    try await requireEventually("older history request") {
      await transport.historyCallCount == 2
    }
    let request = try #require(await transport.historyCall(at: 1))
    #expect(request.sessionID == "session-long")
    #expect(request.beforeSequence == 11)
    try await transport.resolveHistory(
      call: 1,
      with: page([
        userEntry(sequence: 1, id: "one", text: "one"),
        userEntry(sequence: 2, id: "two", text: "two"),
      ])
    )
    await load.value

    #expect(
      store.items.map(\.id) == [
        "user:one", "user:two", "user:eleven", "user:twelve",
      ])
    #expect(!store.hasMoreHistory)
    #expect(store.latestEventSequence == 12)
  }

  @Test("Reconnect subscription repairs a missing official tail")
  func reconnectSubscriptionRepairsTail() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-reconnect")
    try await requireEventually("initial stream and history") {
      let historyCallCount = await transport.historyCallCount
      let streamCount = await transport.streamCount
      return historyCallCount == 1 && streamCount == 1
    }
    let first = userEntry(sequence: 1, id: "one", text: "one")
    try await transport.resolveHistory(call: 0, with: page([first]))
    await store.ensureConversationLoaded()

    await transport.finishStream(0, throwing: ControlledFailure.disconnected)
    try await requireEventually("reconnected stream", timeout: .seconds(3)) {
      await transport.streamCount >= 2
    }
    await transport.emit(
      UpstreamConversationStreamEnvelope(
        rpcID: "subscribed-3",
        frame: .subscribed(sessionID: "session-reconnect", lastSequence: 3)
      ),
      onStream: 1
    )
    try await requireEventually("tail repair history request") {
      await transport.historyCallCount == 2
    }
    let repairRequest = try #require(await transport.historyCall(at: 1))
    #expect(repairRequest.beforeSequence == nil)
    try await transport.resolveHistory(
      call: 1,
      with: page([
        first,
        userEntry(sequence: 2, id: "two", text: "two"),
        assistantFinalEntry(sequence: 3, text: "repaired reply"),
      ])
    )
    try await requireEventually("repaired tail projection") {
      store.latestEventSequence == 3 && store.items.count == 3
    }

    #expect(store.items.map(\.id) == ["user:one", "user:two", "assistant:1:1"])
    #expect(store.items.last?.text == "repaired reply")
    #expect(store.failureMessage == nil)
  }

  @Test("The store never invents a message before an authoritative event arrives")
  func noOptimisticMessages() async throws {
    let transport = ControllableConversationTransport()
    let store = NativeConversationStore(transport: transport)
    defer { store.selectSession(nil) }

    store.selectSession("session-authoritative")
    try await requireEventually("initial history request") {
      await transport.historyCallCount == 1
    }
    #expect(store.items.isEmpty)
    #expect(store.isLoadingInitialHistory)

    try await transport.resolveHistory(call: 0, with: page([]))
    await store.ensureConversationLoaded()
    store.refreshAfterUpstreamMutation()
    try await requireEventually("post-mutation authoritative tail request") {
      await transport.historyCallCount == 2
    }

    #expect(store.items.isEmpty)
    #expect(await transport.promptCallCount == 0)
    try await transport.resolveHistory(call: 1, with: page([]))
    try await requireEventually("tail repair completes") {
      !store.isLoadingInitialHistory && store.failureMessage == nil
    }
    #expect(store.items.isEmpty)
  }
}

private enum ControlledFailure: Error {
  case disconnected
}

private actor ControllableConversationTransportState {
  struct HistoryCall: Equatable, Sendable {
    let sessionID: String
    let beforeSequence: Int?
    let maxMessages: Int?
  }

  private struct PendingHistory {
    let call: HistoryCall
    let continuation: CheckedContinuation<UpstreamHistoryPage, Error>
  }

  private(set) var historyCalls: [HistoryCall] = []
  private(set) var promptCalls = 0
  private(set) var cancelCallCount = 0
  private(set) var lastCancelledSessionID: String?
  private(set) var queueActions: [UpstreamQueueAction] = []
  private(set) var approvalResponses: [UpstreamApprovalOutcome] = []
  private(set) var questionResponses: [UpstreamQuestionAnswer] = []
  private var rejectsCancellation = false
  private var pendingHistory: [Int: PendingHistory] = [:]
  private var streamContinuations:
    [AsyncThrowingStream<UpstreamConversationStreamEnvelope, Error>.Continuation] = []

  func history(
    sessionID: String,
    beforeSequence: Int?,
    maxMessages: Int?
  ) async throws -> UpstreamHistoryPage {
    let call = HistoryCall(
      sessionID: sessionID,
      beforeSequence: beforeSequence,
      maxMessages: maxMessages
    )
    let index = historyCalls.count
    historyCalls.append(call)
    return try await withCheckedThrowingContinuation { continuation in
      pendingHistory[index] = PendingHistory(call: call, continuation: continuation)
    }
  }

  func resolveHistory(call index: Int, with page: UpstreamHistoryPage) throws {
    guard let pending = pendingHistory.removeValue(forKey: index) else {
      throw ControllableTransportError.missingHistoryCall(index)
    }
    pending.continuation.resume(returning: page)
  }

  func recordPrompt() {
    promptCalls += 1
  }

  func recordCancellation(sessionID: String) throws {
    cancelCallCount += 1
    lastCancelledSessionID = sessionID
    if rejectsCancellation {
      throw ControlledFailure.disconnected
    }
  }

  func rejectCancellation() {
    rejectsCancellation = true
  }

  func recordQueueAction(_ action: UpstreamQueueAction) {
    queueActions.append(action)
  }

  func recordApprovalResponse(_ outcome: UpstreamApprovalOutcome) {
    approvalResponses.append(outcome)
  }

  func recordQuestionResponse(_ answer: UpstreamQuestionAnswer) {
    questionResponses.append(answer)
  }

  func addStream(
    _ continuation: AsyncThrowingStream<UpstreamConversationStreamEnvelope, Error>.Continuation
  ) {
    streamContinuations.append(continuation)
  }

  func emit(_ envelope: UpstreamConversationStreamEnvelope, onStream index: Int?) throws {
    let target = index ?? (streamContinuations.count - 1)
    guard streamContinuations.indices.contains(target) else {
      throw ControllableTransportError.missingStream(target)
    }
    streamContinuations[target].yield(envelope)
  }

  func finishStream(_ index: Int, throwing error: (any Error)?) throws {
    guard streamContinuations.indices.contains(index) else {
      throw ControllableTransportError.missingStream(index)
    }
    if let error {
      streamContinuations[index].finish(throwing: error)
    } else {
      streamContinuations[index].finish()
    }
  }

  var streamCount: Int {
    streamContinuations.count
  }
}

private enum ControllableTransportError: Error {
  case missingHistoryCall(Int)
  case missingStream(Int)
  case unsupportedAction
}

private final class ControllableConversationTransport: UpstreamConversationTransporting,
  @unchecked Sendable
{
  private let state = ControllableConversationTransportState()

  var historyCallCount: Int {
    get async { await state.historyCalls.count }
  }

  var promptCallCount: Int {
    get async { await state.promptCalls }
  }

  var streamCount: Int {
    get async { await state.streamCount }
  }

  var cancelCallCount: Int {
    get async { await state.cancelCallCount }
  }

  var lastCancelledSessionID: String? {
    get async { await state.lastCancelledSessionID }
  }

  var queueActions: [UpstreamQueueAction] {
    get async { await state.queueActions }
  }

  var approvalResponses: [UpstreamApprovalOutcome] {
    get async { await state.approvalResponses }
  }

  var questionResponses: [UpstreamQuestionAnswer] {
    get async { await state.questionResponses }
  }

  func rejectCancellation() async {
    await state.rejectCancellation()
  }

  func historyCall(at index: Int) async -> ControllableConversationTransportState.HistoryCall? {
    let calls = await state.historyCalls
    guard calls.indices.contains(index) else { return nil }
    return calls[index]
  }

  func history(
    sessionID: String,
    beforeSequence: Int?,
    maxMessages: Int?
  ) async throws -> UpstreamHistoryPage {
    try await state.history(
      sessionID: sessionID,
      beforeSequence: beforeSequence,
      maxMessages: maxMessages
    )
  }

  func prompt(
    sessionID: String,
    mode: UpstreamPromptMode,
    content: [UpstreamPromptContentPart],
    clientTimeZone: String?
  ) async throws -> UpstreamPromptResponse {
    await state.recordPrompt()
    return UpstreamPromptResponse()
  }

  func cancel(sessionID: String) async throws {
    try await state.recordCancellation(sessionID: sessionID)
  }

  func updateQueue(
    sessionID: String,
    itemID: String,
    action: UpstreamQueueAction
  ) async throws {
    _ = (sessionID, itemID)
    await state.recordQueueAction(action)
  }

  func respondToApproval(
    _ request: UpstreamApprovalRequest,
    outcome: UpstreamApprovalOutcome
  ) async throws {
    _ = request
    await state.recordApprovalResponse(outcome)
  }

  func respondToQuestion(
    _ request: UpstreamQuestionRequest,
    answer: UpstreamQuestionAnswer
  ) async throws {
    _ = request
    await state.recordQuestionResponse(answer)
  }

  func attachment(
    sessionID: String,
    attachmentID: String
  ) async throws -> UpstreamAttachmentValue {
    _ = (sessionID, attachmentID)
    throw ControllableTransportError.unsupportedAction
  }

  func previewMarkdown(
    sessionID: String,
    path: String
  ) async throws -> UpstreamPreviewMarkdownValue {
    _ = (sessionID, path)
    throw ControllableTransportError.unsupportedAction
  }

  func saveMarkdown(
    sessionID: String,
    path: String,
    content: String,
    expectedModifiedAt: Double
  ) async throws -> UpstreamPreviewMarkdownValue {
    _ = (sessionID, path, content, expectedModifiedAt)
    throw ControllableTransportError.unsupportedAction
  }

  func fork(sessionID: String, atSequence: Int) async throws -> String {
    _ = (sessionID, atSequence)
    throw ControllableTransportError.unsupportedAction
  }

  func openPath(_ path: String) async throws {
    _ = path
    throw ControllableTransportError.unsupportedAction
  }

  func eventStream() -> AsyncThrowingStream<UpstreamConversationStreamEnvelope, Error> {
    AsyncThrowingStream { continuation in
      Task { await state.addStream(continuation) }
    }
  }

  func resolveHistory(call index: Int, with page: UpstreamHistoryPage) async throws {
    try await state.resolveHistory(call: index, with: page)
  }

  func emit(
    _ envelope: UpstreamConversationStreamEnvelope,
    onStream index: Int? = nil
  ) async {
    try? await state.emit(envelope, onStream: index)
  }

  func finishStream(_ index: Int, throwing error: (any Error)? = nil) async {
    try? await state.finishStream(index, throwing: error)
  }
}

@MainActor
private func requireEventually(
  _ description: String,
  timeout: Duration = .seconds(3),
  condition: @escaping @MainActor () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let deadline = clock.now.advanced(by: timeout)
  while clock.now < deadline {
    if await condition() { return }
    try await Task.sleep(for: .milliseconds(5))
  }
  Issue.record("Timed out waiting for \(description)")
  throw ControllableTransportError.missingStream(-1)
}

private func settleTasks() async {
  for _ in 0..<8 {
    await Task.yield()
  }
}

private func page(
  _ entries: [UpstreamHistoryEntry],
  hasMore: Bool = false
) -> UpstreamHistoryPage {
  UpstreamHistoryPage(events: entries, hasMore: hasMore, projections: nil)
}

private func eventEnvelope(
  sessionID: String,
  entry: UpstreamHistoryEntry
) -> UpstreamConversationStreamEnvelope {
  UpstreamConversationStreamEnvelope(
    rpcID: "event-\(entry.event.sequence)",
    frame: .event(sessionID: sessionID, entry: entry)
  )
}

private func userEntry(
  sequence: Int,
  id: String,
  text: String
) -> UpstreamHistoryEntry {
  UpstreamHistoryEntry(
    event: UpstreamSessionEvent(
      type: "user/message",
      sequence: sequence,
      time: Double(sequence),
      data: .object([
        "id": .string(id),
        "role": .string("user"),
        "content": .array([
          .object([
            "type": .string("text"),
            "text": .string(text),
          ])
        ]),
        "source": .object(["kind": .string("user")]),
      ]),
      sourceEventSequences: nil,
      surfaceOperation: .append,
      ignorable: nil
    ),
    view: nil
  )
}

private func assistantChunkEntry(
  sequence: Int,
  chunk: UpstreamJSONValue
) -> UpstreamHistoryEntry {
  UpstreamHistoryEntry(
    event: UpstreamSessionEvent(
      type: "assistant/chunk",
      sequence: sequence,
      time: Double(sequence),
      data: .object([
        "turn": .integer(1),
        "step": .integer(1),
        "chunk": chunk,
      ]),
      sourceEventSequences: nil,
      surfaceOperation: nil,
      ignorable: nil
    ),
    view: nil
  )
}

private func assistantFinalEntry(sequence: Int, text: String) -> UpstreamHistoryEntry {
  UpstreamHistoryEntry(
    event: UpstreamSessionEvent(
      type: "assistant/message",
      sequence: sequence,
      time: Double(sequence),
      data: .object([
        "turn": .integer(1),
        "step": .integer(1),
        "message": .object([
          "id": .string("assistant-final"),
          "role": .string("assistant"),
          "content": .array([
            .object([
              "type": .string("text"),
              "text": .string(text),
            ])
          ]),
          "source": .object([
            "kind": .string("model"),
            "provider": .string("deepseek"),
            "model": .string("deepseek-chat"),
          ]),
        ]),
      ]),
      sourceEventSequences: nil,
      surfaceOperation: .append,
      ignorable: nil
    ),
    view: nil
  )
}

private func internalContextEntry(sequence: Int, text: String) -> UpstreamHistoryEntry {
  UpstreamHistoryEntry(
    event: UpstreamSessionEvent(
      type: "user/message",
      sequence: sequence,
      time: Double(sequence),
      data: .object([
        "id": .string("context-\(sequence)"),
        "role": .string("user"),
        "content": .array([
          .object([
            "type": .string("text"),
            "text": .string(text),
          ])
        ]),
        "source": .object([
          "kind": .string("plugin"),
          "plugin": .string("agent-instructions"),
          "form": .string("instructions"),
        ]),
      ]),
      sourceEventSequences: nil,
      surfaceOperation: .append,
      ignorable: nil
    ),
    view: nil
  )
}

private func toolResultEntry(sequence: Int, text: String) -> UpstreamHistoryEntry {
  UpstreamHistoryEntry(
    event: UpstreamSessionEvent(
      type: "tool/result",
      sequence: sequence,
      time: Double(sequence),
      data: .object([
        "turn": .integer(1),
        "step": .integer(1),
        "message": .object([
          "role": .string("user"),
          "source": .object([
            "kind": .string("tool"),
            "callId": .string("call-\(sequence)"),
          ]),
          "content": .array([
            .object([
              "type": .string("tool-result"),
              "toolCallId": .string("call-\(sequence)"),
              "content": .array([
                .object([
                  "type": .string("text"),
                  "text": .string(text),
                ])
              ]),
            ])
          ]),
        ]),
      ]),
      sourceEventSequences: nil,
      surfaceOperation: .append,
      ignorable: nil
    ),
    view: nil
  )
}

private func mixedAssistantEntry(sequence: Int, text: String) -> UpstreamHistoryEntry {
  UpstreamHistoryEntry(
    event: UpstreamSessionEvent(
      type: "assistant/message",
      sequence: sequence,
      time: Double(sequence),
      data: .object([
        "turn": .integer(2),
        "step": .integer(1),
        "message": .object([
          "id": .string("assistant-mixed"),
          "role": .string("assistant"),
          "content": .array([
            .object(["type": .string("text"), "text": .string(text)]),
            .object([
              "type": .string("reasoning"),
              "text": .string("visible model reasoning"),
            ]),
            .object([
              "type": .string("tool-call"),
              "id": .string("call-private"),
              "name": .string("internal-tool"),
              "arguments": .string("INTERNAL_ARGUMENTS_FIXTURE"),
            ]),
          ]),
          "source": .object([
            "kind": .string("model"),
            "provider": .string("deepseek"),
            "model": .string("deepseek-chat"),
          ]),
        ]),
      ]),
      sourceEventSequences: nil,
      surfaceOperation: .append,
      ignorable: nil
    ),
    view: nil
  )
}
