import AppKit
import QuartzCore

/// Computes deterministic frame samples for a panel resize without scaling cached window content.
enum PanelResizeTransitionPolicy {
  static func frame(
    from start: CGRect,
    to target: CGRect,
    progress: CGFloat,
    curve: RabbisirMotionCurve
  ) -> CGRect {
    let clamped = min(max(progress, 0), 1)
    let eased: CGFloat =
      switch curve {
      case .easeInOut:
        clamped * clamped * (3 - 2 * clamped)
      case .easeOut:
        1 - pow(1 - clamped, 3)
      }
    return CGRect(
      x: start.minX + (target.minX - start.minX) * eased,
      y: start.minY + (target.minY - start.minY) * eased,
      width: start.width + (target.width - start.width) * eased,
      height: start.height + (target.height - start.height) * eased
    )
  }
}

/// Owns one live panel-resize stream so replacement requests continue from the visible frame.
@MainActor
final class PanelResizeTransitionCoordinator {
  private var task: Task<Void, Never>?
  private var generation: UInt64 = 0

  var isTransitioning: Bool { task != nil }

  func cancel() {
    generation &+= 1
    task?.cancel()
    task = nil
  }

  func transition(
    window: NSWindow,
    to targetFrame: CGRect,
    spec: RabbisirMotionSpec,
    policy: MotionAccessibilityPolicy = .current,
    completion: @escaping @MainActor () -> Void
  ) {
    transition(
      windowTargets: [(window, targetFrame)],
      spec: spec,
      policy: policy,
      completion: completion
    )
  }

  func transition(
    windowTargets: [(window: NSWindow, frame: CGRect)],
    spec: RabbisirMotionSpec,
    policy: MotionAccessibilityPolicy = .current,
    completion: @escaping @MainActor () -> Void
  ) {
    cancel()
    let targets = windowTargets.map { target in
      (window: target.window, start: target.window.frame, target: target.frame)
    }
    guard policy.allowsSpatialTransitions, spec.duration > 0 else {
      for target in targets {
        apply(target.target, to: target.window)
      }
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
        for target in targets {
          let frame = PanelResizeTransitionPolicy.frame(
            from: target.start,
            to: target.target,
            progress: progress,
            curve: spec.curve
          )
          apply(frame, to: target.window)
        }
        if progress >= 1 { break }
        try? await Task.sleep(for: .milliseconds(8))
      }
      guard !Task.isCancelled, generation == transitionGeneration else { return }
      for target in targets {
        apply(target.target, to: target.window)
      }
      task = nil
      completion()
    }
  }

  private func apply(_ frame: CGRect, to window: NSWindow) {
    window.setFrame(frame, display: false)
    window.contentView?.needsLayout = true
    window.contentView?.layoutSubtreeIfNeeded()
    window.contentView?.displayIfNeeded()
  }
}
