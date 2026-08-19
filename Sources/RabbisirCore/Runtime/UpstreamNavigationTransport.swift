import Foundation

/// One persistent upstream session projected into the native navigation tree.
struct RuntimeNavigationSession: Equatable, Identifiable, Sendable {
  let id: String
  let title: String
  let isSelected: Bool
  let updatedAt: Double
  let cwd: String?

  init(
    id: String,
    title: String,
    isSelected: Bool,
    updatedAt: Double,
    cwd: String? = nil
  ) {
    self.id = id
    self.title = title
    self.isSelected = isSelected
    self.updatedAt = updatedAt
    self.cwd = cwd
  }
}

/// One persistent upstream workspace and its ordered visible sessions.
struct RuntimeNavigationProject: Equatable, Identifiable, Sendable {
  let id: String
  let title: String
  let sessions: [RuntimeNavigationSession]

  var containsSelectedSession: Bool {
    sessions.contains(where: \.isSelected)
  }
}

struct UpstreamNavigationSnapshot: Equatable, Sendable {
  let projects: [RuntimeNavigationProject]
  let selectedSessionID: String?
  let selectedWorkspaceTitle: String?
}

protocol UpstreamNavigationTransporting: Sendable {
  func snapshot(selectedSessionID: String?) async throws -> UpstreamNavigationSnapshot
  func adoptWorkspace(path: String) async throws -> String
  func renameWorkspace(workspaceID: String, title: String) async throws
  func deleteWorkspace(workspaceID: String) async throws
  func moveWorkspace(workspaceID: String, beforeWorkspaceID: String?) async throws
  func renameSession(sessionID: String, title: String) async throws
  func forkSession(sessionID: String) async throws -> String
  func moveSession(
    sessionID: String,
    toWorkspaceID: String,
    beforeSessionID: String?
  ) async throws
  func archiveSession(sessionID: String) async throws
}

/// Reads the official workspace and session registries without scraping rendered rows.
final class UpstreamNavigationTransport: UpstreamNavigationTransporting, @unchecked Sendable {
  private let baseURL: URL
  private let session: URLSession

  init(baseURL: URL, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.session = session
  }

  func snapshot(selectedSessionID: String?) async throws -> UpstreamNavigationSnapshot {
    async let sessionList: SessionListValue = call(
      method: "session.list",
      payload: SessionListRequest()
    )
    async let workspaceList: WorkspaceListValue = call(
      method: "workspace.list",
      payload: WorkspaceListRequest()
    )
    return UpstreamNavigationProjection.make(
      sessions: try await sessionList.items,
      workspaces: try await workspaceList.items,
      archivedSessionIDs: Set(try await workspaceList.archivedSessionIDs),
      selectedSessionID: selectedSessionID
    )
  }

  func adoptWorkspace(path: String) async throws -> String {
    let created: WorkspaceCreateValue = try await call(
      method: "workspace.create",
      payload: WorkspaceCreateRequest(path: path)
    )
    let sessions: SessionListValue = try await call(
      method: "session.list",
      payload: SessionListRequest()
    )
    let sessionByID = Dictionary(
      uniqueKeysWithValues: sessions.items.map { ($0.sessionID, $0) }
    )
    if let existingBlankSessionID = created.workspace.sessionIDs.first(where: { sessionID in
      sessionByID[sessionID]?.blank == true
        && sessionByID[sessionID]?.origin != "subagent"
    }) {
      return existingBlankSessionID
    }
    let createdSession: SessionCreateValue = try await call(
      method: "session.create",
      payload: SessionCreateRequest(workspaceID: created.workspace.workspaceID)
    )
    return createdSession.sessionID
  }

  func renameWorkspace(workspaceID: String, title: String) async throws {
    let _: WorkspaceRenameValue = try await call(
      method: "workspace.rename",
      payload: WorkspaceRenameRequest(workspaceID: workspaceID, title: title)
    )
  }

  func deleteWorkspace(workspaceID: String) async throws {
    let _: WorkspaceDeleteValue = try await call(
      method: "workspace.delete",
      payload: WorkspaceDeleteRequest(workspaceID: workspaceID)
    )
  }

  func moveWorkspace(workspaceID: String, beforeWorkspaceID: String?) async throws {
    let _: WorkspaceInsertBeforeValue = try await call(
      method: "workspace.insertBefore",
      payload: WorkspaceInsertBeforeRequest(
        workspaceID: workspaceID,
        beforeWorkspaceID: beforeWorkspaceID
      )
    )
  }

