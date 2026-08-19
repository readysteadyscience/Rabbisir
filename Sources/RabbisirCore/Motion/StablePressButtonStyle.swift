import SwiftUI

/// Provides press feedback without changing a control's geometry or baseline.
struct RabbisirStablePressButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .contentShape(Rectangle())
  }
}
