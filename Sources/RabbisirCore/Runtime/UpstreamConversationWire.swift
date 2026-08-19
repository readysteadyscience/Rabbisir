import Foundation

/// Lossless JSON values carried by the upstream RPC and session-event protocols.
enum UpstreamJSONValue: Codable, Equatable, Sendable {
  case object([String: UpstreamJSONValue])
  case array([UpstreamJSONValue])
  case string(String)
  case integer(Int64)
  case number(Double)
  case boolean(Bool)
  case null

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if container.decodeNil() {
      self = .null
    } else if let value = try? container.decode(Bool.self) {
      self = .boolean(value)
    } else if let value = try? container.decode(Int64.self) {
      self = .integer(value)
    } else if let value = try? container.decode(Double.self) {
      self = .number(value)
    } else if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode([UpstreamJSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: UpstreamJSONValue].self) {
      self = .object(value)
    } else {
      throw DecodingError.dataCorruptedError(
        in: container,
        debugDescription: "Upstream value is not JSON"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .object(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .string(let value): try container.encode(value)
    case .integer(let value): try container.encode(value)
    case .number(let value): try container.encode(value)
    case .boolean(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  var objectValue: [String: UpstreamJSONValue]? {
    guard case .object(let value) = self else { return nil }
    return value
  }

  var arrayValue: [UpstreamJSONValue]? {
    guard case .array(let value) = self else { return nil }
    return value
  }

  var stringValue: String? {
    guard case .string(let value) = self else { return nil }
    return value
  }

  var integerValue: Int? {
    switch self {
    case .integer(let value): Int(exactly: value)
    case .number(let value) where value.rounded() == value: Int(exactly: value)
    default: nil
    }
  }

  var numberValue: Double? {
    switch self {
    case .integer(let value): Double(value)
    case .number(let value): value
    default: nil
    }
  }

  var booleanValue: Bool? {
    guard case .boolean(let value) = self else { return nil }
    return value
  }
}

/// Placement metadata attached to user, assistant, and tool-result surface events.
enum UpstreamSurfaceOperation: Codable, Equatable, Sendable {
  case append
  case replace(start: Int, end: Int)

  private enum CodingKeys: String, CodingKey {
    case op
    case start
    case end
  }

  init(from decoder: Decoder) throws {
    if let string = try? decoder.singleValueContainer().decode(String.self) {
      guard string == "append" else {
        throw DecodingError.dataCorrupted(
          .init(codingPath: decoder.codingPath, debugDescription: "Unknown surface operation")
        )
      }
      self = .append
      return
    }
    let container = try decoder.container(keyedBy: CodingKeys.self)
    guard try container.decode(String.self, forKey: .op) == "replace" else {
      throw DecodingError.dataCorruptedError(
        forKey: .op,
        in: container,
        debugDescription: "Unknown surface operation"
      )
    }
    self = try .replace(
      start: container.decode(Int.self, forKey: .start),
      end: container.decode(Int.self, forKey: .end)
    )
  }

  func encode(to encoder: Encoder) throws {
    switch self {
    case .append:
      var container = encoder.singleValueContainer()
      try container.encode("append")
    case .replace(let start, let end):
      var container = encoder.container(keyedBy: CodingKeys.self)
      try container.encode("replace", forKey: .op)
      try container.encode(start, forKey: .start)
      try container.encode(end, forKey: .end)
    }
  }
}

/// One authoritative event from `session.history` or `session/event`.
struct UpstreamSessionEvent: Codable, Equatable, Sendable {
  let type: String
  let sequence: Int
  let time: Double
  let data: UpstreamJSONValue
  let sourceEventSequences: [Int]?
  let surfaceOperation: UpstreamSurfaceOperation?
  let ignorable: Bool?

  private enum CodingKeys: String, CodingKey {
    case type
    case sequence = "seq"
    case time
    case data
    case sourceEventSequences = "sourceEventSeqs"
    case surfaceOperation = "surfaceOp"
    case ignorable
  }
}

/// One history row, including the host-computed tool presentation when present.
struct UpstreamHistoryEntry: Codable, Equatable, Sendable {
  let event: UpstreamSessionEvent
  let view: UpstreamJSONValue?
}

/// Projection values riding the tail page of session history.
struct UpstreamProjectionBlock: Codable, Equatable, Sendable {
  let asOfSequence: Int
  let values: [String: UpstreamJSONValue]

  private enum CodingKeys: String, CodingKey {
    case asOfSequence = "asOfSeq"
    case values
  }
}

/// One backwards-paginated upstream runtime history response.
struct UpstreamHistoryPage: Codable, Equatable, Sendable {
  let events: [UpstreamHistoryEntry]
  let hasMore: Bool
  let projections: UpstreamProjectionBlock?
}

/// Exact payload accepted by the official `session.history` method.
struct UpstreamHistoryRequest: Codable, Equatable, Sendable {
  let sessionID: String
  let beforeSequence: Int?
  let maxMessages: Int?

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case beforeSequence = "beforeSeq"
    case maxMessages
  }
}

struct UpstreamAttachmentRequest: Codable, Equatable, Sendable {
  let sessionID: String
  let attachmentID: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case attachmentID = "attachmentId"
  }
}

struct UpstreamAttachmentValue: Codable, Equatable, Sendable {
  let attachment: UpstreamImageAttachmentValue
  let data: String
}

struct UpstreamImageAttachmentValue: Codable, Equatable, Sendable {
  let attachmentID: String
  let mediaType: String
  let bytes: Int
  let width: Int
  let height: Int
  let name: String?

  private enum CodingKeys: String, CodingKey {
    case attachmentID = "attachmentId"
    case mediaType
    case bytes
    case width
    case height
    case name
  }
}

struct UpstreamPreviewMarkdownRequest: Codable, Equatable, Sendable {
  let sessionID: String
  let path: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case path
  }
}

struct UpstreamMarkdownDocument: Codable, Equatable, Sendable {
  let path: String
  let content: String
  let bytes: Int
  let modifiedAt: Double
}

struct UpstreamPreviewMarkdownValue: Codable, Equatable, Sendable {
  let document: UpstreamMarkdownDocument
}

struct UpstreamSaveMarkdownRequest: Codable, Equatable, Sendable {
  let sessionID: String
  let path: String
  let content: String
  let expectedModifiedAt: Double

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case path
    case content
    case expectedModifiedAt
  }
}

