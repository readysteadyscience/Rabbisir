import Foundation
import Testing

@testable import RabbisirCore

@Suite("Upstream native conversation projection")
struct RuntimeConversationProjectionTests {
  @Test("Version one semantics decode without raw bridge payload")
  func decodesVisibleRows() throws {
    let projection = try #require(RuntimeNativeConversationProjection.decode(envelope))

    #expect(projection.version == 1)
    #expect(projection.sessionID == "session-1")
    #expect(projection.rows.map(\.kind) == [.user, .tool, .turnTail])
    #expect(projection.rows[0].copyText == "visible user")
    #expect(projection.rows[1].tool?.title == "已读取文件")
    #expect(projection.rows[2].turnTail?.producedFiles == ["REPORT.md"])
    #expect(!String(describing: projection).contains("PRIVATE_MODEL_REASONING"))
    #expect(!String(describing: projection).contains("developer"))
  }

  @Test("Unknown version and unknown row kinds fail closed")
  func rejectsUnknownSemantics() throws {
    let unsupported = try JSONSerialization.jsonObject(
      with: Data(envelope.replacingOccurrences(of: #""version": 1"#, with: #""version": 2"#).utf8)
    )
    #expect(RuntimeNativeConversationProjection.decode(unsupported) == nil)

    let unknownRow = try JSONSerialization.jsonObject(
      with: Data(
        envelope.replacingOccurrences(of: #""kind": "tool""#, with: #""kind": "system""#).utf8)
    )
    let projection = try #require(RuntimeNativeConversationProjection.decode(unknownRow))
    #expect(projection.rows.map(\.kind) == [.user, .turnTail])
  }

  @Test("An idle official projection cannot leave a native row streaming")
  func settlesStaleStreamingRowsWhenIdle() throws {
    let stale = envelope.replacingOccurrences(
      of: #""isStreaming": false"#,
      with: #""isStreaming": true"#,
      options: [],
      range: envelope.range(of: #""isStreaming": false"#)
    )

    let projection = try #require(RuntimeNativeConversationProjection.decode(stale))

    #expect(!projection.isRunning)
    #expect(!projection.rows[0].isStreaming)
  }

  @Test("Host channel forwards semantics without DOM extraction")
  func channelIsSemanticOnly() {
    let script = RuntimeConversationProjectionBridge.channelInstallationScript
    #expect(script.contains("webkit?.messageHandlers"))
    #expect(script.contains("messageHandlers?.rabbisirConversationProjection"))
    #expect(!script.contains("(messageHandlerName)"))
    #expect(script.contains("postMessage(JSON.stringify(value))"))
    #expect(
      RuntimeConversationProjectionBridge.projectionScript(afterRevision: 9).contains(
        "JSON.stringify(value)"))
    #expect(!script.contains("querySelector"))
    #expect(!script.contains("textContent"))
    #expect(!script.contains("innerHTML"))
  }

  @Test("Native submission bridge decodes only official semantic results")
  func decodesSubmissionResults() throws {
    let prompt = try #require(
      RuntimeConversationSubmissionResult.decode(
        #"{"accepted":true,"action":"prompt","mode":"steer"}"#
      ))
    #expect(prompt.accepted)
    #expect(prompt.action == .prompt)
    #expect(prompt.mode == .steer)

    let queueSteer = try #require(
      RuntimeConversationSubmissionResult.decode(
        #"{"accepted":true,"action":"steer-queue","mode":"steer"}"#
      ))
    #expect(queueSteer.action == .steerQueue)
    #expect(queueSteer.mode == .steer)

    #expect(
      RuntimeConversationSubmissionResult.decode(
        #"{"accepted":true,"action":"prompt","mode":"invented"}"#
      ) == nil)
    #expect(
      RuntimeConversationSubmissionResult.decode(
        #"{"accepted":true,"action":"prompt","mode":null}"#
      ) == nil)
    #expect(
      RuntimeConversationSubmissionResult.decode(
        #"{"accepted":true,"action":"none","mode":"queue"}"#
      ) == nil)
    #expect(
      RuntimeConversationSubmissionResult.decode(
        #"{"accepted":true,"action":"steer-queue","mode":null}"#
      ) == nil)

    let script = RuntimeConversationProjectionBridge.submitScript
    #expect(script.contains("bridge.submit(text, gesture)"))
    #expect(!script.contains("querySelector"))
    #expect(!script.contains("click()"))
  }

  @Test("Malformed optional fields reject the whole semantic envelope")
  func rejectsMalformedOptionalFields() throws {
    let malformedTurn = try JSONSerialization.jsonObject(
      with: Data(envelope.replacingOccurrences(of: #""turn": 1"#, with: #""turn": "1""#).utf8)
    )
    #expect(RuntimeNativeConversationProjection.decode(malformedTurn) == nil)

    let malformedDetail = try JSONSerialization.jsonObject(
      with: Data(envelope.replacingOccurrences(of: #""detail": null"#, with: #""detail": 7"#).utf8)
    )
    #expect(RuntimeNativeConversationProjection.decode(malformedDetail) == nil)

    let malformedMetric = try JSONSerialization.jsonObject(
      with: Data(
        envelope.replacingOccurrences(
          of: #""tokensPerSecond": 12.5"#, with: #""tokensPerSecond": "fast""#
        ).utf8)
    )
    #expect(RuntimeNativeConversationProjection.decode(malformedMetric) == nil)
  }
}

private let envelope = #"""
  {
    "version": 1,
    "revision": 7,
    "sessionId": "session-1",
    "openState": "open",
    "hasMore": true,
    "loadingOlder": false,
    "running": false,
    "rows": [
      {
        "id": "user-1", "kind": "user", "sequence": 1,
        "text": "visible user", "detail": null, "images": [],
        "isStreaming": false, "turn": 1, "time": 10,
        "copyText": "visible user", "tool": null, "turnTail": null
      },
      {
        "id": "reasoning-1", "kind": "reasoning", "sequence": 2,
        "text": "PRIVATE_MODEL_REASONING", "detail": "PRIVATE_MODEL_REASONING",
        "images": [], "isStreaming": false, "turn": 1, "time": 15,
        "copyText": null, "tool": null, "turnTail": null
      },
      {
        "id": "tool-1", "kind": "tool", "sequence": 2,
        "text": "已读取文件", "detail": "visible result", "images": [],
        "isStreaming": false, "turn": 1, "time": 20, "copyText": null,
        "tool": { "title": "已读取文件", "summary": "README.md", "state": "succeeded" },
        "turnTail": null
      },
      {
        "id": "tail-1", "kind": "turn-tail", "sequence": 3,
        "text": "", "detail": null, "images": [], "isStreaming": false,
        "turn": 1, "time": 30, "copyText": "visible assistant", "tool": null,
        "turnTail": {
          "durationMilliseconds": 20, "firstTokenLatencyMilliseconds": 4,
          "tokensPerSecond": 12.5, "producedFiles": ["REPORT.md"],
          "branchSequence": 2, "isBranchUnavailable": false
        }
      }
    ]
  }
  """#
