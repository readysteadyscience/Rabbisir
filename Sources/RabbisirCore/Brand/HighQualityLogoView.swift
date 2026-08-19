import AppKit
import SwiftUI

struct HighQualityLogoView: NSViewRepresentable {
  @Environment(\.rabbisirCopy) private var copy
  let image: NSImage
  let readabilityShadow: LaunchReadabilityShadow?

  init(image: NSImage, readabilityShadow: LaunchReadabilityShadow? = nil) {
    self.image = image
    self.readabilityShadow = readabilityShadow
  }

  func makeNSView(context: Context) -> HighQualityLogoNSView {
    HighQualityLogoNSView(
      image: image,
      readabilityShadow: readabilityShadow,
      accessibilityLabel: copy.launch.logo
    )
  }

  func updateNSView(_ nsView: HighQualityLogoNSView, context: Context) {
    nsView.image = image
    nsView.readabilityShadow = readabilityShadow
    nsView.setAccessibilityLabel(copy.launch.logo)
  }
}

final class HighQualityLogoNSView: NSView {
  var image: NSImage {
    didSet {
      needsDisplay = true
    }
  }
  var readabilityShadow: LaunchReadabilityShadow? {
    didSet {
      applyReadabilityShadow()
    }
  }

  init(
    image: NSImage,
    readabilityShadow: LaunchReadabilityShadow? = nil,
    accessibilityLabel: String = RabbisirAppIdentity.displayName
  ) {
    self.image = image
    self.readabilityShadow = readabilityShadow
    super.init(frame: .zero)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layer?.minificationFilter = .trilinear
    layer?.magnificationFilter = .linear
    applyReadabilityShadow()
    setAccessibilityElement(true)
    setAccessibilityRole(.image)
    setAccessibilityLabel(accessibilityLabel)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) is unavailable")
  }

  override var isOpaque: Bool { false }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateContentsScale()
  }

  override func viewDidChangeBackingProperties() {
    super.viewDidChangeBackingProperties()
    updateContentsScale()
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let graphicsContext = NSGraphicsContext.current else { return }

    graphicsContext.imageInterpolation = .high
    graphicsContext.shouldAntialias = true
    graphicsContext.cgContext.interpolationQuality = .high
    graphicsContext.cgContext.setAllowsAntialiasing(true)
    graphicsContext.cgContext.setShouldAntialias(true)
    image.draw(
      in: bounds,
      from: CGRect(origin: .zero, size: image.size),
      operation: .sourceOver,
      fraction: 1,
      respectFlipped: true,
      hints: [.interpolation: NSImageInterpolation.high]
    )
  }

  private func updateContentsScale() {
    layer?.contentsScale = window?.backingScaleFactor ?? 1
  }

  private func applyReadabilityShadow() {
    guard let layer else { return }
    guard let readabilityShadow else {
      layer.shadowOpacity = 0
      layer.shadowPath = nil
      return
    }
    layer.masksToBounds = false
    layer.shadowPath = nil
    layer.shadowColor = readabilityShadow.color.nsColor.cgColor
    layer.shadowOpacity = Float(readabilityShadow.opacity)
    layer.shadowRadius = readabilityShadow.radius
    // AppKit coordinates point upward; the product token's positive Y points down.
    layer.shadowOffset = CGSize(
      width: readabilityShadow.x,
      height: -readabilityShadow.y
    )
  }
}
