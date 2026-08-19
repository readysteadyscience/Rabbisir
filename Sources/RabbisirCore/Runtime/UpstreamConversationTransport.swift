import Foundation

/// Injectable transport used by the native conversation store without changing upstream protocols.
protocol UpstreamConversationTransporting: Sendable {
  func history(
    sessionID: String,
    beforeSequence: Int?,
    maxMessages: Int?
  ) async throws -> UpstreamHistoryPage

  func prompt(
    sessionID: String,
    mode: UpstreamPromptMode,
    content: [UpstreamPromptContentPart],
    clientTimeZone: String?
  ) async throws -> UpstreamPromptResponse

  func attachment(
    sessionID: String,
    attachmentID: String
  ) async throws -> UpstreamAttachmentValue

  func previewMarkdown(
    sessionID: String,
    path: String
  ) async throws -> UpstreamPreviewMarkdownValue

  func saveMarkdown(
    sessionID: String,
    path: String,
    content: String,
    expectedModifiedAt: Double
  ) async throws -> UpstreamPreviewMarkdownValue

  func fork(sessionID: String, atSequence: Int) async throws -> String

  func cancel(sessionID: String) async throws

  func updateQueue(
    sessionID: String,
    itemID: String,
    action: UpstreamQueueAction
  ) async throws

  func respondToApproval(
    _ request: UpstreamApprovalRequest,
    outcome: UpstreamApprovalOutcome
  ) async throws

  func respondToQuestion(
    _ request: UpstreamQuestionRequest,
    answer: UpstreamQuestionAnswer
  ) async throws

  func openPath(_ path: String) async throws

  func eventStream() -> AsyncThrowingStream<UpstreamConversationStreamEnvelope, Error>
}

extension UpstreamConversationTransporting {
  func updateQueue(
    sessionID: String,
    itemID: String,
    action: UpstreamQueueAction
  ) async throws {
    _ = (sessionID, itemID, action)
    throw UpstreamConversationTransportError.cancellationRejected
  }

  func respondToApproval(
    _ request: UpstreamApprovalRequest,
    outcome: UpstreamApprovalOutcome
  ) async throws {
    _ = (request, outcome)
    throw UpstreamConversationTransportError.cancellationRejected
  }

  func respondToQuestion(
    _ request: UpstreamQuestionRequest,
    answer: UpstreamQuestionAnswer
  ) async throws {
    _ = (request, answer)
    throw UpstreamConversationTransportError.cancellationRejected
  }
}

enum UpstreamConversationTransportError: Error, Equatable, Sendable {
  case invalidBaseURL
  case unsupportedWebSocketMessage
  case carrierStatus(Int)
  case cancellationRejected
}

/// URLSession carrier for the official HTTP RPC and downlink-only mux WebSocket endpoints.
final class UpstreamConversationTransport: UpstreamConversationTransporting, @unchecked Sendable {
  private let baseURL: URL
  private let session: URLSession

