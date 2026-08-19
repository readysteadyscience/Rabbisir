import Foundation
import Testing

@testable import RabbisirCore

@Suite("Native conversation reducer")
struct ConversationReducerTests {
  @Test("History and duplicate live events fold idempotently")
  func mergesHistoryAndLiveEventsBySequence() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: [try entry(userJSON(sequence: 1, text: "hello"))],
        hasMore: false,
        projections: nil
      ))

    let duplicate = try entry(userJSON(sequence: 1, text: "hello"))
    let changed = reducer.ingest(duplicate)
    #expect(!changed)
    #expect(reducer.eventCount == 1)
    #expect(reducer.projection().messages.map(\.id) == ["user:message-1"])
  }

  @Test("Streaming chunks update one stable row and final output replaces it")
  func foldsStreamingAssistantIntoFinalMessage() throws {
    var reducer = ConversationReducer()
    reducer.merge(
      UpstreamHistoryPage(
        events: [
          try entry(
            chunkJSON(
              sequence: 2, chunk: "{\"type\":\"block-start\",\"index\":0,\"blockType\":\"text\"}")),
          try entry(
            chunkJSON(sequence: 3, chunk: "{\"type\":\"text-delta\",\"index\":0,\"text\":\"Hel\"}")),
          try entry(
            chunkJSON(sequence: 4, chunk: "{\"type\":\"text-delta\",\"index\":0,\"text\":\"lo\"}")),
        ],
        hasMore: false,
        projections: nil
      ))

    let partial = try #require(reducer.projection().messages.first)
    #expect(partial.id == "assistant:1:1")
    #expect(partial.blocks == [.text("Hello")])
    #expect(partial.isStreaming)

    reducer.ingest(try entry(assistantJSON(sequence: 5, text: "Hello")))
    let final = try #require(reducer.projection().messages.first)
    #expect(final.id == partial.id)
    #expect(final.sequence == 5)
    #expect(final.blocks == [.text("Hello")])
    #expect(!final.isStreaming)
    #expect(reducer.projection().messages.count == 1)
  }

  @Test("An aborted turn closes a partial assistant stream without inventing a final message")
  func closesPartialAssistantWhenTurnEndsAborted() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: [
          try entry(
            #"{"type":"turn/start","seq":1,"time":1000,"data":{"turn":1}}"#
          ),
          try entry(
            chunkJSON(
              sequence: 2,
              chunk: #"{"type":"block-start","index":0,"blockType":"text"}"#
            )
          ),
          try entry(
            chunkJSON(
              sequence: 3,
              chunk: #"{"type":"text-delta","index":0,"text":"partial"}"#
            )
          ),
          try entry(
            #"{"type":"turn/end","seq":4,"time":2000,"data":{"turn":1,"reason":{"kind":"aborted"}}}"#
          ),
        ],
        hasMore: false,
        projections: nil
      ))

    let projection = reducer.projection()
    let message = try #require(projection.messages.first)
    let row = try #require(projection.rows.first { $0.kind == .assistant })
    #expect(message.blocks == [.text("partial")])
    #expect(!message.isStreaming)
    #expect(!row.isStreaming)
  }

  @Test("Upstream turn boundaries annotate user and assistant rows without becoming visible rows")
  func projectsAuthoritativeTurnLifecycle() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: [
          try entry(
            """
            {"type":"turn/start","seq":1,"time":1000,"data":{"turn":4}}
            """),
          try entry(userJSON(sequence: 2, text: "question")),
          try entry(
            """
            {"type":"assistant/message","seq":3,"time":2200,
             "data":{"turn":4,"step":1,"message":{"id":"assistant-4","role":"assistant",
                     "content":[{"type":"text","text":"answer"}],"source":{"kind":"model"}}},
             "surfaceOp":"append"}
            """),
          try entry(
            """
            {"type":"turn/end","seq":4,"time":3500,
             "data":{"turn":4,"reason":{"kind":"completed"}}}
            """),
        ],
        hasMore: false,
        projections: nil
      ))

    let projection = reducer.projection()
    #expect(projection.messages.count == 2)
    #expect(projection.messages.map(\.turn) == [4, 4])
    #expect(
      projection.turns[4]
        == UpstreamConversationTurn(
          number: 4,
          startTime: 1000,
          endTime: 3500
        ))
    #expect(projection.latestSequence == 4)
    #expect(reducer.eventCount == 2)
  }

  @Test("Internal surface replacements neither render nor shadow human conversation turns")
  func excludesInternalSurfaceReplacement() throws {
    var reducer = ConversationReducer()
    reducer.merge(
      UpstreamHistoryPage(
        events: [
          try entry(userJSON(sequence: 1, text: "old")),
          try entry(assistantJSON(sequence: 2, text: "answer")),
          try entry(
            """
            {"type":"user/message","seq":6,"time":6,
             "data":{"id":"replacement","role":"user","content":[{"type":"text","text":"summary"}],"source":{"kind":"plugin"}},
             "sourceEventSeqs":[1,2],"surfaceOp":{"op":"replace","start":1,"end":2}}
            """
          ),
        ],
        hasMore: false,
        projections: nil
      ))

    let messages = reducer.projection().messages
    #expect(messages.count == 2)
    #expect(messages.map(\.role) == [.user, .assistant])
    #expect(messages.map(\.blocks) == [[.text("old")], [.text("answer")]])
  }

  @Test("Projection admits only direct human and model assistant visible text")
  func allowListsConversationTurnsAndTextBlocks() throws {
    let fixtures = [
      """
      {"type":"system/message","seq":1,"time":1,
       "data":{"role":"system","content":[{"type":"text","text":"SYSTEM_PRIVATE"}]}}
      """,
      """
      {"type":"developer/message","seq":2,"time":2,
       "data":{"role":"developer","content":[{"type":"text","text":"DEVELOPER_PRIVATE"}]}}
      """,
      """
      {"type":"user/message","seq":3,"time":3,
       "data":{"id":"context","role":"user","source":{"kind":"plugin","plugin":"instructions","form":"instructions"},
               "content":[{"type":"text","text":"PLUGIN_PRIVATE"}]},"surfaceOp":"append"}
      """,
      """
      {"type":"user/message","seq":4,"time":4,
       "data":{"id":"wrong-role","role":"developer","source":{"kind":"user"},
               "content":[{"type":"text","text":"ROLE_PRIVATE"}]},"surfaceOp":"append"}
      """,
      """
      {"type":"tool/result","seq":5,"time":5,
       "data":{"turn":1,"step":1,"message":{"role":"user","source":{"kind":"tool","callId":"call-1"},
               "content":[{"type":"tool-result","toolCallId":"call-1","content":[{"type":"text","text":"TOOL_PRIVATE"}]}]},
               "meta":{"debug":"METADATA_PRIVATE"}},"surfaceOp":"append"}
      """,
      """
      {"type":"assistant/message","seq":6,"time":6,
       "data":{"turn":1,"step":1,"message":{"id":"not-model","role":"assistant",
               "source":{"kind":"plugin","plugin":"internal"},
               "content":[{"type":"text","text":"ASSISTANT_SOURCE_PRIVATE"}]}},"surfaceOp":"append"}
      """,
      """
      {"type":"user/message","seq":9,"time":9,
       "data":{"id":"missing-surface","role":"user","source":{"kind":"user"},
               "content":[{"type":"text","text":"MISSING_SURFACE_PRIVATE"}]}}
      """,
      """
      {"type":"assistant/message","seq":10,"time":10,
       "data":{"turn":3,"step":1,"message":{"id":"replacement-model","role":"assistant",
               "source":{"kind":"model","provider":"deepseek","model":"deepseek-chat"},
               "content":[{"type":"text","text":"REPLACEMENT_PRIVATE"}]}},
       "sourceEventSeqs":[7,8],"surfaceOp":{"op":"replace","start":7,"end":8}}
      """,
      """
      {"type":"assistant/message","seq":11,"time":11,
       "data":{"turn":4,"step":1,"message":{"id":"reasoning-only","role":"assistant",
               "source":{"kind":"model","provider":"deepseek","model":"deepseek-reasoner"},
               "content":[{"type":"reasoning","text":"REASONING_ONLY_PRIVATE"}]}},"surfaceOp":"append"}
      """,
      """
      {"type":"user/message","seq":7,"time":7,
       "data":{"id":"human","role":"user","source":{"kind":"user"},"debug":"USER_METADATA_PRIVATE",
               "content":[{"type":"text","text":"visible human"},
                          {"type":"reasoning","text":"USER_REASONING_PRIVATE"},
                          {"type":"internal","text":"USER_BLOCK_PRIVATE"}]},"surfaceOp":"append"}
      """,
      """
      {"type":"assistant/message","seq":8,"time":8,
       "data":{"turn":2,"step":1,"debug":"ASSISTANT_METADATA_PRIVATE","message":{"id":"model","role":"assistant",
               "source":{"kind":"model","provider":"deepseek","model":"deepseek-chat","replayState":{"raw":"REPLAY_PRIVATE"}},
               "content":[{"type":"text","text":"visible assistant"},
                          {"type":"reasoning","text":"REASONING_PRIVATE"},
                          {"type":"tool-call","id":"call-2","name":"secret_tool","arguments":"TOOL_ARGS_PRIVATE"},
                          {"type":"image","attachment":{"attachmentId":"IMAGE_METADATA_PRIVATE"}},
                          {"type":"debug","text":"UNKNOWN_BLOCK_PRIVATE"}]}},"surfaceOp":"append"}
      """,
    ]
    var reducer = ConversationReducer()

    reducer.reset(
      to: UpstreamHistoryPage(
        events: try fixtures.map(entry),
        hasMore: false,
        projections: nil
      ))

    let projection = reducer.projection()
    let messages = projection.messages
    #expect(reducer.eventCount == 2)
    #expect(messages.map(\.role) == [.user, .assistant])
    #expect(
      messages.map(\.blocks) == [
        [.text("visible human")],
        [.text("visible assistant")],
      ])
    #expect(!String(describing: projection.rows).contains("REASONING_ONLY_PRIVATE"))
    #expect(!String(describing: projection.rows).contains("REASONING_PRIVATE"))
    let rendered = projection.rows.map { [$0.text, $0.detail ?? ""] }.flatMap { $0 }
    #expect(
      !rendered.contains { value in
        value.contains("SYSTEM_PRIVATE")
          || value.contains("DEVELOPER_PRIVATE")
          || value.contains("TOOL_PRIVATE")
          || value.contains("METADATA_PRIVATE")
          || value.contains("TOOL_ARGS_PRIVATE")
      })
  }

  @Test("Streaming projection admits text chunks but no reasoning, tool, or unknown block payload")
  func allowListsStreamingTextChunks() throws {
    let chunks = [
      "{\"type\":\"block-start\",\"index\":0,\"blockType\":\"reasoning\"}",
      "{\"type\":\"reasoning-delta\",\"index\":0,\"text\":\"STREAM_REASONING_PRIVATE\"}",
      "{\"type\":\"text-delta\",\"index\":0,\"text\":\"WRONG_INDEX_PRIVATE\"}",
      "{\"type\":\"tool-call-delta\",\"index\":1,\"id\":\"call\",\"name\":\"private\",\"argumentsDelta\":\"STREAM_TOOL_PRIVATE\"}",
      "{\"type\":\"block-end\",\"index\":2,\"block\":{\"type\":\"reasoning\",\"text\":\"BLOCK_REASONING_PRIVATE\"}}",
      "{\"type\":\"block-start\",\"index\":3,\"blockType\":\"text\"}",
      "{\"type\":\"text-delta\",\"index\":3,\"text\":\"visible \"}",
      "{\"type\":\"block-end\",\"index\":3,\"block\":{\"type\":\"text\",\"text\":\"visible stream\"}}",
      "{\"type\":\"block-end\",\"index\":4,\"block\":{\"type\":\"debug\",\"text\":\"STREAM_UNKNOWN_PRIVATE\"}}",
    ]
    var reducer = ConversationReducer()

    reducer.merge(
      UpstreamHistoryPage(
        events: try chunks.enumerated().map { offset, chunk in
          try entry(chunkJSON(sequence: offset + 1, chunk: chunk))
        },
        hasMore: false,
        projections: nil
      ))

    let message = try #require(reducer.projection().messages.first)
    #expect(reducer.projection().messages.count == 1)
    #expect(message.role == .assistant)
    #expect(message.blocks == [.text("visible stream")])
    #expect(message.isStreaming)
    let rows = reducer.projection().rows
    #expect(!String(describing: rows).contains("STREAM_REASONING_PRIVATE"))
    #expect(
      !rows.contains { row in
        row.text.contains("STREAM_TOOL_PRIVATE")
          || (row.detail?.contains("STREAM_TOOL_PRIVATE") == true)
          || row.text.contains("STREAM_UNKNOWN_PRIVATE")
          || (row.detail?.contains("STREAM_UNKNOWN_PRIVATE") == true)
      })
  }

  @Test("Upstream assistant block order and one complete turn copy survive projection")
  func preservesAssistantBlockOrderAndClosingCopy() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: try [
          #"{"type":"turn/start","seq":1,"time":1,"data":{"turn":5}}"#,
          #"{"type":"assistant/message","seq":2,"time":2,"data":{"turn":5,"step":1,"message":{"id":"mixed","role":"assistant","source":{"kind":"model"},"content":[{"type":"text","text":"第一段"},{"type":"reasoning","text":"中间思考"},{"type":"text","text":"第二段"}]}} ,"surfaceOp":"append"}"#,
          #"{"type":"turn/end","seq":3,"time":3,"data":{"turn":5,"reason":{"kind":"completed"}}}"#,
        ].map(entry),
        hasMore: false,
        projections: nil
      ))

    let rows = reducer.projection().rows
    #expect(rows.map(\.kind) == [.assistant, .assistant, .turnTail])
    #expect(rows.dropLast().map(\.text) == ["第一段", "第二段"])
    #expect(rows.last?.copyText == "第一段\n\n第二段")
  }

  @Test("Image-only official user messages remain visible")
  func projectsImageOnlyUserMessage() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: [
          try entry(
            #"{"type":"user/message","seq":1,"time":1,"data":{"id":"image-user","role":"user","source":{"kind":"user"},"content":[{"type":"image","attachment":{"attachmentId":"user-image","mediaType":"image/png","bytes":9,"width":32,"height":24,"name":"capture.png"}}]},"surfaceOp":"append"}"#
          )
        ],
        hasMore: false,
        projections: nil
      ))

    let row = try #require(reducer.projection().rows.first)
    #expect(row.kind == .user)
    #expect(row.text.isEmpty)
    #expect(row.images.map(\.attachmentID) == ["user-image"])
  }

  @Test("A non-model final message removes its partial without exposing either payload")
  func invalidAssistantFinalClearsPartial() throws {
    var reducer = ConversationReducer()
    reducer.merge(
      UpstreamHistoryPage(
        events: [
          try entry(
            chunkJSON(
              sequence: 1, chunk: "{\"type\":\"block-start\",\"index\":0,\"blockType\":\"text\"}")),
          try entry(
            chunkJSON(
              sequence: 2,
              chunk: "{\"type\":\"text-delta\",\"index\":0,\"text\":\"visible before final\"}")),
        ],
        hasMore: false,
        projections: nil
      ))
    #expect(reducer.projection().messages.count == 1)

    reducer.ingest(
      try entry(
        """
        {"type":"assistant/message","seq":3,"time":3,
         "data":{"turn":1,"step":1,"message":{"id":"invalid","role":"assistant",
                 "source":{"kind":"plugin","plugin":"internal"},
                 "content":[{"type":"text","text":"PRIVATE_FINAL"}]}},"surfaceOp":"append"}
        """
      ))

    #expect(reducer.projection().messages.isEmpty)
    #expect(reducer.eventCount == 0)
  }

  @Test("A finalized long history discards all source chunks after one linear pass")
  func compactsFinalizedLongHistory() {
    let chunkCount = 17_847
    let chunks = (0..<chunkCount).map { sequence in
      UpstreamHistoryEntry(
        event: UpstreamSessionEvent(
          type: "assistant/chunk",
          sequence: sequence,
          time: Double(sequence),
          data: .object([
            "turn": .integer(1),
            "step": .integer(1),
            "chunk": .object([
              "type": .string("text-delta"),
              "index": .integer(0),
              "text": .string(""),
            ]),
          ]),
          sourceEventSequences: nil,
          surfaceOperation: nil,
          ignorable: nil
        ),
        view: nil
      )
    }
    let final = UpstreamHistoryEntry(
      event: UpstreamSessionEvent(
        type: "assistant/message",
        sequence: chunkCount,
        time: Double(chunkCount),
        data: .object([
          "turn": .integer(1),
          "step": .integer(1),
          "message": .object([
            "id": .string("assistant-final"),
            "role": .string("assistant"),
            "content": .array([
              .object([
                "type": .string("text"),
                "text": .string("done"),
              ])
            ]),
            "source": .object(["kind": .string("model")]),
          ]),
        ]),
        sourceEventSequences: nil,
        surfaceOperation: .append,
        ignorable: nil
      ),
      view: nil
    )
    var reducer = ConversationReducer()

    reducer.reset(
      to: UpstreamHistoryPage(
        events: chunks + [final],
        hasMore: false,
        projections: nil
      ))

    #expect(reducer.eventCount == 1)
    #expect(reducer.projection().messages.count == 1)
    #expect(reducer.projection().messages[0].blocks == [.text("done")])
  }

  @Test("Upstream safe tool rows, turn tail, and produced files survive projection")
  func projectsUpstreamConversationNodes() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: [
          try entry(
            """
            {"type":"turn/start","seq":1,"time":1000,"data":{"turn":9}}
            """),
          try entry(userJSON(sequence: 2, text: "生成报告")),
          try entry(
            """
            {"type":"assistant/message","seq":3,"time":1400,
             "data":{"turn":9,"step":1,"message":{"id":"assistant-process","role":"assistant",
                     "content":[{"type":"reasoning","text":"先检查目录"},{"type":"text","text":"正在检查。"}],
                     "source":{"kind":"model"}}},"surfaceOp":"append"}
            """),
          try entryWithView(
            event: """
              {"type":"tool/call","seq":4,"time":1500,
               "data":{"turn":9,"step":1,"callId":"call-write","name":"write","arguments":"{\\"file_path\\":\\"report.md\\"}"}}
              """,
            view: """
              {"for":"call","view":{"card":"diff","title":"Write report.md",
               "diffs":[{"path":"report.md","oldText":null,"newText":"# Report"}],
               "locations":[{"path":"report.md"}]}}
              """
          ),
          try entryWithView(
            event: """
              {"type":"tool/result","seq":5,"time":1700,
               "data":{"turn":9,"step":1,"message":{"role":"user","source":{"kind":"tool","callId":"call-write"},
               "content":[{"type":"tool-result","toolCallId":"call-write","content":[{"type":"text","text":"written"}]}]}},
               "surfaceOp":"append"}
              """,
            view: """
              {"for":"result","view":{"card":"diff","title":"Wrote report.md",
               "diffs":[{"path":"report.md","oldText":null,"newText":"# Report"}]}}
              """
          ),
          try entry(
            """
            {"type":"assistant/message","seq":6,"time":2200,
             "data":{"turn":9,"step":2,"message":{"id":"assistant-final","role":"assistant",
                     "content":[{"type":"text","text":"报告已生成。"}],"source":{"kind":"model"}}},
             "surfaceOp":"append"}
            """),
          try entry(
            """
            {"type":"turn/end","seq":7,"time":3500,"data":{"turn":9,"reason":{"kind":"completed"}}}
            """),
        ],
        hasMore: false,
        projections: nil
      ))

    let rows = reducer.projection().rows
    #expect(
      rows.map(\.kind) == [
        .user, .assistant, .tool, .assistant, .turnTail,
      ])
    #expect(
      rows.filter { $0.copyText != nil }.map(\.copyText) == [
        "生成报告", "报告已生成。",
      ])
    #expect(!String(describing: rows).contains("先检查目录"))
    #expect(rows.first { $0.kind == .tool }?.tool?.title == "写入")
    #expect(rows.first { $0.kind == .tool }?.tool?.state == .succeeded)
    #expect(rows.last?.turnTail?.producedFiles == ["report.md"])
    #expect(rows.last?.turnTail?.durationMilliseconds == 2500)
  }

  @Test("Failed and read-only tools never become produced files")
  func excludesNonProducedToolLocations() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: [
          try entry(#"{"type":"turn/start","seq":1,"time":1,"data":{"turn":1}}"#),
          try entryWithView(
            event:
              #"{"type":"tool/call","seq":2,"time":2,"data":{"turn":1,"step":1,"callId":"read","name":"read","arguments":"{}"}}"#,
            view:
              #"{"for":"call","view":{"card":"generic","title":"Read a.md","kind":"read","locations":[{"path":"a.md"}]}}"#
          ),
          try entry(
            """
            {"type":"tool/result","seq":3,"time":3,"data":{"turn":1,"step":1,
             "message":{"role":"user","source":{"kind":"tool","callId":"read"},
             "content":[{"type":"tool-result","toolCallId":"read","content":[]}]}} ,"surfaceOp":"append"}
            """),
          try entryWithView(
            event:
              #"{"type":"tool/call","seq":4,"time":4,"data":{"turn":1,"step":1,"callId":"write","name":"write","arguments":"{}"}}"#,
            view:
              #"{"for":"call","view":{"card":"diff","title":"Write b.md","diffs":[],"locations":[{"path":"b.md"}]}}"#
          ),
          try entry(
            """
            {"type":"tool/result","seq":5,"time":5,"data":{"turn":1,"step":1,
             "message":{"role":"user","source":{"kind":"tool","callId":"write"},
             "content":[{"type":"tool-result","toolCallId":"write","content":[],"isError":true}]}} ,"surfaceOp":"append"}
            """),
          try entry(
            """
            {"type":"assistant/message","seq":6,"time":6,
             "data":{"turn":1,"step":2,"message":{"id":"assistant-final","role":"assistant",
                     "content":[{"type":"text","text":"done"}],"source":{"kind":"model"}}},
             "surfaceOp":"append"}
            """),
          try entry(
            #"{"type":"turn/end","seq":7,"time":7,"data":{"turn":1,"reason":{"kind":"completed"}}}"#
          ),
        ],
        hasMore: false,
        projections: nil
      ))

    #expect(reducer.projection().rows.last?.turnTail?.producedFiles == [String]())
  }

  @Test("Upstream structured tool result views drive native details without raw payload fallback")
  func projectsUpstreamStructuredToolDetails() throws {
    let fixtures: [(String, String, String, String, [String])] = [
      (
        "bash",
        #"{"for":"call","view":{"card":"terminal","title":"pwd","cwd":"/work"}}"#,
        #"{"for":"result","view":{"card":"terminal","title":"pwd complete","output":"/work\n","exitCode":0}}"#,
        "Bash",
        ["/work", "exit 0"]
      ),
      (
        "read",
        #"{"for":"call","view":{"card":"generic","title":"Read src/a.swift","kind":"read","locations":[{"path":"src/a.swift"}]}}"#,
        #"{"for":"result","view":{"card":"read","path":"src/a.swift","offset":2,"lines":[{"number":2,"text":"let value = 1"}],"totalLines":9,"lang":"swift"}}"#,
        "Read",
        ["src/a.swift", "2  let value = 1", "1 / 9"]
      ),
      (
        "grep",
        #"{"for":"call","view":{"card":"generic","title":"Search Swift","kind":"search"}}"#,
        #"{"for":"result","view":{"card":"search","shape":"paths","paths":["A.swift","B.swift"],"truncated":true,"total":4}}"#,
        "Grep",
        ["A.swift", "B.swift", "2 / 4", "Truncated"]
      ),
      (
        "web_search",
        #"{"for":"call","view":{"card":"generic","title":"Search web","kind":"search"}}"#,
        #"{"for":"result","view":{"card":"web","kind":"search","sources":[{"url":"https://example.com","title":"Example","snippet":"Official source"}],"answer":"Answer","truncated":false}}"#,
        "Search",
        ["Answer", "Example", "https://example.com", "Official source"]
      ),
    ]
    var entries: [UpstreamHistoryEntry] = []
    for (index, fixture) in fixtures.enumerated() {
      let callID = "call-\(index)"
      entries.append(
        try entryWithView(
          event:
            #"{"type":"tool/call","seq":\#(index * 2 + 1),"time":1,"data":{"turn":1,"step":1,"callId":"\#(callID)","name":"\#(fixture.0)","arguments":"RAW_ARGUMENTS_MUST_NOT_RENDER"}}"#,
          view: fixture.1
        ))
      entries.append(
        try entryWithView(
          event:
            #"{"type":"tool/result","seq":\#(index * 2 + 2),"time":2,"data":{"turn":1,"step":1,"message":{"role":"user","source":{"kind":"tool","callId":"\#(callID)"},"content":[{"type":"tool-result","toolCallId":"\#(callID)","content":[{"type":"text","text":"RAW_RESULT_MUST_NOT_RENDER"}]}]}},"surfaceOp":"append"}"#,
          view: fixture.2
        ))
    }
    var reducer = ConversationReducer()
    reducer.reset(to: UpstreamHistoryPage(events: entries, hasMore: false, projections: nil))

    let rows = reducer.projection(copy: RabbisirCopy(language: .english)).rows.filter {
      $0.kind == .tool
    }
    #expect(rows.count == fixtures.count)
    for (index, fixture) in fixtures.enumerated() {
      #expect(rows[index].tool?.title == fixture.3)
      for expected in fixture.4 {
        #expect(rows[index].detail?.contains(expected) == true)
      }
      #expect(rows[index].detail?.contains("RAW_ARGUMENTS_MUST_NOT_RENDER") == false)
      #expect(rows[index].detail?.contains("RAW_RESULT_MUST_NOT_RENDER") == false)
    }
  }

  @Test("Keyed official tool views keep their official row titles")
  func projectsUpstreamKeyedToolTitles() throws {
    let fixtures: [(name: String, title: String)] = [
      ("web_fetch", "Fetch"),
      ("web_search", "Search"),
      ("grep", "Grep"),
      ("glob", "Glob"),
    ]
    let entries = try fixtures.enumerated().map { index, fixture in
      try entryWithView(
        event:
          #"{"type":"tool/call","seq":\#(index + 1),"time":1,"data":{"turn":1,"step":1,"callId":"call-\#(index)","name":"\#(fixture.name)","arguments":"RAW_ARGUMENTS_MUST_NOT_RENDER"}}"#,
        view: #"{"for":"call","view":{"card":"generic","title":"Safe summary","kind":"search"}}"#
      )
    }
    var reducer = ConversationReducer()
    reducer.reset(to: UpstreamHistoryPage(events: entries, hasMore: false, projections: nil))

    let rows = reducer.projection(copy: RabbisirCopy(language: .english)).rows.filter {
      $0.kind == .tool
    }
    #expect(rows.map { $0.tool?.title } == fixtures.map(\.title))
  }

  @Test("Upstream tool interruption and failure summaries preserve settled semantics")
  func projectsUpstreamToolSettlementSemantics() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: [
          try entryWithView(
            event:
              #"{"type":"tool/call","seq":1,"time":1,"data":{"turn":1,"step":1,"callId":"stopped","name":"bash","arguments":"RAW_ARGUMENTS_MUST_NOT_RENDER"}}"#,
            view:
              #"{"for":"call","view":{"card":"terminal","title":"sleep 10","description":"Wait briefly"}}"#
          ),
          try entryWithView(
            event:
              #"{"type":"tool/result","seq":2,"time":2,"data":{"turn":1,"step":1,"error":{"name":"AbortError","code":"interrupted"},"message":{"role":"user","source":{"kind":"tool","callId":"stopped"},"content":[{"type":"tool-result","toolCallId":"stopped","content":[],"isError":true}]}} ,"surfaceOp":"append"}"#,
            view:
              #"{"for":"result","view":{"card":"terminal","output":"Interrupted","signal":"SIGINT"}}"#
          ),
          try entryWithView(
            event:
              #"{"type":"tool/call","seq":3,"time":3,"data":{"turn":1,"step":1,"callId":"failed","name":"read","arguments":"RAW_ARGUMENTS_MUST_NOT_RENDER"}}"#,
            view:
              #"{"for":"call","view":{"card":"generic","title":"Read protected.txt","kind":"read","locations":[{"path":"protected.txt"}]}}"#
          ),
          try entryWithView(
            event:
              #"{"type":"tool/result","seq":4,"time":4,"data":{"turn":1,"step":1,"error":{"name":"PermissionError","code":"denied"},"message":{"role":"user","source":{"kind":"tool","callId":"failed"},"content":[{"type":"tool-result","toolCallId":"failed","content":[],"isError":true}]}} ,"surfaceOp":"append"}"#,
            view:
              #"{"for":"result","view":{"card":"generic","content":[{"type":"text","text":"Permission denied\nAsk for access"}]}}"#
          ),
        ],
        hasMore: false,
        projections: nil
      ))

    let rows = reducer.projection().rows.filter { $0.kind == .tool }
    #expect(rows.count == 2)
    #expect(rows[0].tool?.state == .stopped)
    #expect(rows[0].tool?.summary == "Wait briefly")
    #expect(rows[1].tool?.state == .failed)
    #expect(rows[1].tool?.summary == "Permission denied")
    #expect(rows[1].detail == "Permission denied\nAsk for access")
  }

  @Test("Terminal tools keep the concise description collapsed and the command in expanded detail")
  func projectsUpstreamTerminalSummaryAndDetail() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: [
          try entryWithView(
            event:
              #"{"type":"tool/call","seq":1,"time":1,"data":{"turn":1,"step":1,"callId":"bash-1","name":"bash","arguments":"RAW_ARGUMENTS_MUST_NOT_RENDER"}}"#,
            view:
              #"{"for":"call","view":{"card":"terminal","title":"mv report.md ~/Desktop && git status --short","description":"Move report to Desktop and verify project folder clean","cwd":"/work"}}"#
          ),
          try entryWithView(
            event:
              #"{"type":"tool/result","seq":2,"time":2,"data":{"turn":1,"step":1,"message":{"role":"user","source":{"kind":"tool","callId":"bash-1"},"content":[{"type":"tool-result","toolCallId":"bash-1","content":[{"type":"text","text":"RAW_RESULT_MUST_NOT_RENDER"}]}]}},"surfaceOp":"append"}"#,
            view: #"{"for":"result","view":{"card":"terminal","output":"clean\n","exitCode":0}}"#
          ),
        ],
        hasMore: false,
        projections: nil
      ))

    let row = try #require(reducer.projection().rows.first { $0.kind == .tool })
    #expect(row.tool?.title == "Bash")
    #expect(row.tool?.summary == "Move report to Desktop and verify project folder clean")
    #expect(row.detail?.contains("mv report.md ~/Desktop && git status --short") == true)
    #expect(row.detail?.contains("clean") == true)
    #expect(row.detail?.contains("RAW_ARGUMENTS_MUST_NOT_RENDER") == false)
    #expect(row.detail?.contains("RAW_RESULT_MUST_NOT_RENDER") == false)
  }

  @Test("Commands use the official bare name and keep multiline settlement text expandable")
  func projectsUpstreamCommandSummaryAndDetail() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: try [
          #"{"type":"command/run","seq":1,"time":1,"data":{"commandId":"cmd-1","name":"permission","args":" workspace-write","source":{"kind":"user"}}}"#,
          #"{"type":"command/done","seq":2,"time":2,"data":{"commandId":"cmd-1","kind":"success","text":"Permission updated\nworkspace-write"}}"#,
        ].map(entry),
        hasMore: false,
        projections: nil
      ))

    let row = try #require(reducer.projection().rows.first { $0.kind == .command })
    #expect(row.tool?.title == "permission")
    #expect(row.tool?.summary == "Permission updated")
    #expect(row.detail == "Permission updated\nworkspace-write")
  }

  @Test("Upstream command retry compaction and max-token notices survive projection")
  func projectsUpstreamLifecycleNotices() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: try [
          #"{"type":"command/run","seq":1,"time":100,"data":{"commandId":"cmd-1","name":"status","args":" --short","source":{"kind":"user"}}}"#,
          #"{"type":"command/done","seq":2,"time":200,"data":{"commandId":"cmd-1","kind":"success","text":"ready"}}"#,
          #"{"type":"turn/start","seq":3,"time":300,"data":{"turn":2}}"#,
          #"{"type":"llm/retry","seq":4,"time":400,"data":{"turn":2,"step":1,"retryId":"retry-1","retry":1,"maximum":3,"delayMs":1200,"failure":{"message":"temporary"}}}"#,
          #"{"type":"compaction/summary","seq":5,"time":500,"data":{"compactionId":"compact-1","summary":[{"type":"text","text":"summary"}],"shadowedSeqs":[1,2],"shadowedTokenCount":42}}"#,
          #"{"type":"assistant/message","seq":6,"time":600,"data":{"turn":2,"step":2,"message":{"id":"answer","role":"assistant","content":[{"type":"text","text":"partial answer"}],"source":{"kind":"model"}}},"surfaceOp":"append"}"#,
          #"{"type":"turn/end","seq":7,"time":900,"data":{"turn":2,"reason":{"kind":"max-tokens"}}}"#,
        ].map(entry),
        hasMore: false,
        projections: nil
      ))

    let rows = reducer.projection().rows
    #expect(rows.contains { $0.id == "command:cmd-1" && $0.tool?.state == .succeeded })
    #expect(rows.contains { $0.id == "model-retry:retry-1" && $0.detail == "temporary" })
    #expect(rows.contains { $0.kind == .compaction && $0.detail == "summary" })
    #expect(rows.contains { $0.id == "turn-max-tokens:2" })
    #expect(rows.contains { $0.id == "turn-tail:2" && $0.copyText == "partial answer" })
  }

  @Test("Upstream image blocks and completed-turn metrics survive projection")
  func projectsImagesAndTurnMetrics() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: try [
          #"{"type":"turn/start","seq":1,"time":1000,"data":{"turn":3}}"#,
          #"{"type":"step/start","seq":2,"time":1200,"data":{"turn":3,"step":1}}"#,
          #"{"type":"assistant/chunk","seq":3,"time":1500,"data":{"turn":3,"step":1,"chunk":{"type":"text-delta","index":0,"text":"首字"}}}"#,
          #"{"type":"assistant/message","seq":4,"time":2500,"data":{"turn":3,"step":1,"message":{"id":"assistant-image","role":"assistant","source":{"kind":"model"},"content":[{"type":"reasoning","text":"先看图片"},{"type":"image","attachment":{"attachmentId":"attachment-1","mediaType":"image/png","bytes":128,"width":640,"height":480,"name":"preview.png"}},{"type":"text","text":"图片已生成"}]},"usage":{"outputTokens":50}},"surfaceOp":"append"}"#,
          #"{"type":"turn/end","seq":5,"time":3000,"data":{"turn":3,"reason":{"kind":"completed"}}}"#,
        ].map(entry),
        hasMore: false,
        projections: nil
      ))

    let rows = reducer.projection().rows
    #expect(rows.map(\.kind) == [.image, .assistant, .turnTail])
    let image = try #require(rows.first { $0.kind == .image }?.images.first)
    #expect(image.attachmentID == "attachment-1")
    #expect(image.mediaType == "image/png")
    #expect(image.pixelWidth == 640)
    #expect(image.pixelHeight == 480)

    let tail = try #require(rows.last?.turnTail)
    #expect(tail.durationMilliseconds == 2000)
    #expect(tail.firstTokenLatencyMilliseconds == 300)
    #expect(tail.tokensPerSecond == 50)
    #expect(tail.branchSequence == 4)
    #expect(!tail.isBranchUnavailable)
  }

  @Test("Produced files and branching stop at the official closing assistant")
  func scopesTailActionsToClosingAssistant() throws {
    var reducer = ConversationReducer()
    reducer.reset(
      to: UpstreamHistoryPage(
        events: [
          try entry(#"{"type":"turn/start","seq":1,"time":1,"data":{"turn":4}}"#),
          try entry(
            #"{"type":"assistant/message","seq":2,"time":2,"data":{"turn":4,"step":1,"message":{"id":"closing","role":"assistant","source":{"kind":"model"},"content":[{"type":"text","text":"完成"}]}},"surfaceOp":"append"}"#
          ),
          try entryWithView(
            event:
              #"{"type":"tool/call","seq":3,"time":3,"data":{"turn":4,"step":1,"callId":"late","name":"write","arguments":"{}"}}"#,
            view:
              #"{"for":"call","view":{"card":"diff","title":"Write late.md","locations":[{"path":"late.md"}]}}"#
          ),
          try entry(
            #"{"type":"tool/result","seq":4,"time":4,"data":{"turn":4,"step":1,"message":{"role":"user","source":{"kind":"tool","callId":"late"},"content":[{"type":"tool-result","toolCallId":"late","content":[]}]}} ,"surfaceOp":"append"}"#
          ),
          try entry(
            #"{"type":"turn/end","seq":5,"time":5,"data":{"turn":4,"reason":{"kind":"completed"}}}"#
          ),
        ],
        hasMore: false,
        projections: nil
      ))

    let tail = try #require(reducer.projection().rows.last?.turnTail)
    #expect(tail.producedFiles.isEmpty)
    #expect(tail.branchSequence == 2)
    #expect(tail.isBranchUnavailable)
  }

  private func entry(_ eventJSON: String) throws -> UpstreamHistoryEntry {
    try JSONDecoder().decode(
      UpstreamHistoryEntry.self,
      from: Data("{\"event\":\(eventJSON)}".utf8)
    )
  }

  private func entryWithView(event: String, view: String) throws -> UpstreamHistoryEntry {
    try JSONDecoder().decode(
      UpstreamHistoryEntry.self,
      from: Data("{\"event\":\(event),\"view\":\(view)}".utf8)
    )
  }

  private func userJSON(sequence: Int, text: String) -> String {
    """
    {"type":"user/message","seq":\(sequence),"time":\(sequence),
     "data":{"id":"message-\(sequence)","role":"user","content":[{"type":"text","text":"\(text)"}],"source":{"kind":"user"}},
     "surfaceOp":"append"}
    """
  }

  private func chunkJSON(sequence: Int, chunk: String) -> String {
    """
    {"type":"assistant/chunk","seq":\(sequence),"time":\(sequence),
     "data":{"turn":1,"step":1,"chunk":\(chunk)}}
    """
  }

  private func assistantJSON(sequence: Int, text: String) -> String {
    """
    {"type":"assistant/message","seq":\(sequence),"time":\(sequence),
     "data":{"turn":1,"step":1,"message":{"id":"assistant-message","role":"assistant","content":[{"type":"text","text":"\(text)"}],"source":{"kind":"model","provider":"deepseek","model":"deepseek-chat"}}},
     "surfaceOp":"append"}
    """
  }
}
