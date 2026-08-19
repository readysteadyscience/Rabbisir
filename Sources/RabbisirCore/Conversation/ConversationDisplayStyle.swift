import AppKit
import QuartzCore
import SwiftUI

enum ConversationReadabilityMode: Equatable, Sendable {
  case obsidianEdge
  case hardMonochrome
}

struct ConversationReadabilityPreferences: Equatable, Sendable {
  let increaseContrast: Bool
  let reduceTransparency: Bool
  let differentiateWithoutColor: Bool
  let reduceMotion: Bool

  @MainActor
  static var currentAppKit: Self {
    let workspace = NSWorkspace.shared
    return Self(
      increaseContrast: workspace.accessibilityDisplayShouldIncreaseContrast,
      reduceTransparency: workspace.accessibilityDisplayShouldReduceTransparency,
      differentiateWithoutColor: workspace.accessibilityDisplayShouldDifferentiateWithoutColor,
      reduceMotion: workspace.accessibilityDisplayShouldReduceMotion
    )
  }
}

struct ConversationTightShadow: Equatable, Sendable {
  let opacity: Double
  let radius: CGFloat
  let x: CGFloat
  let y: CGFloat

  @MainActor
  var nsShadow: NSShadow {
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(opacity)
    shadow.shadowBlurRadius = radius
    // AppKit text coordinates point upward; the product token's positive Y points down.
    shadow.shadowOffset = NSSize(width: x, height: -y)
    return shadow
  }
}

enum ConversationReadabilityTone: Equatable, Sendable {
  case primary
  case secondary
  case tertiary
  case link
  case success
  case failure
}

/// One source of truth for foreground and edge contrast over arbitrary desktop imagery.
@MainActor
struct ConversationReadabilityStyle {
  let mode: ConversationReadabilityMode
  let tightShadow: ConversationTightShadow
  let differentiateWithoutColor: Bool
  let reduceMotion: Bool

  static var currentAppKit: Self {
    resolve(preferences: .currentAppKit)
  }

  static func resolve(preferences: ConversationReadabilityPreferences) -> Self {
    let mode: ConversationReadabilityMode =
      preferences.increaseContrast || preferences.reduceTransparency
      ? .hardMonochrome
      : .obsidianEdge
    let shadow =
      switch mode {
      case .obsidianEdge:
        ConversationTightShadow(opacity: 0.48, radius: 0.8, x: 0, y: 0.5)
      case .hardMonochrome:
        ConversationTightShadow(opacity: 0.94, radius: 0, x: 0, y: 1)
      }
    return Self(
      mode: mode,
      tightShadow: shadow,
      differentiateWithoutColor: preferences.differentiateWithoutColor,
      reduceMotion: preferences.reduceMotion
    )
  }

  func nsColor(for tone: ConversationReadabilityTone) -> NSColor {
    if mode == .hardMonochrome {
      return switch tone {
      case .primary, .link, .success, .failure:
        .white
      case .secondary:
        NSColor.white.withAlphaComponent(0.86)
      case .tertiary:
        NSColor.white.withAlphaComponent(0.72)
      }
    }
    return switch tone {
    case .primary:
      .white
    case .secondary:
      NSColor.white.withAlphaComponent(0.82)
    case .tertiary:
      NSColor.white.withAlphaComponent(0.68)
    case .link:
      NSColor(calibratedRed: 0.48, green: 0.82, blue: 1, alpha: 1)
    case .success:
      .systemGreen
    case .failure:
      .systemRed
    }
  }

  func color(for tone: ConversationReadabilityTone) -> Color {
    Color(nsColor: nsColor(for: tone))
  }
}

enum ConversationDisplayPalette {
  @MainActor static var primaryNSColor: NSColor {
    ConversationReadabilityStyle.currentAppKit.nsColor(for: .primary)
  }
  @MainActor static var secondaryNSColor: NSColor {
    ConversationReadabilityStyle.currentAppKit.nsColor(for: .secondary)
  }
  @MainActor static var tertiaryNSColor: NSColor {
    ConversationReadabilityStyle.currentAppKit.nsColor(for: .tertiary)
  }
  @MainActor static var linkNSColor: NSColor {
    ConversationReadabilityStyle.currentAppKit.nsColor(for: .link)
  }

  @MainActor static var primaryColor: Color { Color(nsColor: primaryNSColor) }
  @MainActor static var secondaryColor: Color { Color(nsColor: secondaryNSColor) }
  @MainActor static var tertiaryColor: Color { Color(nsColor: tertiaryNSColor) }
}

