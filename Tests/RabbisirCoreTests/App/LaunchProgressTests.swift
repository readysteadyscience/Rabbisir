import AppKit
import Testing

@testable import RabbisirCore

@Suite("Rabbisir launch progress")
struct LaunchProgressTests {
  @Test("Launch contrast uses one tight lower shadow per semantic role")
  func launchReadabilityUsesCentralizedSingleShadows() {
    let foreground = LaunchReadabilityStyle.shadow(for: .lightForeground)
    let logo = LaunchReadabilityStyle.shadow(for: .darkLogo)

    #expect(foreground == LaunchReadabilityStyle.lightForeground)
    #expect(foreground.opacity > 0.5)
    #expect(foreground.opacity < 0.75)
    #expect(foreground.radius <= 2)
    #expect(foreground.x == 0)
    #expect(foreground.y > 0)

    #expect(logo == LaunchReadabilityStyle.darkLogo)
    #expect(logo.opacity < 0.5)
    #expect(logo.radius >= 4)
    #expect(logo.radius <= 6)
    #expect(logo.x == 0)
    #expect(logo.y > 0)
  }

  @Test("Logo glow follows every alpha edge instead of an outer shadow path")
  @MainActor
  func logoGlowUsesTheCompleteAlphaMask() throws {
    let image = try RabbisirBrandAssets.loadLogo()
    let logoView = HighQualityLogoNSView(
      image: image,
      readabilityShadow: LaunchReadabilityStyle.darkLogo
    )
    let layer = try #require(logoView.layer)

    #expect(layer.shadowPath == nil)
    #expect(layer.shadowOpacity == Float(LaunchReadabilityStyle.darkLogo.opacity))
    #expect(layer.shadowRadius == LaunchReadabilityStyle.darkLogo.radius)
    #expect(layer.shadowOffset.width == 0)
    #expect(layer.shadowOffset.height == -LaunchReadabilityStyle.darkLogo.y)
    #expect(!layer.masksToBounds)
  }

  @Test("Observable launch phases advance with completed initialization work")
  @MainActor
  func launchPhasesAdvanceMonotonically() {
    let model = LaunchProgressModel()

    #expect(model.phase == .loadingBrandAsset)
    #expect(model.progress == 0.08)

    model.brandAssetDidLoad(NSImage(size: NSSize(width: 16, height: 16)))
    #expect(model.phase == .brandAssetReady)
    #expect(model.progress == 0.28)

    model.workspaceDidPrepare()
    #expect(model.phase == .workspaceReady)
    #expect(model.progress == 0.58)

    model.runtimeDidBecomeReady()
    #expect(model.phase == .runtimeReady)
    #expect(model.progress == 0.88)

    model.complete()
    #expect(model.phase == .completed)
    #expect(model.progress == 1)
  }

  @Test("A failed stage exposes diagnostics and can restart without fake progress")
  @MainActor
  func failureCanRetryFromTheOwningStage() {
    let model = LaunchProgressModel()
    model.fail(message: "diagnostic")

    #expect(model.canRetry)
    #expect(model.failureMessage == "diagnostic")
    model.workspaceDidPrepare()
    #expect(model.phase == .loadingBrandAsset)

    model.restartAssetLoading()
    #expect(!model.canRetry)
    #expect(model.phase == .loadingBrandAsset)
  }

