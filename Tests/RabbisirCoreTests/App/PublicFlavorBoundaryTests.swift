import AppKit
import Testing

@testable import RabbisirCore

@Suite("Rabbisir public product boundary", .serialized)
struct PublicFlavorBoundaryTests {
  @Test("Public menus and settings expose only public capabilities in both languages")
  @MainActor
  func menuAndSettingsBoundary() {
    let forbidden = [
      "外" + "观",
      "助" + "力",
      ["App", "earance"].joined(),
      ["Support", "Rabbisir"].joined(separator: " "),
      ["Check for", "Updates"].joined(separator: " "),
    ]
    for language in RabbisirInterfaceLanguage.allCases {
      let menu = ApplicationMenu.make(target: NSObject(), language: language)
      let visibleText = menu.items.flatMap { item in
        [item.title] + (item.submenu?.items.map(\.title) ?? [])
      }.joined(separator: "\n")
      #expect(forbidden.allSatisfy { !visibleText.contains($0) })
      #expect(menu.items.last?.title == (language == .chinese ? "帮助" : "Help"))
    }
    #expect(
      NativeSettingsSection.allCases.map(\.rawValue) == [
        "general", "models", "plugins", "agentPresets",
      ])
  }

  @Test("Public Help discovers creator, Discord, license, and GitHub feedback")
  func publicHelpBoundary() throws {
    for language in RabbisirInterfaceLanguage.allCases {
      let article = try RabbisirHelpCatalog(language: language).article(
        for: .communityAndLicense
      )
      #expect(article.plainText.contains("YelZap"))
      #expect(article.plainText.contains("Discord"))
      #expect(article.plainText.contains("GitHub"))
      #expect(article.plainText.contains("MIT"))
      #expect(article.externalLinks.count == 3)
    }
  }

  @Test("Public menu-bar accessibility tree has no private status control")
  @MainActor
  func menuBarAccessibilityBoundary() {
    let view = MenuBarIslandContentView(
      state: WorkspaceState(),
      frame: CGRect(origin: .zero, size: MenuBarIslandPresentation.size),
      localization: RabbisirLocalization.shared,
      isWorkspaceVisible: { true },
      setWorkspaceVisible: { _ in }
    )
    let identifiers = descendants(of: view).compactMap { $0.accessibilityIdentifier() }
    #expect(!identifiers.contains { $0.contains("software" + "Update") })
  }

  @Test("Private local resources are absent from the public resource bundle")
  func privateResourceBoundary() {
    #expect(
      RabbisirResourceBundle.current.url(
        forResource: ["OpenSource", "Maintenance", "QRCode"].joined(),
        withExtension: "png",
        subdirectory: "Brand"
      ) == nil
    )
  }

  @MainActor
  private func descendants(of root: NSView) -> [NSView] {
    [root] + root.subviews.flatMap(descendants(of:))
  }
}