  func renameSession(sessionID: String, title: String) async throws {
    let _: SessionRenameValue = try await call(
      method: "session.rename",
      payload: SessionRenameRequest(sessionID: sessionID, title: title)
    )
  }

  func forkSession(sessionID: String) async throws -> String {
    let value: SessionForkValue = try await call(
      method: "session.fork",
      payload: SessionIDRequest(sessionID: sessionID)
    )
    return value.sessionID
  }

  func moveSession(
    sessionID: String,
    toWorkspaceID: String,
    beforeSessionID: String?
  ) async throws {
    let _: WorkspaceInsertSessionBeforeValue = try await call(
      method: "workspace.insertSessionBefore",
      payload: WorkspaceInsertSessionBeforeRequest(
        workspaceID: toWorkspaceID,
        sessionID: sessionID,
        beforeSessionID: beforeSessionID
      )
    )
  }

  func archiveSession(sessionID: String) async throws {
    let _: WorkspaceArchiveSessionValue = try await call(
      method: "workspace.archiveSession",
      payload: SessionIDRequest(sessionID: sessionID)
    )
  }

  private func call<Request: Encodable, Value: Decodable>(
    method: String,
    payload: Request
  ) async throws -> Value {
    let rpcID = UUID().uuidString
    let body = try UpstreamConversationWire.encodeRequest(
      method: method,
      rpcID: rpcID,
      payload: payload
    )
    guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
      throw UpstreamConversationTransportError.invalidBaseURL
    }
    components.path = "/api/\(method)"
    components.query = nil
    components.fragment = nil
    guard let endpoint = components.url else {
      throw UpstreamConversationTransportError.invalidBaseURL
    }
    var request = URLRequest(url: endpoint)
    request.httpMethod = "POST"
    request.httpBody = body
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    let (data, response) = try await session.data(for: request)
    guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
      throw UpstreamConversationTransportError.carrierStatus(
        (response as? HTTPURLResponse)?.statusCode ?? -1
      )
    }
    return try UpstreamConversationWire.decodeResponse(
      data,
      expectedRPCID: rpcID,
      as: Value.self
    )
  }
}

/// Builds project navigation from current Workspace registrations. The upstream runtime
/// retains sessions after a registration is removed, but those sessions do not
/// create a replacement project row in Rabbisir.
enum UpstreamNavigationProjection {
  static let ungroupedProjectID = "rabbisir.navigation.ungrouped"

  static func make(
    sessions: [NavigationSessionSummary],
    workspaces: [NavigationWorkspace],
    archivedSessionIDs: Set<String>,
    selectedSessionID: String?
  ) -> UpstreamNavigationSnapshot {
    let byID = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sessionID, $0) })
    let projects: [RuntimeNavigationProject] = workspaces.map { workspace in
      let rows = workspace.sessionIDs.compactMap { id -> RuntimeNavigationSession? in
        guard let session = byID[id],
          isVisible(
            session,
            archivedSessionIDs: archivedSessionIDs
          )
        else { return nil }
        return row(session, selectedSessionID: selectedSessionID)
      }
      return RuntimeNavigationProject(
        id: workspace.workspaceID,
        title: workspace.title,
        sessions: rows
      )
    }
    let selectedWorkspace = selectedSessionID.flatMap { sessionID in
      guard let session = byID[sessionID],
        session.origin != "subagent",
        !archivedSessionIDs.contains(sessionID)
      else { return nil as NavigationWorkspace? }
      return workspaces.first { $0.sessionIDs.contains(sessionID) }
    }
    let effectiveSelectedSessionID = selectedSessionID.flatMap { sessionID in
      selectedWorkspace == nil ? nil : sessionID
    }
    return UpstreamNavigationSnapshot(
      projects: projects,
      selectedSessionID: effectiveSelectedSessionID,
      selectedWorkspaceTitle: selectedWorkspace?.title
    )
  }

  private static func isVisible(
    _ session: NavigationSessionSummary,
    archivedSessionIDs: Set<String>
  ) -> Bool {
    session.origin != "subagent"
      && !archivedSessionIDs.contains(session.sessionID)
      && !session.blank
  }

  private static func row(
    _ session: NavigationSessionSummary,
    selectedSessionID: String?
  ) -> RuntimeNavigationSession {
    RuntimeNavigationSession(
      id: session.sessionID,
      title: session.displayTitle,
      isSelected: session.sessionID == selectedSessionID,
      updatedAt: session.updatedAt,
      cwd: session.cwd
    )
  }
}