struct UpstreamForkRequest: Codable, Equatable, Sendable {
  let sessionID: String
  let atSequence: Int?

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case atSequence = "atSeq"
  }
}

struct UpstreamForkValue: Codable, Equatable, Sendable {
  let sessionID: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
  }
}

struct UpstreamCancelRequest: Codable, Equatable, Sendable {
  let sessionID: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
  }
}

struct UpstreamCancelValue: Codable, Equatable, Sendable {
  let accepted: Bool
}

struct UpstreamOpenPathRequest: Codable, Equatable, Sendable {
  let path: String
}

struct UpstreamOpenPathValue: Codable, Equatable, Sendable {
  let opened: Bool
}

enum UpstreamQueuePlacement: String, Codable, Equatable, Sendable {
  case queued
  case steering
  case context
}

enum UpstreamQueueAction: Encodable, Equatable, Sendable {
  case edit(text: String)
  case remove
  case steer

  private enum CodingKeys: String, CodingKey {
    case kind
    case content
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .edit(let text):
      try container.encode("edit", forKey: .kind)
      try container.encode([UpstreamPromptContentPart.text(text)], forKey: .content)
    case .remove:
      try container.encode("remove", forKey: .kind)
    case .steer:
      try container.encode("steer", forKey: .kind)
    }
  }
}

struct UpstreamUpdateQueueRequest: Encodable, Equatable, Sendable {
  let sessionID: String
  let itemID: String
  let action: UpstreamQueueAction

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case itemID = "itemId"
    case action
  }
}

struct UpstreamUpdateQueueValue: Decodable, Equatable, Sendable {
  let accepted: Bool
}

