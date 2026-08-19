import AppKit
import CoreGraphics
import QuartzCore
import Testing

@testable import RabbisirCore

@Suite("Native conversation display style")
struct ConversationDisplayStyleTests {
  @Test("Contrast backdrop is faint and reaches full transparency on three outer edges")
  func featheredBackdropHasNoHardTopOrSideEdge() {
    let presentation = ConversationContrastBackdropPresentation.self

    #expect(presentation.baseOpacity > 0)
    #expect(presentation.baseOpacity <= 0.22)
    #expect(presentation.opacity(at: CGPoint(x: 0.5, y: 0)) == 0)
    #expect(presentation.opacity(at: CGPoint(x: 0, y: 0.7)) == 0)
    #expect(presentation.opacity(at: CGPoint(x: 1, y: 0.7)) == 0)
    #expect(
      presentation.opacity(at: CGPoint(x: 0.5, y: 1))
        == presentation.baseOpacity
    )
  }

  @Test("Feather ramps increase smoothly toward the readable center and bottom")
  func featherRampsAreMonotonic() {
    let presentation = ConversationContrastBackdropPresentation.self
    let horizontalSamples = stride(from: 0.0, through: 0.5, by: 0.02).map {
      presentation.opacity(at: CGPoint(x: $0, y: 1))
    }
    let verticalSamples = stride(from: 0.0, through: 1.0, by: 0.04).map {
      presentation.opacity(at: CGPoint(x: 0.5, y: $0))
    }

    #expect(zip(horizontalSamples, horizontalSamples.dropFirst()).allSatisfy(<=))
    #expect(zip(verticalSamples, verticalSamples.dropFirst()).allSatisfy(<=))
  }

  @Test("Conversation palette has white primary text and nonblack semantic colors")
  @MainActor
  func conversationPaletteRemainsReadable() {
    #expect(ConversationDisplayPalette.primaryNSColor == .white)
    #expect(ConversationDisplayPalette.secondaryNSColor.alphaComponent > 0.7)
    #expect(ConversationDisplayPalette.linkNSColor != .black)
    #expect(ConversationTextAppearance.body.color == .white)
    #expect(ConversationActionVisualState.idle.nsColor != .black)
  }

  @Test("Default conversation readability uses one tight dark edge shadow")
  @MainActor
  func defaultReadabilityToken() {
    let style = ConversationReadabilityStyle.resolve(
      preferences: ConversationReadabilityPreferences(
        increaseContrast: false,
        reduceTransparency: false,
        differentiateWithoutColor: false,
        reduceMotion: false
      )
    )

    #expect(style.mode == .obsidianEdge)
    #expect(style.nsColor(for: .primary) == .white)
    #expect(style.nsColor(for: .link) != .black)
    #expect((0.6...0.9).contains(style.tightShadow.radius))
    #expect((0.40...0.52).contains(style.tightShadow.opacity))
    #expect(style.tightShadow.y == 0.5)
  }

  @Test("High contrast and reduced transparency select the hard monochrome token")
  @MainActor
  func accessibilityReadabilityFallback() {
    for preferences in [
      ConversationReadabilityPreferences(
        increaseContrast: true,
        reduceTransparency: false,
        differentiateWithoutColor: false,
        reduceMotion: false
      ),
      ConversationReadabilityPreferences(
        increaseContrast: false,
        reduceTransparency: true,
        differentiateWithoutColor: true,
        reduceMotion: true
      ),
    ] {
      let style = ConversationReadabilityStyle.resolve(preferences: preferences)
      #expect(style.mode == .hardMonochrome)
      #expect(style.nsColor(for: .primary) == .white)
      #expect(style.nsColor(for: .link) == .white)
      #expect(style.tightShadow.radius == 0)
      #expect(style.tightShadow.opacity >= 0.9)
    }
  }

  @Test("Contrast backdrop never owns a pointer hit")
  @MainActor
  func contrastBackdropPassesPointerHitsThrough() {
    let view = ConversationContrastBackdropView(
      frame: CGRect(x: 0, y: 0, width: 692, height: 895)
    )

    #expect(view.hitTest(CGPoint(x: 346, y: 447)) == nil)
  }

  @Test("Layer-backed feather renders as one continuous alpha field")
  @MainActor
  func contrastBackdropRendersWithoutTransparentTiles() throws {
    let pixelWidth = 240
    let pixelHeight = 180
    let view = ConversationContrastBackdropView(
      frame: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight)
    )
    view.layoutSubtreeIfNeeded()
    view.layer?.layoutIfNeeded()

    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixelWidth,
        pixelsHigh: pixelHeight,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    let graphics = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    view.layer?.render(in: graphics.cgContext)

    let middleRow = (0..<pixelWidth).map { x in
      bitmap.colorAt(x: x, y: pixelHeight / 2)?.alphaComponent ?? 0
    }
    let risingHalf = Array(middleRow.prefix(pixelWidth / 2))
    let fallingHalf = Array(middleRow.suffix(pixelWidth / 2))
    let centerAlpha = middleRow[pixelWidth / 2]

    #expect(centerAlpha > 0.15)
    #expect(zip(risingHalf, risingHalf.dropFirst()).allSatisfy { $0 <= $1 + 0.01 })
    #expect(zip(fallingHalf, fallingHalf.dropFirst()).allSatisfy { $0 >= $1 - 0.01 })
    #expect(middleRow.filter { $0 > 0.10 }.count > pixelWidth / 2)
  }
}
