import Foundation

enum RabbisirMotionCurve: Equatable, Sendable {
  case easeInOut
  case easeOut
}

struct RabbisirMotionSpec: Equatable, Sendable {
  let duration: TimeInterval
  let curve: RabbisirMotionCurve
}

/// Semantic durations shared by finite Rabbisir interface feedback.
enum RabbisirMotionToken {
  static let sidebarShowHide = RabbisirMotionSpec(duration: 0.35, curve: .easeInOut)
  static let buttonPress = RabbisirMotionSpec(duration: 0.10, curve: .easeOut)
  static let statusFeedback = RabbisirMotionSpec(duration: 0.12, curve: .easeOut)
  static let composerContentResize = RabbisirMotionSpec(duration: 0.16, curve: .easeOut)
  static let conversationDisclosure = RabbisirMotionSpec(duration: 0.22, curve: .easeInOut)
  static let navigationRowHandleReveal = RabbisirMotionSpec(duration: 0.16, curve: .easeOut)
  static let panelWidthReset = RabbisirMotionSpec(duration: 0.35, curve: .easeInOut)
  static let workspaceVisibilityFade = RabbisirMotionSpec(duration: 0.32, curve: .easeInOut)
  static let launchFade = RabbisirMotionSpec(duration: 0.24, curve: .easeOut)
  static let handleGripBreath = RabbisirMotionSpec(duration: 1.15, curve: .easeInOut)
}
