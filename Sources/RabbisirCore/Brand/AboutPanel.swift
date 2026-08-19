import AppKit
import Combine
import SwiftUI

enum RabbisirAboutTypography {
  static let metadata: RabbisirTypographyRole = .caption
  static let attribution: RabbisirTypographyRole = .callout
  static let supporting: RabbisirTypographyRole = .caption
  static let action: RabbisirTypographyRole = .headline
  static let footer: RabbisirTypographyRole = .caption
}

struct RabbisirAboutContent: Equatable, Sendable {
  let versionText: String
  let attributions: [String]
  let copyrightText: String
  let accessibilityLabel: String

  static func resolve(copy: RabbisirCopy, bundleVersion: RabbisirBundleVersion) -> Self {
    let versionText = copy.aboutVersion(
      shortVersion: bundleVersion.shortVersion,
      buildVersion: bundleVersion.buildVersion
    )
    let copyrightText = copy.aboutCopyright
    let attributions = copy.aboutAttributions
    return Self(
      versionText: versionText,
      attributions: attributions,
      copyrightText: copyrightText,
      accessibilityLabel: copy.aboutAccessibility(
        version: versionText,
        attributions: attributions,
        copyrightText: copyrightText
      )
    )
  }
}

struct RabbisirAboutWebsite: Equatable, Sendable {
  let title: String
  let url: URL

  static func resolve(copy: RabbisirCopy) -> Self {
    Self(
      title: copy.language == .chinese ? "进入官网" : "Visit Website",
      url: URL(string: "https://github.com/readysteadyscience/Rabbisir")!
    )
  }
}

enum RabbisirAboutDestination: CaseIterable, Sendable {
  case developer
  case upstream
  case community

  func title(copy: RabbisirCopy) -> String {
    switch (copy.language, self) {
    case (_, .developer): "YelZap"
    case (.chinese, .upstream): "上游"
    case (.english, .upstream): "Upstream"
    case (.chinese, .community): "社区"
    case (.english, .community): "Community"
    }
  }

  var url: URL {
    switch self {
    case .developer: URL(string: "https://github.com/readysteadyscience/Rabbisir")!
    case .upstream: URL(string: "https://github.com/deepseek-ai/deepseek-harness")!
    case .community: URL(string: "https://discord.gg/gT4TUHGkQm")!
    }
  }

  var asset: (name: String, extension: String)? {
    switch self {
    case .developer: ("YelZapAvatar", "png")
    case .upstream: nil
    case .community: ("DiscordSymbolColor", "svg")
    }
  }

  var systemSymbol: String {
    switch self {
    case .developer: "person.crop.circle"
    case .upstream: "arrow.up.right.circle"
    case .community: "bubble.left.and.bubble.right.fill"
    }
  }
}

struct RabbisirBrandTitleGeometry: Equatable, Sendable {
  let layoutSize: CGSize
  let titleFrame: CGRect
  let badgeFrame: CGRect

  static func resolve(titleSize: CGSize, badgeSize: CGSize) -> Self {
    Self(
      layoutSize: titleSize,
      titleFrame: CGRect(origin: .zero, size: titleSize),
      badgeFrame: CGRect(
        x: titleSize.width - 2,
        y: 4 - badgeSize.height,
        width: badgeSize.width,
        height: badgeSize.height
      )
    )
  }

  static func badgeOffset(badgeSize: CGSize) -> CGSize {
    CGSize(width: badgeSize.width - 2, height: 4 - badgeSize.height)
  }
}

enum RabbisirWindowTitle {
  static func main(displayName: String) -> String {
    displayName
  }
}

struct RabbisirBrandTitleContent: Equatable, Sendable {
  let title: String
  let badge: String?

  static var current: Self {
    resolve(displayName: RabbisirAppIdentity.displayName)
  }

  static func resolve(displayName: String) -> Self {
    switch displayName {
    case RabbisirOpenIdentity.displayName:
      Self(title: RabbisirLaunchIdentity.production.displayName, badge: "OPEN")
    case RabbisirLaunchIdentity.development.displayName:
      resolve(identity: .development)
    default:
      resolve(identity: .production)
    }
  }

  static func resolve(identity: RabbisirLaunchIdentity) -> Self {
    switch identity {
    case .production:
      Self(title: RabbisirLaunchIdentity.production.displayName, badge: nil)
    case .development:
      Self(title: RabbisirLaunchIdentity.production.displayName, badge: "DEV")
    }
  }
}

