import AppKit
import Testing

@testable import RabbisirCore

@Suite("Scrollbar-free navigation scrolling")
struct ScrollbarFreeScrollViewBridgeTests {
  @Test("Policy removes scrollers without narrowing the document viewport")
  @MainActor
  func removesScrollersWithoutLayoutReservation() {
    let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 360, height: 480))
    scrollView.scrollerStyle = .legacy
    scrollView.hasVerticalScroller = true
    scrollView.hasHorizontalScroller = true
    scrollView.documentView = NSView(frame: CGRect(x: 0, y: 0, width: 360, height: 1_200))

    ScrollbarFreeScrollViewPolicy.apply(to: scrollView)
    scrollView.tile()

    #expect(!scrollView.hasVerticalScroller)
    #expect(!scrollView.hasHorizontalScroller)
    #expect(scrollView.scrollerStyle == .overlay)
    #expect(scrollView.contentView.frame.width == scrollView.bounds.width)
  }

  @Test("A scroller-free view remains programmatically scrollable")
  @MainActor
  func preservesScrolling() {
    let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 360, height: 480))
    scrollView.documentView = NSView(frame: CGRect(x: 0, y: 0, width: 360, height: 1_200))
    ScrollbarFreeScrollViewPolicy.apply(to: scrollView)

    scrollView.contentView.scroll(to: CGPoint(x: 0, y: 320))
    scrollView.reflectScrolledClipView(scrollView.contentView)

    #expect(scrollView.contentView.bounds.origin.y == 320)
  }

  @Test("Transparent navigation gaps remain wheel-scroll hit targets")
  @MainActor
  func transparentGapsRemainHitTargets() {
    let bridge = ScrollbarConfigurationView(frame: CGRect(x: 0, y: 0, width: 264, height: 480))
    bridge.wantsLayer = true
    bridge.layer?.backgroundColor = NSColor.clear.cgColor

    #expect(bridge.hitTest(CGPoint(x: 132, y: 240)) === bridge)
    #expect(bridge.hitTest(CGPoint(x: -1, y: 240)) == nil)
    #expect(bridge.layer?.backgroundColor?.alpha == 0)
  }

  @Test("Overflow state follows the actual scroll position and clears at both boundaries")
  @MainActor
  func overflowStateTracksBoundaries() {
    let scrollView = NSScrollView(frame: CGRect(x: 0, y: 0, width: 360, height: 480))
    let documentView = FlippedTestDocumentView(
      frame: CGRect(x: 0, y: 0, width: 360, height: 1_400)
    )
    scrollView.documentView = documentView
    let state = ScrollbarFreeScrollViewState()

    scrollView.contentView.scroll(to: CGPoint(x: 0, y: 0))
    state.update(from: scrollView)
    #expect(
      state.overflowVisibility
        == NativeNavigationOverflowVisibility(hasHiddenAbove: false, hasHiddenBelow: true)
    )

    scrollView.contentView.scroll(to: CGPoint(x: 0, y: 420))
    state.update(from: scrollView)
    #expect(
      state.overflowVisibility
        == NativeNavigationOverflowVisibility(hasHiddenAbove: true, hasHiddenBelow: true)
    )

    scrollView.contentView.scroll(to: CGPoint(x: 0, y: 920))
    state.update(from: scrollView)
    #expect(
      state.overflowVisibility
        == NativeNavigationOverflowVisibility(hasHiddenAbove: true, hasHiddenBelow: false)
    )
  }
}

private final class FlippedTestDocumentView: NSView {
  override var isFlipped: Bool { true }
}
