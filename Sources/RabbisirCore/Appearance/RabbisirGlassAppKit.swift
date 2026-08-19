import AppKit

/// Hosts content in Apple's native glass without an app-owned tint or backing layer.
@MainActor
private final class RabbisirGlassContainerView: NSView {
  let hostedContentView: NSView
  let nativeGlassView: NSView

  init(contentView: NSView, cornerRadius: CGFloat) {
    hostedContentView = contentView

    if #available(macOS 26.0, *) {
      let glass = NSGlassEffectView()
      glass.cornerRadius = cornerRadius
      glass.style = .regular
      glass.tintColor = nil
      glass.contentView = contentView
      nativeGlassView = glass
    } else {
      let glass = NSVisualEffectView()
      glass.material = .underWindowBackground
      glass.blendingMode = .behindWindow
      glass.state = .active
      glass.wantsLayer = true
      glass.layer?.cornerRadius = cornerRadius
      glass.layer?.masksToBounds = true
      contentView.translatesAutoresizingMaskIntoConstraints = false
      glass.addSubview(contentView)
      NSLayoutConstraint.activate([
        contentView.leadingAnchor.constraint(equalTo: glass.leadingAnchor),
        contentView.trailingAnchor.constraint(equalTo: glass.trailingAnchor),
        contentView.topAnchor.constraint(equalTo: glass.topAnchor),
        contentView.bottomAnchor.constraint(equalTo: glass.bottomAnchor),
      ])
      nativeGlassView = glass
    }

    super.init(frame: .zero)
    nativeGlassView.translatesAutoresizingMaskIntoConstraints = false
    addSubview(nativeGlassView)
    NSLayoutConstraint.activate([
      nativeGlassView.leadingAnchor.constraint(equalTo: leadingAnchor),
      nativeGlassView.trailingAnchor.constraint(equalTo: trailingAnchor),
      nativeGlassView.topAnchor.constraint(equalTo: topAnchor),
      nativeGlassView.bottomAnchor.constraint(equalTo: bottomAnchor),
    ])
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }
}

@MainActor
enum RabbisirGlassAppKitAdapter {
  static func makeEffectGroup(
    contentView: NSView,
    spacing: CGFloat
  ) -> NSView {
    if #available(macOS 26.0, *) {
      let container = NSGlassEffectContainerView()
      container.spacing = spacing
      container.contentView = contentView
      return container
    }
    return contentView
  }

  static func makeContainer(
    contentView: NSView,
    cornerRadius: CGFloat,
    role: RabbisirGlassSurfaceRole,
    resolvedAppearance: NSAppearance? = nil
  ) -> NSView {
    let container = RabbisirGlassContainerView(
      contentView: contentView,
      cornerRadius: cornerRadius
    )
    container.appearance = resolvedAppearance
    return container
  }

  static func contentView(in container: NSView) -> NSView? {
    (container as? RabbisirGlassContainerView)?.hostedContentView
  }

  static func nativeGlassView(in container: NSView) -> NSView? {
    (container as? RabbisirGlassContainerView)?.nativeGlassView
  }
}
