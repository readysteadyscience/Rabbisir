import Foundation

/// Versioned official-client semantics consumed by Rabbisir's replaceable native renderer.
struct RuntimeNativeConversationProjection: Equatable, Sendable {
  static let supportedVersion = 1

  let version: Int
  let revision: UInt64
  let sessionID: String?
  let openState: String
  let hasMore: Bool
  let isLoadingOlder: Bool
  let isRunning: Bool
  let rows: [NativeConversationItem]

  static func decode(_ value: Any?) -> Self? {
    let object: Any
    if let serialized = value as? String {
      guard let decoded = try? JSONSerialization.jsonObject(with: Data(serialized.utf8)) else {
        return nil
      }
      object = decoded
    } else {
      guard let value else { return nil }
      object = value
    }
    guard let wire = WireEnvelope(jsonObject: object) else { return nil }
    guard wire.version == supportedVersion else { return nil }
    return Self(
      version: wire.version,
      revision: wire.revision,
      sessionID: wire.sessionID,
      openState: wire.openState,
      hasMore: wire.hasMore,
      isLoadingOlder: wire.loadingOlder,
      isRunning: wire.running,
      rows: wire.rows.compactMap { $0.nativeItem(isRunning: wire.running) }
    )
  }
}

/// JavaScript calls for the versioned semantic bridge; no selector, DOM, or rendered text crosses it.
enum RuntimeConversationProjectionBridge {
  static let messageHandlerName = "rabbisirConversationProjection"

  static let channelInstallationScript = """
    (() => {
      globalThis.__DSH_NATIVE_CONVERSATION_PROJECTION_DID_CHANGE__ = value => {
        const handler = globalThis.webkit?.messageHandlers?.\(messageHandlerName);
        if (handler && value && typeof value === 'object') {
          handler.postMessage(JSON.stringify(value));
        }
      };
    })()
    """

  static func projectionScript(afterRevision: UInt64) -> String {
    """
    (() => {
      const bridge = globalThis.__DSH_NATIVE_CONVERSATION_PROJECTION__;
      if (!bridge || typeof bridge.read !== 'function') return null;
      const value = bridge.read((afterRevision));
      return value === null ? null : JSON.stringify(value);
    })()
    """
  }

  static let loadOlderScript = """
    (() => {
      const bridge = globalThis.__DSH_NATIVE_CONVERSATION_PROJECTION__;
      return bridge && typeof bridge.loadOlder === 'function'
        ? bridge.loadOlder().then(() => true)
        : Promise.resolve(false);
    })()
    """

  static let submitScript = """
    const bridge = globalThis.__DSH_NATIVE_CONVERSATION_PROJECTION__;
    if (!bridge || typeof bridge.submit !== 'function') return null;
    return JSON.stringify(await bridge.submit(text, gesture));
    """
}

struct RuntimeConversationSubmissionResult: Equatable, Sendable {
  enum Action: String, Sendable {
    case prompt
    case steerQueue = "steer-queue"
    case none
  }

  let accepted: Bool
  let action: Action
  let mode: UpstreamPromptMode?

  static func decode(_ value: Any?) -> Self? {
    let decoded: Any?
    if let serialized = value as? String {
      decoded = try? JSONSerialization.jsonObject(with: Data(serialized.utf8))
    } else {
      decoded = value
    }
    guard let fields = decoded as? [String: Any],
      let accepted = fields["accepted"] as? Bool,
      let actionValue = fields["action"] as? String,
      let action = Action(rawValue: actionValue)
    else { return nil }
    let mode: UpstreamPromptMode?
    if fields["mode"] is NSNull {
      mode = nil
    } else if let modeValue = fields["mode"] as? String {
      guard let decodedMode = UpstreamPromptMode(rawValue: modeValue) else { return nil }
      mode = decodedMode
    } else {
      return nil
    }
    switch action {
    case .prompt:
      guard mode != nil else { return nil }
    case .steerQueue:
      guard mode == .steer else { return nil }
    case .none:
      guard mode == nil else { return nil }
    }
    return Self(accepted: accepted, action: action, mode: mode)
  }
}

private struct WireEnvelope {
  let version: Int
  let revision: UInt64
  let sessionID: String?
  let openState: String
  let hasMore: Bool
  let loadingOlder: Bool
  let running: Bool
  let rows: [WireRow]

