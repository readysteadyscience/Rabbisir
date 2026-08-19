import Foundation

/// User-visible content admitted to the native conversation surface.
enum UpstreamConversationBlock: Equatable, Sendable {
  case text(String)
  case image(UpstreamImageAttachmentReference)
}

/// One image reference carried by an upstream runtime conversation block.
struct UpstreamImageAttachmentReference: Equatable, Sendable {
  let attachmentID: String
  let mediaType: String
  let bytes: Int?
  let pixelWidth: Int?
  let pixelHeight: Int?
  let name: String?
}

enum UpstreamConversationRole: Equatable, Sendable {
  case user
  case assistant
}

/// One stable row projected from authoritative upstream session events.
struct UpstreamConversationMessage: Identifiable, Equatable, Sendable {
  let id: String
  let sequence: Int
  let time: Double
  let turn: Int?
  let role: UpstreamConversationRole
  let blocks: [UpstreamConversationBlock]
  let isStreaming: Bool
}

/// Authoritative lifecycle boundaries for one upstream turn.
struct UpstreamConversationTurn: Equatable, Sendable {
  let number: Int
  let startTime: Double?
  let endTime: Double?

  var isComplete: Bool { endTime != nil }
}

/// Immutable native transcript projection after history and live events are merged.
struct UpstreamConversationProjection: Equatable, Sendable {
  let messages: [UpstreamConversationMessage]
  let rows: [UpstreamConversationRow]
  let turns: [Int: UpstreamConversationTurn]
  let latestSequence: Int?
}

/// Upstream runtime conversation nodes admitted to the native presentation layer.
struct UpstreamConversationRow: Identifiable, Equatable, Sendable {
  enum Kind: Equatable, Sendable {
    case user
    case assistant
    case image
    case tool
    case command
    case compaction
    case notice
    case error
    case turnTail
  }

  let id: String
  let kind: Kind
  let sequence: Int
  let presentationOrder: Int
  let turn: Int?
  let text: String
  let detail: String?
  let images: [UpstreamImageAttachmentReference]
  let isStreaming: Bool
  let copyText: String?
  let tool: UpstreamToolPresentation?
  let turnTail: UpstreamTurnTailPresentation?

  init(
    id: String,
    kind: Kind,
    sequence: Int,
    presentationOrder: Int,
    turn: Int?,
    text: String,
    detail: String?,
    images: [UpstreamImageAttachmentReference] = [],
    isStreaming: Bool,
    copyText: String?,
    tool: UpstreamToolPresentation?,
    turnTail: UpstreamTurnTailPresentation?
  ) {
    self.id = id
    self.kind = kind
    self.sequence = sequence
    self.presentationOrder = presentationOrder
    self.turn = turn
    self.text = text
    self.detail = detail
    self.images = images
    self.isStreaming = isStreaming
    self.copyText = copyText
    self.tool = tool
    self.turnTail = turnTail
  }
}

struct UpstreamToolPresentation: Equatable, Sendable {
  enum State: Equatable, Sendable {
    case running
    case succeeded
    case failed
    case stopped
  }

  let title: String
  let summary: String?
  let state: State
}

struct UpstreamTurnTailPresentation: Equatable, Sendable {
  let durationMilliseconds: Double?
  let firstTokenLatencyMilliseconds: Double?
  let tokensPerSecond: Double?
  let producedFiles: [String]
  let branchSequence: Int?
  let isBranchUnavailable: Bool
}

/// Idempotently merges paginated history and mux events, then projects stable message rows.
struct ConversationReducer: Sendable {
  private var entriesBySequence: [Int: UpstreamHistoryEntry] = [:]
  private var turnBoundariesBySequence: [Int: UpstreamHistoryEntry] = [:]
  private var toolCallsByID: [String: UpstreamHistoryEntry] = [:]
  private var toolResultsByID: [String: UpstreamHistoryEntry] = [:]
  private var statusEntriesBySequence: [Int: UpstreamHistoryEntry] = [:]
  private var stepStartsByKey: [AssistantKey: UpstreamHistoryEntry] = [:]
  private var firstTokenTimeByKey: [AssistantKey: Double] = [:]
  private var commandRunsByID: [String: UpstreamHistoryEntry] = [:]
  private var commandDoneByID: [String: UpstreamHistoryEntry] = [:]
  private var partials: [AssistantKey: PartialAssistant] = [:]
  private var finalizedAssistantKeys = Set<AssistantKey>()

  var eventCount: Int {
    entriesBySequence.count
      + toolCallsByID.count
      + toolResultsByID.keys.filter { toolCallsByID[$0] != nil }.count
      + statusEntriesBySequence.count
      + stepStartsByKey.count
      + commandRunsByID.count
      + commandDoneByID.keys.filter { commandRunsByID[$0] != nil }.count
      + partials.values.reduce(0) { $0 + $1.eventCount }
  }

  mutating func reset(to page: UpstreamHistoryPage) {
    entriesBySequence.removeAll(keepingCapacity: true)
    turnBoundariesBySequence.removeAll(keepingCapacity: true)
    toolCallsByID.removeAll(keepingCapacity: true)
    toolResultsByID.removeAll(keepingCapacity: true)
    statusEntriesBySequence.removeAll(keepingCapacity: true)
    stepStartsByKey.removeAll(keepingCapacity: true)
    firstTokenTimeByKey.removeAll(keepingCapacity: true)
    commandRunsByID.removeAll(keepingCapacity: true)
    commandDoneByID.removeAll(keepingCapacity: true)
    partials.removeAll(keepingCapacity: true)
    finalizedAssistantKeys.removeAll(keepingCapacity: true)
    ingestPage(page)
  }

  mutating func merge(_ page: UpstreamHistoryPage) {
    ingestPage(page)
  }

