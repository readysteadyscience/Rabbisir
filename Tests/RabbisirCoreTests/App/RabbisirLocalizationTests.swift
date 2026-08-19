import Foundation
import Testing

@testable import RabbisirCore

@Suite("Rabbisir localization")
struct RabbisirLocalizationTests {
  @Test("First launch follows the preferred system language")
  @MainActor
  func firstLaunchUsesSystemLanguage() throws {
    let defaults = try makeDefaults()

    #expect(
      RabbisirLocalization(
        defaults: defaults,
        preferredLanguages: ["zh-Hans-CN"]
      ).language == .chinese
    )
    #expect(
      RabbisirLocalization(
        defaults: defaults,
        preferredLanguages: ["en-US"]
      ).language == .english
    )
  }

  @Test("An explicit choice persists even when it matches the current default")
  @MainActor
  func explicitChoicePersists() throws {
    let defaults = try makeDefaults()
    let localization = RabbisirLocalization(
      defaults: defaults,
      preferredLanguages: ["zh-Hans-CN"]
    )

    localization.select(.chinese)

    let restored = RabbisirLocalization(
      defaults: defaults,
      preferredLanguages: ["en-US"]
    )
    #expect(restored.language == .chinese)
  }

  @Test("Public Window, Language, and Help keep their localized native order")
  @MainActor
  func languageMenuCheckmarkFollowsSelection() throws {
    let target = NSObject()
    let chineseMenu = ApplicationMenu.make(target: target, language: .chinese)
    let englishMenu = ApplicationMenu.make(target: target, language: .english)
    let chineseLanguageIndex = try #require(
      chineseMenu.items.firstIndex(where: { $0.title == "Language" })
    )
    let chineseWindowIndex = try #require(
      chineseMenu.items.firstIndex(where: { $0.title == "窗口" })
    )
    let chineseEditIndex = try #require(
      chineseMenu.items.firstIndex(where: { $0.title == "编辑" })
    )
    let englishLanguageIndex = try #require(
      englishMenu.items.firstIndex(where: { $0.title == "语言" })
    )
    let englishWindowIndex = try #require(
      englishMenu.items.firstIndex(where: { $0.title == "Window" })
    )
    let englishEditIndex = try #require(
      englishMenu.items.firstIndex(where: { $0.title == "Edit" })
    )
    let languageMenu = try #require(englishMenu.items[englishLanguageIndex].submenu)

    #expect(languageMenu.items.first(where: { $0.title == "中文" })?.state == .off)
    #expect(languageMenu.items.first(where: { $0.title == "English" })?.state == .on)
    #expect(chineseWindowIndex == chineseEditIndex + 1)
    #expect(chineseLanguageIndex == chineseWindowIndex + 1)
    #expect(englishWindowIndex == englishEditIndex + 1)
    #expect(englishLanguageIndex == englishWindowIndex + 1)
    #expect(chineseMenu.items.last?.title == "帮助")
    #expect(englishMenu.items.last?.title == "Help")
    let privateChineseTitles = ["外" + "观", "助" + "力", "支持" + "开源维护"]
    let privateEnglishTitles = [
      ["App", "earance"].joined(), ["Support", "Rabbisir"].joined(separator: " "),
    ]
    #expect(!chineseMenu.items.contains { privateChineseTitles.contains($0.title) })
    #expect(!englishMenu.items.contains { privateEnglishTitles.contains($0.title) })
    #expect(!chineseMenu.items.first!.submenu!.items.contains { $0.title.contains("更新") })
    #expect(!englishMenu.items.first!.submenu!.items.contains { $0.title.contains("Update") })
  }

  @Test("The shared catalog resolves app-owned copy in both languages")
  func sharedCatalogResolvesBothLanguages() {
    let chinese = RabbisirCopy(language: .chinese)
    let english = RabbisirCopy(language: .english)

    #expect(chinese[.settingsGeneral] == "通用")
    #expect(english[.settingsGeneral] == "General")
    #expect(chinese[.conversationLoadEarlier] == "载入更早消息")
    #expect(english[.conversationLoadEarlier] == "Load Earlier Messages")
    #expect(chinese[.composerPlaceholder] == "想聊点什么？")
    #expect(english[.composerPlaceholder] == "What would you like to talk about?")
    #expect(chinese[.composerStopGeneration] == "停止生成")
    #expect(english[.composerStopGeneration] == "Stop Generating")
    #expect(chinese[.composerStoppingGeneration] == "正在停止…")
    #expect(english[.composerStoppingGeneration] == "Stopping…")
    #expect(chinese[.artifactExport] == "导出")
    #expect(english[.artifactExport] == "Export")
    #expect(chinese.menuBar.browserIdle == "即将推出")
    #expect(chinese.menuBar.browserIdleDetail == "内置浏览器控制即将开放。")
    #expect(english.menuBar.browserIdle == "Coming Soon")
    #expect(english.menuBar.browserIdleDetail == "Built-in browser control is coming soon.")
    #expect(chinese.toolTitle("read") == "读取")
    #expect(english.toolTitle("read") == "Read")
    #expect(chinese.composerPermissionName("Full access") == "完全访问")
    #expect(english.composerPermissionName("完全访问") == "Full access")
    #expect(chinese.composerPermissionName("workspace-write") == "工作区写入")
    #expect(english.composerPermissionName("Workspace Write") == "Workspace write")
  }

  @Test("Dynamic app copy is localized without rewriting user content")
  func dynamicCopyPreservesUserValues() {
    let projectName = "My 项目 01"
    let chinese = RabbisirCopy(language: .chinese)
    let english = RabbisirCopy(language: .english)

    #expect(chinese.currentWorkspace(projectName) == "当前工作区：My 项目 01")
    #expect(english.currentWorkspace(projectName) == "Current Workspace: My 项目 01")
    #expect(chinese.deleteProjectConfirmation(projectName).contains(projectName))
    #expect(english.deleteProjectConfirmation(projectName).contains(projectName))
  }

  @Test("Brand and official model values remain untouched")
  func protectedNamesRemainUntouched() {
    let values = [
      RabbisirAppIdentity.displayName,
      "DeepSeek-V4-Pro",
      "deepseek-v4-pro",
      "Max",
    ]

    for language in RabbisirInterfaceLanguage.allCases {
      let copy = RabbisirCopy(language: language)
      for value in values {
        #expect(copy.verbatim(value) == value)
      }
    }
  }

  @Test("Built-in Agent preset metadata follows the selected interface language")
  func builtInAgentPresetMetadataIsLocalized() {
    let chinese = RabbisirCopy(language: .chinese).agentPresets
    let english = RabbisirCopy(language: .english).agentPresets

    #expect(chinese.builtInName(id: "cordis", fallback: "Creative Mode") == "创造模式")
    #expect(english.builtInName(id: "cordis", fallback: "创造模式") == "Creative Mode")
    #expect(english.localizedName("标准模式") == "Standard Mode")
    #expect(english.localizedName("创造模式") == "Creative Mode")
    #expect(chinese.localizedName("Creative Mode") == "创造模式")
    #expect(
      english.builtInDescription(id: "standard", fallback: "功能完整的编码 Agent。")
        == "A full-featured coding Agent with file editing, Shell, file and web search, Skills, plans, goals, subagents, and workflows."
    )
    #expect(
      english.localizedDescription("仅提供持久 bash 与 str_replace_editor 的双工具编码 Agent。")
        == "A two-tool coding Agent providing only persistent bash and str_replace_editor."
    )
  }

  @Test("Custom Agent preset metadata remains user-authored content")
  func customAgentPresetMetadataRemainsVerbatim() {
    let copy = RabbisirCopy(language: .english).agentPresets
    let customName = "我的创造模式"
    let customDescription = "这是用户自己写的说明。"

    #expect(copy.localizedName(customName) == customName)
    #expect(copy.localizedDescription(customDescription) == customDescription)
    #expect(
      copy.builtInDescription(id: "my-preset", fallback: customDescription) == customDescription)
  }

  private func makeDefaults() throws -> UserDefaults {
    let suite = "RabbisirTests.Localization.\(UUID().uuidString)"
    let defaults = try #require(UserDefaults(suiteName: suite))
    defaults.removePersistentDomain(forName: suite)
    return defaults
  }
}
