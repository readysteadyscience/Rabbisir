import Testing

@testable import RabbisirCore

@Suite("Conversation backdrop layout")
struct ConversationBackdropLayoutTests {
  @Test("An empty conversation owns no contrast backdrop")
  func emptyConversationRetractsToTheBottom() {
    #expect(
      ConversationBackdropLayout.height(
        visibleMessageCount: 0,
        measuredContentHeight: 400,
        viewportHeight: 800
      ) == 0
    )
  }

  @Test("Visible content adds a fixed comfortable top inset")
  func firstMessageStartsBackdropGrowth() {
    #expect(
      ConversationBackdropLayout.height(
        visibleMessageCount: 1,
        measuredContentHeight: 120,
        viewportHeight: 800
      ) == 152
    )
  }

  @Test("Long content never grows beyond the conversation viewport")
  func longConversationStopsAtViewportTop() {
    #expect(
      ConversationBackdropLayout.height(
        visibleMessageCount: 8,
        measuredContentHeight: 1_200,
        viewportHeight: 720
      ) == 720
    )
  }
}