  @discardableResult
  mutating func ingest(_ entry: UpstreamHistoryEntry) -> Bool {
    let event = entry.event
    switch event.type {
    case "assistant/chunk":
      guard let key = assistantKey(event.data), !finalizedAssistantKeys.contains(key) else {
        return false
      }
      if isTokenDelta(event.data), firstTokenTimeByKey[key] == nil {
        firstTokenTimeByKey[key] = event.time
      }
      var partial = partials[key] ?? PartialAssistant(key: key)
      let changed = partial.ingest(event)
      partials[key] = partial
      return changed
    case "assistant/message":
      guard let key = assistantKey(event.data) else { return false }
      finalizedAssistantKeys.insert(key)
      let removedPartial = partials.removeValue(forKey: key) != nil
      guard isVisibleAssistantMessage(event) else {
        entriesBySequence.removeValue(forKey: event.sequence)
        return removedPartial
      }
      let prior = entriesBySequence.updateValue(entry, forKey: event.sequence)
      return prior != entry
    case "user/message":
      guard isVisibleUserMessage(event) else {
        entriesBySequence.removeValue(forKey: event.sequence)
        return false
      }
      let prior = entriesBySequence.updateValue(entry, forKey: event.sequence)
      return prior != entry
    case "turn/start", "turn/end":
      guard turnNumber(event.data) != nil else { return false }
      let prior = turnBoundariesBySequence.updateValue(entry, forKey: event.sequence)
      return prior != entry
    case "step/start":
      guard let key = assistantKey(event.data) else { return false }
      let prior = stepStartsByKey.updateValue(entry, forKey: key)
      return prior != entry
    case "tool/call":
      guard let callID = toolCallID(event.data),
        turnNumber(event.data) != nil,
        upstreamToolCallView(entry.view) != nil
      else { return false }
      let prior = toolCallsByID.updateValue(entry, forKey: callID)
      return prior != entry
    case "tool/result":
      guard event.surfaceOperation == .append,
        let callID = toolResultCallID(event.data)
      else { return false }
      let prior = toolResultsByID.updateValue(entry, forKey: callID)
      return prior != entry
    case "command/run":
      guard let commandID = stringIdentity(event.data, key: "commandId") else { return false }
      let prior = commandRunsByID.updateValue(entry, forKey: commandID)
      return prior != entry
    case "command/done":
      guard let commandID = stringIdentity(event.data, key: "commandId") else { return false }
      let prior = commandDoneByID.updateValue(entry, forKey: commandID)
      return prior != entry
    case "llm/retry", "llm/retry-started", "compaction/summary":
      let prior = statusEntriesBySequence.updateValue(entry, forKey: event.sequence)
      return prior != entry
    default:
      return false
    }
  }

  func projection(
    copy: RabbisirCopy = RabbisirCopy(language: .chinese)
  ) -> UpstreamConversationProjection {
    let turns = projectedTurns()
    let entries = entriesBySequence.values.sorted { left, right in
      left.event.sequence < right.event.sequence
    }
    var messages: [UpstreamConversationMessage] = []

    for entry in entries {
      let event = entry.event
      switch event.type {
      case "user/message":
        if let message = projectedUserMessage(
          event,
          turn: turnContaining(sequence: event.sequence)
        ) {
          messages.append(message)
        }
      case "assistant/message":
        guard let key = assistantKey(event.data),
          let message = projectedAssistantMessage(event, key: key)
        else { continue }
        messages.append(message)
      default:
        continue
      }
    }

    for partial in partials.values {
      let isStreaming = turns[partial.key.turn]?.endTime == nil
      if let message = partial.message(isStreaming: isStreaming) {
        messages.append(message)
      }
    }
    messages.sort {
      if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
      return $0.id < $1.id
    }
    return UpstreamConversationProjection(
      messages: messages,
      rows: projectedRows(messages: messages, turns: turns, copy: copy),
      turns: turns,
      latestSequence: ([
        entries.last?.event.sequence,
        turnBoundariesBySequence.keys.max(),
        stepStartsByKey.values.map(\.event.sequence).max(),
      ]
        + partials.values.map(\.latestSequence))
        .compactMap { $0 }
        .max()
    )
  }

  private mutating func ingestPage(_ page: UpstreamHistoryPage) {
    for entry in page.events {
      ingest(entry)
    }
  }

  private func projectedTurns() -> [Int: UpstreamConversationTurn] {
    var starts: [Int: Double] = [:]
    var ends: [Int: Double] = [:]
    for entry in turnBoundariesBySequence.values {
      guard let turn = turnNumber(entry.event.data) else { continue }
      switch entry.event.type {
      case "turn/start": starts[turn] = entry.event.time
      case "turn/end": ends[turn] = entry.event.time
      default: break
      }
    }
    return Set(starts.keys).union(ends.keys).reduce(into: [:]) { result, turn in
      result[turn] = UpstreamConversationTurn(
        number: turn,
        startTime: starts[turn],
        endTime: ends[turn]
      )
    }
  }

  private func turnContaining(sequence: Int) -> Int? {
    var openTurn: Int?
    for entry in turnBoundariesBySequence.values.sorted(by: {
      $0.event.sequence < $1.event.sequence
    }) where entry.event.sequence <= sequence {
      guard let turn = turnNumber(entry.event.data) else { continue }
      switch entry.event.type {
      case "turn/start": openTurn = turn
      case "turn/end" where openTurn == turn: openTurn = nil
      default: break
      }
    }
    return openTurn
  }

