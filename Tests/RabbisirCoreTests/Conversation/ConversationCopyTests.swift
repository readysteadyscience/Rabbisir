import Foundation
import Testing

@testable import RabbisirCore

@Suite("Native conversation copy controls")
struct ConversationCopyTests {
  @Test("Only allow-listed user and assistant visible text reaches the clipboard writer")
  @MainActor
  func copiesOnlyProjectedVisibleText() {
    var writes: [String] = []
    let controller = ConversationCopyController(
      clipboardWriter: ConversationClipboardWriter { text in
        writes.append(text)
        return true
      }
    )
    let user = NativeConversationItem(
      id: "user-1",
      kind: .user,
      text: "用户可见文本",
      detail: "不得复制的内部元数据"
    )
    let assistant = NativeConversationItem(
      id: "assistant-1",
      kind: .assistant,
      text: "第一段\n\n**Markdown 标题**\n- 条目\n`code`",
      detail: "不得复制的 bridge payload"
    )
    let internalItems = [
      NativeConversationItem(id: "system", kind: .system, text: "system prompt"),
      NativeConversationItem(id: "tool", kind: .tool, text: "tool result"),
      NativeConversationItem(id: "error", kind: .error, text: "debug metadata"),
    ]

    #expect(controller.copyVisibleText(from: user))
    #expect(controller.copyVisibleText(from: assistant))
    for item in internalItems {
      #expect(!controller.copyVisibleText(from: item))
    }

    #expect(writes == [user.text, assistant.text])
    #expect(controller.copiedMessageID == assistant.id)
    #expect(controller.visualState(for: assistant) == .success)
    #expect([user, assistant] == ([user, assistant] + internalItems).filter(\.isUserVisible))
  }

  @Test("Repeated copies preserve exact complete text and update feedback to the latest row")
  @MainActor
  func repeatedCopiesAreExact() {
    var writes: [String] = []
    let controller = ConversationCopyController(
      clipboardWriter: ConversationClipboardWriter { text in
        writes.append(text)
        return true
      }
    )
    let user = NativeConversationItem(id: "user", kind: .user, text: "同一条用户消息")
    let assistant = NativeConversationItem(
      id: "assistant",
      kind: .assistant,
      text: "多段回复\n\n第二段，含 [链接](https://example.com)。"
    )

    #expect(controller.copyVisibleText(from: user))
    #expect(controller.copyVisibleText(from: assistant))
    #expect(controller.copyVisibleText(from: user))

    #expect(writes == [user.text, assistant.text, user.text])
    #expect(controller.copiedMessageID == user.id)
  }

  @Test("Clipboard failures never report copied feedback")
  @MainActor
  func failedWriteHasNoSuccessFeedback() {
    let clipboard = MutableClipboardResult()
    let controller = ConversationCopyController(
      clipboardWriter: ConversationClipboardWriter { clipboard.write($0) }
    )
    let item = NativeConversationItem(id: "assistant", kind: .assistant, text: "visible")

    #expect(controller.copyVisibleText(from: item))
    #expect(controller.copiedMessageID == item.id)
    clipboard.shouldSucceed = false
    #expect(!controller.copyVisibleText(from: item))
    #expect(controller.copiedMessageID == nil)
    #expect(controller.visualState(for: item) == .failure)
  }

  @Test("Copied feedback is temporary")
  @MainActor
  func copiedFeedbackExpires() async throws {
    let controller = ConversationCopyController(
      clipboardWriter: ConversationClipboardWriter { _ in true },
      feedbackDuration: .milliseconds(20)
    )
    let item = NativeConversationItem(id: "assistant", kind: .assistant, text: "visible")

    #expect(controller.copyVisibleText(from: item))
    #expect(controller.visualState(for: item) == .success)
    await Task.yield()
    try await Task.sleep(for: .milliseconds(300))
    #expect(controller.visualState(for: item) == .idle)
  }

  @Test("Copy controls expose stable role-specific accessibility metadata")
  func copyAccessibilityMetadata() {
    let user = NativeConversationItem(id: "user-7", kind: .user, text: "hello")
    let assistant = NativeConversationItem(id: "assistant-9", kind: .assistant, text: "hi")

    #expect(
      ConversationCopyPresentation.accessibilityIdentifier(for: user)
        == "Rabbisir.nativeConversation.copy.user-7"
    )
    #expect(
      ConversationCopyPresentation.accessibilityLabel(for: user) == "复制此消息"
    )
    #expect(
      ConversationCopyPresentation.accessibilityLabel(for: assistant) == "复制此消息"
    )
    #expect(
      ConversationCopyPresentation.accessibilityHelp(for: user)
        == "复制这条用户消息的完整可见文本"
    )
    #expect(
      ConversationCopyPresentation.accessibilityHelp(for: assistant)
        == "复制这条 AI 回复的完整可见文本"
    )
    let copy = RabbisirCopy(language: .chinese)
    #expect(ConversationActionVisualState.idle.accessibilityValue(copy: copy) == "可复制")
    #expect(ConversationActionVisualState.success.accessibilityValue(copy: copy) == "已复制")
    #expect(ConversationActionVisualState.failure.accessibilityValue(copy: copy) == "复制失败")
  }
}

@MainActor
private final class MutableClipboardResult {
  var shouldSucceed = true

  func write(_ text: String) -> Bool {
    _ = text
    return shouldSucceed
  }
}