  @Test("The packaged user-owned logo is present and decodable")
  @MainActor
  func packagedLogoLoads() throws {
    let image = try RabbisirBrandAssets.loadLogo()
    let sourcePixelWidth =
      image.representations
      .map(\.pixelsWide)
      .max() ?? 0
    let sourcePixelHeight =
      image.representations
      .map(\.pixelsHigh)
      .max() ?? 0
    let imageData = try #require(image.tiffRepresentation)
    let bitmap = try #require(NSBitmapImageRep(data: imageData))

    #expect(RabbisirBrandAssets.logoURL != nil)
    #expect(image.isValid)
    #expect(image.size.width > 0)
    #expect(image.size.height > 0)
    #expect(sourcePixelWidth == 1_342)
    #expect(sourcePixelHeight == 1_887)
    for backingScale in [1.0, 2.0] {
      #expect(
        CGFloat(sourcePixelWidth)
          >= LaunchContentPlacement.logoDisplaySize.width * backingScale
      )
      #expect(
        CGFloat(sourcePixelHeight)
          >= LaunchContentPlacement.logoDisplaySize.height * backingScale
      )
    }

    let leftEdgeHasArtwork = (0..<bitmap.pixelsHigh).contains {
      bitmap.colorAt(x: 0, y: $0)?.alphaComponent ?? 0 > 0.01
    }
    let rightEdgeHasArtwork = (0..<bitmap.pixelsHigh).contains {
      bitmap.colorAt(x: bitmap.pixelsWide - 1, y: $0)?.alphaComponent ?? 0 > 0.01
    }
    let bottomEdgeHasArtwork = (0..<bitmap.pixelsWide).contains {
      bitmap.colorAt(x: $0, y: 0)?.alphaComponent ?? 0 > 0.01
    }
    let topEdgeHasArtwork = (0..<bitmap.pixelsWide).contains {
      bitmap.colorAt(x: $0, y: bitmap.pixelsHigh - 1)?.alphaComponent ?? 0 > 0.01
    }
    #expect(leftEdgeHasArtwork)
    #expect(rightEdgeHasArtwork)
    #expect(bottomEdgeHasArtwork)
    #expect(topEdgeHasArtwork)
  }

  @Test("The light and dark macOS app icons are packaged and decodable")
  @MainActor
  func packagedAppIconLoads() throws {
    for appearance in RabbisirAppIconAppearance.allCases {
      let image = try RabbisirBrandAssets.loadAppIcon(for: appearance)

      #expect(RabbisirBrandAssets.appIconURL(for: appearance)?.pathExtension == "icns")
      #expect(image.isValid)
      #expect(
        image.representations.contains { representation in
          representation.pixelsWide == 1_024 && representation.pixelsHigh == 1_024
        })
    }
  }

  @Test("App icon variants keep the authorized mark and inverse neutral tiles")
  @MainActor
  func appIconVariantsUseInverseNeutralColors() throws {
    let light = try rasterize(RabbisirBrandAssets.loadAppIcon(for: .light))
    let dark = try rasterize(RabbisirBrandAssets.loadAppIcon(for: .dark))
    let lightBackground = try #require(light.colorAt(x: 150, y: 512))
    let darkBackground = try #require(dark.colorAt(x: 150, y: 512))
    let lightMark = try #require(light.colorAt(x: 512, y: 512))
    let darkMark = try #require(dark.colorAt(x: 512, y: 512))

    #expect(lightBackground.brightnessComponent > 0.85)
    #expect(lightBackground.brightnessComponent < 1)
    #expect(darkBackground.brightnessComponent > 0)
    #expect(darkBackground.brightnessComponent < 0.2)
    #expect(lightMark.brightnessComponent < 0.1)
    #expect(darkMark.brightnessComponent > 0.9)
  }

  @Test("App icon appearance follows the effective system appearance")
  func appIconAppearanceFollowsSystem() throws {
    let light = try #require(NSAppearance(named: .aqua))
    let dark = try #require(NSAppearance(named: .darkAqua))

    #expect(RabbisirAppIconAppearance.resolve(light) == .light)
    #expect(RabbisirAppIconAppearance.resolve(dark) == .dark)
  }

  @MainActor
  private func rasterize(_ image: NSImage) throws -> NSBitmapImageRep {
    let bitmap = try #require(
      NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: 1_024,
        pixelsHigh: 1_024,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
      )
    )
    let context = try #require(NSGraphicsContext(bitmapImageRep: bitmap))
    let previous = NSGraphicsContext.current
    NSGraphicsContext.current = context
    image.draw(
      in: CGRect(x: 0, y: 0, width: 1_024, height: 1_024),
      from: .zero,
      operation: .copy,
      fraction: 1
    )
    context.flushGraphics()
    NSGraphicsContext.current = previous
    return bitmap
  }

  @Test("Visible native identity uses Rabbisir with factual upstream attribution")
  func rabbisirIdentityIsDistinct() {
    #expect(RabbisirAppIdentity.displayName == "Rabbisir")
    #expect(RabbisirAppIdentity.upstreamAttribution == "Built on DeepSeek Harness")
    #expect(RabbisirAppIdentity.coreAttribution == "Core follows DeepSeek Harness")
  }

  @Test("The complete launch group is centered in the primary visible frame")
  func completeLaunchGroupUsesVisibleFrameCenter() {
    let visibleFrame = CGRect(x: 0, y: 0, width: 3_840, height: 1_050)
    let frame = LaunchPanelPlacement.frame(
      contentSize: CGSize(width: 760, height: 460),
      in: visibleFrame
    )

    #expect(frame.midX == visibleFrame.midX)
    #expect(frame.midY == visibleFrame.midY)
    #expect(visibleFrame.contains(frame))
  }

  @Test("Brand and progress rows keep the same center as brand width changes")
  func launchRowsShareOneHorizontalAnchor() {
    let containerWidth: CGFloat = 760
    let progressFrame = LaunchContentPlacement.centeredFrame(
      contentSize: CGSize(width: 420, height: 4),
      in: containerWidth
    )

    for brandWidth in [418.0, 568.0, 640.0] {
      let brandFrame = LaunchContentPlacement.centeredFrame(
        contentSize: CGSize(width: brandWidth, height: 240),
        in: containerWidth
      )

      #expect(brandFrame.midX == progressFrame.midX)
      #expect(brandFrame.midX == containerWidth / 2)
    }

    #expect(LaunchContentPlacement.brandSpacing == 16)
    #expect(LaunchContentPlacement.logoDisplaySize.width == 125.8125)
    #expect(LaunchContentPlacement.logoDisplaySize.height == 176.90625)
    #expect(LaunchContentPlacement.titleOpticalLeadingCorrection == -4)
  }

  @Test("Preview presentation is fixed and does not reuse live progress")
  func previewPresentationUsesAnExplicitStaticSample() {
    let preview = LaunchPresentationMode.preview

    #expect(preview.displayedProgress(liveProgress: 0.08) == 0.58)
    #expect(preview.displayedProgress(liveProgress: 1) == 0.58)
    #expect(preview.displayedStatus(liveStatus: "live") == "启动页预览 · 固定进度")
  }

  @Test("Live presentation continues to reflect observable initialization")
  func livePresentationUsesTheProgressModel() {
    let live = LaunchPresentationMode.live

    #expect(live.displayedProgress(liveProgress: 0.28) == 0.28)
    #expect(live.displayedStatus(liveStatus: "资源已就绪") == "资源已就绪")
  }

  @Test("Preview route requires the explicit development argument")
  func previewRouteIsNeverTheDefault() {
    #expect(ApplicationLaunchRoute.resolve(arguments: ["Rabbisir"]) == .live)
    #expect(
      ApplicationLaunchRoute.resolve(arguments: ["Rabbisir", "--preview-details"])
        == .live
    )
    #expect(
      ApplicationLaunchRoute.resolve(arguments: ["Rabbisir", "--launch-preview"])
        == .preview
    )
  }
}
