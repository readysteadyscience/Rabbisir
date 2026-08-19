import CoreGraphics
import Testing

@testable import RabbisirCore

@Suite("Native conversation scrolling")
struct ConversationScrollPolicyTests {
  @Test("Initial history opens at the latest message without animation")
  func initialHistoryUsesTheTail() {
    var policy = ConversationScrollPolicy()

    let action = policy.contentDidChange(
      previousIDs: [],
      currentIDs: ["message:1", "message:2"]
    )

    #expect(action == .followTail(animated: false))
    #expect(policy.hasPositionedInitialContent)
  }

  @Test("Streaming and appended messages follow only while the user remains at the tail")
  func tailFollowingRespectsUserPosition() {
    var policy = ConversationScrollPolicy()
    _ = policy.contentDidChange(previousIDs: [], currentIDs: ["assistant:1"])

    _ = policy.viewportDidUpdate(distanceFromBottom: 0, contentTopOffset: -600)
    #expect(
      policy.contentDidChange(
        previousIDs: ["assistant:1"],
        currentIDs: ["assistant:1"]
      ) == .followTail(animated: true)
    )

    _ = policy.viewportDidUpdate(distanceFromBottom: 180, contentTopOffset: -420)
    #expect(
      policy.contentDidChange(
        previousIDs: ["assistant:1"],
        currentIDs: ["assistant:1", "tool:1"]
      ) == .none
    )

    _ = policy.viewportDidUpdate(distanceFromBottom: 12, contentTopOffset: -610)
    #expect(
      policy.contentDidChange(
        previousIDs: ["assistant:1", "tool:1"],
        currentIDs: ["assistant:1", "tool:1", "assistant:2"]
      ) == .followTail(animated: true)
    )
  }

  @Test("Prepending history preserves the first previously visible stable ID")
  func prependPreservesAnchor() {
    var policy = ConversationScrollPolicy()
    _ = policy.contentDidChange(
      previousIDs: [],
      currentIDs: ["message:20", "message:21"]
    )
    _ = policy.viewportDidUpdate(distanceFromBottom: 300, contentTopOffset: -4)

    let action = policy.contentDidChange(
      previousIDs: ["message:20", "message:21"],
      currentIDs: ["message:18", "message:19", "message:20", "message:21"]
    )

    #expect(action == .preserveAnchor(id: "message:20"))
  }

  @Test("A simultaneous stream append does not defeat prepend anchor preservation")
  func prependWithConcurrentAppendPreservesAnchor() {
    var policy = ConversationScrollPolicy()
    _ = policy.contentDidChange(
      previousIDs: [],
      currentIDs: ["message:20", "message:21"]
    )

    let action = policy.contentDidChange(
      previousIDs: ["message:20", "message:21"],
      currentIDs: ["message:19", "message:20", "message:21", "message:22"]
    )

    #expect(action == .preserveAnchor(id: "message:20"))
  }

  @Test("Older history loads only after leaving and returning to the top boundary")
  func historyBoundaryRequiresARealReturn() {
    var policy = ConversationScrollPolicy()

    let initialTop = policy.viewportDidUpdate(
      distanceFromBottom: 400,
      contentTopOffset: 0
    )
    let movedToTail = policy.viewportDidUpdate(
      distanceFromBottom: 0,
      contentTopOffset: -700
    )
    let returnedToTop = policy.viewportDidUpdate(
      distanceFromBottom: 700,
      contentTopOffset: -8
    )

    #expect(!initialTop)
    #expect(!movedToTail)
    #expect(returnedToTop)
  }

  @Test("Session reset restores initial tail placement and boundary tracking")
  func sessionResetStartsFresh() {
    var policy = ConversationScrollPolicy()
    _ = policy.contentDidChange(previousIDs: [], currentIDs: ["old:1"])
    _ = policy.viewportDidUpdate(distanceFromBottom: 200, contentTopOffset: -200)

    policy.resetForSession()

    #expect(policy.isFollowingTail)
    #expect(!policy.hasPositionedInitialContent)
    #expect(
      policy.contentDidChange(
        previousIDs: [],
        currentIDs: ["new:1"]
      ) == .followTail(animated: false)
    )
  }

  @Test("Conversation rows keep the upstream-derived stable ID")
  func itemIdentityIsStableAcrossStreamingRevisions() {
    let partial = NativeConversationItem(
      id: "assistant:turn-2:step-1",
      kind: .assistant,
      text: "部分",
      isStreaming: true
    )
    let final = NativeConversationItem(
      id: "assistant:turn-2:step-1",
      kind: .assistant,
      text: "部分回复",
      isStreaming: false
    )

    #expect(partial.id == final.id)
    #expect(partial != final)
  }

  @Test("Conversation UI identity scopes an official message ID to its session")
  func itemIdentityIsUniqueAcrossSessions() {
    let first = ConversationUIIdentity.scoped(
      sessionID: "session-one",
      messageID: "assistant:1:1"
    )
    let repeated = ConversationUIIdentity.scoped(
      sessionID: "session-one",
      messageID: "assistant:1:1"
    )
    let second = ConversationUIIdentity.scoped(
      sessionID: "session-two",
      messageID: "assistant:1:1"
    )

    #expect(first == repeated)
    #expect(first != second)
  }
}
