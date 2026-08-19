import Testing

@testable import RabbisirCore

@Suite("Rabbisir motion tokens")
struct MotionTokenTests {
  @Test("Sidebar motion uses one smooth non-spring duration")
  func sidebarMotionToken() {
    let token = RabbisirMotionToken.sidebarShowHide

    #expect((0.32...0.38).contains(token.duration))
    #expect(token.curve == .easeInOut)
  }

  @Test("Panel width reset reuses the smooth sidebar timing")
  func panelWidthResetMotionToken() {
    #expect(RabbisirMotionToken.panelWidthReset == RabbisirMotionToken.sidebarShowHide)
  }

  @Test("Complete workspace visibility uses a perceptible finite crossfade")
  func workspaceVisibilityFadeToken() {
    let token = RabbisirMotionToken.workspaceVisibilityFade

    #expect((0.28...0.36).contains(token.duration))
    #expect(token.curve == .easeInOut)
  }

  @Test("Conversation disclosures use one short non-spring layout transition")
  func conversationDisclosureToken() {
    let token = RabbisirMotionToken.conversationDisclosure

    #expect((0.18...0.26).contains(token.duration))
    #expect(token.curve == .easeInOut)
  }

  @Test("Reduced motion disables spatial transitions without changing other preferences")
  func reduceMotionPolicy() {
    #expect(MotionAccessibilityPolicy(reduceMotion: false).allowsSpatialTransitions)
    #expect(!MotionAccessibilityPolicy(reduceMotion: true).allowsSpatialTransitions)
  }
}
