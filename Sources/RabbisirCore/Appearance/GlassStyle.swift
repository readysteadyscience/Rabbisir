import SwiftUI

enum NativePanelContentPalette {
  /// Keeps controls independent from the translucency of the glass behind them.
  static let primary = Color(nsColor: .labelColor)
  static let secondary = Color(nsColor: .labelColor)
}

enum TrailingEdgePanelShapeMetrics {
  static let topLeadingRadius: CGFloat = 20
  static let bottomLeadingRadius: CGFloat = 20
  static let topTrailingRadius: CGFloat = 0
  static let bottomTrailingRadius: CGFloat = 0
}

struct TrailingEdgePanelShape: Shape {
  func path(in rect: CGRect) -> Path {
    let bodyLeft = rect.minX + PanelResizeHandleMetrics.protrusion
    let handleHeight = min(PanelResizeHandleVariant.details.size.height, rect.height * 0.72)
    let handleTop = rect.midY - handleHeight / 2
    let handleBottom = rect.midY + handleHeight / 2
    let handleJoinRadius: CGFloat = 4
    let handleTipRadius: CGFloat = 4
    let topRadius = min(
      TrailingEdgePanelShapeMetrics.topLeadingRadius,
      max(0, rect.maxX - bodyLeft),
      rect.height / 2
    )
    let bottomRadius = min(
      TrailingEdgePanelShapeMetrics.bottomLeadingRadius,
      max(0, rect.maxX - bodyLeft),
      rect.height / 2
    )
    var path = Path()
    path.move(to: CGPoint(x: bodyLeft + topRadius, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
    path.addLine(to: CGPoint(x: bodyLeft + bottomRadius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: bodyLeft, y: rect.maxY - bottomRadius),
      control: CGPoint(x: bodyLeft, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: bodyLeft, y: handleBottom + handleJoinRadius))
    path.addQuadCurve(
      to: CGPoint(x: bodyLeft - handleJoinRadius, y: handleBottom),
      control: CGPoint(x: bodyLeft, y: handleBottom)
    )
    path.addLine(to: CGPoint(x: rect.minX + handleTipRadius, y: handleBottom))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: handleBottom - handleTipRadius),
      control: CGPoint(x: rect.minX, y: handleBottom)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: handleTop + handleTipRadius))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + handleTipRadius, y: handleTop),
      control: CGPoint(x: rect.minX, y: handleTop)
    )
    path.addLine(to: CGPoint(x: bodyLeft - handleJoinRadius, y: handleTop))
    path.addQuadCurve(
      to: CGPoint(x: bodyLeft, y: handleTop - handleJoinRadius),
      control: CGPoint(x: bodyLeft, y: handleTop)
    )
    path.addLine(to: CGPoint(x: bodyLeft, y: rect.minY + topRadius))
    path.addQuadCurve(
      to: CGPoint(x: bodyLeft + topRadius, y: rect.minY),
      control: CGPoint(x: bodyLeft, y: rect.minY)
    )
    path.closeSubpath()
    return path
  }
}

extension View {
  func nativePanelContentForeground() -> some View {
    foregroundStyle(NativePanelContentPalette.primary)
  }

}

struct InputComposerShape: Shape {
  static let outerTopInset: CGFloat = 8
  static let outerBottomInset: CGFloat = 0
  static let tabX: CGFloat = 0
  static let tabRight: CGFloat = 322
  static let mainTop: CGFloat = 25
  static let tabRadius: CGFloat = 14
  static let mainRadius: CGFloat = 22
  static let joinRadius: CGFloat = 9
  static let collapsedSurfaceHeight: CGFloat =
    SpatialWorkspaceLayoutPolicy.inputHeight - outerTopInset - outerBottomInset
  var composerSurfaceHeight: CGFloat = collapsedSurfaceHeight

  static func resizeGripTopOffset(
    containerHeight: CGFloat,
    composerSurfaceHeight: CGFloat
  ) -> CGFloat {
    let surfaceHeight = max(
      0,
      containerHeight - outerTopInset - outerBottomInset
    )
    let handleHeight = min(
      PanelResizeHandleVariant.composer.size.height,
      surfaceHeight * 0.56
    )
    return outerTopInset
      + handleTop(
        surfaceHeight: surfaceHeight,
        composerSurfaceHeight: composerSurfaceHeight,
        handleHeight: handleHeight
      )
  }

  private static func handleTop(
    surfaceHeight: CGFloat,
    composerSurfaceHeight: CGFloat,
    handleHeight: CGFloat
  ) -> CGFloat {
    let expansionHeight = max(0, surfaceHeight - composerSurfaceHeight)
    let mainTop = min(Self.mainTop + expansionHeight, surfaceHeight)
    return min(mainTop, max(0, surfaceHeight - handleHeight))
  }