  private func projectedRows(
    messages: [UpstreamConversationMessage],
    turns: [Int: UpstreamConversationTurn],
    copy: RabbisirCopy
  ) -> [UpstreamConversationRow] {
    var rows: [UpstreamConversationRow] = []
    let partialRowsByID = Dictionary(
      uniqueKeysWithValues: partials.values.map {
        let isStreaming = turns[$0.key.turn]?.endTime == nil
        return ($0.key.stableID, $0.rows(copy: copy, isStreaming: isStreaming))
      }
    )
    let finalEntries = entriesBySequence.values.reduce(into: [String: UpstreamHistoryEntry]()) {
      result, entry in
      guard entry.event.type == "assistant/message",
        let key = assistantKey(entry.event.data)
      else { return }
      result[key.stableID] = entry
    }

    for message in messages {
      switch message.role {
      case .user:
        let text = joinedVisibleText(message.blocks)
        rows.append(
          UpstreamConversationRow(
            id: message.id,
            kind: .user,
            sequence: message.sequence,
            presentationOrder: 0,
            turn: message.turn,
            text: text,
            detail: nil,
            images: message.blocks.compactMap(\.imageValue),
            isStreaming: false,
            copyText: text.isEmpty ? nil : text,
            tool: nil,
            turnTail: nil
          ))
      case .assistant:
        if let entry = finalEntries[message.id] {
          rows.append(contentsOf: projectedAssistantRows(entry, fallback: message, copy: copy))
        } else if let partialRows = partialRowsByID[message.id] {
          rows.append(contentsOf: partialRows)
        } else {
          let text = joinedVisibleText(message.blocks)
          rows.append(
            UpstreamConversationRow(
              id: message.id,
              kind: .assistant,
              sequence: message.sequence,
              presentationOrder: 0,
              turn: message.turn,
              text: text,
              detail: nil,
              isStreaming: message.isStreaming,
              copyText: nil,
              tool: nil,
              turnTail: nil
            ))
        }
      }
    }

    let representedFinalIDs = Set(
      messages
        .filter { $0.role == .assistant }
        .map(\.id)
    )
    for (id, entry) in finalEntries where !representedFinalIDs.contains(id) {
      guard let key = assistantKey(entry.event.data) else { continue }
      rows.append(
        contentsOf: projectedAssistantRows(
          entry,
          fallback: UpstreamConversationMessage(
            id: id,
            sequence: entry.event.sequence,
            time: entry.event.time,
            turn: key.turn,
            role: .assistant,
            blocks: [],
            isStreaming: false
          ),
          copy: copy
        ))
    }

    for (callID, callEntry) in toolCallsByID {
      guard
        let row = projectedToolRow(
          callID: callID,
          callEntry: callEntry,
          resultEntry: toolResultsByID[callID],
          copy: copy
        )
      else { continue }
      rows.append(row)
    }

    rows.append(contentsOf: projectedCommandRows())
    rows.append(contentsOf: projectedStatusRows(turns: turns, copy: copy))

    rows.sort {
      if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
      if $0.presentationOrder != $1.presentationOrder {
        return $0.presentationOrder < $1.presentationOrder
      }
      return $0.id < $1.id
    }

    for turn in turns.values.filter(\.isComplete).sorted(by: { $0.number < $1.number }) {
      guard let closing = closingAssistant(turn: turn.number) else { continue }
      let files = producedFiles(turn: turn.number, through: closing.sequence)
      let metrics = turnMetrics(turn: turn.number)
      rows.append(
        UpstreamConversationRow(
          id: "turn-tail:\(turn.number)",
          kind: .turnTail,
          sequence: max(
            closing.sequence,
            turnEndSequence(turn.number) ?? closing.sequence
          ),
          presentationOrder: .max,
          turn: turn.number,
          text: "",
          detail: nil,
          isStreaming: false,
          copyText: closing.text,
          tool: nil,
          turnTail: UpstreamTurnTailPresentation(
            durationMilliseconds: durationMilliseconds(turn),
            firstTokenLatencyMilliseconds: metrics.firstTokenLatencyMilliseconds,
            tokensPerSecond: metrics.tokensPerSecond,
            producedFiles: files,
            branchSequence: closing.sequence,
            isBranchUnavailable: latestTranscriptSequence(turn: turn.number) != closing.sequence
          )
        ))
    }

    rows.sort {
      if $0.sequence != $1.sequence { return $0.sequence < $1.sequence }
      if $0.presentationOrder != $1.presentationOrder {
        return $0.presentationOrder < $1.presentationOrder
      }
      if $0.kind == .turnTail { return false }
      if $1.kind == .turnTail { return true }
      return $0.id < $1.id
    }
    return rows
  }

  private func projectedAssistantRows(
    _ entry: UpstreamHistoryEntry,
    fallback: UpstreamConversationMessage,
    copy: RabbisirCopy
  ) -> [UpstreamConversationRow] {
    guard let message = entry.event.data.objectValue?["message"]?.objectValue else {
      return []
    }
    var rows: [UpstreamConversationRow] = []
    let content = message["content"]?.arrayValue ?? []
    var emittedTextCount = 0
    for (index, block) in content.enumerated() {
      guard let object = block.objectValue,
        let type = object["type"]?.stringValue
      else { continue }
      switch type {
      case "reasoning":
        continue
      case "text":
        guard let text = object["text"]?.stringValue, !text.isEmpty else { continue }
        let rowID =
          emittedTextCount == 0
          ? fallback.id
          : "\(fallback.id):text:\(index)"
        emittedTextCount += 1
        rows.append(
          UpstreamConversationRow(
            id: rowID,
            kind: .assistant,
            sequence: fallback.sequence,
            presentationOrder: index,
            turn: fallback.turn,
            text: text,
            detail: nil,
            isStreaming: fallback.isStreaming,
            copyText: nil,
            tool: nil,
            turnTail: nil
          ))
      case "image":
        guard let image = imageAttachment(object["attachment"]) else { continue }
        rows.append(
          UpstreamConversationRow(
            id: "\(fallback.id):image:\(index)",
            kind: .image,
            sequence: fallback.sequence,
            presentationOrder: index,
            turn: fallback.turn,
            text: image.name ?? copy.conversationImageFallback,
            detail: nil,
            images: [image],
            isStreaming: false,
            copyText: nil,
            tool: nil,
            turnTail: nil
          ))
      default:
        continue
      }
    }
    return rows
  }

