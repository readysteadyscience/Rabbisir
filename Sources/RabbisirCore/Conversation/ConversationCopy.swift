import AppKit
import Foundation

@MainActor
struct ConversationClipboardWriter {
  private let writeAction: @MainActor (String) -> Bool

  init(write: @escaping @MainActor (String) -> Bool) {
    writeAction = write
  }

  @discardableResult
  func write(_ visibleText: String) -> Bool {
    writeAction(visibleText)
  }

  static let system = ConversationClipboardWriter { visibleText in
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    return pasteboard.setString(visibleText, forType: .string)
  }
}

@MainActor
final class ConversationCopyController: ObservableObject {
  @Published private(set) var feedback: ConversationCopyFeedback?

  private let clipboardWriter: ConversationClipboardWriter
  private let feedbackDuration: Duration
  private var feedbackResetTask: Task<Void, Never>?

  init(
    clipboardWriter: ConversationClipboardWriter = .system,
    feedbackDuration: Duration = .seconds(1.5)
  ) {
    self.clipboardWriter = clipboardWriter
    self.feedbackDuration = feedbackDuration
  }

  @discardableResult
  func copyVisibleText(from item: NativeConversationItem) -> Bool {
    guard item.isUserVisible, let copyText = item.copyText else { return false }
    guard clipboardWriter.write(copyText) else {
      showFeedback(.failed, for: item.id)
      return false
    }

    showFeedback(.copied, for: item.id)
    return true
  }

  var copiedMessageID: String? {
    guard feedback?.result == .copied else { return nil }
    return feedback?.messageID
  }

  func visualState(for item: NativeConversationItem) -> ConversationActionVisualState {
    guard feedback?.messageID == item.id else { return .idle }
    return switch feedback?.result {
    case .copied:
      .success
    case .failed:
      .failure
    case nil:
      .idle
    }
  }

  func resetFeedback() {
    feedbackResetTask?.cancel()
    feedbackResetTask = nil
    feedback = nil
  }

  private func showFeedback(_ result: ConversationCopyResult, for messageID: String) {
    feedbackResetTask?.cancel()
    feedback = ConversationCopyFeedback(messageID: messageID, result: result)
    let duration = feedbackDuration
    feedbackResetTask = Task { @MainActor [weak self] in
      do {
        try await Task.sleep(for: duration)
      } catch {
        return
      }
      guard self?.feedback?.messageID == messageID else { return }
      self?.feedback = nil
    }
  }
}

enum ConversationCopyResult: Equatable, Sendable {
  case copied
  case failed
}

struct ConversationCopyFeedback: Equatable, Sendable {
  let messageID: String
  let result: ConversationCopyResult
}

enum ConversationCopyPresentation {
  static func accessibilityLabel(for item: NativeConversationItem) -> String {
    _ = item
    return "复制此消息"
  }

  static func accessibilityHelp(for item: NativeConversationItem) -> String {
    switch item.kind {
    case .user:
      "复制这条用户消息的完整可见文本"
    case .assistant:
      "复制这条 AI 回复的完整可见文本"
    case .turnTail:
      "复制本轮 AI 最终回复的完整可见文本"
    case .image, .tool, .command, .compaction, .notice, .system, .error:
      "复制此消息的完整可见文本"
    }
  }

  static func accessibilityIdentifier(for item: NativeConversationItem) -> String {
    "Rabbisir.nativeConversation.copy.\(item.id)"
  }
}
