import SwiftUI

private struct RabbisirGlassSurfaceModifier<SurfaceShape: Shape>: ViewModifier {
  let role: RabbisirGlassSurfaceRole
  let shape: SurfaceShape
  let interactive: Bool?
  let clipsToShape: Bool

  func body(content: Content) -> some View {
    let configuration = RabbisirGlassMaterialPolicy.configuration(
      role: role,
      interactive: interactive
    )
    resolvedBody(content: content, configuration: configuration)
  }

  @ViewBuilder
  private func resolvedBody(
    content: Content,
    configuration: RabbisirGlassMaterialConfiguration
  ) -> some View {
    if #available(macOS 26.0, *) {
      let glass =
        configuration.isInteractive
        ? Glass.regular.interactive()
        : Glass.regular
      if clipsToShape {
        content
          .glassEffect(glass, in: shape)
          .clipShape(shape)
      } else {
        content
          .glassEffect(glass, in: shape)
      }
    } else {
      content
        .background(.ultraThinMaterial, in: shape)
        .modifier(RabbisirConditionalClipModifier(shape: shape, clips: clipsToShape))
    }
  }
}

/// Gives every independently hosted Rabbisir panel one shared application activation state.
struct RabbisirApplicationActiveRoot<Content: View>: View {
  @ObservedObject private var activity: RabbisirApplicationActivity
  private let content: Content

  init(
    activity: RabbisirApplicationActivity = .shared,
    @ViewBuilder content: () -> Content
  ) {
    self.activity = activity
    self.content = content()
  }

  var body: some View {
    content.environment(\.appearsActive, activity.appearsActive)
  }
}

private struct RabbisirConditionalClipModifier<SurfaceShape: Shape>: ViewModifier {
  let shape: SurfaceShape
  let clips: Bool

  @ViewBuilder
  func body(content: Content) -> some View {
    if clips {
      content.clipShape(shape)
    } else {
      content
    }
  }
}

extension View {
  /// Applies the selected Rabbisir skin to a semantic surface.
  func rabbisirGlassSurface<SurfaceShape: Shape>(
    _ shape: SurfaceShape,
    role: RabbisirGlassSurfaceRole,
    interactive: Bool? = nil,
    clipsToShape: Bool = true
  ) -> some View {
    modifier(
      RabbisirGlassSurfaceModifier(
        role: role,
        shape: shape,
        interactive: interactive,
        clipsToShape: clipsToShape
      )
    )
  }

  func rabbisirMainPanelGlass<SurfaceShape: Shape>(
    _ shape: SurfaceShape,
    role: RabbisirGlassSurfaceRole,
    clipsToShape: Bool = true
  ) -> some View {
    rabbisirGlassSurface(
      shape,
      role: role,
      clipsToShape: clipsToShape
    )
  }

  func rabbisirGlassSurface(cornerRadius: CGFloat, interactive: Bool = false) -> some View {
    rabbisirGlassSurface(
      RoundedRectangle(cornerRadius: cornerRadius),
      role: interactive ? .interactiveControl : .auxiliary,
      interactive: interactive
    )
  }

  func rabbisirGlassSurface<SurfaceShape: Shape>(
    _ shape: SurfaceShape,
    interactive: Bool = false
  ) -> some View {
    rabbisirGlassSurface(
      shape,
      role: interactive ? .interactiveControl : .auxiliary,
      interactive: interactive
    )
  }

  func rabbisirGlassSurfaceAllowingOverflow<SurfaceShape: Shape>(
    _ shape: SurfaceShape,
    interactive: Bool = false
  ) -> some View {
    rabbisirGlassSurface(
      shape,
      role: interactive ? .interactiveControl : .auxiliary,
      interactive: interactive,
      clipsToShape: false
    )
  }
}