  private func closingAssistant(turn: Int) -> (sequence: Int, text: String)? {
    entriesBySequence.values
      .compactMap { entry -> (sequence: Int, text: String)? in
        guard entry.event.type == "assistant/message",
          assistantKey(entry.event.data)?.turn == turn,
          let message = entry.event.data.objectValue?["message"]?.objectValue
        else {
          return nil
        }
        let text = visibleTextBlocks(message["content"])
          .compactMap(\.textValue)
          .joined(separator: "\n\n")
        return text.isEmpty ? nil : (entry.event.sequence, text)
      }
      .max { $0.sequence < $1.sequence }
  }

  private func projectedToolRow(
    callID: String,
    callEntry: UpstreamHistoryEntry,
    resultEntry: UpstreamHistoryEntry?,
    copy: RabbisirCopy
  ) -> UpstreamConversationRow? {
    guard let data = callEntry.event.data.objectValue,
      let turn = data["turn"]?.integerValue,
      let callView = upstreamToolCallView(callEntry.view)
    else { return nil }
    let resultView = upstreamToolResultView(resultEntry?.view)
    let toolName = data["name"]?.stringValue ?? ""
    let title = copy.toolTitle(toolName)
    let detail = toolPresentationDetail(callView: callView, resultView: resultView, copy: copy)
    let state: UpstreamToolPresentation.State
    if let resultEntry {
      if toolResultWasInterrupted(resultEntry.event.data) {
        state = .stopped
      } else {
        state = toolResultIsError(resultEntry.event.data) ? .failed : .succeeded
      }
    } else {
      state = .running
    }
    let summary =
      state == .failed
      ? detail.map(firstVisibleLine)
      : toolSummary(toolName: toolName, view: callView)
    return UpstreamConversationRow(
      id: "tool:\(callID)",
      kind: .tool,
      sequence: callEntry.event.sequence,
      presentationOrder: 0,
      turn: turn,
      text: title,
      detail: detail,
      isStreaming: resultEntry == nil,
      copyText: nil,
      tool: UpstreamToolPresentation(
        title: title,
        summary: summary,
        state: state
      ),
      turnTail: nil
    )
  }

  private func producedFiles(turn: Int, through closingSequence: Int) -> [String] {
    var seen = Set<String>()
    return toolCallsByID.compactMap { callID, callEntry -> [String]? in
      guard turnNumber(callEntry.event.data) == turn,
        let result = toolResultsByID[callID],
        result.event.sequence <= closingSequence,
        !toolResultIsError(result.event.data),
        let view = upstreamToolCallView(callEntry.view),
        isMutationView(view)
      else { return nil }
      return view["locations"]?.arrayValue?.compactMap { location in
        location.objectValue?["path"]?.stringValue
      }
    }
    .flatMap { $0 }
    .filter { seen.insert($0).inserted }
  }

  private func latestTranscriptSequence(turn: Int) -> Int? {
    var latest = entriesBySequence.values
      .filter { turnNumber($0.event.data) == turn }
      .map(\.event.sequence)
      .max()
    let lifecycle = toolCallsByID.values
      .filter { turnNumber($0.event.data) == turn }
      .map(\.event.sequence)
    let results = toolResultsByID.values
      .filter { turnNumber($0.event.data) == turn }
      .map(\.event.sequence)
    let retries = statusEntriesBySequence.values
      .filter {
        turnNumber($0.event.data) == turn
          && ($0.event.type == "llm/retry" || $0.event.type == "llm/retry-started")
      }
      .map(\.event.sequence)
    for candidate in lifecycle + results + retries {
      latest = max(latest ?? candidate, candidate)
    }
    return latest
  }

  private func turnMetrics(turn: Int) -> (
    firstTokenLatencyMilliseconds: Double?,
    tokensPerSecond: Double?
  ) {
    let finals = entriesBySequence.values.compactMap {
      entry -> (AssistantKey, UpstreamHistoryEntry)? in
      guard entry.event.type == "assistant/message",
        let key = assistantKey(entry.event.data),
        key.turn == turn
      else { return nil }
      return (key, entry)
    }
    let firstStep = finals.map(\.0).min { $0.step < $1.step }
    let firstTokenLatency = firstStep.flatMap { key -> Double? in
      guard let start = stepStartsByKey[key]?.event.time,
        let firstToken = firstTokenTimeByKey[key]
      else { return nil }
      return max(0, firstToken - start)
    }
    var decodedMilliseconds = 0.0
    var outputTokens = 0.0
    var sampled = false
    for (key, entry) in finals {
      guard let firstToken = firstTokenTimeByKey[key],
        let usage = entry.event.data.objectValue?["usage"]?.objectValue,
        let tokens = usage["outputTokens"]?.numberValue
      else { continue }
      decodedMilliseconds += max(0, entry.event.time - firstToken)
      outputTokens += tokens
      sampled = true
    }
    return (
      firstTokenLatency,
      sampled && decodedMilliseconds > 0
        ? outputTokens / (decodedMilliseconds / 1_000)
        : nil
    )
  }

  private func turnEndSequence(_ turn: Int) -> Int? {
    turnBoundariesBySequence.values.first {
      $0.event.type == "turn/end" && turnNumber($0.event.data) == turn
    }?.event.sequence
  }

  private func projectedCommandRows() -> [UpstreamConversationRow] {
    commandRunsByID.compactMap { commandID, run -> UpstreamConversationRow? in
      guard let data = run.event.data.objectValue,
        let name = data["name"]?.stringValue
      else { return nil }
      let done = commandDoneByID[commandID]
      let doneData = done?.event.data.objectValue
      let outcome = doneData?["kind"]?.stringValue
      let settlement = doneData?["text"]?.stringValue
      let summary = settlement.map(firstVisibleLine)
      let detail = settlement?.contains("\n") == true ? settlement : nil
      return UpstreamConversationRow(
        id: "command:\(commandID)",
        kind: .command,
        sequence: run.event.sequence,
        presentationOrder: 0,
        turn: turnContaining(sequence: run.event.sequence),
        text: name,
        detail: detail,
        isStreaming: done == nil,
        copyText: nil,
        tool: UpstreamToolPresentation(
          title: name,
          summary: summary,
          state: done == nil ? .running : outcome == "success" ? .succeeded : .failed
        ),
        turnTail: nil
      )
    }
  }

