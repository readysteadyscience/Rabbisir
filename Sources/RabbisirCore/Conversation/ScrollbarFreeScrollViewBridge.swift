import AppKit
import SwiftUI

@MainActor
final class ScrollbarFreeScrollViewState: ObservableObject {
  @Published private(set) var overflowVisibility = NativeNavigationOverflowVisibility(
    hasHiddenAbove: false,
    hasHiddenBelow: false
  )

  func update(from scrollView: NSScrollView) {
    guard let documentView = scrollView.documentView else { return }
    let visibleBounds = scrollView.contentView.bounds
    let documentBounds = documentView.bounds
    let scrollableDistance = max(0, documentBounds.height - visibleBounds.height)
    guard scrollableDistance > 1 else {
      publish(NativeNavigationOverflowVisibility(hasHiddenAbove: false, hasHiddenBelow: false))
      return
    }

    let distanceFromTop: CGFloat
    if documentView.isFlipped {
      distanceFromTop = visibleBounds.minY - documentBounds.minY
    } else {
      distanceFromTop = documentBounds.maxY - visibleBounds.maxY
    }
    let clampedDistanceFromTop = min(max(0, distanceFromTop), scrollableDistance)
    publish(
      NativeNavigationOverflowVisibility(
        hasHiddenAbove: clampedDistanceFromTop > 1,
        hasHiddenBelow: clampedDistanceFromTop < scrollableDistance - 1
      )
    )
  }

  private func publish(_ visibility: NativeNavigationOverflowVisibility) {
    guard overflowVisibility != visibility else { return }
    overflowVisibility = visibility
  }
}

/// Keeps a SwiftUI-backed scroll view wheel-scrollable without installing scrollers.
@MainActor
enum ScrollbarFreeScrollViewPolicy {
  /// Removes both scrollers so AppKit cannot draw or reserve space for them.
  ///
  /// - Parameter scrollView: The AppKit scroll view that owns the SwiftUI content.
  static func apply(to scrollView: NSScrollView) {
    scrollView.scrollerStyle = .overlay
    scrollView.hasVerticalScroller = false
    scrollView.hasHorizontalScroller = false
    scrollView.autohidesScrollers = true
  }
}

/// Applies `ScrollbarFreeScrollViewPolicy` to the nearest enclosing SwiftUI scroll view.
struct ScrollbarFreeScrollViewBridge: NSViewRepresentable {
  let state: ScrollbarFreeScrollViewState

  func makeNSView(context: Context) -> ScrollbarConfigurationView {
    let view = ScrollbarConfigurationView()
    view.wantsLayer = true
    view.layer?.backgroundColor = NSColor.clear.cgColor
    view.state = state
    return view
  }

  func updateNSView(_ nsView: ScrollbarConfigurationView, context: Context) {
    nsView.state = state
    nsView.applyConfiguration()
  }
}

final class ScrollbarConfigurationView: NSView {
  weak var state: ScrollbarFreeScrollViewState?
  private weak var observedScrollView: NSScrollView?

  deinit {
    NotificationCenter.default.removeObserver(self)
  }

  override func hitTest(_ point: NSPoint) -> NSView? {
    bounds.contains(point) ? self : nil
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func scrollWheel(with event: NSEvent) {
    guard let scrollView = enclosingScrollView else {
      super.scrollWheel(with: event)
      return
    }
    scrollView.scrollWheel(with: event)
  }

  override func viewDidMoveToSuperview() {
    super.viewDidMoveToSuperview()
    scheduleConfiguration()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    scheduleConfiguration()
  }

  override func layout() {
    super.layout()
    applyConfiguration()
  }

  func applyConfiguration() {
    guard let scrollView = enclosingScrollView else { return }
    ScrollbarFreeScrollViewPolicy.apply(to: scrollView)
    observe(scrollView)
    scheduleMetricsUpdate()
  }

  private func scheduleConfiguration() {
    Task { @MainActor [weak self] in
      self?.applyConfiguration()
    }
  }

  private func observe(_ scrollView: NSScrollView) {
    guard observedScrollView !== scrollView else { return }
    NotificationCenter.default.removeObserver(self)
    observedScrollView = scrollView
    scrollView.contentView.postsBoundsChangedNotifications = true
    scrollView.documentView?.postsFrameChangedNotifications = true
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(scrollGeometryDidChange),
      name: NSView.boundsDidChangeNotification,
      object: scrollView.contentView
    )
    if let documentView = scrollView.documentView {
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(scrollGeometryDidChange),
        name: NSView.frameDidChangeNotification,
        object: documentView
      )
    }
  }

  @objc private func scrollGeometryDidChange() {
    scheduleMetricsUpdate()
  }

  private func scheduleMetricsUpdate() {
    Task { @MainActor [weak self] in
      guard let self, let observedScrollView else { return }
      state?.update(from: observedScrollView)
    }
  }
}
