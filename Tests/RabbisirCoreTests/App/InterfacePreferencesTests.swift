import Foundation
import Testing

@testable import RabbisirCore

@Suite("Rabbisir interface preferences")
struct InterfacePreferencesTests {
  @Test("First use keeps every current interface default")
  func defaultsRemainUnspecified() throws {
    let (defaults, suite) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let preferences = RabbisirInterfacePreferencesStore(defaults: defaults)

    #expect(preferences.workspaceWidths == RabbisirWorkspaceWidthPreferences())
    #expect(preferences.settingsWindowSize == nil)
    #expect(preferences.helpWindowSize == nil)
  }

  @Test("Workspace widths and settings size survive store reconstruction")
  func valuesRoundTrip() throws {
    let (defaults, suite) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = RabbisirInterfacePreferencesStore(defaults: defaults)

    first.setSidebarWidth(336)
    first.setConversationWidth(840)
    first.setDetailsWidth(960)
    first.setSettingsWindowSize(CGSize(width: 1_120, height: 760))
    first.setHelpWindowSize(CGSize(width: 1_040, height: 740))

    let restored = RabbisirInterfacePreferencesStore(defaults: defaults)
    #expect(
      restored.workspaceWidths
        == RabbisirWorkspaceWidthPreferences(
          sidebar: 336,
          conversation: 840,
          details: 960
        )
    )
    #expect(restored.settingsWindowSize == CGSize(width: 1_120, height: 760))
    #expect(restored.helpWindowSize == CGSize(width: 1_040, height: 740))
  }

  @Test("Writes clamp to the actual adjustable panel and window bounds")
  func writesClampToSupportedBounds() throws {
    let (defaults, suite) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let preferences = RabbisirInterfacePreferencesStore(defaults: defaults)

    preferences.setSidebarWidth(-5)
    preferences.setConversationWidth(50_000)
    preferences.setDetailsWidth(2)
    preferences.setSettingsWindowSize(CGSize(width: 200, height: 50_000))
    preferences.setHelpWindowSize(CGSize(width: 120, height: 90_000))

    #expect(
      preferences.workspaceWidths.sidebar
        == SpatialWorkspaceLayoutPolicy.minimumSidebarWidth
    )
    #expect(
      preferences.workspaceWidths.conversation
        == SpatialWorkspaceLayoutPolicy.maximumConversationWidth
    )
    #expect(
      preferences.workspaceWidths.details
        == SpatialWorkspaceLayoutPolicy.minimumDetailsWidth
    )
    #expect(
      preferences.settingsWindowSize
        == CGSize(
          width: NativeSettingsWindowLayout.minimumSize.width,
          height: NativeSettingsWindowLayout.maximumStoredSize.height
        )
    )
    #expect(
      preferences.helpWindowSize
        == CGSize(
          width: RabbisirHelpWindowLayout.minimumSize.width,
          height: RabbisirHelpWindowLayout.maximumStoredSize.height
        )
    )
  }

  @Test("Corrupt and obsolete values fail closed to current defaults")
  func corruptAndObsoleteValuesAreIgnored() throws {
    let (defaults, suite) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(
      RabbisirInterfacePreferencesStore.schemaVersion,
      forKey: RabbisirInterfacePreferenceKey.schemaVersion
    )
    defaults.set("not-a-number", forKey: RabbisirInterfacePreferenceKey.sidebarWidth)
    defaults.set(Double.infinity, forKey: RabbisirInterfacePreferenceKey.conversationWidth)
    defaults.set(-100, forKey: RabbisirInterfacePreferenceKey.detailsWidth)
    defaults.set(1e100, forKey: RabbisirInterfacePreferenceKey.settingsWidth)
    defaults.set(700, forKey: RabbisirInterfacePreferenceKey.settingsHeight)
    defaults.set(Double.nan, forKey: RabbisirInterfacePreferenceKey.helpWidth)
    defaults.set(700, forKey: RabbisirInterfacePreferenceKey.helpHeight)

    let corrupt = RabbisirInterfacePreferencesStore(defaults: defaults)
    #expect(corrupt.workspaceWidths == RabbisirWorkspaceWidthPreferences())
    #expect(corrupt.settingsWindowSize == nil)
    #expect(corrupt.helpWindowSize == nil)

    defaults.set(
      RabbisirInterfacePreferencesStore.schemaVersion + 1,
      forKey: RabbisirInterfacePreferenceKey.schemaVersion
    )
    defaults.set(320, forKey: RabbisirInterfacePreferenceKey.sidebarWidth)
    let obsolete = RabbisirInterfacePreferencesStore(defaults: defaults)
    #expect(obsolete.workspaceWidths == RabbisirWorkspaceWidthPreferences())
  }

  @Test("Restored preferences remain constrained by the current display work area")
  func restoredWidthsRespectCurrentDisplay() throws {
    let (defaults, suite) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let first = RabbisirInterfacePreferencesStore(defaults: defaults)
    first.setSidebarWidth(440)
    first.setConversationWidth(1_200)
    first.setDetailsWidth(4_000)
    let restored = RabbisirInterfacePreferencesStore(defaults: defaults).workspaceWidths
    let visible = CGRect(x: -900, y: 100, width: 1_600, height: 900)

    let layout = SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visible,
      detailsVisible: true,
      preferredSidebarWidth: restored.sidebar,
      preferredConversationWidth: restored.conversation,
      preferredDetailsWidth: restored.details
    )

    #expect(visible.contains(layout.sidebarFrame))
    #expect(visible.contains(layout.mainFrame))
    #expect(visible.contains(layout.inputFrame))
    #expect(layout.detailsFrame.map(visible.contains) == true)
  }

  @Test("Language selection remains in the existing localized preference")
  @MainActor
  func languageStillRestores() throws {
    let (defaults, suite) = try makeDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    let localization = RabbisirLocalization(
      defaults: defaults,
      preferredLanguages: ["en-US"]
    )
    localization.select(.chinese)

    let restored = RabbisirLocalization(
      defaults: defaults,
      preferredLanguages: ["en-US"]
    )
    #expect(restored.language == .chinese)
  }

  private func makeDefaults() throws -> (UserDefaults, String) {
    let suite = "RabbisirTests.InterfacePreferences.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return (defaults, suite)
  }
}