  private func projectedStatusRows(
    turns: [Int: UpstreamConversationTurn],
    copy: RabbisirCopy
  ) -> [UpstreamConversationRow] {
    var rows: [UpstreamConversationRow] = []
    let retryEntries = statusEntriesBySequence.values.filter {
      $0.event.type == "llm/retry" || $0.event.type == "llm/retry-started"
    }
    let retries = Dictionary(grouping: retryEntries) { entry in
      stringIdentity(entry.event.data, key: "retryId") ?? String(entry.event.sequence)
    }
    for (retryID, chain) in retries {
      guard let latest = chain.max(by: { $0.event.sequence < $1.event.sequence }),
        let data = latest.event.data.objectValue
      else { continue }
      let turn = data["turn"]?.integerValue
      let attempt = data["retry"]?.integerValue
      let maximum = data["maximum"]?.integerValue
      let seconds = data["delayMs"]?.numberValue.map { $0 / 1_000 }
      let status =
        latest.event.type == "llm/retry-started"
        ? copy.conversationRetryingModel
        : copy.conversationWaitingToRetryModel
      let counters =
        attempt.map { attempt in
          maximum.map { "（\(attempt)/\($0)）" } ?? "（\(attempt)）"
        } ?? ""
      let delay = seconds.map { " · \(String(format: "%.1f", $0))s" } ?? ""
      rows.append(
        UpstreamConversationRow(
          id: "model-retry:\(retryID)",
          kind: .notice,
          sequence: latest.event.sequence,
          presentationOrder: 0,
          turn: turn,
          text: status + counters + delay,
          detail: failureMessage(data["failure"]),
          isStreaming: latest.event.type != "llm/retry-started",
          copyText: nil,
          tool: nil,
          turnTail: nil
        ))
    }

    for entry in statusEntriesBySequence.values where entry.event.type == "compaction/summary" {
      let data = entry.event.data.objectValue
      let summary = visibleTextBlocks(data?["summary"]).compactMap(\.textValue).joined()
      let itemCount = data?["shadowedSeqs"]?.arrayValue?.count
      let tokenCount = data?["shadowedTokenCount"]?.integerValue
      let result =
        if let itemCount, let tokenCount {
          copy.conversationCompacted(itemCount: itemCount, tokenCount: tokenCount)
        } else {
          copy.conversationContextCompacted
        }
      rows.append(
        UpstreamConversationRow(
          id: "compaction:\(entry.event.sequence)",
          kind: .compaction,
          sequence: entry.event.sequence,
          presentationOrder: 0,
          turn: turnContaining(sequence: entry.event.sequence),
          text: result,
          detail: summary.isEmpty ? nil : summary,
          isStreaming: false,
          copyText: nil,
          tool: nil,
          turnTail: nil
        ))
    }

    for entry in turnBoundariesBySequence.values where entry.event.type == "turn/end" {
      guard let data = entry.event.data.objectValue,
        let turn = data["turn"]?.integerValue,
        let reason = data["reason"]?.objectValue,
        let kind = reason["kind"]?.stringValue
      else { continue }
      if kind == "max-tokens" {
        rows.append(
          statusRow(
            id: "turn-max-tokens:\(turn)",
            kind: .notice,
            entry: entry,
            turn: turn,
            text: copy.conversationOutputLimitReached,
            detail: copy.conversationOutputLimitDetail
          ))
      } else if kind == "error" && !hasRetry(for: turn) {
        rows.append(
          statusRow(
            id: "turn-error:\(turn)",
            kind: .error,
            entry: entry,
            turn: turn,
            text: copy.conversationRunFailed,
            detail: failureMessage(reason["error"])
          ))
      }
    }
    _ = turns
    return rows
  }

  private func statusRow(
    id: String,
    kind: UpstreamConversationRow.Kind,
    entry: UpstreamHistoryEntry,
    turn: Int,
    text: String,
    detail: String?
  ) -> UpstreamConversationRow {
    UpstreamConversationRow(
      id: id,
      kind: kind,
      sequence: entry.event.sequence,
      presentationOrder: 0,
      turn: turn,
      text: text,
      detail: detail,
      isStreaming: false,
      copyText: nil,
      tool: nil,
      turnTail: nil
    )
  }

  private func hasRetry(for turn: Int) -> Bool {
    statusEntriesBySequence.values.contains { entry in
      (entry.event.type == "llm/retry" || entry.event.type == "llm/retry-started")
        && turnNumber(entry.event.data) == turn
    }
  }
}

private struct AssistantKey: Hashable, Sendable {
  let turn: Int
  let step: Int

  var stableID: String { "assistant:\(turn):\(step)" }
}

private struct PartialAssistant: Sendable {
  let key: AssistantKey
  private(set) var blocks: [Int: PartialAssistantBlock] = [:]
  private(set) var latestSequence = -1
  private(set) var latestTime = 0.0
  private var seenSequences = Set<Int>()

  var eventCount: Int { seenSequences.count }

  init(key: AssistantKey) {
    self.key = key
  }

  mutating func ingest(_ event: UpstreamSessionEvent) -> Bool {
    guard seenSequences.insert(event.sequence).inserted else { return false }
    guard let data = event.data.objectValue,
      let chunk = data["chunk"]?.objectValue,
      let type = chunk["type"]?.stringValue
    else { return false }
    latestSequence = max(latestSequence, event.sequence)
    latestTime = max(latestTime, event.time)
    let index = chunk["index"]?.integerValue
    switch type {
    case "block-start":
      guard let index, let blockType = chunk["blockType"]?.stringValue else { return false }
      switch blockType {
      case "text": blocks[index] = .text("")
      default: return false
      }
    case "text-delta":
      guard let index,
        let text = chunk["text"]?.stringValue,
        let current = blocks[index]?.textValue
      else { return false }
      blocks[index] = .text(current.appending(text))
    case "block-end":
      guard let index,
        let block = chunk["block"]?.objectValue,
        let blockType = block["type"]?.stringValue
      else { return false }
      switch blockType {
      case "text":
        guard let text = block["text"]?.stringValue, !text.isEmpty else { return false }
        blocks[index] = .text(text)
      case "image":
        guard let image = imageAttachment(block["attachment"]) else { return false }
        blocks[index] = .image(image)
      default:
        return false
      }
    default:
      return false
    }
    return true
  }

