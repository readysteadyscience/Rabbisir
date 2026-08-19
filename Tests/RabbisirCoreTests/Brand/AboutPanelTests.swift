import AppKit
import CoreGraphics
import CryptoKit
import Testing

@testable import RabbisirCore

@Suite("Rabbisir About presentation")
struct RabbisirAboutPresentationTests {
  @Test("About uses the shared semantic typography roles for localized text")
  func aboutUsesSharedLocalizedTypography() {
    #expect(RabbisirAboutTypography.metadata == .caption)
    #expect(RabbisirAboutTypography.attribution == .callout)
    #expect(RabbisirAboutTypography.supporting == .caption)
    #expect(RabbisirAboutTypography.action == .headline)
    #expect(RabbisirAboutTypography.footer == .caption)
  }

  @Test("About packages the authorized creator avatar and official community mark")
  @MainActor
  func aboutPackagesAuthorizedOriginalAssets() throws {
    #expect(RabbisirAboutDestination.developer.asset?.name == "YelZapAvatar")
    #expect(RabbisirAboutDestination.developer.asset?.extension == "png")
    #expect(RabbisirAboutDestination.upstream.asset == nil)
    #expect(RabbisirAboutDestination.community.asset?.name == "DiscordSymbolColor")
    #expect(RabbisirAboutDestination.community.asset?.extension == "svg")

    let avatarURL = try #require(
      RabbisirBrandAssets.aboutImageURL(named: "YelZapAvatar", extension: "png")
    )
    let avatarData = try Data(contentsOf: avatarURL)
    #expect(
      SHA256.hash(data: avatarData).hexString
        == "4d30bc3ccdc9b646a4ee4e3a230f00b855b07b04f2011dec81290a3fe27d395d"
    )
    let avatar = try RabbisirBrandAssets.loadAboutImage(
      named: "YelZapAvatar",
      extension: "png"
    )
    #expect(avatar.isValid)
    #expect(avatar.size == CGSize(width: 460, height: 460))
    #expect(!avatar.isTemplate)

    let discordURL = try #require(
      RabbisirBrandAssets.aboutImageURL(named: "DiscordSymbolColor", extension: "svg")
    )
    let discordData = try Data(contentsOf: discordURL)
    #expect(
      SHA256.hash(data: discordData).hexString
        == "296286aa112c4400af8e96191ab888f81abd4bd1d5dc7294112a622ef43581b1"
    )
    #expect(String(decoding: discordData, as: UTF8.self).contains("fill=\"#5865F2\""))
    let discord = try RabbisirBrandAssets.loadAboutImage(
      named: "DiscordSymbolColor",
      extension: "svg"
    )
    #expect(discord.isValid)
    #expect(!discord.isTemplate)
  }

  @Test("About uses native adaptive glass instead of a fixed light background")
  @MainActor
  func aboutUsesNativeAdaptiveGlass() throws {
    let content = NSView()
    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 460, height: 470),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    RabbisirAboutMaterialPolicy.configure(panel)
    let container = RabbisirAboutMaterialPolicy.makeContainer(contentView: content)

    #expect(!panel.isOpaque)
    #expect(panel.backgroundColor.alphaComponent == 0)
    #expect(!panel.hasShadow)

    if #available(macOS 26.0, *) {
      let glass = try #require(
        RabbisirGlassAppKitAdapter.nativeGlassView(in: container) as? NSGlassEffectView
      )
      #expect(RabbisirGlassAppKitAdapter.contentView(in: container) === content)
      #expect(glass.cornerRadius == RabbisirAboutMaterialPolicy.cornerRadius)
      #expect(glass.style == .regular)
      #expect(glass.tintColor == nil)
      #expect(container.subviews == [glass])
    } else {
      #expect(RabbisirGlassAppKitAdapter.nativeGlassView(in: container) is NSVisualEffectView)
    }
  }

  @Test("About exposes both factual upstream attribution lines")
  func aboutIncludesCompleteAttribution() {
    let english = RabbisirAboutContent.resolve(
      copy: RabbisirCopy(language: .english),
      bundleVersion: RabbisirBundleVersion(shortVersion: "1.2.3", buildVersion: "45")
    )
    let chinese = RabbisirAboutContent.resolve(
      copy: RabbisirCopy(language: .chinese),
      bundleVersion: RabbisirBundleVersion(shortVersion: "1.2.3", buildVersion: "45")
    )

    #expect(
      english.attributions == [
        "Built on DeepSeek Harness",
        "Core follows DeepSeek Harness",
      ])
    #expect(english.accessibilityLabel.contains("Built on DeepSeek Harness"))
    #expect(english.accessibilityLabel.contains("Core follows DeepSeek Harness"))
    #expect(
      chinese.attributions == [
        "基于 DeepSeek Harness",
        "核心持续跟随 DeepSeek Harness。",
      ])
    #expect(chinese.accessibilityLabel.contains("基于 DeepSeek Harness"))
    #expect(chinese.accessibilityLabel.contains("核心持续跟随 DeepSeek Harness。"))
  }

  @Test("About uses three concise localized repository, upstream, and community links")
  func aboutDestinationsAreCompactAndLocalized() {
    let chinese = RabbisirCopy(language: .chinese)
    let english = RabbisirCopy(language: .english)

    #expect(RabbisirAboutDestination.allCases.count == 3)
    #expect(RabbisirAboutDestination.developer.title(copy: chinese) == "YelZap")
    #expect(RabbisirAboutDestination.developer.title(copy: english) == "YelZap")
    #expect(
      RabbisirAboutDestination.developer.url.absoluteString
        == "https://github.com/readysteadyscience/Rabbisir"
    )

    #expect(RabbisirAboutDestination.upstream.title(copy: chinese) == "上游")
    #expect(RabbisirAboutDestination.upstream.title(copy: english) == "Upstream")
    #expect(
      RabbisirAboutDestination.upstream.url.absoluteString
        == "https://github.com/deepseek-ai/deepseek-harness"
    )

    #expect(RabbisirAboutDestination.community.title(copy: chinese) == "社区")
    #expect(RabbisirAboutDestination.community.title(copy: english) == "Community")
    #expect(
      RabbisirAboutDestination.community.url.absoluteString
        == "https://discord.gg/gT4TUHGkQm"
    )
  }

  @Test("About localizes its version line and standard copyright footer")
  func aboutMetadataIsLocalized() {
    let version = RabbisirBundleVersion(shortVersion: "1.2.3", buildVersion: "45")
    let chinese = RabbisirAboutContent.resolve(
      copy: RabbisirCopy(language: .chinese),
      bundleVersion: version
    )
    let english = RabbisirAboutContent.resolve(
      copy: RabbisirCopy(language: .english),
      bundleVersion: version
    )

    #expect(chinese.versionText == "版本 1.2.3 · 构建 45")
    #expect(english.versionText == "Version 1.2.3 · Build 45")
    #expect(chinese.copyrightText == "版权所有 © 2026 YelZap。保留所有权利。")
    #expect(english.copyrightText == "Copyright © 2026 YelZap. All rights reserved.")
  }

  @Test("About exposes a localized website button backed by the current real repository")
  func aboutWebsiteUsesCurrentRepository() {
    let chinese = RabbisirAboutWebsite.resolve(copy: RabbisirCopy(language: .chinese))
    let english = RabbisirAboutWebsite.resolve(copy: RabbisirCopy(language: .english))

    #expect(chinese.title == "进入官网")
    #expect(english.title == "Visit Website")
    #expect(chinese.url.absoluteString == "https://github.com/readysteadyscience/Rabbisir")
    #expect(english.url == chinese.url)
  }

  @Test("DEV badge overlays the title without changing its layout footprint")
  func developmentBadgeDoesNotResizeBrandTitle() {
    let titleSize = CGSize(width: 284, height: 92)
    let badgeSize = CGSize(width: 54, height: 19)
    let geometry = RabbisirBrandTitleGeometry.resolve(
      titleSize: titleSize,
      badgeSize: badgeSize
    )

    #expect(geometry.layoutSize == titleSize)
    #expect(geometry.titleFrame == CGRect(origin: .zero, size: titleSize))
    #expect(geometry.badgeFrame.minX == titleSize.width - 2)
    #expect(geometry.badgeFrame.maxY == 4)
  }

  @Test("DEV and Open are badges while the brand title never contains a version")
  func nonProductionIdentitiesUseBadgesInsteadOfVersions() {
    let development = RabbisirBrandTitleContent.resolve(identity: .development)
    let open = RabbisirBrandTitleContent.resolve(displayName: RabbisirOpenIdentity.displayName)
    let production = RabbisirBrandTitleContent.resolve(identity: .production)

    #expect(development.title == "Rabbisir")
    #expect(development.badge == "DEV")
    #expect(!development.title.contains(RabbisirVersion.displayVersion))
    #expect(open.title == "Rabbisir")
    #expect(open.badge == "OPEN")
    #expect(production.title == "Rabbisir")
    #expect(production.badge == nil)
  }

  @Test("Workspace title keeps the product name independent from version metadata")
  func workspaceTitleExcludesVersion() {
    #expect(RabbisirWindowTitle.main(displayName: "Rabbisir") == "Rabbisir")
    #expect(RabbisirWindowTitle.main(displayName: "Rabbisir DEV") == "Rabbisir DEV")
    #expect(RabbisirWindowTitle.main(displayName: "Rabbisir Open") == "Rabbisir Open")
  }
}

extension Digest {
  fileprivate var hexString: String {
    map { String(format: "%02x", $0) }.joined()
  }
}
