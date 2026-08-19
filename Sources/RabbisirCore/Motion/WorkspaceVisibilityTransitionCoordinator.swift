import AppKit
import QuartzCore

enum WorkspaceVisibilityTransitionPolicy {
  static func opacity(
    from start: CGFloat,
    to target: CGFloat,
    progress: CGFloat,
    curve: RabbisirMotionCurve
  ) -> CGFloat {
    let clamped = min(max(progress, 0), 1)
    let eased: CGFloat =
      switch curve {
      case .easeInOut:
        clamped * clamped * (3 - 2 * clamped)
      case .easeOut:
        1 - pow(1 - clamped, 3)
      }
    return start + (target - start) * eased
  }
}

/// Owns the finite workspace crossfade so replacement requests continue from
/// the currently visible opacity and stale completions cannot hide new UI.
@MainActor
final class WorkspaceVisibilityTransitionCoordinator {
  private var task: Task<Void, Never>?
  private var generation: UInt64 = 0

  func cancel() {
    generation &+= 1
    task?.cancel()
    task = nil
  }

  func transition(
    from start: CGFloat,
    to target: CGFloat,
    spec: RabbisirMotionSpec,
    apply: @escaping @MainActor (CGFloat) -> Void,
    completion: @escaping @MainActor () -> Void
  ) {
    cancel()
    let resolvedStart = min(max(start, 0), 1)
    let resolvedTarget = min(max(target, 0), 1)
    guard spec.duration > 0, abs(resolvedStart - resolvedTarget) > 0.001 else {
      apply(resolvedTarget)
      completion()
      return
    }

    generation &+= 1
    let transitionGeneration = generation
    let startTime = CACurrentMediaTime()
    task = Task { @MainActor [weak self] in
      guard let self else { return }
      while !Task.isCancelled {
        let elapsed = CACurrentMediaTime() - startTime
        let progress = min(1, elapsed / spec.duration)
        apply(
          WorkspaceVisibilityTransitionPolicy.opacity(
            from: resolvedStart,
            to: resolvedTarget,
            progress: progress,
            curve: spec.curve
          )
        )
        if progress >= 1 { break }
        try? await Task.sleep(for: .milliseconds(8))
      }
      guard !Task.isCancelled, generation == transitionGeneration else { return }
      apply(resolvedTarget)
      task = nil
      completion()
    }
  }
}