  func message(isStreaming: Bool) -> UpstreamConversationMessage? {
    let ordered = blocks.keys.sorted().compactMap { index -> UpstreamConversationBlock? in
      guard case .text(let text) = blocks[index], !text.isEmpty else { return nil }
      return .text(text)
    }
    guard !ordered.isEmpty, latestSequence >= 0 else { return nil }
    return UpstreamConversationMessage(
      id: key.stableID,
      sequence: latestSequence,
      time: latestTime,
      turn: key.turn,
      role: .assistant,
      blocks: ordered,
      isStreaming: isStreaming
    )
  }

  func rows(copy: RabbisirCopy, isStreaming: Bool) -> [UpstreamConversationRow] {
    blocks.keys.sorted().compactMap { index in
      guard let block = blocks[index] else { return nil }
      switch block {
      case .text(let text) where !text.isEmpty:
        return UpstreamConversationRow(
          id: index == firstTextIndex ? key.stableID : "\(key.stableID):text:\(index)",
          kind: .assistant,
          sequence: latestSequence,
          presentationOrder: index,
          turn: key.turn,
          text: text,
          detail: nil,
          isStreaming: isStreaming,
          copyText: nil,
          tool: nil,
          turnTail: nil
        )
      case .image(let image):
        return UpstreamConversationRow(
          id: "\(key.stableID):image:\(index)",
          kind: .image,
          sequence: latestSequence,
          presentationOrder: index,
          turn: key.turn,
          text: image.name ?? copy.conversationImageFallback,
          detail: nil,
          images: [image],
          isStreaming: isStreaming,
          copyText: nil,
          tool: nil,
          turnTail: nil
        )
      default:
        return nil
      }
    }
  }

  private var firstTextIndex: Int? {
    blocks.keys.sorted().first { index in
      guard case .text(let text) = blocks[index] else { return false }
      return !text.isEmpty
    }
  }
}

private enum PartialAssistantBlock: Sendable {
  case text(String)
  case image(UpstreamImageAttachmentReference)

  var textValue: String? {
    guard case .text(let value) = self else { return nil }
    return value
  }
}

extension ConversationReducer {
  fileprivate func isVisibleUserMessage(_ event: UpstreamSessionEvent) -> Bool {
    guard let data = event.data.objectValue else { return false }
    return event.surfaceOperation == .append
      && data["role"]?.stringValue == "user"
      && data["source"]?.objectValue?["kind"]?.stringValue == "user"
      && visibleUserBlocks(data["content"]).isEmpty == false
  }

  fileprivate func isVisibleAssistantMessage(_ event: UpstreamSessionEvent) -> Bool {
    guard let message = event.data.objectValue?["message"]?.objectValue else { return false }
    return event.surfaceOperation == .append
      && message["role"]?.stringValue == "assistant"
      && message["source"]?.objectValue?["kind"]?.stringValue == "model"
      && hasVisibleAssistantContent(message["content"])
  }

  fileprivate func projectedUserMessage(
    _ event: UpstreamSessionEvent,
    turn: Int?
  ) -> UpstreamConversationMessage? {
    guard let data = event.data.objectValue,
      event.surfaceOperation == .append,
      data["role"]?.stringValue == "user",
      data["source"]?.objectValue?["kind"]?.stringValue == "user"
    else { return nil }
    let blocks = visibleUserBlocks(data["content"])
    guard !blocks.isEmpty else { return nil }
    return UpstreamConversationMessage(
      id: "user:\(data["id"]?.stringValue ?? String(event.sequence))",
      sequence: event.sequence,
      time: event.time,
      turn: turn,
      role: .user,
      blocks: blocks,
      isStreaming: false
    )
  }

  fileprivate func projectedAssistantMessage(
    _ event: UpstreamSessionEvent,
    key: AssistantKey
  ) -> UpstreamConversationMessage? {
    guard let data = event.data.objectValue,
      event.surfaceOperation == .append,
      let message = data["message"]?.objectValue,
      message["role"]?.stringValue == "assistant",
      message["source"]?.objectValue?["kind"]?.stringValue == "model"
    else { return nil }
    let blocks = visibleTextBlocks(message["content"])
    guard !blocks.isEmpty else { return nil }
    return UpstreamConversationMessage(
      id: key.stableID,
      sequence: event.sequence,
      time: event.time,
      turn: key.turn,
      role: .assistant,
      blocks: blocks,
      isStreaming: false
    )
  }
}

private func assistantKey(_ value: UpstreamJSONValue) -> AssistantKey? {
  guard let data = value.objectValue,
    let turn = data["turn"]?.integerValue,
    let step = data["step"]?.integerValue
  else { return nil }
  return AssistantKey(turn: turn, step: step)
}

private func isTokenDelta(_ value: UpstreamJSONValue) -> Bool {
  guard let type = value.objectValue?["chunk"]?.objectValue?["type"]?.stringValue else {
    return false
  }
  return type == "text-delta"
}

private func hasVisibleAssistantContent(_ value: UpstreamJSONValue?) -> Bool {
  value?.arrayValue?.contains { block in
    guard let object = block.objectValue,
      let type = object["type"]?.stringValue
    else { return false }
    switch type {
    case "text":
      return object["text"]?.stringValue?.isEmpty == false
    case "image":
      return imageAttachment(object["attachment"]) != nil
    default:
      return false
    }
  } == true
}

