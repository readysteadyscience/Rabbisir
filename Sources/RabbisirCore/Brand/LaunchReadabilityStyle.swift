import AppKit
import SwiftUI

enum LaunchReadabilityRole: Equatable, Sendable {
  case lightForeground
  case darkLogo
}

struct LaunchReadabilityShadow: Equatable, Sendable {
  let color: LaunchReadabilityShadowColor
  let opacity: Double
  let radius: CGFloat
  let x: CGFloat
  let y: CGFloat
}

enum LaunchReadabilityShadowColor: Equatable, Sendable {
  case black
  case white

  var swiftUIColor: Color {
    switch self {
    case .black: .black
    case .white: .white
    }
  }

  @MainActor
  var nsColor: NSColor {
    switch self {
    case .black: .black
    case .white: .white
    }
  }
}

/// Centralized contrast treatment for launch content drawn directly over the desktop.
enum LaunchReadabilityStyle {
  static let lightForeground = LaunchReadabilityShadow(
    color: .black,
    opacity: 0.68,
    radius: 1.6,
    x: 0,
    y: 1.25
  )

  static let darkLogo = LaunchReadabilityShadow(
    color: .white,
    opacity: 0.38,
    radius: 5,
    x: 0,
    y: 2.25
  )

  static func shadow(for role: LaunchReadabilityRole) -> LaunchReadabilityShadow {
    switch role {
    case .lightForeground:
      lightForeground
    case .darkLogo:
      darkLogo
    }
  }
}

private struct LaunchReadabilityModifier: ViewModifier {
  let role: LaunchReadabilityRole

  func body(content: Content) -> some View {
    let shadow = LaunchReadabilityStyle.shadow(for: role)
    content.shadow(
      color: shadow.color.swiftUIColor.opacity(shadow.opacity),
      radius: shadow.radius,
      x: shadow.x,
      y: shadow.y
    )
  }
}

extension View {
  func launchReadability(_ role: LaunchReadabilityRole) -> some View {
    modifier(LaunchReadabilityModifier(role: role))
  }
}