struct UpstreamQueueItem: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let placement: UpstreamQueuePlacement
  let message: UpstreamJSONValue

  var editableText: String? {
    guard let blocks = message.objectValue?["content"]?.arrayValue else { return nil }
    var text = ""
    for block in blocks {
      guard let object = block.objectValue,
        object["type"]?.stringValue == "text",
        let value = object["text"]?.stringValue
      else { return nil }
      text += value
    }
    return text
  }

  var preview: String {
    let blocks = message.objectValue?["content"]?.arrayValue ?? []
    let parts = blocks.compactMap { block -> String? in
      guard let object = block.objectValue else { return nil }
      switch object["type"]?.stringValue {
      case "text": return object["text"]?.stringValue
      case "image": return "[image]"
      default: return nil
      }
    }
    let flattened = parts.joined(separator: " ")
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
    guard flattened.count > 200 else { return flattened }
    return String(flattened.prefix(200)) + "…"
  }
}

enum UpstreamApprovalOutcome: String, Codable, Equatable, Sendable {
  case allowedOnce = "allowed-once"
  case rejected
}

struct UpstreamApprovalRequest: Equatable, Sendable {
  let rpcID: String
  let sessionID: String
  let approvalID: String
  let toolName: String
  let callID: String?
  let reason: String?
}

struct UpstreamApprovalResponse: Codable, Equatable, Sendable {
  let sessionID: String
  let approvalID: String
  let outcome: UpstreamApprovalOutcome

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case approvalID = "approvalId"
    case outcome
  }
}

struct UpstreamQuestionOption: Codable, Equatable, Sendable {
  let label: String
  let description: String?
}

struct UpstreamQuestionIntent: Codable, Equatable, Sendable {
  let kind: Kind
  let approve: String

  enum Kind: String, Codable, Equatable, Sendable {
    case planReview = "plan-review"
  }
}

struct UpstreamQuestionItem: Codable, Equatable, Sendable, Identifiable {
  let id: String
  let question: String
  let detail: String?
  let header: String?
  let options: [UpstreamQuestionOption]?
  let multiSelect: Bool?
  let intent: UpstreamQuestionIntent?
}

struct UpstreamQuestionRequest: Equatable, Sendable {
  let rpcID: String
  let sessionID: String
  let questions: [UpstreamQuestionItem]
}

struct UpstreamQuestionAnswerItem: Codable, Equatable, Sendable {
  let id: String
  let selected: [String]
  let custom: String?
}

struct UpstreamQuestionAnswer: Codable, Equatable, Sendable {
  let answers: [UpstreamQuestionAnswerItem]
}

struct UpstreamQuestionResponse: Codable, Equatable, Sendable {
  let sessionID: String
  let answer: UpstreamQuestionAnswer

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case answer
  }
}

enum UpstreamPromptMode: String, Codable, Equatable, Sendable {
  case queue
  case steer
}

enum UpstreamImageMediaType: String, Codable, Equatable, Sendable {
  case png = "image/png"
  case jpeg = "image/jpeg"
  case webp = "image/webp"
  case gif = "image/gif"
}

/// Browser-wire prompt parts accepted by `session.prompt`.
enum UpstreamPromptContentPart: Codable, Equatable, Sendable {
  case text(String)
  case image(mediaType: UpstreamImageMediaType, data: String, name: String?)

  private enum CodingKeys: String, CodingKey {
    case type
    case text
    case mediaType
    case data
    case name
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    switch try container.decode(String.self, forKey: .type) {
    case "text":
      self = try .text(container.decode(String.self, forKey: .text))
    case "image":
      self = try .image(
        mediaType: container.decode(UpstreamImageMediaType.self, forKey: .mediaType),
        data: container.decode(String.self, forKey: .data),
        name: container.decodeIfPresent(String.self, forKey: .name)
      )
    default:
      throw DecodingError.dataCorruptedError(
        forKey: .type,
        in: container,
        debugDescription: "Unsupported prompt content part"
      )
    }
  }

