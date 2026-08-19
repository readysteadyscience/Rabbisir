import Foundation
import Testing

@testable import RabbisirCore

@Suite("upstream navigation transport", .serialized)
struct UpstreamNavigationTransportTests {
  @Test("Projection uses durable workspace and session identities")
  func stableProjection() {
    let sessions = [
      summary("session-a", title: "Alpha", updatedAt: 20),
      summary("session-b", title: "Beta", updatedAt: 10),
      summary("session-child", title: "Hidden child", updatedAt: 30, origin: "subagent"),
      summary("session-blank", title: "Hidden blank", updatedAt: 40, blank: true),
      summary("session-loose", title: "Loose", updatedAt: 50),
    ]
    let snapshot = UpstreamNavigationProjection.make(
      sessions: sessions,
      workspaces: [
        NavigationWorkspace(
          workspaceID: "workspace-real",
          title: "Project",
          sessionIDs: ["session-b", "session-a", "session-child", "session-blank"]
        )
      ],
      archivedSessionIDs: [],
      selectedSessionID: "session-a"
    )

    #expect(snapshot.projects.map(\.id) == ["workspace-real"])
    #expect(snapshot.projects[0].sessions.map(\.id) == ["session-b", "session-a"])
    #expect(snapshot.projects[0].sessions[1].isSelected)
  }

  @Test("Blank and archived sessions never appear as navigation rows")
  func blankAndArchivePolicy() {
    let selected = summary("selected-blank", title: "Draft", updatedAt: 2, blank: true)
    let archived = summary("archived", title: "Archived", updatedAt: 3)
    let snapshot = UpstreamNavigationProjection.make(
      sessions: [selected, archived],
      workspaces: [
        NavigationWorkspace(
          workspaceID: "workspace",
          title: "Project",
          sessionIDs: [selected.sessionID, archived.sessionID]
        )
      ],
      archivedSessionIDs: [archived.sessionID],
      selectedSessionID: selected.sessionID
    )

    #expect(snapshot.projects[0].sessions.isEmpty)
    #expect(!snapshot.projects[0].containsSelectedSession)
    #expect(snapshot.selectedSessionID == selected.sessionID)
    #expect(snapshot.selectedWorkspaceTitle == "Project")
  }

  @Test("Deregistered workspace sessions do not become a replacement project row")
  func deregisteredWorkspaceDoesNotBecomeUngroupedProject() {
    let snapshot = UpstreamNavigationProjection.make(
      sessions: [
        summary(
          "session-kept-after-workspace-delete",
          title: "Kept session",
          updatedAt: 1
        )
      ],
      workspaces: [],
      archivedSessionIDs: [],
      selectedSessionID: "session-kept-after-workspace-delete"
    )

    #expect(snapshot.projects.isEmpty)
    #expect(snapshot.selectedSessionID == nil)
  }

  @Test("Upstream list RPCs feed the native tree")
  func upstreamRPCs() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NavigationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    NavigationURLProtocol.reset()
    NavigationURLProtocol.handler = { request, body in
      let requestObject = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
      )
      let rpcID = try #require(requestObject["rpcId"] as? String)
      let method = try #require(requestObject["method"] as? String)
      let value: String
      switch method {
      case "session.list":
        value = """
          {"items":[{"sessionId":"session-real","updatedAt":42,"running":false,
          "blank":false,"cwd":"/tmp/project","projections":{"asOfSeq":2,
          "values":{"title":"Real session"}}}]}
          """
      case "workspace.list":
        value = """
          {"items":[{"workspaceId":"workspace-real","path":"/tmp/project",
          "title":"Real project","sessionIds":["session-real"],
          "createdAt":"2026-08-14T00:00:00.000Z","updatedAt":"2026-08-14T00:00:00.000Z"}],
          "archivedSessionIds":[]}
          """
      default:
        Issue.record("Unexpected method \(method)")
        value = "{}"
      }
      let response = try #require(
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
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

