import Testing

@testable import RabbisirCore

@Suite("Upstream runtime conversation projection")
struct ConversationTurnProjectionTests {
  @Test("Upstream steps remain independent and only the closing answer owns turn copy")
  func preservesAssistantStepsAndClosingCopyOwnership() throws {
    let items = [
      item("user", .user, "请调查", turn: 7, start: 1_000, end: 25_200),
      item("step-1", .assistant, "我会先检查目录", turn: 7, start: 1_000, end: 25_200),
      item("step-2", .assistant, "继续检查配置", turn: 7, start: 1_000, end: 25_200),
      item("final", .assistant, "调查完成，以下是报告", turn: 7, start: 1_000, end: 25_200),
    ]

    let units = NativeConversationTurnProjection.units(from: items)
    #expect(
      units.map(\.id) == [
        "message:user", "message:step-1", "message:step-2", "message:final", "turn-tail:7",
      ])
    #expect(
      units.compactMap(\.copyText) == [
        "请调查", "调查完成，以下是报告",
      ])
    #expect(units.last?.runDuration == 24.2)
  }

  @Test("Incomplete turns expose no assistant copy action")
  func keepsTurnsIndependent() {
    let items = [
      item("user-1", .user, "第一问", turn: 1),
      item("answer-1", .assistant, "第一答", turn: 1, end: 4_000),
      item("user-2", .user, "第二问", turn: 2),
      item("work-2", .assistant, "处理中", turn: 2),
      item("answer-2", .assistant, "第二答", turn: 2),
    ]

    let units = NativeConversationTurnProjection.units(from: items)
    #expect(
      units.map(\.id) == [
        "message:user-1", "message:answer-1", "turn-tail:1",
        "message:user-2", "message:work-2", "message:answer-2",
      ])
    #expect(units.compactMap(\.copyText) == ["第一问", "第一答", "第二问"])
  }

  @Test("Duration labels match the completed upstream turn interval")
  func formatsDuration() {
    let chinese = RabbisirCopy(language: .chinese)
    let english = RabbisirCopy(language: .english)
    #expect(ConversationRunDurationFormatter.string(seconds: 2, copy: chinese) == "耗时 2秒")
    #expect(ConversationRunDurationFormatter.string(seconds: 1_442, copy: chinese) == "耗时 24分2秒")
    #expect(ConversationRunDurationFormatter.string(seconds: 1_442, copy: english) == "24m 2s")
  }

  private func item(
    _ id: String,
    _ kind: NativeConversationItem.Kind,
    _ text: String,
    turn: Int?,
    start: Double? = nil,
    end: Double? = nil
  ) -> NativeConversationItem {
    NativeConversationItem(
      id: id,
      kind: kind,
      text: text,
      turn: turn,
      turnStartedAt: start,
      turnEndedAt: end
    )
  }
}