  func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    switch self {
    case .text(let text):
      try container.encode("text", forKey: .type)
      try container.encode(text, forKey: .text)
    case .image(let mediaType, let data, let name):
      try container.encode("image", forKey: .type)
      try container.encode(mediaType, forKey: .mediaType)
      try container.encode(data, forKey: .data)
      try container.encodeIfPresent(name, forKey: .name)
    }
  }
}

/// Exact payload accepted by the official `session.prompt` method.
struct UpstreamPromptRequest: Codable, Equatable, Sendable {
  let sessionID: String
  let mode: UpstreamPromptMode
  let content: [UpstreamPromptContentPart]
  let clientTimeZone: String?

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case mode
    case content
    case clientTimeZone
  }
}

struct UpstreamPromptResponse: Decodable, Equatable, Sendable {
  struct Command: Decodable, Equatable, Sendable {
    let kind: String
    let text: String?

    init(text: String? = nil) {
      kind = "success"
      self.text = text
    }

    private enum CodingKeys: String, CodingKey {
      case kind
      case text
    }

    init(from decoder: Decoder) throws {
      let container = try decoder.container(keyedBy: CodingKeys.self)
      let kind = try container.decode(String.self, forKey: .kind)
      guard kind == "success" else {
        throw DecodingError.dataCorruptedError(
          forKey: .kind,
          in: container,
          debugDescription: "session.prompt command kind must be success"
        )
      }
      self.kind = kind
      self.text = try container.decodeIfPresent(String.self, forKey: .text)
    }
  }

  let accepted: Bool
  let command: Command?

  init(command: Command? = nil) {
    accepted = true
    self.command = command
  }

  private enum CodingKeys: String, CodingKey {
    case accepted
    case command
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    let accepted = try container.decode(Bool.self, forKey: .accepted)
    guard accepted else {
      throw DecodingError.dataCorruptedError(
        forKey: .accepted,
        in: container,
        debugDescription: "session.prompt accepted must be true"
      )
    }
    self.accepted = accepted
    self.command = try container.decodeIfPresent(Command.self, forKey: .command)
  }
}

struct UpstreamRPCError: Codable, Error, Equatable, Sendable {
  let code: String
  let message: String
  let details: UpstreamJSONValue
}

/// Conversation-relevant frame extracted from the all-session mux stream.
enum UpstreamConversationStreamFrame: Equatable, Sendable {
  case event(sessionID: String, entry: UpstreamHistoryEntry)
  case subscribed(sessionID: String, lastSequence: Int)
  case queue(sessionID: String, items: [UpstreamQueueItem])
  case approvalRequested(UpstreamApprovalRequest)
  case approvalResolved(sessionID: String, approvalID: String)
  case questionRequested(UpstreamQuestionRequest)
  case questionResolved(sessionID: String, questionRPCID: String)
  case projection(sessionID: String, key: String, value: UpstreamJSONValue, sequence: Int)
  case streamError(UpstreamRPCError)
  case unrelated(type: String, sessionID: String?)
}

struct UpstreamConversationStreamEnvelope: Equatable, Sendable {
  let rpcID: String
  let frame: UpstreamConversationStreamFrame
}

enum UpstreamConversationWireError: Error, Equatable, Sendable {
  case invalidEnvelope(String)
  case rpcIDMismatch(expected: String, actual: String)
  case server(UpstreamRPCError)
}

/// Encoding and two-level decoding for the upstream runtime RPC envelopes.
enum UpstreamConversationWire {
  static func encodeRequest<Payload: Encodable>(
    method: String,
    rpcID: String,
    payload: Payload
  ) throws -> Data {
    try JSONEncoder().encode(
      ClientRequest(type: "client-request", rpcID: rpcID, method: method, payload: payload)
    )
  }

  static func encodeResponse<Value: Encodable>(rpcID: String, value: Value) throws -> Data {
    try JSONEncoder().encode(
      ClientResponse(
        type: "client-response",
        rpcID: rpcID,
        result: ClientSuccess(ok: true, value: value)
      )
    )
  }

  static func decodeHistoryResponse(_ data: Data, expectedRPCID: String) throws
    -> UpstreamHistoryPage
  {
    try decodeResponse(data, expectedRPCID: expectedRPCID, as: UpstreamHistoryPage.self)
  }

