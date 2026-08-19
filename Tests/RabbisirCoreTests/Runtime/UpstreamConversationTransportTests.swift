import Foundation
import Testing

@testable import RabbisirCore

@Suite("upstream conversation transport", .serialized)
struct UpstreamConversationTransportTests {
  @Test("Injected URLSession carries history over the official endpoint and envelope")
  func historyUsesUpstreamCarrier() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ConversationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }

    ConversationURLProtocol.handler = { request, requestBody in
      let object = try #require(
        JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
      )
      let rpcID = try #require(object["rpcId"] as? String)
      let response = try #require(
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        )
      )
      let body = Data(
        """
        {"type":"server-response","rpcId":"\(rpcID)","result":{"ok":true,"value":{"events":[],"hasMore":false}}}
        """.utf8
      )
      return (response, body)
    }

    let transport = UpstreamConversationTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )
    let page = try await transport.history(
      sessionID: "session-real",
      beforeSequence: 51,
      maxMessages: 25
    )
    let captured = try #require(ConversationURLProtocol.lastRequest)
    let capturedBody = try #require(ConversationURLProtocol.lastBody)
    let object = try #require(
      JSONSerialization.jsonObject(with: capturedBody) as? [String: Any]
    )
    let payload = try #require(object["payload"] as? [String: Any])

    #expect(captured.url?.path == "/api/session.history")
    #expect(captured.httpMethod == "POST")
    #expect(captured.value(forHTTPHeaderField: "Content-Type") == "application/json")
    #expect(object["method"] as? String == "session.history")
    #expect(payload["sessionId"] as? String == "session-real")
    #expect(payload["beforeSeq"] as? Int == 51)
    #expect(payload["maxMessages"] as? Int == 25)
    #expect(!page.hasMore)
  }

  @Test("Upstream conversation actions use their exact RPC methods and payloads")
  func actionsUseUpstreamCarrier() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ConversationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var observed: [(String, [String: Any])] = []

    ConversationURLProtocol.handler = { request, requestBody in
      let object = try #require(
        JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
      )
      let method = try #require(object["method"] as? String)
      let rpcID = try #require(object["rpcId"] as? String)
      let payload = try #require(object["payload"] as? [String: Any])
      observed.append((method, payload))
      let value: String =
        switch method {
        case "session.attachment":
          #"{"attachment":{"attachmentId":"image-1","mediaType":"image/png","bytes":4,"width":2,"height":2,"name":"sample.png"},"data":"AAAA"}"#
        case "session.previewMarkdown":
          ##"{"document":{"path":"report.md","content":"# Report","bytes":8,"modifiedAt":12}}"##
        case "session.saveMarkdown":
          ##"{"document":{"path":"report.md","content":"# Updated","bytes":9,"modifiedAt":13}}"##
        case "session.fork":
          #"{"sessionId":"child-session"}"#
        case "session.cancel":
          #"{"accepted":true}"#
        case "session.updateQueue":
          #"{"accepted":true}"#
        case "host.openPath":
          #"{"opened":true}"#
        default:
          throw UpstreamConversationTransportError.unsupportedWebSocketMessage
        }
      let response = try #require(
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        )
      )
      return (
        response,
        Data(
          "{\"type\":\"server-response\",\"rpcId\":\"\(rpcID)\",\"result\":{\"ok\":true,\"value\":\(value)}}"
            .utf8)
      )
    }

    let transport = UpstreamConversationTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )
    let attachment = try await transport.attachment(
      sessionID: "session-real",
      attachmentID: "image-1"
    )
    let markdown = try await transport.previewMarkdown(
      sessionID: "session-real",
      path: "report.md"
    )
    let savedMarkdown = try await transport.saveMarkdown(
      sessionID: "session-real",
      path: "report.md",
      content: "# Updated",
      expectedModifiedAt: 12
    )
    let child = try await transport.fork(sessionID: "session-real", atSequence: 42)
    try await transport.cancel(sessionID: "session-real")
    try await transport.updateQueue(
      sessionID: "session-real",
      itemID: "queued-1",
      action: .edit(text: "updated prompt")
    )
    try await transport.openPath("/workspace/report.txt")

    #expect(attachment.attachment.attachmentID == "image-1")
    #expect(markdown.document.content == "# Report")
    #expect(child == "child-session")
    #expect(
      observed.map(\.0) == [
        "session.attachment",
        "session.previewMarkdown",
        "session.saveMarkdown",
        "session.fork",
        "session.cancel",
        "session.updateQueue",
        "host.openPath",
      ])
    #expect(observed[0].1["attachmentId"] as? String == "image-1")
    #expect(observed[1].1["path"] as? String == "report.md")
    #expect(savedMarkdown.document.content == "# Updated")
    #expect(observed[2].1["path"] as? String == "report.md")
    #expect(observed[2].1["content"] as? String == "# Updated")
    #expect(observed[2].1["expectedModifiedAt"] as? Double == 12)
    #expect(observed[3].1["atSeq"] as? Int == 42)
    #expect(observed[4].1["sessionId"] as? String == "session-real")
    #expect(observed[5].1["itemId"] as? String == "queued-1")
    #expect(
      (observed[5].1["action"] as? [String: Any])?["kind"] as? String == "edit"
    )
    #expect(observed[6].1["path"] as? String == "/workspace/report.txt")
  }

  @Test("Approval and question answers use the echoed server RPC on api respond")
  func interactionsUseResponseCarrier() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [ConversationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    var observed: [[String: Any]] = []

    ConversationURLProtocol.handler = { request, requestBody in
      let object = try #require(
        JSONSerialization.jsonObject(with: requestBody) as? [String: Any]
      )
      observed.append(object)
      let response = try #require(
        HTTPURLResponse(
          url: request.url!,
          statusCode: 200,
          httpVersion: "HTTP/1.1",
          headerFields: ["Content-Type": "application/json"]
        )
      )
      #expect(request.url?.path == "/api/respond")
      return (response, Data(#"{"accepted":true}"#.utf8))
    }

    let transport = UpstreamConversationTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )
    try await transport.respondToApproval(
      UpstreamApprovalRequest(
        rpcID: "approval-rpc",
        sessionID: "session-real",
        approvalID: "approval-1",
        toolName: "bash",
        callID: nil,
        reason: nil
      ),
      outcome: .rejected
    )
    try await transport.respondToQuestion(
      UpstreamQuestionRequest(
        rpcID: "question-rpc",
        sessionID: "session-real",
        questions: []
      ),
      answer: UpstreamQuestionAnswer(
        answers: [
          UpstreamQuestionAnswerItem(id: "choice", selected: ["No"], custom: nil)
        ]
      )
    )

    #expect(observed.map { $0["rpcId"] as? String } == ["approval-rpc", "question-rpc"])
    #expect(observed.allSatisfy { $0["type"] as? String == "client-response" })
    let approvalResult = try #require(observed[0]["result"] as? [String: Any])
    let approval = try #require(approvalResult["value"] as? [String: Any])
    #expect(approval["outcome"] as? String == "rejected")
  }

  @Test("Event mux uses the official WebSocket carrier endpoint")
  func eventStreamUsesWebSocketCarrierEndpoint() throws {
    let insecure = try UpstreamConversationTransport.webSocketEndpoint(
      from: #require(URL(string: "http://harness.invalid:1234/old?token=private#fragment"))
    )
    let secure = try UpstreamConversationTransport.webSocketEndpoint(
      from: #require(URL(string: "https://harness.invalid/base"))
    )

    #expect(insecure.absoluteString == "ws://harness.invalid:1234/api/events.mux")
    #expect(secure.absoluteString == "wss://harness.invalid/api/events.mux")
  }

  @Test("Event mux rejects unsupported base URL schemes")
  func eventStreamRejectsUnsupportedScheme() throws {
    #expect(throws: UpstreamConversationTransportError.invalidBaseURL) {
      try UpstreamConversationTransport.webSocketEndpoint(
        from: #require(URL(string: "file:///tmp/runtime"))
      )
    }
  }
}

private final class ConversationURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest, Data) throws -> (HTTPURLResponse, Data))?
  nonisolated(unsafe) static var lastRequest: URLRequest?
  nonisolated(unsafe) static var lastBody: Data?

  override class func canInit(with request: URLRequest) -> Bool { true }

  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lastRequest = request
    do {
      let requestBody = try Self.bodyData(for: request)
      Self.lastBody = requestBody
      let handler = try #require(Self.handler)
      let (response, data) = try handler(request, requestBody)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}

  private static func bodyData(for request: URLRequest) throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
      if count == 0 { break }
      data.append(buffer, count: count)
    }
    return data
  }
}