  init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
  }

  func history(
    sessionID: String,
    beforeSequence: Int? = nil,
    maxMessages: Int? = nil
  ) async throws -> UpstreamHistoryPage {
    let rpcID = UUID().uuidString
    let data = try UpstreamConversationWire.encodeRequest(
      method: "session.history",
      rpcID: rpcID,
      payload: UpstreamHistoryRequest(
        sessionID: sessionID,
        beforeSequence: beforeSequence,
        maxMessages: maxMessages
      )
    )
    let response = try await post(method: "session.history", body: data)
    return try UpstreamConversationWire.decodeHistoryResponse(response, expectedRPCID: rpcID)
  }

  func prompt(
    sessionID: String,
    mode: UpstreamPromptMode,
    content: [UpstreamPromptContentPart],
    clientTimeZone: String? = nil
  ) async throws -> UpstreamPromptResponse {
    let rpcID = UUID().uuidString
    let data = try UpstreamConversationWire.encodeRequest(
      method: "session.prompt",
      rpcID: rpcID,
      payload: UpstreamPromptRequest(
        sessionID: sessionID,
        mode: mode,
        content: content,
        clientTimeZone: clientTimeZone
      )
    )
    let response = try await post(method: "session.prompt", body: data)
    return try UpstreamConversationWire.decodePromptResponse(response, expectedRPCID: rpcID)
  }

  func eventStream() -> AsyncThrowingStream<UpstreamConversationStreamEnvelope, Error> {
    AsyncThrowingStream { continuation in
      let socket: URLSessionWebSocketTask
      do {
        socket = session.webSocketTask(with: try Self.webSocketEndpoint(from: baseURL))
      } catch {
        continuation.finish(throwing: error)
        return
      }
      socket.resume()
      let receiveTask = Task {
        do {
          while !Task.isCancelled {
            try Task.checkCancellation()
            let message = try await socket.receive()
            let data: Data
            switch message {
            case .data(let payload):
              data = payload
            case .string(let payload):
              data = Data(payload.utf8)
            @unknown default:
              throw UpstreamConversationTransportError.unsupportedWebSocketMessage
            }
            continuation.yield(try UpstreamConversationWire.decodeMuxEnvelope(data))
          }
          continuation.finish()
        } catch is CancellationError {
          continuation.finish()
        } catch {
          continuation.finish(throwing: error)
        }
      }
      continuation.onTermination = { @Sendable _ in
        receiveTask.cancel()
        socket.cancel(with: .goingAway, reason: nil)
      }
    }
  }

  func attachment(
    sessionID: String,
    attachmentID: String
  ) async throws -> UpstreamAttachmentValue {
    try await call(
      method: "session.attachment",
      payload: UpstreamAttachmentRequest(
        sessionID: sessionID,
        attachmentID: attachmentID
      )
    )
  }

  func previewMarkdown(
    sessionID: String,
    path: String
  ) async throws -> UpstreamPreviewMarkdownValue {
    try await call(
      method: "session.previewMarkdown",
      payload: UpstreamPreviewMarkdownRequest(sessionID: sessionID, path: path)
    )
  }

  func saveMarkdown(
    sessionID: String,
    path: String,
    content: String,
    expectedModifiedAt: Double
  ) async throws -> UpstreamPreviewMarkdownValue {
    try await call(
      method: "session.saveMarkdown",
      payload: UpstreamSaveMarkdownRequest(
        sessionID: sessionID,
        path: path,
        content: content,
        expectedModifiedAt: expectedModifiedAt
      )
    )
  }

  func fork(sessionID: String, atSequence: Int) async throws -> String {
    let value: UpstreamForkValue = try await call(
      method: "session.fork",
      payload: UpstreamForkRequest(sessionID: sessionID, atSequence: atSequence)
    )
    return value.sessionID
  }

  func cancel(sessionID: String) async throws {
    let value: UpstreamCancelValue = try await call(
      method: "session.cancel",
      payload: UpstreamCancelRequest(sessionID: sessionID)
    )
    guard value.accepted else {
      throw UpstreamConversationTransportError.cancellationRejected
    }
  }

  func updateQueue(
    sessionID: String,
    itemID: String,
    action: UpstreamQueueAction
  ) async throws {
    let value: UpstreamUpdateQueueValue = try await call(
      method: "session.updateQueue",
      payload: UpstreamUpdateQueueRequest(
        sessionID: sessionID,
        itemID: itemID,
        action: action
      )
    )
    guard value.accepted else {
      throw UpstreamConversationTransportError.cancellationRejected
    }
  }

  func respondToApproval(
    _ request: UpstreamApprovalRequest,
    outcome: UpstreamApprovalOutcome
  ) async throws {
    try await respond(
      rpcID: request.rpcID,
      value: UpstreamApprovalResponse(
        sessionID: request.sessionID,
        approvalID: request.approvalID,
        outcome: outcome
      )
    )
  }

  func respondToQuestion(
    _ request: UpstreamQuestionRequest,
    answer: UpstreamQuestionAnswer
  ) async throws {
    try await respond(
      rpcID: request.rpcID,
      value: UpstreamQuestionResponse(sessionID: request.sessionID, answer: answer)
    )
  }

  func openPath(_ path: String) async throws {
    let _: UpstreamOpenPathValue = try await call(
      method: "host.openPath",
      payload: UpstreamOpenPathRequest(path: path)
    )
  }

  private func post(method: String, body: Data) async throws -> Data {
    var request = URLRequest(url: try endpoint(path: "/api/\(method)"))
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw UpstreamConversationTransportError.carrierStatus(
        (response as? HTTPURLResponse)?.statusCode ?? -1
      )
    }
    return data
  }

  private func respond<Value: Encodable>(rpcID: String, value: Value) async throws {
    var request = URLRequest(url: try endpoint(path: "/api/respond"))
    request.httpMethod = "POST"
    request.httpBody = try UpstreamConversationWire.encodeResponse(rpcID: rpcID, value: value)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw UpstreamConversationTransportError.carrierStatus(
        (response as? HTTPURLResponse)?.statusCode ?? -1
      )
    }
    try UpstreamConversationWire.decodeReceipt(data)
  }

  private func call<Request: Encodable, Value: Decodable>(
    method: String,
    payload: Request
  ) async throws -> Value {
    let rpcID = UUID().uuidString
    let data = try UpstreamConversationWire.encodeRequest(
      method: method,
      rpcID: rpcID,
      payload: payload
    )
    let response = try await post(method: method, body: data)
    return try UpstreamConversationWire.decodeResponse(
      response,
      expectedRPCID: rpcID,
      as: Value.self
    )
  }

  private func endpoint(path: String) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw UpstreamConversationTransportError.invalidBaseURL
    }
    components.path = path
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
      throw UpstreamConversationTransportError.invalidBaseURL
    }
    return url
  }

  static func webSocketEndpoint(from baseURL: URL) throws -> URL {
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw UpstreamConversationTransportError.invalidBaseURL
    }
    switch components.scheme?.lowercased() {
    case "http":
      components.scheme = "ws"
    case "https":
      components.scheme = "wss"
    default:
      throw UpstreamConversationTransportError.invalidBaseURL
    }
    components.path = "/api/events.mux"
    components.query = nil
    components.fragment = nil
    guard let url = components.url else {
      throw UpstreamConversationTransportError.invalidBaseURL
    }
    return url
  }
}