  static func decodePromptResponse(_ data: Data, expectedRPCID: String) throws
    -> UpstreamPromptResponse
  {
    try decodeResponse(data, expectedRPCID: expectedRPCID, as: UpstreamPromptResponse.self)
  }

  static func decodeMuxEnvelope(_ data: Data) throws -> UpstreamConversationStreamEnvelope {
    let envelope = try JSONDecoder().decode(ServerRequest.self, from: data)
    guard envelope.type == "server-request" else {
      throw UpstreamConversationWireError.invalidEnvelope("Expected server-request")
    }
    guard let payload = envelope.payload.objectValue,
      let frameType = payload["type"]?.stringValue
    else {
      throw UpstreamConversationWireError.invalidEnvelope("Mux payload has no type")
    }
    guard envelope.method == frameType else {
      throw UpstreamConversationWireError.invalidEnvelope("Mux method does not match payload type")
    }
    let frame: UpstreamConversationStreamFrame
    switch frameType {
    case "session/event":
      let decoded = try decodePayload(SessionEventFrame.self, from: envelope.payload)
      frame = .event(
        sessionID: decoded.sessionID,
        entry: UpstreamHistoryEntry(event: decoded.event, view: decoded.view)
      )
    case "session/subscribed":
      let decoded = try decodePayload(SessionSubscribedFrame.self, from: envelope.payload)
      frame = .subscribed(sessionID: decoded.sessionID, lastSequence: decoded.lastSequence)
    case "session/queue":
      let decoded = try decodePayload(SessionQueueFrame.self, from: envelope.payload)
      frame = .queue(sessionID: decoded.sessionID, items: decoded.items)
    case "approval/requested":
      let decoded = try decodePayload(ApprovalRequestedFrame.self, from: envelope.payload)
      frame = .approvalRequested(
        UpstreamApprovalRequest(
          rpcID: envelope.rpcID,
          sessionID: decoded.sessionID,
          approvalID: decoded.approvalID,
          toolName: decoded.toolName,
          callID: decoded.callID,
          reason: decoded.reason
        )
      )
    case "approval/resolved":
      let decoded = try decodePayload(ApprovalResolvedFrame.self, from: envelope.payload)
      frame = .approvalResolved(
        sessionID: decoded.sessionID,
        approvalID: decoded.approvalID
      )
    case "question/requested":
      let decoded = try decodePayload(QuestionRequestedFrame.self, from: envelope.payload)
      guard !decoded.questions.isEmpty else {
        throw UpstreamConversationWireError.invalidEnvelope("Question batch is empty")
      }
      frame = .questionRequested(
        UpstreamQuestionRequest(
          rpcID: envelope.rpcID,
          sessionID: decoded.sessionID,
          questions: decoded.questions
        )
      )
    case "question/resolved":
      let decoded = try decodePayload(QuestionResolvedFrame.self, from: envelope.payload)
      frame = .questionResolved(
        sessionID: decoded.sessionID,
        questionRPCID: decoded.questionRPCID
      )
    case "session/projection":
      let decoded = try decodePayload(SessionProjectionFrame.self, from: envelope.payload)
      frame = .projection(
        sessionID: decoded.sessionID,
        key: decoded.key,
        value: decoded.value,
        sequence: decoded.sequence
      )
    case "stream/error":
      let decoded = try decodePayload(StreamErrorFrame.self, from: envelope.payload)
      frame = .streamError(decoded.error)
    default:
      frame = .unrelated(type: frameType, sessionID: payload["sessionId"]?.stringValue)
    }
    return UpstreamConversationStreamEnvelope(rpcID: envelope.rpcID, frame: frame)
  }

  static func decodeResponse<Value: Decodable>(
    _ data: Data,
    expectedRPCID: String,
    as: Value.Type
  ) throws -> Value {
    let envelope = try JSONDecoder().decode(ServerResponse<Value>.self, from: data)
    guard envelope.type == "server-response" else {
      throw UpstreamConversationWireError.invalidEnvelope("Expected server-response")
    }
    guard envelope.rpcID == expectedRPCID else {
      throw UpstreamConversationWireError.rpcIDMismatch(
        expected: expectedRPCID,
        actual: envelope.rpcID
      )
    }
    switch envelope.result {
    case .success(let value): return value
    case .failure(let error): throw UpstreamConversationWireError.server(error)
    }
  }