    let transport = UpstreamNavigationTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )
    let snapshot = try await transport.snapshot(selectedSessionID: "session-real")

    #expect(snapshot.projects.map(\.id) == ["workspace-real"])
    #expect(snapshot.projects[0].sessions.map(\.id) == ["session-real"])
    #expect(snapshot.projects[0].sessions[0].title == "Real session")
    #expect(snapshot.projects[0].sessions[0].cwd == "/tmp/project")
    #expect(
      Set(NavigationURLProtocol.capturedPaths) == ["/api/session.list", "/api/workspace.list"])
  }

  @Test("Workspace actions use the official durable mutation RPCs")
  func upstreamWorkspaceMutations() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NavigationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let recorder = NavigationRequestRecorder()
    NavigationURLProtocol.reset()
    NavigationURLProtocol.handler = { request, body in
      let requestObject = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
      )
      let rpcID = try #require(requestObject["rpcId"] as? String)
      let method = try #require(requestObject["method"] as? String)
      let payload = try #require(requestObject["payload"] as? [String: Any])
      recorder.append(method: method, payload: payload)
      let value: String
      switch method {
      case "workspace.rename":
        value = """
          {"workspace":{"workspaceId":"workspace-real","path":"/tmp/project",
          "title":"Renamed","sessionIds":[],"createdAt":"2026-08-14T00:00:00.000Z",
          "updatedAt":"2026-08-15T00:00:00.000Z"}}
          """
      case "workspace.insertBefore":
        value = "{\"workspaceIds\":[\"workspace-real\",\"workspace-other\"]}"
      case "workspace.delete":
        value = "{\"deleted\":true}"
      default:
        Issue.record("Unexpected method \(method)")
        value = "{}"
      }
      let response = try #require(
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
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

    let transport = UpstreamNavigationTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )
    try await transport.renameWorkspace(workspaceID: "workspace-real", title: "Renamed")
    try await transport.moveWorkspace(
      workspaceID: "workspace-real",
      beforeWorkspaceID: "workspace-other"
    )
    try await transport.deleteWorkspace(workspaceID: "workspace-real")

    let requests = recorder.requests
    #expect(
      requests.map(\.method) == [
        "workspace.rename", "workspace.insertBefore", "workspace.delete",
      ])
    #expect(requests[0].payload["workspaceId"] as? String == "workspace-real")
    #expect(requests[0].payload["title"] as? String == "Renamed")
    #expect(requests[1].payload["beforeWorkspaceId"] as? String == "workspace-other")
    #expect(requests[2].payload["workspaceId"] as? String == "workspace-real")
  }

  @Test("Workspace adoption uses official create and session RPCs")
  func upstreamWorkspaceAdoption() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NavigationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let recorder = NavigationRequestRecorder()
    NavigationURLProtocol.reset()
    NavigationURLProtocol.handler = { request, body in
      let requestObject = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
      )
      let rpcID = try #require(requestObject["rpcId"] as? String)
      let method = try #require(requestObject["method"] as? String)
      let payload = try #require(requestObject["payload"] as? [String: Any])
      recorder.append(method: method, payload: payload)
      let value: String
      switch method {
      case "workspace.create":
        value = """
          {"workspace":{"workspaceId":"workspace-new","path":"/tmp/rabbisir-e2e",
          "title":"rabbisir-e2e","sessionIds":[],
          "createdAt":"2026-08-17T00:00:00.000Z",
          "updatedAt":"2026-08-17T00:00:00.000Z"},"created":true}
          """
      case "session.list":
        value = #"{"items":[]}"#
      case "session.create":
        value = #"{"sessionId":"session-new"}"#
      default:
        Issue.record("Unexpected method \(method)")
        value = "{}"
      }
      let response = try #require(
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
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

    let transport = UpstreamNavigationTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )
    let sessionID = try await transport.adoptWorkspace(path: "/tmp/rabbisir-e2e")

    #expect(sessionID == "session-new")
    #expect(
      recorder.requests.map(\.method) == [
        "workspace.create", "session.list", "session.create",
      ])
    #expect(recorder.requests[0].payload["path"] as? String == "/tmp/rabbisir-e2e")
    #expect(recorder.requests[2].payload["workspaceId"] as? String == "workspace-new")
  }

  @Test("Session actions use only official durable mutation RPCs")
  func upstreamSessionMutations() async throws {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [NavigationURLProtocol.self]
    let session = URLSession(configuration: configuration)
    defer { session.invalidateAndCancel() }
    let recorder = NavigationRequestRecorder()
    NavigationURLProtocol.reset()
    NavigationURLProtocol.handler = { request, body in
      let requestObject = try #require(
        JSONSerialization.jsonObject(with: body) as? [String: Any]
      )
      let rpcID = try #require(requestObject["rpcId"] as? String)
      let method = try #require(requestObject["method"] as? String)
      let payload = try #require(requestObject["payload"] as? [String: Any])
      recorder.append(method: method, payload: payload)
      let value: String
      switch method {
      case "session.rename":
        value = #"{"title":"Renamed session","seq":9}"#
      case "session.fork":
        value = #"{"sessionId":"session-child"}"#
      case "workspace.insertSessionBefore":
        value = """
          {"workspace":{"workspaceId":"workspace-real","path":"/tmp/project",
          "title":"Project","sessionIds":["session-real","session-other"],
          "createdAt":"2026-08-14T00:00:00.000Z",
          "updatedAt":"2026-08-15T00:00:00.000Z"}}
          """
      case "workspace.archiveSession":
        value = #"{"archivedSessionIds":["session-real"]}"#
      default:
        Issue.record("Unexpected method \(method)")
        value = "{}"
      }
      let response = try #require(
        HTTPURLResponse(
          url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
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

    let transport = UpstreamNavigationTransport(
      baseURL: try #require(URL(string: "http://harness.invalid")),
      session: session
    )
    try await transport.renameSession(sessionID: "session-real", title: "Renamed session")
    let childID = try await transport.forkSession(sessionID: "session-real")
    try await transport.moveSession(
      sessionID: "session-real",
      toWorkspaceID: "workspace-real",
      beforeSessionID: "session-other"
    )
    try await transport.archiveSession(sessionID: "session-real")

    #expect(childID == "session-child")
    let requests = recorder.requests
    #expect(
      requests.map(\.method) == [
        "session.rename", "session.fork", "workspace.insertSessionBefore",
        "workspace.archiveSession",
      ])
    #expect(requests[0].payload["sessionId"] as? String == "session-real")
    #expect(requests[0].payload["title"] as? String == "Renamed session")
    #expect(requests[1].payload["sessionId"] as? String == "session-real")
    #expect(requests[2].payload["workspaceId"] as? String == "workspace-real")
    #expect(requests[2].payload["beforeSessionId"] as? String == "session-other")
    #expect(requests[3].payload["sessionId"] as? String == "session-real")
  }

  private func summary(
    _ id: String,
    title: String,
    updatedAt: Double,
    origin: String? = nil,
    blank: Bool = false
  ) -> NavigationSessionSummary {
    NavigationSessionSummary(
      sessionID: id,
      updatedAt: updatedAt,
      blank: blank,
      origin: origin,
      cwd: nil,
      projections: NavigationProjectionBlock(values: ["title": .string(title)])
    )
  }
}

