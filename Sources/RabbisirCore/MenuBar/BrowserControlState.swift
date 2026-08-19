import Foundation

public enum BrowserControlPhase: Equatable, Sendable {
  case idle
  case active
  case failed(String)

  var title: String {
    switch self {
    case .idle:
      "即将推出"
    case .active:
      "控制进行中"
    case .failed:
      "控制失败"
    }
  }

  var detail: String {
    switch self {
    case .idle:
      "内置浏览器控制即将开放。"
    case .active:
      "用户已发起浏览器控制，控制正在进行。"
    case .failed(let reason):
      "本次浏览器控制明确失败：\(reason)"
    }
  }

  var accessibilityStatus: String {
    switch self {
    case .idle:
      "即将推出"
    case .active:
      "进行中"
    case .failed(let reason):
      "失败，\(reason)"
    }
  }

  func title(copy: RabbisirMenuBarCopy) -> String {
    switch self {
    case .idle: copy.browserIdle
    case .active: copy.browserActive
    case .failed: copy.browserFailed
    }
  }

  func detail(copy: RabbisirMenuBarCopy) -> String {
    switch self {
    case .idle: copy.browserIdleDetail
    case .active: copy.browserActiveDetail
    case .failed(let reason): copy.browserFailureDetail(reason)
    }
  }
}

enum BrowserControlMotion: Equatable {
  case none
  case breathe
  case flash
}

enum BrowserControlPresentation {
  static func motion(
    for phase: BrowserControlPhase,
    reduceMotion: Bool
  ) -> BrowserControlMotion {
    guard !reduceMotion else { return .none }
    switch phase {
    case .idle:
      return .none
    case .active:
      return .breathe
    case .failed:
      return .flash
    }
  }
}

#if DEBUG
  enum BrowserControlDevelopmentPreview {
    static let activeArgument = "--browser-control-preview-active"
    static let failedArgument = "--browser-control-preview-failed"

    @MainActor
    static func apply(arguments: [String], to state: WorkspaceState) {
      if arguments.contains(failedArgument) {
        state.browserControlDidBegin()
        state.browserControlDidFail(reason: "开发验收状态事件")
      } else if arguments.contains(activeArgument) {
        state.browserControlDidBegin()
      }
    }
  }
#endif