  static func decodeReceipt(_ data: Data) throws {
    let receipt = try JSONDecoder().decode(RPCReceipt.self, from: data)
    guard receipt.accepted else {
      throw UpstreamConversationWireError.invalidEnvelope(
        receipt.reason ?? "Response was not accepted"
      )
    }
  }

  private static func decodePayload<Value: Decodable>(
    _ type: Value.Type,
    from payload: UpstreamJSONValue
  ) throws -> Value {
    try JSONDecoder().decode(type, from: JSONEncoder().encode(payload))
  }
}

private struct ClientRequest<Payload: Encodable>: Encodable {
  let type: String
  let rpcID: String
  let method: String
  let payload: Payload

  private enum CodingKeys: String, CodingKey {
    case type
    case rpcID = "rpcId"
    case method
    case payload
  }
}

private struct ClientSuccess<Value: Encodable>: Encodable {
  let ok: Bool
  let value: Value
}

private struct ClientResponse<Value: Encodable>: Encodable {
  let type: String
  let rpcID: String
  let result: ClientSuccess<Value>

  private enum CodingKeys: String, CodingKey {
    case type
    case rpcID = "rpcId"
    case result
  }
}

private struct ServerRequest: Decodable {
  let type: String
  let rpcID: String
  let method: String
  let payload: UpstreamJSONValue

  private enum CodingKeys: String, CodingKey {
    case type
    case rpcID = "rpcId"
    case method
    case payload
  }
}

private enum ServerResult<Value: Decodable>: Decodable {
  case success(Value)
  case failure(UpstreamRPCError)

  private enum CodingKeys: String, CodingKey {
    case ok
    case value
    case error
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    if try container.decode(Bool.self, forKey: .ok) {
      self = try .success(container.decode(Value.self, forKey: .value))
    } else {
      self = try .failure(container.decode(UpstreamRPCError.self, forKey: .error))
    }
  }
}

private struct ServerResponse<Value: Decodable>: Decodable {
  let type: String
  let rpcID: String
  let result: ServerResult<Value>

  private enum CodingKeys: String, CodingKey {
    case type
    case rpcID = "rpcId"
    case result
  }
}

private struct RPCReceipt: Decodable {
  let accepted: Bool
  let reason: String?
}

private struct SessionEventFrame: Decodable {
  let sessionID: String
  let event: UpstreamSessionEvent
  let view: UpstreamJSONValue?

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case event
    case view
  }
}

private struct SessionSubscribedFrame: Decodable {
  let sessionID: String
  let lastSequence: Int

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case lastSequence = "lastSeq"
  }
}

private struct SessionQueueFrame: Decodable {
  let sessionID: String
  let items: [UpstreamQueueItem]

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case items
  }
}

private struct ApprovalRequestedFrame: Decodable {
  let sessionID: String
  let approvalID: String
  let toolName: String
  let callID: String?
  let reason: String?

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case approvalID = "approvalId"
    case toolName
    case callID = "callId"
    case reason
  }
}

private struct ApprovalResolvedFrame: Decodable {
  let sessionID: String
  let approvalID: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case approvalID = "approvalId"
  }
}

private struct QuestionRequestedFrame: Decodable {
  let sessionID: String
  let questions: [UpstreamQuestionItem]

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case questions
  }
}

private struct QuestionResolvedFrame: Decodable {
  let sessionID: String
  let questionRPCID: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case questionRPCID = "questionRpcId"
  }
}

private struct SessionProjectionFrame: Decodable {
  let sessionID: String
  let key: String
  let value: UpstreamJSONValue
  let sequence: Int

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case key
    case value
    case sequence = "seq"
  }
}

private struct StreamErrorFrame: Decodable {
  let error: UpstreamRPCError
}
