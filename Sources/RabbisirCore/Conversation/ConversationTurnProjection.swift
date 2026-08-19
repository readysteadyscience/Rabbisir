import Foundation

/// One upstream runtime message node or completed-turn footer in display order.
enum NativeConversationDisplayUnit: Identifiable, Equatable, Sendable {
  case message(NativeConversationItem)
  case turnTail(
    id: String,
    turn: Int,
    copyText: String,
    runDuration: TimeInterval?
  )

  var id: String {
    switch self {
    case .message(let item):
      "message:\(item.id)"
    case .turnTail(let id, _, _, _):
      id
    }
  }

  var copyText: String? {
    switch self {
    case .message(let item) where item.kind == .user:
      item.text
    case .turnTail(_, _, let copyText, _):
      copyText
    default:
      nil
    }
  }

  var runDuration: TimeInterval? {
    guard case .turnTail(_, _, _, let duration) = self else { return nil }
    return duration
  }
}

/// Preserves official assistant steps and adds one footer after each completed turn.
enum NativeConversationTurnProjection {
  static func units(from items: [NativeConversationItem]) -> [NativeConversationDisplayUnit] {
    var units = items.filter(\.isUserVisible).map(NativeConversationDisplayUnit.message)
    let completedTurns = Dictionary(
      grouping: items.compactMap { item -> NativeConversationItem? in
        guard item.kind == .assistant, item.turn != nil, item.turnEndedAt != nil else { return nil }
        return item
      }, by: { $0.turn! })

    for (turn, assistantItems) in completedTurns {
      guard let closing = assistantItems.last else { continue }
      let start = closing.turnStartedAt ?? assistantItems.first?.turnStartedAt
      let end = closing.turnEndedAt ?? assistantItems.last?.turnEndedAt
      let duration = start.flatMap { start in end.map { max(0, $0 - start) / 1_000 } }
      guard
        let insertionIndex = units.lastIndex(where: { unit in
          guard case .message(let item) = unit else { return false }
          return item.turn == turn
        })
      else { continue }
      units.insert(
        .turnTail(
          id: "turn-tail:\(turn)",
          turn: turn,
          copyText: closing.text,
          runDuration: duration
        ),
        at: units.index(after: insertionIndex)
      )
    }
    return units
  }
}

enum ConversationRunDurationFormatter {
  static func string(seconds: TimeInterval, copy: RabbisirCopy) -> String {
    copy.runDuration(seconds: seconds)
  }
}
