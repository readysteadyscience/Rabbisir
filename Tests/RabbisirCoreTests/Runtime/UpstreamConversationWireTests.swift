import Foundation
import Testing

@testable import RabbisirCore

@Suite("upstream conversation wire")
struct UpstreamConversationWireTests {
  @Test("History requests use the official full-form RPC envelope")
  func encodesUpstreamHistoryEnvelope() throws {
    let data = try UpstreamConversationWire.encodeRequest(
      method: "session.history",
      rpcID: "rpc-history",
      payload: UpstreamHistoryRequest(
        sessionID: "session-real",
        beforeSequence: 42,
        maxMessages: 20
      )
    )
    let object = try #require(
      JSONSerialization.jsonObject(with: data) as? [String: Any]
    )
    let payload = try #require(object["payload"] as? [String: Any])

    #expect(object["type"] as? String == "client-request")
    #expect(object["rpcId"] as? String == "rpc-history")
    #expect(object["method"] as? String == "session.history")
    #expect(payload["sessionId"] as? String == "session-real")
    #expect(payload["beforeSeq"] as? Int == 42)
    #expect(payload["maxMessages"] as? Int == 20)
  }

  @Test("History responses preserve event, surface, and projection fields")
  func decodesUpstreamHistoryResponse() throws {
    let data = Data(
      """
      {
        "type":"server-response",
        "rpcId":"rpc-history",
        "result":{"ok":true,"value":{
          "events":[{"event":{
            "type":"user/message","seq":7,"time":101.5,
            "data":{"id":"message-1","role":"user","content":[{"type":"text","text":"hello"}],"source":{"kind":"user"}},
            "sourceEventSeqs":[4,5],"surfaceOp":"append"
          }}],
          "hasMore":true,
          "projections":{"asOfSeq":7,"values":{"title":{"text":"Session"}}}
        }}
      }
      """.utf8
    )

    let page = try UpstreamConversationWire.decodeHistoryResponse(
      data,
      expectedRPCID: "rpc-history"
    )

    #expect(page.hasMore)
    #expect(page.events.count == 1)
    #expect(page.events[0].event.sequence == 7)
    #expect(page.events[0].event.surfaceOperation == .append)
    #expect(page.events[0].event.sourceEventSequences == [4, 5])
    #expect(page.projections?.asOfSequence == 7)
  }

  @Test("Mux decoding validates both envelope levels")
  func decodesSessionEventMuxEnvelope() throws {
    let data = Data(
      """
      {
        "type":"server-request","rpcId":"push-1","method":"session/event",
        "payload":{"type":"session/event","sessionId":"session-real","event":{
          "type":"assistant/chunk","seq":9,"time":110,
          "data":{"turn":2,"step":1,"chunk":{"type":"text-delta","index":0,"text":"Hi"}}
        }}
      }
      """.utf8
    )

    let envelope = try UpstreamConversationWire.decodeMuxEnvelope(data)
    #expect(envelope.rpcID == "push-1")
    guard case .event(let sessionID, let entry) = envelope.frame else {
      Issue.record("Expected session/event")
      return
    }
    #expect(sessionID == "session-real")
    #expect(entry.event.type == "assistant/chunk")
    #expect(entry.event.sequence == 9)
  }

  @Test("Mux decoding preserves queue and answerable interaction semantics")
  func decodesQueueApprovalAndQuestionFrames() throws {
    let queue = try UpstreamConversationWire.decodeMuxEnvelope(
      Data(
        #"{"type":"server-request","rpcId":"push-queue","method":"session/queue","payload":{"type":"session/queue","sessionId":"session-real","items":[{"id":"queued-1","placement":"queued","message":{"id":"message-1","role":"user","content":[{"type":"text","text":"queued prompt"}],"source":{"kind":"user"}}}]}}"#
          .utf8
      )
    )
    guard case .queue(let sessionID, let items) = queue.frame else {
      Issue.record("Expected session/queue")
      return
    }
    #expect(sessionID == "session-real")
    #expect(items.count == 1)
    #expect(items[0].id == "queued-1")
    #expect(items[0].placement == .queued)
    #expect(items[0].editableText == "queued prompt")
    #expect(items[0].preview == "queued prompt")

    let approval = try UpstreamConversationWire.decodeMuxEnvelope(
      Data(
        #"{"type":"server-request","rpcId":"approval-rpc","method":"approval/requested","payload":{"type":"approval/requested","sessionId":"session-real","approvalId":"approval-1","toolName":"bash","reason":"Run the requested command"}}"#
          .utf8
      )
    )
    guard case .approvalRequested(let request) = approval.frame else {
      Issue.record("Expected approval/requested")
      return
    }
    #expect(request.rpcID == "approval-rpc")
    #expect(request.sessionID == "session-real")
    #expect(request.approvalID == "approval-1")
    #expect(request.toolName == "bash")

    let question = try UpstreamConversationWire.decodeMuxEnvelope(
      Data(
        #"{"type":"server-request","rpcId":"question-rpc","method":"question/requested","payload":{"type":"question/requested","sessionId":"session-real","questions":[{"id":"choice","header":"Decision","question":"Continue?","options":[{"label":"Yes","description":"Continue safely"}],"multiSelect":false}]}}"#
          .utf8
      )
    )
    guard case .questionRequested(let request) = question.frame else {
      Issue.record("Expected question/requested")
      return
    }
    #expect(request.rpcID == "question-rpc")
    #expect(request.questions.first?.id == "choice")
    #expect(request.questions.first?.options?.first?.label == "Yes")
  }

  @Test("Answer envelopes echo the server request id without minting a new RPC")
  func encodesAnswerEnvelope() throws {
    let data = try UpstreamConversationWire.encodeResponse(
      rpcID: "approval-rpc",
      value: UpstreamApprovalResponse(
        sessionID: "session-real",
        approvalID: "approval-1",
        outcome: .allowedOnce
      )
    )
    let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    let result = try #require(object["result"] as? [String: Any])
    let value = try #require(result["value"] as? [String: Any])
    #expect(object["type"] as? String == "client-response")
    #expect(object["rpcId"] as? String == "approval-rpc")
    #expect(result["ok"] as? Bool == true)
    #expect(value["outcome"] as? String == "allowed-once")
  }

  @Test("RPC correlation mismatches are rejected")
  func rejectsMismatchedRPCID() throws {
    let data = Data(
      """
      {"type":"server-response","rpcId":"other","result":{"ok":true,"value":{"events":[],"hasMore":false}}}
      """.utf8
    )

    #expect(
      throws: UpstreamConversationWireError.rpcIDMismatch(
        expected: "expected",
        actual: "other"
      )
    ) {
      try UpstreamConversationWire.decodeHistoryResponse(data, expectedRPCID: "expected")
    }
  }
}