struct NavigationSessionSummary: Decodable, Equatable, Sendable {
  let sessionID: String
  let updatedAt: Double
  let blank: Bool
  let origin: String?
  let cwd: String?
  let projections: NavigationProjectionBlock?

  var displayTitle: String {
    if let title = projections?.values["title"]?.stringValue, !title.isEmpty {
      return title
    }
    if let cwd, !cwd.isEmpty {
      let trimmed = cwd.replacingOccurrences(
        of: "[/\\\\]+$",
        with: "",
        options: .regularExpression
      )
      if let name = trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last,
        !name.isEmpty
      {
        return String(name)
      }
    }
    return sessionID
  }

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case updatedAt
    case blank
    case origin
    case cwd
    case projections
  }
}

struct NavigationProjectionBlock: Decodable, Equatable, Sendable {
  let values: [String: UpstreamJSONValue]
}

struct NavigationWorkspace: Decodable, Equatable, Sendable {
  let workspaceID: String
  let title: String
  let sessionIDs: [String]

  private enum CodingKeys: String, CodingKey {
    case workspaceID = "workspaceId"
    case title
    case sessionIDs = "sessionIds"
  }
}

private struct SessionListRequest: Encodable {}
private struct WorkspaceListRequest: Encodable {}

private struct WorkspaceCreateRequest: Encodable {
  let path: String
}

private struct SessionCreateRequest: Encodable {
  let workspaceID: String

  private enum CodingKeys: String, CodingKey {
    case workspaceID = "workspaceId"
  }
}

private struct SessionListValue: Decodable {
  let items: [NavigationSessionSummary]
}

private struct WorkspaceListValue: Decodable {
  let items: [NavigationWorkspace]
  let archivedSessionIDs: [String]

  private enum CodingKeys: String, CodingKey {
    case items
    case archivedSessionIDs = "archivedSessionIds"
  }
}

private struct WorkspaceCreateValue: Decodable {
  let workspace: NavigationWorkspace
}

private struct SessionCreateValue: Decodable {
  let sessionID: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
  }
}

private struct WorkspaceRenameRequest: Encodable {
  let workspaceID: String
  let title: String

  private enum CodingKeys: String, CodingKey {
    case workspaceID = "workspaceId"
    case title
  }
}

private struct WorkspaceDeleteRequest: Encodable {
  let workspaceID: String

  private enum CodingKeys: String, CodingKey {
    case workspaceID = "workspaceId"
  }
}

private struct WorkspaceInsertBeforeRequest: Encodable {
  let workspaceID: String
  let beforeWorkspaceID: String?

  private enum CodingKeys: String, CodingKey {
    case workspaceID = "workspaceId"
    case beforeWorkspaceID = "beforeWorkspaceId"
  }
}

private struct SessionIDRequest: Encodable {
  let sessionID: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
  }
}

private struct SessionRenameRequest: Encodable {
  let sessionID: String
  let title: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
    case title
  }
}

private struct WorkspaceInsertSessionBeforeRequest: Encodable {
  let workspaceID: String
  let sessionID: String
  let beforeSessionID: String?

  private enum CodingKeys: String, CodingKey {
    case workspaceID = "workspaceId"
    case sessionID = "sessionId"
    case beforeSessionID = "beforeSessionId"
  }
}

private struct WorkspaceRenameValue: Decodable {
  let workspace: NavigationWorkspace
}

private struct WorkspaceDeleteValue: Decodable {
  let deleted: Bool
}

private struct WorkspaceInsertBeforeValue: Decodable {
  let workspaceIDs: [String]

  private enum CodingKeys: String, CodingKey {
    case workspaceIDs = "workspaceIds"
  }
}

private struct SessionRenameValue: Decodable {
  let title: String
  let seq: Int
}

private struct SessionForkValue: Decodable {
  let sessionID: String

  private enum CodingKeys: String, CodingKey {
    case sessionID = "sessionId"
  }
}

private struct WorkspaceInsertSessionBeforeValue: Decodable {
  let workspace: NavigationWorkspace
}

private struct WorkspaceArchiveSessionValue: Decodable {
  let archivedSessionIDs: [String]

  private enum CodingKeys: String, CodingKey {
    case archivedSessionIDs = "archivedSessionIds"
  }
}
