import AppKit
import CoreGraphics
import Foundation
import SwiftUI
import Testing

@testable import RabbisirCore

@Suite("Native conversation interaction surface")
struct ConversationInteractionSurfaceTests {
  @Test("The native conversation column always receives mouse and scroll input")
  func nativeConversationColumnDoesNotPassThrough() {
    #expect(!ConversationWorkspaceHitPolicy.ignoresMouseEvents)
  }

  @Test("Independent hit islands order only above a visible native workspace")
  func independentWindowLifecycleRequiresEveryVisibilityGate() {
    #expect(
      ConversationInteractionWindowLifecycle.presentation(
        isEnabled: true,
        isWorkspaceVisible: true,
        isParentVisible: true,
        parentWindowNumber: 42
      ) == .aboveParent(windowNumber: 42)
    )
    #expect(
      ConversationInteractionWindowLifecycle.presentation(
        isEnabled: false,
        isWorkspaceVisible: true,
        isParentVisible: true,
        parentWindowNumber: 42
      ) == .hidden
    )
    #expect(
      ConversationInteractionWindowLifecycle.presentation(
        isEnabled: true,
        isWorkspaceVisible: false,
        isParentVisible: true,
        parentWindowNumber: 42
      ) == .hidden
    )
    #expect(
      ConversationInteractionWindowLifecycle.presentation(
        isEnabled: true,
        isWorkspaceVisible: true,
        isParentVisible: false,
        parentWindowNumber: 42
      ) == .hidden
    )
    #expect(
      ConversationInteractionWindowLifecycle.presentation(
        isEnabled: true,
        isWorkspaceVisible: true,
        isParentVisible: true,
        parentWindowNumber: 0
      ) == .hidden
    )
  }

  @Test("The SwiftUI probe uses NSTextView's designated initializer")
  @MainActor
  func probeConstructsWithoutTheUnavailableConveniencePath() {
    let probe = ConversationMessageProbeView(
      id: "message.body",
      text: "visible text",
      appearance: .body,
      interactionSurface: nil
    )

    #expect(probe.string == "visible text")
  }

  @Test("Inline native text remains visible, selectable, and link-aware without detached panels")
  @MainActor
  func inlineTextOwnsInteractionInsideTheConversationWindow() throws {
    let probe = ConversationMessageProbeView(
      id: "message.inline",
      text: "参考 https://example.com/docs",
      appearance: .body,
      interactionSurface: nil
    )

    #expect(probe.isSelectable)
    #expect(probe.textColor != .clear)
    let attributed = try #require(probe.textStorage)
    #expect(
      ConversationLinkDetection.links(in: attributed)
        == [URL(string: "https://example.com/docs")!]
    )
  }

  @Test("A short message reports its visible glyph width instead of filling the row")
  @MainActor
  func shortMessageKeepsIntrinsicWidth() {
    let probe = ConversationMessageProbeView(
      id: "message.short",
      text: "好的",
      appearance: .body,
      interactionSurface: nil
    )

    let size = probe.preferredSize(for: 420)

    #expect(size.width < 80)
    #expect(size.height >= ConversationTextAppearance.body.font.pointSize)
  }

  @Test("A tall message keeps its full measured height above the viewport")
  @MainActor
  func tallMessageDoesNotCompressToViewportHeight() {
    let probe = ConversationMessageProbeView(
      id: "message.long",
      text: Array(repeating: "这一行用于验证长消息不会被压缩。", count: 120).joined(separator: "\n"),
      appearance: .body,
      interactionSurface: nil
    )

    let size = probe.preferredSize(for: 260)

    #expect(size.height > 900)
  }

  @Test("An action probe publishes one clipped accessible hit region and invokes its action")
  @MainActor
  func actionProbePublishesAccessibleHitRegion() throws {
    let surface = ConversationInteractionSurfaceModel()
    var publishedRegions: [ConversationActionRegion] = []
    var actionCount = 0
    surface.onActionRegionsChanged = { publishedRegions = $0 }
    let window = NSWindow(
      contentRect: CGRect(x: 50, y: 50, width: 320, height: 180),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    let root = NSView(frame: CGRect(x: 0, y: 0, width: 320, height: 180))
    window.contentView = root
    let probe = ConversationActionProbeView(
      id: "message.copy",
      accessibilityLabel: "复制此消息",
      accessibilityHelp: "复制这条用户消息的完整可见文本",
      accessibilityIdentifier: "Rabbisir.nativeConversation.copy.message",
      visualState: .success,
      reduceMotion: true,
      interactionSurface: surface
    ) {
      actionCount += 1
    }
    probe.frame = CGRect(x: 24, y: 32, width: 72, height: 24)
    root.addSubview(probe)
    root.layoutSubtreeIfNeeded()

    let region = try #require(publishedRegions.first)
    #expect(region.id == "message.copy")
    #expect(region.accessibilityLabel == "复制此消息")
    #expect(region.accessibilityHelp == "复制这条用户消息的完整可见文本")
    #expect(
      region.accessibilityIdentifier == "Rabbisir.nativeConversation.copy.message"
    )
    #expect(region.visualState == .success)
    #expect(region.reduceMotion)
    #expect(region.visibleFrame.size == probe.frame.size)

    probe.performConversationAction()
    #expect(actionCount == 1)
    probe.detach()
  }

  @Test("The clear action panel owns a real mouse and accessibility button hit target")
  @MainActor
  func actionPanelDoesNotPassThrough() {
    let panel = ConversationActionPanel(
      frame: CGRect(x: 40, y: 40, width: 32, height: 24)
    )
    panel.button.frame = CGRect(x: 0, y: 0, width: 32, height: 24)
    var actionCount = 0
    panel.button.actionHandler = { actionCount += 1 }

    #expect(panel.styleMask.contains(.nonactivatingPanel))
    #expect(panel.canBecomeKey)
    #expect(panel.becomesKeyOnlyIfNeeded)
    #expect(!panel.ignoresMouseEvents)
    #expect(!panel.button.needsPanelToBecomeKey)
    #expect(!panel.button.isTransparent)
    #expect(panel.button.title.isEmpty)
    #expect(
      panel.contentView?.hitTest(CGPoint(x: 16, y: 12)) === panel.button
    )

    panel.button.update(visualState: .success, reduceMotion: true)
    #expect(panel.button.image != nil)
    #expect(panel.button.contentTintColor == .systemGreen)
    panel.button.performClick(nil)
    #expect(actionCount == 1)
    #expect(panel.button.accessibilityPerformPress())
    #expect(actionCount == 2)
  }

  @Test("Only the visible text intersection becomes a hit island")
  func clippingKeepsBlankConversationSpaceOutsideTheIsland() throws {
    let content = CGRect(x: 40, y: 80, width: 220, height: 90)
    let clip = CGRect(x: 0, y: 120, width: 300, height: 200)
    let visible = try #require(
      ConversationHitIslandGeometry.visibleFrame(
        contentFrame: content,
        clipFrame: clip
      )
    )

    #expect(visible == CGRect(x: 40, y: 120, width: 220, height: 50))
    #expect(!visible.contains(CGPoint(x: 20, y: 140)))
    #expect(!visible.contains(CGPoint(x: 100, y: 100)))
  }

  @Test("A fully clipped text block creates no interaction window")
  func offscreenTextDoesNotCreateAnIsland() {
    let visible = ConversationHitIslandGeometry.visibleFrame(
      contentFrame: CGRect(x: 20, y: 20, width: 120, height: 40),
      clipFrame: CGRect(x: 20, y: 100, width: 120, height: 40)
    )

    #expect(visible == nil)
  }

  @Test("HTTP and existing local file references use native link attributes")
  @MainActor
  func messageLinksRemainActionableWithoutReadingRawRuntimePayloads() {
    let localPath = "/tmp/rabbisir-fixture/result.md"
    let attributed = ConversationLinkDetection.attributedString(
      text: "参考 https://example.com/docs 和 `\(localPath)`",
      appearance: .body,
      fileExists: { $0 == localPath }
    )
    let links = Set(ConversationLinkDetection.links(in: attributed))

    #expect(links.contains(URL(string: "https://example.com/docs")!))
    #expect(links.contains(URL(fileURLWithPath: localPath)))
  }

  @Test("A nonexistent local path is plain selectable text")
  @MainActor
  func nonexistentLocalPathIsNotAnOpenableReference() {
    let attributed = ConversationLinkDetection.attributedString(
      text: "`/tmp/rabbisir-fixture/missing.md`",
      appearance: .body,
      fileExists: { _ in false }
    )

    #expect(ConversationLinkDetection.links(in: attributed).isEmpty)
  }

  @Test("Official assistant Markdown keeps block layout and native emphasis")
  @MainActor
  func rendersMarkdownWithoutExposingSourceMarkers() throws {
    let attributed = ConversationLinkDetection.attributedString(
      text: "# 标题\n\n- **条目**\n\n`code`",
      appearance: .body,
      fileExists: { _ in false }
    )

    #expect(attributed.string == "标题\n\n• 条目\n\ncode")
    #expect(!attributed.string.contains("**"))
    let itemRange = (attributed.string as NSString).range(of: "条目")
    let itemFont = try #require(
      attributed.attribute(.font, at: itemRange.location, effectiveRange: nil) as? NSFont)
    #expect(itemFont.fontDescriptor.symbolicTraits.contains(.bold))
    let codeRange = (attributed.string as NSString).range(of: "code")
    let codeFont = try #require(
      attributed.attribute(.font, at: codeRange.location, effectiveRange: nil) as? NSFont)
    #expect(codeFont.fontDescriptor.symbolicTraits.contains(.monoSpace))
  }
}