  func path(in rect: CGRect) -> Path {
    let bodyRight = rect.maxX - PanelResizeHandleMetrics.protrusion
    let handleHeight = min(PanelResizeHandleVariant.composer.size.height, rect.height * 0.56)
    let expansionHeight = max(0, rect.height - composerSurfaceHeight)
    let mainTop = min(Self.mainTop + expansionHeight, rect.maxY)
    let handleTop = Self.handleTop(
      surfaceHeight: rect.height,
      composerSurfaceHeight: composerSurfaceHeight,
      handleHeight: handleHeight
    )
    let handleBottom = handleTop + handleHeight
    let handleJoinRadius: CGFloat = 4
    let handleTipRadius: CGFloat = 4
    let tabX = min(Self.tabX, rect.maxX)
    let tabRight = min(max(tabX + Self.tabRadius * 2, Self.tabRight), bodyRight)
    let handleSharesMainTop = abs(handleTop - mainTop) < 0.5
    let mainRadius = min(Self.mainRadius, rect.width / 2, max(0, rect.height - mainTop) / 2)
    let tabRadius = min(Self.tabRadius, max(0, tabRight - tabX) / 2, rect.height / 2)
    let tabTop = rect.minY
    let joinRadius = min(Self.joinRadius, max(0, tabRight - tabX) / 3, mainTop)
    let rightTopRadius = min(
      mainRadius,
      max(handleTipRadius, handleTop - mainTop - handleJoinRadius)
    )
    let rightBottomRadius = min(
      mainRadius,
      max(handleTipRadius, rect.maxY - handleBottom - handleJoinRadius)
    )

    var path = Path()
    path.move(to: CGPoint(x: tabX + tabRadius, y: tabTop))
    path.addLine(to: CGPoint(x: tabRight - tabRadius, y: tabTop))
    path.addQuadCurve(
      to: CGPoint(x: tabRight, y: tabTop + tabRadius),
      control: CGPoint(x: tabRight, y: tabTop)
    )
    path.addLine(to: CGPoint(x: tabRight, y: mainTop - joinRadius))
    path.addQuadCurve(
      to: CGPoint(x: tabRight + joinRadius, y: mainTop),
      control: CGPoint(x: tabRight, y: mainTop)
    )
    if handleSharesMainTop {
      path.addLine(to: CGPoint(x: rect.maxX - handleTipRadius, y: handleTop))
    } else {
      path.addLine(to: CGPoint(x: bodyRight - rightTopRadius, y: mainTop))
      path.addQuadCurve(
        to: CGPoint(x: bodyRight, y: mainTop + rightTopRadius),
        control: CGPoint(x: bodyRight, y: mainTop)
      )
      path.addLine(to: CGPoint(x: bodyRight, y: handleTop - handleJoinRadius))
      path.addQuadCurve(
        to: CGPoint(x: bodyRight + handleJoinRadius, y: handleTop),
        control: CGPoint(x: bodyRight, y: handleTop)
      )
      path.addLine(to: CGPoint(x: rect.maxX - handleTipRadius, y: handleTop))
    }
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: handleTop + handleTipRadius),
      control: CGPoint(x: rect.maxX, y: handleTop)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: handleBottom - handleTipRadius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - handleTipRadius, y: handleBottom),
      control: CGPoint(x: rect.maxX, y: handleBottom)
    )
    path.addLine(to: CGPoint(x: bodyRight + handleJoinRadius, y: handleBottom))
    path.addQuadCurve(
      to: CGPoint(x: bodyRight, y: handleBottom + handleJoinRadius),
      control: CGPoint(x: bodyRight, y: handleBottom)
    )
    path.addLine(to: CGPoint(x: bodyRight, y: rect.maxY - rightBottomRadius))
    path.addQuadCurve(
      to: CGPoint(x: bodyRight - rightBottomRadius, y: rect.maxY),
      control: CGPoint(x: bodyRight, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX + mainRadius, y: rect.maxY))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX, y: rect.maxY - mainRadius),
      control: CGPoint(x: rect.minX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: tabTop + tabRadius))
    path.addQuadCurve(
      to: CGPoint(x: rect.minX + tabRadius, y: tabTop),
      control: CGPoint(x: rect.minX, y: tabTop)
    )
    path.closeSubpath()
    return path
  }
}

@MainActor
final class ComposerResizeGripVisualState: ObservableObject {
  @Published private(set) var isHovered = false
  @Published private(set) var isActive = false

  func setHovered(_ value: Bool) {
    isHovered = value
  }

  func setActive(_ value: Bool) {
    isActive = value
  }
}

struct ComposerResizeGripDots: View {
  @ObservedObject var state: ComposerResizeGripVisualState
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isPulseRaised = false

  var body: some View {
    ZStack {
      dots
        .opacity(
          PanelResizeHandlePalette.gripOpacity(
            isHovered: state.isHovered,
            isActive: state.isActive
          )
        )

      if !reduceMotion {
        dots
          .opacity(isPulseRaised ? 0.34 : 0.08)
      }
    }
    .frame(
      width: PanelResizeHandleVariant.composer.size.width,
      height: PanelResizeHandleVariant.composer.size.height
    )
    .onAppear {
      updateMotion()
    }
    .onChange(of: reduceMotion) {
      updateMotion()
    }
    .allowsHitTesting(false)
    .accessibilityHidden(true)
  }

  private var dots: some View {
    VStack(spacing: 5) {
      ForEach(0..<3, id: \.self) { _ in
        Circle()
          .fill(Color(nsColor: .labelColor))
          .frame(width: 3, height: 3)
      }
    }
  }

  private func updateMotion() {
    if reduceMotion {
      isPulseRaised = false
      return
    }
    withAnimation(
      .easeInOut(duration: RabbisirMotionToken.handleGripBreath.duration)
        .repeatForever(autoreverses: true)
    ) {
      isPulseRaised = true
    }
  }
}