  init?(jsonObject: Any) {
    guard let value = jsonObject as? [String: Any],
      let version = jsonInt(value["version"]),
      let revision = jsonUInt64(value["revision"]),
      let openState = value["openState"] as? String,
      let hasMore = jsonBool(value["hasMore"]),
      let loadingOlder = jsonBool(value["loadingOlder"]),
      let running = jsonBool(value["running"]),
      let rowValues = value["rows"] as? [Any]
    else { return nil }
    let rows = rowValues.compactMap(WireRow.init(jsonObject:))
    guard rows.count == rowValues.count else { return nil }
    let sessionID = jsonOptionalValue(value["sessionId"], String.init(jsonValue:))
    guard sessionID.isValid else { return nil }
    self.version = version
    self.revision = revision
    self.sessionID = sessionID.value
    self.openState = openState
    self.hasMore = hasMore
    self.loadingOlder = loadingOlder
    self.running = running
    self.rows = rows
  }
}

private struct WireRow {
  let id: String
  let kind: String
  let sequence: Int
  let text: String
  let detail: String?
  let images: [WireImage]
  let isStreaming: Bool
  let turn: Int?
  let time: Double?
  let copyText: String?
  let tool: WireTool?
  let turnTail: WireTurnTail?

  init?(jsonObject: Any) {
    guard let value = jsonObject as? [String: Any],
      let id = value["id"] as? String,
      let kind = value["kind"] as? String,
      let sequence = jsonInt(value["sequence"]),
      let text = value["text"] as? String,
      let imageValues = value["images"] as? [Any],
      let isStreaming = jsonBool(value["isStreaming"])
    else { return nil }
    let images = imageValues.compactMap(WireImage.init(jsonObject:))
    guard images.count == imageValues.count else { return nil }
    let detail = jsonOptionalValue(value["detail"], String.init(jsonValue:))
    let turn = jsonOptionalValue(value["turn"], jsonInt)
    let time = jsonOptionalValue(value["time"], jsonDouble)
    let copyText = jsonOptionalValue(value["copyText"], String.init(jsonValue:))
    let tool = jsonOptionalValue(value["tool"], WireTool.init(jsonObject:))
    let turnTail = jsonOptionalValue(value["turnTail"], WireTurnTail.init(jsonObject:))
    guard detail.isValid, turn.isValid, time.isValid, copyText.isValid,
      tool.isValid, turnTail.isValid
    else { return nil }
    self.id = id
    self.kind = kind
    self.sequence = sequence
    self.text = text
    self.detail = detail.value
    self.images = images
    self.isStreaming = isStreaming
    self.turn = turn.value
    self.time = time.value
    self.copyText = copyText.value
    self.tool = tool.value
    self.turnTail = turnTail.value
  }

  func nativeItem(isRunning: Bool) -> NativeConversationItem? {
    guard let nativeKind else { return nil }
    return NativeConversationItem(
      id: id,
      kind: nativeKind,
      text: text,
      detail: detail,
      images: images.map(\.nativeReference),
      isStreaming: isStreaming && isRunning,
      turn: turn,
      copyText: copyText,
      allowsCopy: copyText != nil,
      tool: tool?.nativeTool,
      turnTail: turnTail?.nativeTurnTail
    )
  }

  private var nativeKind: NativeConversationItem.Kind? {
    switch kind {
    case "user": .user
    case "assistant": .assistant
    case "reasoning": nil
    case "image": .image
    case "tool": .tool
    case "command": .command
    case "compaction": .compaction
    case "notice": .notice
    case "error": .error
    case "turn-tail": .turnTail
    default: nil
    }
  }
}

private struct WireImage {
  let attachmentID: String
  let mediaType: String
  let bytes: Int?
  let width: Int?
  let height: Int?
  let name: String?

  init?(jsonObject: Any) {
    guard let value = jsonObject as? [String: Any],
      let attachmentID = value["attachmentId"] as? String,
      let mediaType = value["mediaType"] as? String
    else { return nil }
    let bytes = jsonOptionalValue(value["bytes"], jsonInt)
    let width = jsonOptionalValue(value["width"], jsonInt)
    let height = jsonOptionalValue(value["height"], jsonInt)
    let name = jsonOptionalValue(value["name"], String.init(jsonValue:))
    guard bytes.isValid, width.isValid, height.isValid, name.isValid else { return nil }
    self.attachmentID = attachmentID
    self.mediaType = mediaType
    self.bytes = bytes.value
    self.width = width.value
    self.height = height.value
    self.name = name.value
  }

  var nativeReference: UpstreamImageAttachmentReference {
    UpstreamImageAttachmentReference(
      attachmentID: attachmentID,
      mediaType: mediaType,
      bytes: bytes,
      pixelWidth: width,
      pixelHeight: height,
      name: name
    )
  }
}

private struct WireTool {
  let title: String
  let summary: String?
  let state: String