private struct ConversationReadabilityModifier: ViewModifier {
  let tone: ConversationReadabilityTone
  @Environment(\.colorSchemeContrast) private var colorSchemeContrast
  @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
  @Environment(\.accessibilityDifferentiateWithoutColor) private var differentiateWithoutColor
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    let style = ConversationReadabilityStyle.resolve(
      preferences: ConversationReadabilityPreferences(
        increaseContrast: colorSchemeContrast == .increased,
        reduceTransparency: reduceTransparency,
        differentiateWithoutColor: differentiateWithoutColor,
        reduceMotion: reduceMotion
      )
    )
    content
      .foregroundStyle(style.color(for: tone))
      .shadow(
        color: .black.opacity(style.tightShadow.opacity),
        radius: style.tightShadow.radius,
        x: style.tightShadow.x,
        y: style.tightShadow.y
      )
  }
}

extension View {
  func conversationReadability(_ tone: ConversationReadabilityTone) -> some View {
    modifier(ConversationReadabilityModifier(tone: tone))
  }
}

enum ConversationContrastBackdropPresentation {
  static let baseOpacity: CGFloat = 0.20
  static let sideFeatherFraction: CGFloat = 0.18
  static let topFeatherFraction: CGFloat = 0.30

  static func opacity(at unitPoint: CGPoint) -> CGFloat {
    let x = min(max(unitPoint.x, 0), 1)
    let y = min(max(unitPoint.y, 0), 1)
    let horizontal = min(
      1,
      min(x / sideFeatherFraction, (1 - x) / sideFeatherFraction)
    )
    let vertical = min(1, y / topFeatherFraction)
    return baseOpacity * max(0, horizontal) * max(0, vertical)
  }
}

struct ConversationContrastBackdrop: NSViewRepresentable {
  func makeNSView(context: Context) -> ConversationContrastBackdropView {
    ConversationContrastBackdropView()
  }

  func updateNSView(_ view: ConversationContrastBackdropView, context: Context) {
    view.needsLayout = true
  }
}

final class ConversationContrastBackdropView: NSView {
  private let verticalContainer = CALayer()
  private let fillLayer = CALayer()
  private let horizontalMask = CAGradientLayer()
  private let verticalMask = CAGradientLayer()

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    configureLayerTree()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override var isOpaque: Bool { false }

  override func hitTest(_ point: NSPoint) -> NSView? {
    nil
  }

  override func layout() {
    super.layout()
    layoutLayerTree()
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    updateContentsScale()
  }

  private func configureLayerTree() {
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    layerContentsRedrawPolicy = .onSetNeedsDisplay

    let disabledActions: [String: CAAction] = [
      "bounds": NSNull(),
      "frame": NSNull(),
      "position": NSNull(),
      "opacity": NSNull(),
    ]
    for layer in [verticalContainer, fillLayer, horizontalMask, verticalMask] {
      layer.actions = disabledActions
    }

    fillLayer.backgroundColor = NSColor.black.cgColor
    fillLayer.opacity = Float(ConversationContrastBackdropPresentation.baseOpacity)

    horizontalMask.type = .axial
    horizontalMask.startPoint = CGPoint(x: 0, y: 0.5)
    horizontalMask.endPoint = CGPoint(x: 1, y: 0.5)
    horizontalMask.colors = [
      NSColor.clear.cgColor,
      NSColor.white.cgColor,
      NSColor.white.cgColor,
      NSColor.clear.cgColor,
    ]
    horizontalMask.locations = [
      0,
      NSNumber(value: ConversationContrastBackdropPresentation.sideFeatherFraction),
      NSNumber(value: 1 - ConversationContrastBackdropPresentation.sideFeatherFraction),
      1,
    ]

    verticalMask.type = .axial
    verticalMask.startPoint = CGPoint(x: 0.5, y: 1)
    verticalMask.endPoint = CGPoint(x: 0.5, y: 0)
    verticalMask.colors = [
      NSColor.clear.cgColor,
      NSColor.white.cgColor,
      NSColor.white.cgColor,
    ]
    verticalMask.locations = [
      0,
      NSNumber(value: ConversationContrastBackdropPresentation.topFeatherFraction),
      1,
    ]

    fillLayer.mask = horizontalMask
    verticalContainer.mask = verticalMask
    verticalContainer.addSublayer(fillLayer)
    layer?.addSublayer(verticalContainer)
    layoutLayerTree()
  }

  private func layoutLayerTree() {
    CATransaction.begin()
    CATransaction.setDisableActions(true)
    verticalContainer.frame = bounds
    fillLayer.frame = verticalContainer.bounds
    horizontalMask.frame = fillLayer.bounds
    verticalMask.frame = verticalContainer.bounds
    CATransaction.commit()
    updateContentsScale()
  }

  private func updateContentsScale() {
    let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    verticalContainer.contentsScale = scale
    fillLayer.contentsScale = scale
    horizontalMask.contentsScale = scale
    verticalMask.contentsScale = scale
  }
}