private func imageAttachment(_ value: UpstreamJSONValue?) -> UpstreamImageAttachmentReference? {
  guard let object = value?.objectValue,
    let attachmentID = object["attachmentId"]?.stringValue,
    let mediaType = object["mediaType"]?.stringValue
  else { return nil }
  return UpstreamImageAttachmentReference(
    attachmentID: attachmentID,
    mediaType: mediaType,
    bytes: object["bytes"]?.integerValue,
    pixelWidth: object["width"]?.integerValue,
    pixelHeight: object["height"]?.integerValue,
    name: object["name"]?.stringValue
  )
}

private func turnNumber(_ value: UpstreamJSONValue) -> Int? {
  value.objectValue?["turn"]?.integerValue
}

private func toolCallID(_ value: UpstreamJSONValue) -> String? {
  value.objectValue?["callId"]?.stringValue
}

private func stringIdentity(_ value: UpstreamJSONValue, key: String) -> String? {
  guard let raw = value.objectValue?[key] else { return nil }
  if let string = raw.stringValue, !string.isEmpty { return string }
  if let integer = raw.integerValue { return String(integer) }
  return nil
}

private func failureMessage(_ value: UpstreamJSONValue?) -> String? {
  guard let object = value?.objectValue else { return nil }
  return object["message"]?.stringValue
    ?? object["code"]?.stringValue
}

private func toolResultCallID(_ value: UpstreamJSONValue) -> String? {
  value.objectValue?["message"]?.objectValue?["source"]?.objectValue?["callId"]?.stringValue
}

private func upstreamToolCallView(
  _ value: UpstreamJSONValue?
) -> [String: UpstreamJSONValue]? {
  guard let envelope = value?.objectValue,
    envelope["for"]?.stringValue == "call"
  else { return nil }
  return envelope["view"]?.objectValue
}

private func upstreamToolResultView(
  _ value: UpstreamJSONValue?
) -> [String: UpstreamJSONValue]? {
  guard let envelope = value?.objectValue,
    envelope["for"]?.stringValue == "result"
  else { return nil }
  return envelope["view"]?.objectValue
}

private func toolResultIsError(_ value: UpstreamJSONValue) -> Bool {
  let blocks = value.objectValue?["message"]?.objectValue?["content"]?.arrayValue ?? []
  return blocks.contains { block in
    block.objectValue?["type"]?.stringValue == "tool-result"
      && block.objectValue?["isError"]?.booleanValue == true
  }
}

private func toolResultWasInterrupted(_ value: UpstreamJSONValue) -> Bool {
  value.objectValue?["error"]?.objectValue?["code"]?.stringValue == "interrupted"
}

private func toolSummary(
  toolName: String,
  view: [String: UpstreamJSONValue]
) -> String? {
  if toolName == "bash" || toolName == "pwsh" || toolName == "run_code" {
    if let description = view["description"]?.stringValue, !description.isEmpty {
      return firstVisibleLine(description)
    }
  }
  if let path = view["locations"]?.arrayValue?.first?.objectValue?["path"]?.stringValue {
    return firstVisibleLine(path)
  }
  if let description = view["description"]?.stringValue, !description.isEmpty {
    return firstVisibleLine(description)
  }
  if let title = view["title"]?.stringValue, !title.isEmpty {
    let line = firstVisibleLine(title)
    return !isKnownUpstreamToolName(toolName) && !toolName.isEmpty
      ? "\(toolName) · \(line)"
      : line
  }
  return toolName.isEmpty ? nil : toolName
}

private func isKnownUpstreamToolName(_ toolName: String) -> Bool {
  [
    "bash", "pwsh", "read", "web_fetch", "web_search", "grep", "glob", "write",
    "edit", "run_code", "cordis_package_inspect", "cordis_runtime_inspect", "cordis_run",
    "cordis_stop", "cordis_undefine",
  ].contains(toolName)
}

private func toolPresentationDetail(
  callView: [String: UpstreamJSONValue],
  resultView: [String: UpstreamJSONValue]?,
  copy: RabbisirCopy
) -> String? {
  guard let resultView else { return toolCallDetail(callView) }
  let card = resultView["card"]?.stringValue
  let lines: [String] =
    switch card {
    case "terminal": terminalDetail(callView: callView, resultView: resultView)
    case "diff": diffDetail(resultView)
    case "read": readDetail(resultView)
    case "search": searchDetail(resultView, copy: copy)
    case "web": webDetail(resultView, copy: copy)
    case "generic": visibleContentLines(resultView["content"])
    default: []
    }
  return lines.isEmpty ? toolCallDetail(callView) : lines.joined(separator: "\n")
}

private func toolCallDetail(_ view: [String: UpstreamJSONValue]) -> String? {
  var lines: [String] = []
  if let description = view["description"]?.stringValue, !description.isEmpty {
    lines.append(description)
  }
  if let cwd = view["cwd"]?.stringValue, !cwd.isEmpty { lines.append(cwd) }
  lines.append(contentsOf: visibleContentLines(view["content"]))
  if let locations = view["locations"]?.arrayValue {
    lines.append(
      contentsOf: locations.compactMap { location in
        guard let object = location.objectValue,
          let path = object["path"]?.stringValue
        else { return nil }
        return object["line"]?.integerValue.map { "\(path):\($0)" } ?? path
      })
  }
  return lines.isEmpty ? nil : lines.joined(separator: "\n")
}

private func terminalDetail(
  callView: [String: UpstreamJSONValue],
  resultView: [String: UpstreamJSONValue]
) -> [String] {
  var lines: [String] = []
  if let command = callView["title"]?.stringValue, !command.isEmpty { lines.append(command) }
  if let cwd = callView["cwd"]?.stringValue, !cwd.isEmpty { lines.append(cwd) }
  if let output = resultView["output"]?.stringValue, !output.isEmpty {
    lines.append(output.trimmingCharacters(in: .newlines))
  }
  if let exitCode = resultView["exitCode"]?.integerValue {
    lines.append("exit \(exitCode)")
  } else if let signal = resultView["signal"]?.stringValue {
    lines.append(signal)
  }
  return lines
}