struct RabbisirBrandTitleView: View {
  let content: RabbisirBrandTitleContent
  let font: Font
  let color: Color

  private var badgeSize: CGSize {
    CGSize(width: max(44, CGFloat(content.badge?.count ?? 0) * 6 + 14), height: 19)
  }

  var body: some View {
    Text(content.title)
      .font(font)
      .foregroundStyle(color)
      .overlay(alignment: .topTrailing) {
        if let badge = content.badge {
          Text(badge)
            .font(.system(size: 9.5, weight: .semibold, design: .rounded))
            .foregroundStyle(color.opacity(0.82))
            .frame(width: badgeSize.width, height: badgeSize.height)
            .overlay {
              Capsule()
                .stroke(color.opacity(0.58), lineWidth: 0.8)
            }
            .offset(
              RabbisirBrandTitleGeometry.badgeOffset(badgeSize: badgeSize)
            )
            .accessibilityLabel(badge)
        }
      }
  }
}

struct RabbisirBundleVersion: Equatable, Sendable {
  let shortVersion: String
  let buildVersion: String

  static var current: Self {
    resolve(infoDictionary: Bundle.main.infoDictionary)
  }

  static func resolve(infoDictionary: [String: Any]?) -> Self {
    let shortVersion = infoDictionary?["CFBundleShortVersionString"] as? String
    let buildVersion = infoDictionary?["CFBundleVersion"] as? String
    return Self(
      shortVersion: shortVersion?.isEmpty == false
        ? shortVersion!
        : RabbisirVersion.appleShortVersion,
      buildVersion: buildVersion?.isEmpty == false
        ? buildVersion!
        : RabbisirVersion.appleBuildVersion
    )
  }

  var displayText: String {
    "Version \(shortVersion) · Build \(buildVersion)"
  }
}

@MainActor
private final class RabbisirAboutPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }

  override func sendEvent(_ event: NSEvent) {
    if event.type == .keyDown && event.keyCode == 53 {
      orderOut(nil)
      return
    }
    super.sendEvent(event)
  }

  override func cancelOperation(_ sender: Any?) {
    orderOut(sender)
  }
}

@MainActor
enum RabbisirAboutMaterialPolicy {
  static let cornerRadius: CGFloat = 28

  static func configure(_ panel: NSPanel) {
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
  }

  static func makeContainer(
    contentView: NSView
  ) -> NSView {
    RabbisirGlassAppKitAdapter.makeContainer(
      contentView: contentView,
      cornerRadius: cornerRadius,
      role: .auxiliary
    )
  }
}

@MainActor
final class AboutPanelCoordinator: NSObject, NSWindowDelegate {
  private let panel: RabbisirAboutPanel
  private var languageSubscription: AnyCancellable?

  init(
    bundleVersion: RabbisirBundleVersion = .current
  ) throws {
    let size = CGSize(width: 460, height: 470)
    let panel = RabbisirAboutPanel(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    let logo = try RabbisirBrandAssets.loadLogo()
    let destinationImages: [RabbisirAboutDestination: NSImage] = try Dictionary(
      uniqueKeysWithValues: RabbisirAboutDestination.allCases.compactMap {
        destination -> (RabbisirAboutDestination, NSImage)? in
        guard let asset = destination.asset else { return nil }
        return (
          destination,
          try RabbisirBrandAssets.loadAboutImage(
            named: asset.name,
            extension: asset.extension
          )
        )
      }
    )
    let hostingView = NSHostingView(
      rootView: RabbisirLocalizedRoot {
        RabbisirAboutView(
          logo: logo,
          bundleVersion: bundleVersion,
          destinationImages: destinationImages
        )
      }
    )

    self.panel = panel
    super.init()

    panel.identifier = NSUserInterfaceItemIdentifier("Rabbisir.about")
    updatePanelCopy(language: RabbisirLocalization.shared.language)
    panel.isMovableByWindowBackground = true
    RabbisirAboutMaterialPolicy.configure(panel)
    panel.level = .normal
    panel.collectionBehavior = [.moveToActiveSpace, .transient]
    panel.isReleasedWhenClosed = false
    panel.delegate = self
    let materialContainer = RabbisirAboutMaterialPolicy.makeContainer(
      contentView: hostingView
    )
    panel.contentView = materialContainer
    panel.setContentSize(size)
    languageSubscription = RabbisirLocalization.shared.$language
      .removeDuplicates()
      .sink { [weak self] language in
        self?.updatePanelCopy(language: language)
      }
  }

  func show(on requestedScreen: NSScreen? = nil) {
    guard let screen = requestedScreen ?? RabbisirPrimaryScreen.current else { return }
    let frame = RabbisirWindowPlacement.frame(
      currentFrame: panel.frame,
      minimumSize: panel.minSize,
      sourceVisibleFrame: nil,
      targetVisibleFrame: screen.visibleFrame
    )
    panel.setFrame(frame, display: true)
    NSApp.activate(ignoringOtherApps: true)
    panel.makeKeyAndOrderFront(nil)
  }

  func move(to screen: NSScreen) {
    RabbisirWindowMover.move(panel, to: screen)
  }

  var isVisible: Bool { panel.isVisible }

  private func updatePanelCopy(language: RabbisirInterfaceLanguage) {
    let title = RabbisirCopy(language: language)[.about]
    panel.title = title
    panel.setAccessibilityLabel(title)
  }
}

private struct RabbisirAboutView: View {
  @Environment(\.rabbisirCopy) private var copy
  @Environment(\.colorScheme) private var colorScheme
  let logo: NSImage
  let bundleVersion: RabbisirBundleVersion
  let destinationImages: [RabbisirAboutDestination: NSImage]

