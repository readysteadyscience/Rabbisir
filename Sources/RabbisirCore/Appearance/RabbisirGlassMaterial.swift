import Foundation

/// Semantic surfaces that participate in Rabbisir's appearance system.
enum RabbisirGlassSurfaceRole: CaseIterable, Equatable, Sendable {
  case navigation
  case conversation
  case details
  case settings
  case auxiliary
  case interactiveControl
}

/// Resolved material values shared by SwiftUI and AppKit renderers.
struct RabbisirGlassMaterialConfiguration: Equatable, Sendable {
  let isInteractive: Bool
}

/// Resolves semantic surfaces into public Apple glass material values.
///
/// Existing Rabbisir content surfaces deliberately use regular glass. Clear glass can be
/// introduced later only for a specific visually-backed surface whose readability is verified.
enum RabbisirGlassMaterialPolicy {
  static func configuration(
    role: RabbisirGlassSurfaceRole,
    interactive: Bool? = nil
  ) -> RabbisirGlassMaterialConfiguration {
    return RabbisirGlassMaterialConfiguration(
      isInteractive: interactive ?? role.defaultInteractivity
    )
  }
}

extension RabbisirGlassSurfaceRole {
  fileprivate var defaultInteractivity: Bool {
    switch self {
    case .interactiveControl:
      true
    case .navigation, .conversation, .details, .settings, .auxiliary:
      false
    }
  }
}
