import AppKit

struct MotionAccessibilityPolicy: Equatable, Sendable {
  let reduceMotion: Bool

  var allowsSpatialTransitions: Bool { !reduceMotion }

  @MainActor
  static var current: Self {
    Self(reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion)
  }
}