  private var content: RabbisirAboutContent {
    RabbisirAboutContent.resolve(copy: copy, bundleVersion: bundleVersion)
  }

  private var website: RabbisirAboutWebsite {
    RabbisirAboutWebsite.resolve(copy: copy)
  }

  var body: some View {
    VStack(spacing: 0) {
      Spacer(minLength: 20)

      Group {
        if colorScheme == .dark {
          HighQualityLogoView(image: logo).colorInvert()
        } else {
          HighQualityLogoView(image: logo)
        }
      }
      .frame(width: 64, height: 90)
      .accessibilityHidden(true)

      RabbisirBrandTitleView(
        content: .current,
        font: .system(size: 32, weight: .semibold, design: .rounded),
        color: .primary
      )
      .padding(.top, 11)

      Text(content.versionText)
        .rabbisirTypography(RabbisirAboutTypography.metadata)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .padding(.top, 4)

      VStack(spacing: 3) {
        ForEach(content.attributions, id: \.self) { attribution in
          Text(attribution)
        }
      }
      .rabbisirTypography(RabbisirAboutTypography.attribution)
      .foregroundStyle(.primary)
      .padding(.top, 14)

      Text(copy.communityDisclaimer)
        .rabbisirTypography(RabbisirAboutTypography.supporting)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 5)

      Button {
        NSWorkspace.shared.open(website.url)
      } label: {
        Text(website.title)
          .rabbisirTypography(RabbisirAboutTypography.action)
          .foregroundStyle(.primary)
          .underline()
      }
      .buttonStyle(.plain)
      .accessibilityHint(website.url.absoluteString)
      .padding(.top, 12)

      Spacer(minLength: 20)

      HStack(spacing: 22) {
        ForEach(RabbisirAboutDestination.allCases, id: \.self) { destination in
          Button {
            NSWorkspace.shared.open(destination.url)
          } label: {
            RabbisirAboutDestinationLink(
              destination: destination,
              image: destinationImages[destination],
              title: destination.title(copy: copy)
            )
          }
          .buttonStyle(.plain)
        }
      }
      .fixedSize(horizontal: true, vertical: false)

      Text(content.copyrightText)
        .rabbisirTypography(RabbisirAboutTypography.footer)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
        .padding(.top, 18)
        .padding(.bottom, 18)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.clear)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(content.accessibilityLabel)
  }
}

private struct RabbisirAboutDestinationLink: View {
  let destination: RabbisirAboutDestination
  let image: NSImage?
  let title: String

  var body: some View {
    HStack(spacing: 7) {
      if let image {
        Image(nsImage: image)
          .renderingMode(.original)
          .resizable()
          .aspectRatio(contentMode: .fit)
          .frame(width: 24, height: 24)
          .accessibilityHidden(true)
      } else {
        Image(systemName: destination.systemSymbol)
          .font(.system(size: 20, weight: .medium))
          .frame(width: 24, height: 24)
          .accessibilityHidden(true)
      }

      Text(title)
        .rabbisirTypography(RabbisirAboutTypography.action)
        .foregroundStyle(.primary)
        .lineLimit(1)
    }
    .padding(.vertical, 4)
    .contentShape(Rectangle())
    .accessibilityElement(children: .combine)
    .accessibilityHint(destination.url.absoluteString)
  }
}