  init?(jsonObject: Any) {
    guard let value = jsonObject as? [String: Any],
      let title = value["title"] as? String,
      let state = value["state"] as? String
    else { return nil }
    let summary = jsonOptionalValue(value["summary"], String.init(jsonValue:))
    guard summary.isValid else { return nil }
    self.title = title
    self.summary = summary.value
    self.state = state
  }

  var nativeTool: NativeConversationItem.Tool? {
    let nativeState: UpstreamToolPresentation.State
    switch state {
    case "running": nativeState = .running
    case "succeeded": nativeState = .succeeded
    case "failed": nativeState = .failed
    case "stopped": nativeState = .stopped
    default: return nil
    }
    return NativeConversationItem.Tool(title: title, summary: summary, state: nativeState)
  }
}

private struct WireTurnTail {
  let durationMilliseconds: Double?
  let firstTokenLatencyMilliseconds: Double?
  let tokensPerSecond: Double?
  let producedFiles: [String]
  let branchSequence: Int?
  let isBranchUnavailable: Bool

  init?(jsonObject: Any) {
    guard let value = jsonObject as? [String: Any] else { return nil }
    guard let producedFiles = value["producedFiles"] as? [String],
      let isBranchUnavailable = jsonBool(value["isBranchUnavailable"])
    else { return nil }
    let durationMilliseconds = jsonOptionalValue(value["durationMilliseconds"], jsonDouble)
    let firstTokenLatencyMilliseconds = jsonOptionalValue(
      value["firstTokenLatencyMilliseconds"], jsonDouble)
    let tokensPerSecond = jsonOptionalValue(value["tokensPerSecond"], jsonDouble)
    let branchSequence = jsonOptionalValue(value["branchSequence"], jsonInt)
    guard durationMilliseconds.isValid, firstTokenLatencyMilliseconds.isValid,
      tokensPerSecond.isValid, branchSequence.isValid
    else { return nil }
    self.durationMilliseconds = durationMilliseconds.value
    self.firstTokenLatencyMilliseconds = firstTokenLatencyMilliseconds.value
    self.tokensPerSecond = tokensPerSecond.value
    self.producedFiles = producedFiles
    self.branchSequence = branchSequence.value
    self.isBranchUnavailable = isBranchUnavailable
  }

  var nativeTurnTail: NativeConversationItem.TurnTail {
    NativeConversationItem.TurnTail(
      durationMilliseconds: durationMilliseconds,
      firstTokenLatencyMilliseconds: firstTokenLatencyMilliseconds,
      tokensPerSecond: tokensPerSecond,
      producedFiles: producedFiles,
      branchSequence: branchSequence,
      isBranchUnavailable: isBranchUnavailable
    )
  }
}

private struct OptionalJSONValue<Value> {
  let value: Value?
  let isValid: Bool
}

private func jsonOptionalValue<Value>(_ raw: Any?, _ decode: (Any) -> Value?) -> OptionalJSONValue<
  Value
> {
  guard let raw, !(raw is NSNull) else { return OptionalJSONValue(value: nil, isValid: true) }
  guard let value = decode(raw) else { return OptionalJSONValue(value: nil, isValid: false) }
  return OptionalJSONValue(value: value, isValid: true)
}

extension String {
  fileprivate init?(jsonValue: Any) {
    guard let value = jsonValue as? String else { return nil }
    self = value
  }
}

private func jsonBool(_ value: Any?) -> Bool? {
  guard let number = value as? NSNumber,
    CFGetTypeID(number) == CFBooleanGetTypeID()
  else { return nil }
  return number.boolValue
}

private func jsonInt(_ value: Any?) -> Int? {
  guard let number = value as? NSNumber,
    CFGetTypeID(number) != CFBooleanGetTypeID(),
    number.doubleValue.isFinite,
    number.doubleValue.rounded() == number.doubleValue,
    number.doubleValue >= Double(Int.min),
    number.doubleValue <= Double(Int.max)
  else { return nil }
  return number.intValue
}

private func jsonUInt64(_ value: Any?) -> UInt64? {
  guard let number = value as? NSNumber,
    CFGetTypeID(number) != CFBooleanGetTypeID(),
    number.doubleValue.isFinite,
    number.doubleValue.rounded() == number.doubleValue,
    number.doubleValue >= 0,
    number.doubleValue <= Double(UInt64.max)
  else { return nil }
  return number.uint64Value
}

private func jsonDouble(_ value: Any) -> Double? {
  guard let number = value as? NSNumber,
    CFGetTypeID(number) != CFBooleanGetTypeID(),
    number.doubleValue.isFinite
  else { return nil }
  return number.doubleValue
}
