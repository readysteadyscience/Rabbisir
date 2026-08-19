import Testing

@testable import RabbisirCore

@Suite("Native conversation row layout")
struct NativeConversationRowLayoutTests {
  @Test("Assistant text uses the complete composer content width")
  func assistantUsesFullWidth() {
    let layout = NativeConversationRowLayout.resolve(kind: .assistant)

    #expect(layout.leadingReserve == 0)
    #expect(layout.trailingReserve == 0)
    #expect(layout.maximumWidthFraction == 1)
    #expect(NativeConversationRowLayout.horizontalContentInset == 18)
    #expect(layout.maximumContentWidth(in: 700) == 700)
    #expect(layout.contentOriginX(containerWidth: 700, contentWidth: 420) == 0)
  }

  @Test("User text hugs the trailing edge and grows left to a fixed maximum")
  func userHugsTrailingEdge() {
    let layout = NativeConversationRowLayout.resolve(kind: .user)

    #expect(layout.leadingReserve == 0)
    #expect(layout.trailingReserve == 0)
    #expect(layout.maximumWidthFraction == 0.82)
    #expect(layout.maximumWidth == 525)
    #expect(layout.hugsVisibleText)
    #expect(layout.maximumContentWidth(in: 700) == 525)
    #expect(abs(layout.maximumContentWidth(in: 480) - 393.6) < 0.001)
    #expect(layout.contentOriginX(containerWidth: 700, contentWidth: 240) == 460)
  }
}