private func diffDetail(_ view: [String: UpstreamJSONValue]) -> [String] {
  view["diffs"]?.arrayValue?.flatMap { value -> [String] in
    guard let diff = value.objectValue,
      let path = diff["path"]?.stringValue,
      let newText = diff["newText"]?.stringValue
    else { return [] }
    var lines = [path]
    if let oldText = diff["oldText"]?.stringValue, !oldText.isEmpty {
      lines.append("---\n\(oldText)")
    }
    lines.append("+++\n\(newText)")
    return lines
  } ?? []
}

private func readDetail(_ view: [String: UpstreamJSONValue]) -> [String] {
  var lines: [String] = []
  if let path = view["path"]?.stringValue { lines.append(path) }
  let fileLines =
    view["lines"]?.arrayValue?.compactMap { value -> String? in
      guard let line = value.objectValue,
        let number = line["number"]?.integerValue,
        let text = line["text"]?.stringValue
      else { return nil }
      return "\(number)  \(text)"
    } ?? []
  lines.append(contentsOf: fileLines)
  if let total = view["totalLines"]?.integerValue {
    lines.append("\(fileLines.count) / \(total)")
  }
  return lines
}

private func searchDetail(
  _ view: [String: UpstreamJSONValue],
  copy: RabbisirCopy
) -> [String] {
  var lines: [String] = []
  switch view["shape"]?.stringValue {
  case "paths":
    lines.append(contentsOf: view["paths"]?.arrayValue?.compactMap(\.stringValue) ?? [])
  case "matches":
    for file in view["files"]?.arrayValue ?? [] {
      guard let object = file.objectValue,
        let path = object["path"]?.stringValue
      else { continue }
      lines.append(path)
      lines.append(
        contentsOf: object["matches"]?.arrayValue?.compactMap { match in
          guard let item = match.objectValue,
            let number = item["lineNumber"]?.integerValue,
            let text = item["line"]?.stringValue
          else { return nil }
          return "\(number)  \(text)"
        } ?? [])
    }
  default:
    break
  }
  if let total = view["total"]?.integerValue {
    let retained =
      view["shape"]?.stringValue == "paths"
      ? view["paths"]?.arrayValue?.count ?? 0
      : view["files"]?.arrayValue?.reduce(0) { count, file in
        count + (file.objectValue?["matches"]?.arrayValue?.count ?? 0)
      } ?? 0
    lines.append("\(retained) / \(total)")
  }
  if view["truncated"]?.booleanValue == true {
    lines.append(copy.language == .chinese ? "已截断" : "Truncated")
  }
  return lines
}

private func webDetail(
  _ view: [String: UpstreamJSONValue],
  copy: RabbisirCopy
) -> [String] {
  var lines: [String] = []
  switch view["kind"]?.stringValue {
  case "search":
    if let answer = view["answer"]?.stringValue, !answer.isEmpty { lines.append(answer) }
    for source in view["sources"]?.arrayValue ?? [] {
      guard let item = source.objectValue,
        let url = item["url"]?.stringValue
      else { continue }
      if let title = item["title"]?.stringValue, !title.isEmpty { lines.append(title) }
      lines.append(url)
      if let snippet = item["snippet"]?.stringValue, !snippet.isEmpty {
        lines.append(snippet)
      }
    }
  case "fetch":
    if let url = view["url"]?.stringValue { lines.append(url) }
    if let status = view["statusCode"]?.integerValue { lines.append("HTTP \(status)") }
  default:
    break
  }
  if view["truncated"]?.booleanValue == true {
    lines.append(copy.language == .chinese ? "已截断" : "Truncated")
  }
  return lines
}

private func visibleContentLines(_ value: UpstreamJSONValue?) -> [String] {
  value?.arrayValue?.compactMap { block in
    guard let object = block.objectValue,
      object["type"]?.stringValue == "text",
      let text = object["text"]?.stringValue,
      !text.isEmpty
    else { return nil }
    return text
  } ?? []
}

private func isMutationView(_ view: [String: UpstreamJSONValue]) -> Bool {
  if view["card"]?.stringValue == "diff" { return true }
  return view["card"]?.stringValue == "generic"
    && view["kind"]?.stringValue == "edit"
}

private func durationMilliseconds(_ turn: UpstreamConversationTurn) -> Double? {
  guard let start = turn.startTime, let end = turn.endTime else { return nil }
  return max(0, end - start)
}

private func joinedVisibleText(_ blocks: [UpstreamConversationBlock]) -> String {
  blocks.compactMap(\.textValue).joined(separator: "\n\n")
}

private func firstVisibleLine(_ text: String) -> String {
  text.split(whereSeparator: \.isNewline).first.map(String.init) ?? text
}

private func visibleTextBlocks(_ value: UpstreamJSONValue?) -> [UpstreamConversationBlock] {
  value?.arrayValue?.compactMap { block in
    visibleText(block).map(UpstreamConversationBlock.text)
  } ?? []
}

private func visibleUserBlocks(_ value: UpstreamJSONValue?) -> [UpstreamConversationBlock] {
  value?.arrayValue?.compactMap { block in
    if let text = visibleText(block) { return .text(text) }
    guard let object = block.objectValue,
      object["type"]?.stringValue == "image",
      let image = imageAttachment(object["attachment"])
    else { return nil }
    return .image(image)
  } ?? []
}

private func visibleText(_ value: UpstreamJSONValue) -> String? {
  guard let block = value.objectValue,
    block["type"]?.stringValue == "text",
    let text = block["text"]?.stringValue,
    !text.isEmpty
  else { return nil }
  return text
}

extension UpstreamConversationBlock {
  fileprivate var textValue: String? {
    guard case .text(let value) = self else { return nil }
    return value
  }

  fileprivate var imageValue: UpstreamImageAttachmentReference? {
    guard case .image(let value) = self else { return nil }
    return value
  }
}
