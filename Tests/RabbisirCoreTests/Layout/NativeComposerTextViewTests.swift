import AppKit
import SwiftUI
import Testing

@testable import RabbisirCore

@Suite("Native composer text hit surface")
struct NativeComposerTextViewTests {
  @Test("An empty editor clamps a blank-area click to the insertion origin")
  func emptyEditorSelectionIsClamped() {
    #expect(
      ComposerTextSelectionPolicy.clamped(
        NSRange(location: 1, length: 0),
        utf16Length: 0
      ) == NSRange(location: 0, length: 0)
    )
  }

  @Test("Selection clamping preserves valid ranges and bounds invalid ranges")
  func selectionClampingPreservesDocumentBounds() {
    #expect(
      ComposerTextSelectionPolicy.clamped(
        NSRange(location: 2, length: 2),
        utf16Length: 5
      ) == NSRange(location: 2, length: 2)
    )
    #expect(
      ComposerTextSelectionPolicy.clamped(
        NSRange(location: 4, length: 8),
        utf16Length: 5
      ) == NSRange(location: 4, length: 1)
    )
    #expect(
      ComposerTextSelectionPolicy.clamped(
        NSRange(location: NSNotFound, length: 0),
        utf16Length: 5
      ) == NSRange(location: 5, length: 0)
    )
  }

  @Test("The interactive composer panel can activate the app on first click")
  @MainActor
  func interactivePanelCanBecomeMainAndKey() {
    let panel = SpatialPanel(
      frame: CGRect(x: 0, y: 0, width: 400, height: 120), acceptsKeyWindow: true)

    #expect(panel.canBecomeKey)
    #expect(panel.canBecomeMain)
    #expect(!panel.becomesKeyOnlyIfNeeded)
    #expect(!panel.ignoresMouseEvents)
  }

  @Test("The editor owns the complete text viewport width")
  @MainActor
  func editorFillsViewportAndReceivesBlankAreaHits() throws {
    let scrollView = ComposerTextView.scrollableTextView()
    scrollView.frame = CGRect(x: 0, y: 0, width: 640, height: 96)
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    let editor = try #require(scrollView.documentView as? ComposerTextView)
    editor.frame = CGRect(x: 0, y: 0, width: scrollView.contentSize.width, height: 96)

    scrollView.layoutSubtreeIfNeeded()

    #expect(abs(editor.frame.width - scrollView.contentSize.width) < 0.5)
    for x in [CGFloat(4), scrollView.contentSize.width / 2, scrollView.contentSize.width - 4] {
      let point = editor.convert(CGPoint(x: x, y: 48), to: scrollView)
      #expect(scrollView.hitTest(point) === editor)
    }
  }

  @Test("The editor hit surface uses only a sub-visible alpha fill")
  @MainActor
  func editorHitSurfaceRemainsVisuallyTransparent() {
    let color = ComposerTextHitSurfaceStyle.backgroundColor.usingColorSpace(.deviceRGB)

    #expect(color != nil)
    #expect((color?.alphaComponent ?? 1) <= 1 / 255)
  }

  @Test("The placeholder uses the system secondary placeholder foreground")
  func placeholderIsVisuallySecondary() {
    #expect(ComposerPlaceholderStyle.foregroundColor == .placeholderTextColor)
  }

  @Test("Only the editor layer contributes the transparent hit surface")
  @MainActor
  func editorLayerOwnsTheHitSurface() {
    let scrollView = NSScrollView()
    let editor = NSView()
    ComposerTextHitSurfaceStyle.install(in: scrollView, editor: editor)

    #expect(!scrollView.drawsBackground)
    #expect(!scrollView.contentView.drawsBackground)
    #expect(editor.wantsLayer)
    #expect(editor.layer?.backgroundColor == ComposerTextHitSurfaceStyle.backgroundColor.cgColor)
  }

  @Test("The panel container routes the complete editor rectangle to AppKit")
  @MainActor
  func panelContainerRoutesBlankEditorArea() {
    let container = SpatialPanelContentContainer(rootView: AnyView(EmptyView()))
    container.frame = CGRect(x: 0, y: 0, width: 640, height: 120)
    container.layoutSubtreeIfNeeded()
    let editor = ComposerTextView(frame: CGRect(x: 18, y: 30, width: 604, height: 48))
    container.slidingContentView.addSubview(editor)

    #expect(container.hitTest(CGPoint(x: 24, y: 54)) === editor)
    #expect(container.hitTest(CGPoint(x: 320, y: 54)) === editor)
    #expect(container.hitTest(CGPoint(x: 616, y: 54)) === editor)
  }

  @Test("The complete input panel blocks mouse passthrough outside controls")
  @MainActor
  func panelContainerOwnsBlankPanelArea() {
    let container = SpatialPanelContentContainer(rootView: AnyView(EmptyView()))
    container.frame = CGRect(x: 0, y: 0, width: 640, height: 120)
    container.layoutSubtreeIfNeeded()

    #expect(container.acceptsFirstMouse(for: nil))
    #expect(container.hitTest(CGPoint(x: 12, y: 12)) != nil)
    #expect(container.hitTest(CGPoint(x: 628, y: 108)) != nil)
  }

  @Test("The editor and viewport accept the first click")
  @MainActor
  func firstClickIsAccepted() {
    #expect(ComposerTextView().acceptsFirstMouse(for: nil))
  }
}