private final class NavigationRequestRecorder: @unchecked Sendable {
  struct Request {
    let method: String
    let payload: [String: Any]
  }

  private let lock = NSLock()
  private var storage: [Request] = []

  var requests: [Request] {
    lock.withLock { storage }
  }

  func append(method: String, payload: [String: Any]) {
    lock.withLock { storage.append(Request(method: method, payload: payload)) }
  }
}

private final class NavigationURLProtocol: URLProtocol, @unchecked Sendable {
  nonisolated(unsafe) static var handler: ((URLRequest, Data) throws -> (HTTPURLResponse, Data))?
  private static let lock = NSLock()
  nonisolated(unsafe) private static var paths: [String] = []

  static var capturedPaths: [String] {
    lock.withLock { paths }
  }

  static func reset() {
    lock.withLock { paths = [] }
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.lock.withLock { Self.paths.append(request.url?.path ?? "") }
    do {
      let body = try bodyData()
      let handler = try #require(Self.handler)
      let (response, data) = try handler(request, body)
      client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
      client?.urlProtocol(self, didLoad: data)
      client?.urlProtocolDidFinishLoading(self)
    } catch {
      client?.urlProtocol(self, didFailWithError: error)
    }
  }

  override func stopLoading() {}

  private func bodyData() throws -> Data {
    if let body = request.httpBody { return body }
    guard let stream = request.httpBodyStream else { return Data() }
    stream.open()
    defer { stream.close() }
    var result = Data()
    var buffer = [UInt8](repeating: 0, count: 4_096)
    while stream.hasBytesAvailable {
      let count = stream.read(&buffer, maxLength: buffer.count)
      if count < 0 { throw stream.streamError ?? URLError(.cannotDecodeContentData) }
      if count == 0 { break }
      result.append(buffer, count: count)
    }
    return result
  }
}
