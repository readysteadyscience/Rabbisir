import AppKit
import QuartzCore

/// Owns one panel transition stream so a replacement continues from the current presentation.
@MainActor
final class PanelTransitionCoordinator {
  private var generation: UInt64 = 0
  private(set) var isTransitioning = false

  func cancel(contentView: NSView? = nil) {
    generation &+= 1
    isTransitioning = false
    if let contentView {
      settlePresentation(of: contentView)
    }
  }

  func transition(
    contentView: NSView,
    to contentFrame: CGRect,
    windowTargets: [(window: NSWindow, frame: CGRect)] = [],
    policy: MotionAccessibilityPolicy = .current,
    completion: @escaping @MainActor () -> Void
  ) {
    precondition(
      PanelTransitionPolicy.isStrictHorizontalTransition(
        from: contentView.frame,
        to: contentFrame
      ),
      "Panel content transitions must preserve Y and size"
    )

    generation &+= 1
    let transitionGeneration = generation
    settlePresentation(of: contentView)
    for target in windowTargets {
      settleFrame(of: target.window)
    }

    guard policy.allowsSpatialTransitions else {
      contentView.frame = contentFrame
      for target in windowTargets {
        target.window.setFrame(target.frame, display: true)
      }
      isTransitioning = false
      completion()
      return
    }

    isTransitioning = true
    let spec = RabbisirMotionToken.sidebarShowHide
    NSAnimationContext.runAnimationGroup { context in
      context.duration = spec.duration
      context.timingFunction = timingFunction(for: spec.curve)
      context.allowsImplicitAnimation = true
      contentView.animator().frame = contentFrame
      for target in windowTargets {
        target.window.animator().setFrame(target.frame, display: true)
      }
    } completionHandler: { [weak self, weak contentView] in
      MainActor.assumeIsolated {
        guard let self,
          let contentView,
          self.generation == transitionGeneration
        else { return }
        contentView.frame = contentFrame
        for target in windowTargets {
          target.window.setFrame(target.frame, display: true)
        }
        self.isTransitioning = false
        completion()
      }
    }
  }

  private func settlePresentation(of view: NSView) {
    guard let layer = view.layer else { return }
    if let presentationFrame = layer.presentation()?.frame {
      view.frame = presentationFrame
    }
    layer.removeAllAnimations()
  }

  private func settleFrame(of window: NSWindow) {
    window.setFrame(window.frame, display: true)
  }

  private func timingFunction(for curve: RabbisirMotionCurve) -> CAMediaTimingFunction {
    switch curve {
    case .easeInOut:
      CAMediaTimingFunction(name: .easeInEaseOut)
    case .easeOut:
      CAMediaTimingFunction(name: .easeOut)
    }
  }
}
