import Combine
import Foundation
import SwiftUI

enum RabbisirInterfaceLanguage: String, CaseIterable, Identifiable, Sendable {
  case chinese = "zh-Hans"
  case english = "en"

  var id: String { rawValue }

  var locale: Locale { Locale(identifier: rawValue) }

  static func resolve(preferredLanguages: [String]) -> Self {
    guard let language = preferredLanguages.first?.lowercased() else { return .english }
    return language.hasPrefix("zh") ? .chinese : .english
  }

  static func currentPreference(
    defaults: UserDefaults = .standard,
    preferredLanguages: [String] = Locale.preferredLanguages
  ) -> Self {
    guard let stored = defaults.string(forKey: RabbisirLocalizationPreferenceKey.interfaceLanguage),
      let language = Self(rawValue: stored)
    else {
      return resolve(preferredLanguages: preferredLanguages)
    }
    return language
  }
}

typealias MenuBarInterfaceLanguage = RabbisirInterfaceLanguage

enum RabbisirLocalizationPreferenceKey {
  static let interfaceLanguage = "rabbisir.interfaceLanguage"
}

@MainActor
final class RabbisirLocalization: ObservableObject {
  static let shared = RabbisirLocalization()

  @Published private(set) var language: RabbisirInterfaceLanguage

  private let defaults: UserDefaults

  init(
    defaults: UserDefaults = .standard,
    preferredLanguages: [String] = Locale.preferredLanguages
  ) {
    self.defaults = defaults
    if let stored = defaults.string(forKey: RabbisirLocalizationPreferenceKey.interfaceLanguage),
      let language = RabbisirInterfaceLanguage(rawValue: stored)
    {
      self.language = language
    } else {
      language = RabbisirInterfaceLanguage.resolve(preferredLanguages: preferredLanguages)
    }
  }

  func select(_ language: RabbisirInterfaceLanguage) {
    defaults.set(language.rawValue, forKey: RabbisirLocalizationPreferenceKey.interfaceLanguage)
    guard self.language != language else { return }
    self.language = language
  }
}

enum RabbisirStringKey: String, CaseIterable, Sendable {
  case about
  case addWorkspace
  case agentPresets
  case archive
  case artifactCopy
  case artifactCopied
  case artifactExport
  case artifactOpenExternal
  case artifactPrint
  case artifactRefresh
  case artifactSave
  case cancel
  case close
  case composerCommands
  case composerCommandsAndAdd
  case composerPlaceholder
  case composerCurrentPermission
  case composerInputAccessibility
  case composerCurrentModelReasoning
  case composerCurrentOptionsLoading
  case composerNoOptions
  case composerSendCurrent
  case composerStopGeneration
  case composerStopGenerationHint
  case composerStoppingGeneration
  case composerStopRejected
  case composerWorkspaceHint
  case composerCommandsHint
  case composerAgentPresetHint
  case composerOptionsHint
  case composerSelected
  case composerNoModelReasoning
  case composerSubmitRejected
  case composerConfirmationRequired
  case conversationLoadEarlier
  case conversationLoadingEarlier
  case conversationLoading
  case conversationLoadFailed
  case conversationMessages
  case conversationRetry
  case conversationReplyStreaming
  case conversationExpanded
  case conversationCollapsed
  case conversationForkHere
  case conversationImage
  case conversationCopyMessage
  case conversationCopyUserHelp
  case conversationCopyAssistantHelp
  case conversationCopyFinalHelp
  case conversationCopyVisibleHelp
  case conversationCopyAvailable
  case conversationCopyFailed
  case copy
  case create
  case delete
  case detailsEmptyFormats
  case detailsEmptyHint
  case detailsAccessibility
  case detailsFormatsAccessibility
  case done
  case edit
  case hide
  case model
  case newWorkspace
  case newWorkspaceFailure
  case open
  case permissions
  case plugins
  case reload
  case rename
  case retry
  case returnToNativeConversation
  case returnToNativeConversationHint
  case save
  case send
  case sessionLog
  case settings
  case settingsAgentPresets
  case settingsGeneral
  case settingsLoading
  case settingsLoadFailed
  case settingsModels
  case settingsPlugins
  case settingsEnterBehavior
  case settingsEnterBehaviorDescription
  case settingsQueue
  case settingsSteer
  case settingsDefaultPermission
  case settingsDefaultPermissionDescription
  case settingsUnavailable
  case settingsModelDescription
  case settingsCurrentModel
  case settingsCurrentModelDescription
  case settingsConfigured
  case settingsNotConfigured
  case settingsEnterAPIKey
  case settingsDeleteKey
  case settingsReasoningLevel
  case settingsNoModels
  case settingsDeleteKeyTitle
  case settingsDeleteKeyMessage
  case settingsReadingConfiguration
  case settingsConfiguredInRabbisir
  case settingsConfigureAPIKey
  case show
  case showInFinder
  case sidebarEmpty
  case sidebarLoading
  case sidebarAccessibility
  case sidebarArchivedProjects
  case sidebarScrollTop
  case sidebarScrollBottom
  case sidebarCurrentWorkspace
  case sidebarExpanded
  case sidebarCollapsed
  case sidebarToggleWorkspace
  case sidebarPinProject
  case sidebarEditProject
  case sidebarArchiveProject
  case sidebarUnarchiveProject
  case sidebarDeleteProject
  case sidebarPinSession
  case sidebarRenameSession
  case sidebarArchiveSession
  case sidebarDeleteSession
  case sidebarForkSession
  case sidebarMoveToProject
  case sidebarCopyWorkingDirectory
  case sidebarCopySessionID
  case sidebarOpenSession
  case sidebarCurrentSession
  case workspace
}

struct RabbisirCopy: Equatable, Sendable {
  let language: RabbisirInterfaceLanguage

  subscript(key: RabbisirStringKey) -> String {
    switch (language, key) {
    case (.chinese, .about): "关于 \(RabbisirAppIdentity.displayName)"
    case (.english, .about): "About \(RabbisirAppIdentity.displayName)"
    case (.chinese, .addWorkspace): "添加工作区…"
    case (.english, .addWorkspace): "Add Workspace…"
    case (.chinese, .agentPresets), (.chinese, .settingsAgentPresets): "智能体预设"
    case (.english, .agentPresets), (.english, .settingsAgentPresets): "Agent Presets"
    case (.chinese, .archive): "归档"
    case (.english, .archive): "Archive"
    case (.chinese, .artifactCopy), (.chinese, .copy): "复制"
    case (.english, .artifactCopy), (.english, .copy): "Copy"
    case (.chinese, .artifactCopied): "已复制"
    case (.english, .artifactCopied): "Copied"
    case (.chinese, .artifactExport): "导出"
    case (.english, .artifactExport): "Export"
    case (.chinese, .artifactOpenExternal): "外部打开"
    case (.english, .artifactOpenExternal): "Open Externally"
    case (.chinese, .artifactPrint): "打印"
    case (.english, .artifactPrint): "Print"
    case (.chinese, .artifactRefresh), (.chinese, .reload): "刷新"
    case (.english, .artifactRefresh), (.english, .reload): "Refresh"
    case (.chinese, .artifactSave), (.chinese, .save): "保存"
    case (.english, .artifactSave), (.english, .save): "Save"
    case (.chinese, .cancel): "取消"
    case (.english, .cancel): "Cancel"
    case (.chinese, .close): "关闭"
    case (.english, .close): "Close"
    case (.chinese, .composerCommands): "命令"
    case (.english, .composerCommands): "Commands"
    case (.chinese, .composerCommandsAndAdd): "命令与添加"
    case (.english, .composerCommandsAndAdd): "Commands and Add"
    case (.chinese, .composerPlaceholder): "想聊点什么？"
    case (.english, .composerPlaceholder): "What would you like to talk about?"
    case (.chinese, .composerStopGeneration): "停止生成"
    case (.english, .composerStopGeneration): "Stop Generating"
    case (.chinese, .composerStopGenerationHint): "立即取消当前会话正在执行的生成任务"
    case (.english, .composerStopGenerationHint):
      "Cancel the generation currently running in this conversation"
    case (.chinese, .composerStoppingGeneration): "正在停止…"
    case (.english, .composerStoppingGeneration): "Stopping…"
    case (.chinese, .composerStopRejected): "当前任务未能确认停止，请重试"
    case (.english, .composerStopRejected):
      "The current task did not confirm cancellation. Try again."
    case (.chinese, .composerCurrentPermission): "当前访问权限"
    case (.english, .composerCurrentPermission): "Current Access Permission"
    case (.chinese, .composerInputAccessibility): "当前会话输入"
    case (.english, .composerInputAccessibility): "Current Session Input"
    case (.chinese, .composerCurrentModelReasoning): "当前模型与推理等级"
    case (.english, .composerCurrentModelReasoning): "Current Model and Reasoning Level"
    case (.chinese, .composerCurrentOptionsLoading): "正在读取当前会话选项"
    case (.english, .composerCurrentOptionsLoading): "Loading Current Session Options"
    case (.chinese, .composerNoOptions): "当前会话没有可用选项"
    case (.english, .composerNoOptions): "No Options Are Available for the Current Session"
    case (.chinese, .composerSendCurrent): "发送到当前会话"
    case (.english, .composerSendCurrent): "Send to Current Session"
    case (.chinese, .composerWorkspaceHint): "在输入框连体区域展开或收起新建工作区入口"
    case (.english, .composerWorkspaceHint):
      "Expand or collapse the new-workspace entry attached to the composer"
    case (.chinese, .composerCommandsHint): "在输入框上方显示当前会话的命令"
    case (.english, .composerCommandsHint):
      "Show commands for the current session above the composer"
    case (.chinese, .composerAgentPresetHint): "在输入框上方显示新会话可用的智能体预设"
    case (.english, .composerAgentPresetHint):
      "Show Agent presets for new sessions above the composer"
    case (.chinese, .composerOptionsHint): "在输入框上方显示当前会话选项"
    case (.english, .composerOptionsHint): "Show options for the current session above the composer"
    case (.chinese, .composerSelected): "已选择"
    case (.english, .composerSelected): "Selected"
    case (.chinese, .composerNoModelReasoning): "当前会话没有可用的模型与推理等级"
    case (.english, .composerNoModelReasoning):
      "No Models or Reasoning Levels Are Available for the Current Session"
    case (.chinese, .composerSubmitRejected): "当前会话未接受发送，草稿已保留"
    case (.english, .composerSubmitRejected):
      "The current session did not accept the message. The draft was preserved."
    case (.chinese, .composerConfirmationRequired): "请在主会话中完成权限确认"
    case (.english, .composerConfirmationRequired):
      "Complete the permission confirmation in the main session"
    case (.chinese, .conversationLoadEarlier): "载入更早消息"
    case (.english, .conversationLoadEarlier): "Load Earlier Messages"
    case (.chinese, .conversationLoadingEarlier): "正在载入更早消息"
    case (.english, .conversationLoadingEarlier): "Loading Earlier Messages"
    case (.chinese, .conversationLoading): "正在载入会话"
    case (.english, .conversationLoading): "Loading Conversation"
    case (.chinese, .conversationLoadFailed): "无法载入会话"
    case (.english, .conversationLoadFailed): "Could Not Load Conversation"
    case (.chinese, .conversationMessages): "对话消息"
    case (.english, .conversationMessages): "Conversation Messages"
    case (.chinese, .conversationRetry), (.chinese, .retry): "重试"
    case (.english, .conversationRetry), (.english, .retry): "Retry"
    case (.chinese, .conversationReplyStreaming): "回复生成中"
    case (.english, .conversationReplyStreaming): "Generating Reply"
    case (.chinese, .conversationExpanded): "已展开"
    case (.english, .conversationExpanded): "Expanded"
    case (.chinese, .conversationCollapsed): "已折叠"
    case (.english, .conversationCollapsed): "Collapsed"
    case (.chinese, .conversationForkHere): "从这里创建对话分支"
    case (.english, .conversationForkHere): "Create a Conversation Branch Here"
    case (.chinese, .conversationImage): "图片"
    case (.english, .conversationImage): "Image"
    case (.chinese, .conversationCopyMessage): "复制此消息"
    case (.english, .conversationCopyMessage): "Copy This Message"
    case (.chinese, .conversationCopyUserHelp): "复制这条用户消息的完整可见文本"
    case (.english, .conversationCopyUserHelp):
      "Copy the complete visible text of this user message"
    case (.chinese, .conversationCopyAssistantHelp): "复制这条 AI 回复的完整可见文本"
    case (.english, .conversationCopyAssistantHelp):
      "Copy the complete visible text of this AI reply"
    case (.chinese, .conversationCopyFinalHelp): "复制本轮 AI 最终回复的完整可见文本"
    case (.english, .conversationCopyFinalHelp):
      "Copy the complete visible text of the final AI reply in this turn"
    case (.chinese, .conversationCopyVisibleHelp): "复制此消息的完整可见文本"
    case (.english, .conversationCopyVisibleHelp): "Copy the complete visible text of this message"
    case (.chinese, .conversationCopyAvailable): "可复制"
    case (.english, .conversationCopyAvailable): "Copy Available"
    case (.chinese, .conversationCopyFailed): "复制失败"
    case (.english, .conversationCopyFailed): "Copy Failed"
    case (.chinese, .create): "创建"
    case (.english, .create): "Create"
    case (.chinese, .delete): "删除"
    case (.english, .delete): "Delete"
    case (.chinese, .detailsEmptyFormats): "文稿 · PDF · Markdown · 源码"
    case (.english, .detailsEmptyFormats): "Document · PDF · Markdown · Source"
    case (.chinese, .detailsEmptyHint): "从对话中打开内容后，将在这里显示"
    case (.english, .detailsEmptyHint): "Open content from a conversation to view it here"
    case (.chinese, .detailsAccessibility): "右侧详情"
    case (.english, .detailsAccessibility): "Details Panel"
    case (.chinese, .detailsFormatsAccessibility): "这里可显示文稿、PDF、Markdown 和源码内容"
    case (.english, .detailsFormatsAccessibility):
      "Documents, PDF, Markdown, and source code can be shown here"
    case (.chinese, .done): "完成"
    case (.english, .done): "Done"
    case (.chinese, .edit): "编辑"
    case (.english, .edit): "Edit"
    case (.chinese, .hide): "隐藏"
    case (.english, .hide): "Hide"
    case (.chinese, .model), (.chinese, .settingsModels): "模型"
    case (.english, .model), (.english, .settingsModels): "Models"
    case (.chinese, .newWorkspace): "新建工作区"
    case (.english, .newWorkspace): "New Workspace"
    case (.chinese, .newWorkspaceFailure): "无法打开新建工作区，请重试"
    case (.english, .newWorkspaceFailure): "Could Not Open New Workspace. Try Again."
    case (.chinese, .open): "打开"
    case (.english, .open): "Open"
    case (.chinese, .permissions): "权限"
    case (.english, .permissions): "Permissions"
    case (.chinese, .plugins), (.chinese, .settingsPlugins): "插件"
    case (.english, .plugins), (.english, .settingsPlugins): "Plugins"
    case (.chinese, .rename): "重命名"
    case (.english, .rename): "Rename"
    case (.chinese, .returnToNativeConversation): "返回原生对话"
    case (.english, .returnToNativeConversation): "Back to Native Conversation"
    case (.chinese, .returnToNativeConversationHint): "关闭 WebKit 过渡设置并返回原生对话"
    case (.english, .returnToNativeConversationHint):
      "Close transitional WebKit settings and return to the native conversation"
    case (.chinese, .send): "发送"
    case (.english, .send): "Send"
    case (.chinese, .sessionLog): "会话日志"
    case (.english, .sessionLog): "Session Log"
    case (.chinese, .settings): "设置"
    case (.english, .settings): "Settings"
    case (.chinese, .settingsGeneral): "通用"
    case (.english, .settingsGeneral): "General"
    case (.chinese, .settingsLoading): "正在载入 Rabbisir 设置…"
    case (.english, .settingsLoading): "Loading Rabbisir Settings…"
    case (.chinese, .settingsLoadFailed): "设置载入失败"
    case (.english, .settingsLoadFailed): "Failed to Load Settings"
    case (.chinese, .settingsEnterBehavior): "回车键行为"
    case (.english, .settingsEnterBehavior): "Enter Behavior"
    case (.chinese, .settingsEnterBehaviorDescription): "智能体正忙时，按回车键如何处理新输入。"
    case (.english, .settingsEnterBehaviorDescription):
      "Choose how Enter handles new input while the agent is busy."
    case (.chinese, .settingsQueue): "排队"
    case (.english, .settingsQueue): "Queue"
    case (.chinese, .settingsSteer): "引导当前轮次"
    case (.english, .settingsSteer): "Steer Current Turn"
    case (.chinese, .settingsDefaultPermission): "新会话默认权限"
    case (.english, .settingsDefaultPermission): "Default Permission for New Sessions"
    case (.chinese, .settingsDefaultPermissionDescription): "只影响随后创建的会话；当前会话仍使用自身真实状态。"
    case (.english, .settingsDefaultPermissionDescription):
      "Applies only to sessions created later; the current session keeps its existing state."
    case (.chinese, .settingsUnavailable): "此设置当前不可用。"
    case (.english, .settingsUnavailable): "This setting is currently unavailable."
    case (.chinese, .settingsModelDescription): "管理 Rabbisir 使用的 DeepSeek 模型与推理等级。"
    case (.english, .settingsModelDescription):
      "Manage the DeepSeek models and reasoning levels used by Rabbisir."
    case (.chinese, .settingsCurrentModel): "当前模型"
    case (.english, .settingsCurrentModel): "Current Model"
    case (.chinese, .settingsCurrentModelDescription): "用于随后创建的会话；已有会话保留自身选择。"
    case (.english, .settingsCurrentModelDescription):
      "Used for sessions created later; existing sessions keep their own selection."
    case (.chinese, .settingsConfigured): "已配置"
    case (.english, .settingsConfigured): "Configured"
    case (.chinese, .settingsNotConfigured): "未配置"
    case (.english, .settingsNotConfigured): "Not Configured"
    case (.chinese, .settingsEnterAPIKey): "输入新的 DeepSeek API Key"
    case (.english, .settingsEnterAPIKey): "Enter a new DeepSeek API Key"
    case (.chinese, .settingsDeleteKey): "删除 Key"
    case (.english, .settingsDeleteKey): "Delete Key"
    case (.chinese, .settingsReasoningLevel): "推理等级"
    case (.english, .settingsReasoningLevel): "Reasoning Level"
    case (.chinese, .settingsNoModels): "当前没有可用的 DeepSeek 模型。"
    case (.english, .settingsNoModels): "No DeepSeek models are currently available."
    case (.chinese, .settingsDeleteKeyTitle): "删除 DeepSeek API Key？"
    case (.english, .settingsDeleteKeyTitle): "Delete DeepSeek API Key?"
    case (.chinese, .settingsDeleteKeyMessage): "删除后，新请求将无法使用该凭据；现有 Key 不会被读取或显示。"
    case (.english, .settingsDeleteKeyMessage):
      "New requests will no longer use this credential. The existing key is never read or displayed."
    case (.chinese, .settingsReadingConfiguration): "正在读取配置状态"
    case (.english, .settingsReadingConfiguration): "Reading Configuration"
    case (.chinese, .settingsConfiguredInRabbisir): "已在 Rabbisir 中配置"
    case (.english, .settingsConfiguredInRabbisir): "Configured in Rabbisir"
    case (.chinese, .settingsConfigureAPIKey): "在 Rabbisir 中配置 DeepSeek API Key"
    case (.english, .settingsConfigureAPIKey): "Configure a DeepSeek API Key in Rabbisir"
    case (.chinese, .show): "显示"
    case (.english, .show): "Show"
    case (.chinese, .showInFinder): "在 Finder 中显示"
    case (.english, .showInFinder): "Show in Finder"
    case (.chinese, .sidebarEmpty): "当前没有可用项目与会话"
    case (.english, .sidebarEmpty): "No Projects or Sessions Available"
    case (.chinese, .sidebarLoading): "正在读取真实项目与会话"
    case (.english, .sidebarLoading): "Loading Projects and Sessions"
    case (.chinese, .sidebarAccessibility): "项目与会话侧栏"
    case (.english, .sidebarAccessibility): "Projects and Conversations Sidebar"
    case (.chinese, .sidebarArchivedProjects): "已归档项目"
    case (.english, .sidebarArchivedProjects): "Archived Projects"
    case (.chinese, .sidebarScrollTop): "滚动到项目列表顶部"
    case (.english, .sidebarScrollTop): "Scroll to the Top of the Project List"
    case (.chinese, .sidebarScrollBottom): "滚动到项目列表底部"
    case (.english, .sidebarScrollBottom): "Scroll to the Bottom of the Project List"
    case (.chinese, .sidebarCurrentWorkspace): "当前工作区"
    case (.english, .sidebarCurrentWorkspace): "Current Workspace"
    case (.chinese, .sidebarExpanded): "已展开"
    case (.english, .sidebarExpanded): "Expanded"
    case (.chinese, .sidebarCollapsed): "已收起"
    case (.english, .sidebarCollapsed): "Collapsed"
    case (.chinese, .sidebarToggleWorkspace): "展开或收起该工作区的会话"
    case (.english, .sidebarToggleWorkspace): "Expand or collapse conversations in this workspace"
    case (.chinese, .sidebarPinProject): "置顶项目"
    case (.english, .sidebarPinProject): "Pin Project"
    case (.chinese, .sidebarEditProject): "编辑项目名称"
    case (.english, .sidebarEditProject): "Edit Project Name"
    case (.chinese, .sidebarArchiveProject): "归档项目"
    case (.english, .sidebarArchiveProject): "Archive Project"
    case (.chinese, .sidebarUnarchiveProject): "取消归档项目"
    case (.english, .sidebarUnarchiveProject): "Unarchive Project"
    case (.chinese, .sidebarDeleteProject): "删除项目"
    case (.english, .sidebarDeleteProject): "Delete Project"
    case (.chinese, .sidebarPinSession): "置顶会话"
    case (.english, .sidebarPinSession): "Pin Conversation"
    case (.chinese, .sidebarRenameSession): "重命名会话"
    case (.english, .sidebarRenameSession): "Rename Conversation"
    case (.chinese, .sidebarArchiveSession): "归档会话"
    case (.english, .sidebarArchiveSession): "Archive Conversation"
    case (.chinese, .sidebarDeleteSession): "删除会话"
    case (.english, .sidebarDeleteSession): "Delete Conversation"
    case (.chinese, .sidebarForkSession): "创建聊天分支"
    case (.english, .sidebarForkSession): "Create Chat Branch"
    case (.chinese, .sidebarMoveToProject): "移至项目"
    case (.english, .sidebarMoveToProject): "Move to Project"
    case (.chinese, .sidebarCopyWorkingDirectory): "复制工作目录"
    case (.english, .sidebarCopyWorkingDirectory): "Copy Working Directory"
    case (.chinese, .sidebarCopySessionID): "复制会话 ID"
    case (.english, .sidebarCopySessionID): "Copy Conversation ID"
    case (.chinese, .sidebarOpenSession): "打开会话"
    case (.english, .sidebarOpenSession): "Open Conversation"
    case (.chinese, .sidebarCurrentSession): "当前会话"
    case (.english, .sidebarCurrentSession): "Current Conversation"
    case (.chinese, .workspace): "工作区"
    case (.english, .workspace): "Workspace"
    }
  }

  func verbatim(_ value: String) -> String { value }

  func composerPermissionName(_ sourceName: String) -> String {
    switch (language, sourceName.lowercased()) {
    case (.chinese, "full access"), (.chinese, "danger-full-access"), (.chinese, "完全访问"):
      "完全访问"
    case (.english, "full access"), (.english, "danger-full-access"), (.english, "完全访问"):
      "Full access"
    case (.chinese, "workspace write"), (.chinese, "workspace-write"), (.chinese, "工作区写入"):
      "工作区写入"
    case (.english, "workspace write"), (.english, "workspace-write"), (.english, "工作区写入"):
      "Workspace write"
    default:
      sourceName
    }
  }

  func currentWorkspace(_ name: String) -> String {
    switch language {
    case .chinese: "当前工作区：\(name)"
    case .english: "Current Workspace: \(name)"
    }
  }

  func deleteProjectConfirmation(_ name: String) -> String {
    switch language {
    case .chinese: "删除项目“\(name)”？"
    case .english: "Delete project “\(name)”?"
    }
  }

  func openPath(_ path: String) -> String {
    switch language {
    case .chinese: "打开 \(path)"
    case .english: "Open \(path)"
    }
  }

  func conversationCopyHelp(kind: NativeConversationItem.Kind) -> String {
    switch kind {
    case .user: self[.conversationCopyUserHelp]
    case .assistant: self[.conversationCopyAssistantHelp]
    case .turnTail: self[.conversationCopyFinalHelp]
    case .image, .tool, .command, .compaction, .notice, .system, .error:
      self[.conversationCopyVisibleHelp]
    }
  }

  var transitionalSettingsWorkspaceAccessibility: String {
    language == .chinese
      ? "Rabbisir WebKit 过渡设置工作区" : "Rabbisir Transitional WebKit Settings Workspace"
  }

  var nativeConversationAccessibility: String {
    language == .chinese ? "Rabbisir 原生对话消息流" : "Rabbisir Native Conversation Stream"
  }

  var mainConversationAccessibility: String {
    language == .chinese ? "Rabbisir 主会话区域" : "Rabbisir Main Conversation Area"
  }

  var composerPanelAccessibility: String {
    language == .chinese ? "Rabbisir 底部输入面板" : "Rabbisir Composer Panel"
  }

  func composerStatus(_ message: String) -> String {
    language == .chinese ? "输入面板状态：\(message)" : "Composer Status: \(message)"
  }

  func submenuHint(_ title: String) -> String {
    language == .chinese
      ? "在一级选择器右侧展开\(title)二级菜单" : "Open the \(title) submenu to the right of the primary selector"
  }

  func submenuOptions(_ title: String) -> String {
    language == .chinese ? "\(title)二级选项" : "\(title) Submenu Options"
  }

  func pullUpOptions(_ title: String) -> String {
    language == .chinese ? "\(title)上拉选项" : "\(title) Pull-up Options"
  }

  func optionUnavailable(_ kind: String) -> String {
    language == .chinese
      ? "当前会话没有可用的\(kind)" : "No \(kind) option is available for the current conversation"
  }

  func optionRejected(_ kind: String) -> String {
    language == .chinese
      ? "当前会话未接受该\(kind)选项" : "The current conversation did not accept that \(kind) option"
  }

  var sessionModelFallback: String { language == .chinese ? "会话模型" : "Conversation Model" }
  var defaultFallback: String { language == .chinese ? "默认" : "Default" }

  enum SidebarFailure: Sendable {
    case branch, workingDirectory, open, pinProject, renameProject, deleteProject
    case pinSession, renameSession, archiveSession, moveSession
  }

  func sidebarFailure(_ failure: SidebarFailure) -> String {
    switch (language, failure) {
    case (.chinese, .branch): "未能创建会话分支"
    case (.english, .branch): "Could Not Create Conversation Branch"
    case (.chinese, .workingDirectory): "该会话的工作目录当前不可用"
    case (.english, .workingDirectory): "The Working Directory for This Conversation Is Unavailable"
    case (.chinese, .open): "运行时未能打开该会话"
    case (.english, .open): "The Runtime Could Not Open This Conversation"
    case (.chinese, .pinProject): "未能置顶该项目"
    case (.english, .pinProject): "Could Not Pin This Project"
    case (.chinese, .renameProject): "未能更新项目名称"
    case (.english, .renameProject): "Could Not Update the Project Name"
    case (.chinese, .deleteProject): "未能从项目列表移除该项目"
    case (.english, .deleteProject): "Could Not Remove This Project from the Project List"
    case (.chinese, .pinSession): "未能置顶该会话"
    case (.english, .pinSession): "Could Not Pin This Conversation"
    case (.chinese, .renameSession): "未能重命名该会话"
    case (.english, .renameSession): "Could Not Rename This Conversation"
    case (.chinese, .archiveSession): "未能归档该会话"
    case (.english, .archiveSession): "Could Not Archive This Conversation"
    case (.chinese, .moveSession): "未能移动该会话"
    case (.english, .moveSession): "Could Not Move This Conversation"
    }
  }

  var ungroupedSessionPinUnavailable: String {
    language == .chinese
      ? "未分组会话无法在工作区内置顶" : "Ungrouped conversations cannot be pinned within a workspace"
  }

  var sessionDeletionUnavailable: String {
    language == .chinese
      ? "当前版本暂不支持删除会话" : "Deleting conversations is not supported in this version"
  }

  var apiKeyEmpty: String { language == .chinese ? "API Key 不能为空。" : "API Key Cannot Be Empty." }
  var deepSeekKeySaved: String {
    language == .chinese ? "DeepSeek API Key 已安全保存。" : "DeepSeek API Key Saved Securely."
  }
  var deepSeekKeyDeleted: String {
    language == .chinese ? "DeepSeek API Key 已删除。" : "DeepSeek API Key Deleted."
  }
  var settingsSaved: String { language == .chinese ? "设置已保存。" : "Settings Saved." }
  var agentPresetCreated: String { language == .chinese ? "智能体预设已创建。" : "Agent Preset Created." }
  var agentPresetDeleted: String { language == .chinese ? "智能体预设已删除。" : "Agent Preset Deleted." }
  var settingsConflict: String {
    language == .chinese
      ? "设置已被其他窗口更新，请重新选择后再保存。"
      : "Settings were updated in another window. Select the value again before saving."
  }
  func settingsSaveFailed(_ reason: String) -> String {
    language == .chinese ? "保存失败：\(reason)" : "Save Failed: \(reason)"
  }
  func agentPresetReadFailed(_ reason: String) -> String {
    language == .chinese ? "无法读取智能体预设：\(reason)" : "Could Not Read Agent Presets: \(reason)"
  }
  var appIconLoadFailed: String {
    language == .chinese ? "无法载入 Rabbisir 应用图标" : "Could Not Load the Rabbisir App Icon"
  }
  var mainScreenUnavailable: String {
    language == .chinese ? "无法识别 macOS 主屏幕" : "Could Not Identify the Main macOS Display"
  }
  var noWindowCreated: String {
    language == .chinese
      ? "Rabbisir 未创建窗口，请检查显示器连接后重试。"
      : "Rabbisir could not create a window. Check the display connection and try again."
  }
  var launchPreviewUnavailable: String {
    language == .chinese ? "无法打开 Rabbisir 启动页预览" : "Could Not Open the Rabbisir Launch Preview"
  }
  var internalWorkspaceUnavailable: String {
    language == .chinese
      ? "Rabbisir 暂时无法准备内部工作区。请稍后重试。"
      : "Rabbisir could not prepare its internal workspace. Try again shortly."
  }
  var internalRuntimeUnavailable: String {
    language == .chinese
      ? "Rabbisir 的内置运行时暂时不可用。请重试。"
      : "The Rabbisir built-in runtime is temporarily unavailable. Try again."
  }
  var exitLaunchPreview: String { language == .chinese ? "退出启动页预览" : "Exit Launch Preview" }
  var sessionLogUnavailable: String {
    language == .chinese ? "Session Log 当前不可用" : "Session Log Is Currently Unavailable"
  }
  var sessionLogRejected: String {
    language == .chinese
      ? "当前会话未接受本次 Session Log 导出请求。"
      : "The current conversation did not accept the Session Log export request."
  }
  var sessionZIPDownloadFailed: String {
    language == .chinese ? "Session ZIP 下载失败" : "Session ZIP Download Failed"
  }
  var downloadsUnavailable: String {
    language == .chinese
      ? "无法访问当前用户的 Downloads 文件夹。" : "Could Not Access the Current User's Downloads Folder."
  }
  var downloadingSessionZIP: String {
    language == .chinese ? "正在下载 Session ZIP 文件…" : "Downloading Session ZIP…"
  }
  var okay: String { language == .chinese ? "好" : "OK" }
  func sessionZIPSaved(_ filename: String) -> String {
    language == .chinese
      ? "Session ZIP 已保存到 Downloads：\(filename)" : "Session ZIP Saved to Downloads: \(filename)"
  }
  var navigationLoadFailed: String {
    language == .chinese ? "无法读取项目与会话数据" : "Could Not Load Projects and Conversations"
  }
  var currentConversationTitle: String {
    language == .chinese ? "当前 Rabbisir 会话" : "Current Rabbisir Conversation"
  }
  var runtimePreparing: String { language == .chinese ? "正在准备运行时" : "Preparing Runtime" }
  var runtimeReady: String { language == .chinese ? "运行时已载入" : "Runtime Loaded" }
  func runtimeUnavailable(_ message: String) -> String {
    language == .chinese ? "运行时不可用：\(message)" : "Runtime Unavailable: \(message)"
  }
  var resizePanelWidth: String { language == .chinese ? "调整面板宽度" : "Resize Panel Width" }
  var resizePanelWidthHelp: String {
    language == .chinese
      ? "水平拖动以调整宽度；双击恢复默认宽度"
      : "Drag horizontally to resize; double-click to restore the default width"
  }
  var resizeInProgress: String { language == .chinese ? "正在调整" : "Resizing" }
  var resizeAvailable: String { language == .chinese ? "可调整" : "Resizable" }
  var resizeSidebarWidth: String {
    language == .chinese ? "调整项目与对话栏宽度" : "Resize Projects and Conversations Sidebar"
  }
  var resizeConversationWidth: String {
    language == .chinese ? "调整对话区宽度" : "Resize Conversation Area"
  }
  var resizeDetailsWidth: String { language == .chinese ? "调整详情区宽度" : "Resize Details Panel" }
  func runDuration(seconds: TimeInterval) -> String {
    let wholeSeconds = max(0, Int(seconds.rounded(.down)))
    let minutes = wholeSeconds / 60
    let seconds = wholeSeconds % 60
    switch language {
    case .chinese:
      return minutes > 0 ? "耗时 \(minutes)分\(seconds)秒" : "耗时 \(seconds)秒"
    case .english:
      return minutes > 0 ? "\(minutes)m \(seconds)s" : "\(seconds)s"
    }
  }
  var artifactUnavailableToSave: String {
    language == .chinese ? "当前文件暂时无法保存。" : "This file cannot be saved right now."
  }
  var artifactSaveFailed: String {
    language == .chinese ? "保存文件失败，请刷新后重试。" : "Could not save the file. Refresh and try again."
  }
  var artifactUnavailableToOpen: String {
    language == .chinese ? "当前文件暂时无法在外部打开。" : "This file cannot be opened externally right now."
  }
  var artifactOpenFailed: String {
    language == .chinese
      ? "在外部打开文件失败，请稍后重试。" : "Could not open the file externally. Try again later."
  }
  var artifactUnavailableToRefresh: String {
    language == .chinese ? "当前文件暂时无法刷新。" : "This file cannot be refreshed right now."
  }
  var artifactRefreshFailed: String {
    language == .chinese ? "刷新文件失败，请稍后重试。" : "Could not refresh the file. Try again later."
  }
  var unknownBrowserControlError: String {
    language == .chinese ? "未知控制错误" : "Unknown Control Error"
  }
  var composerLoadingWorkspace: String { language == .chinese ? "正在读取工作区" : "Loading Workspace" }
  var composerLoadingAgentPreset: String {
    language == .chinese ? "正在读取智能体预设" : "Loading Agent Preset"
  }
  var composerLoadingModel: String {
    language == .chinese ? "正在读取会话模型" : "Loading Conversation Model"
  }
  var composerLoadingPermission: String {
    language == .chinese ? "正在读取访问权限" : "Loading Access Permission"
  }
  var brandLogoMissing: String {
    language == .chinese
      ? "Rabbisir Logo 未包含在应用资源中。" : "The Rabbisir logo is missing from the app resources."
  }
  var brandLogoUnreadable: String {
    language == .chinese
      ? "Rabbisir Logo 资源无法解码。" : "The Rabbisir logo resource could not be decoded."
  }
  var brandIconMissing: String {
    language == .chinese
      ? "Rabbisir AppIcon 未包含在应用资源中。" : "The Rabbisir app icon is missing from the app resources."
  }
  var brandIconUnreadable: String {
    language == .chinese
      ? "Rabbisir AppIcon 资源无法解码。" : "The Rabbisir app icon resource could not be decoded."
  }
  func runtimeManifestUnsupported(_ version: Int) -> String {
    language == .chinese
      ? "Rabbisir 无法读取内置运行时清单版本 \(version)。"
      : "Rabbisir cannot read built-in runtime manifest version \(version)."
  }
  func runtimeVersionMismatch(expected: String, actual: String) -> String {
    language == .chinese
      ? "内置运行时版本不匹配（需要 \(expected)，实际 \(actual)）。"
      : "Built-in runtime version mismatch (expected \(expected), found \(actual))."
  }
  var runtimeManifestMissing: String {
    language == .chinese
      ? "Rabbisir 的内置运行时清单缺失。请重新构建应用。"
      : "The Rabbisir built-in runtime manifest is missing. Rebuild the app."
  }
  var runtimeManifestInvalid: String {
    language == .chinese
      ? "Rabbisir 的内置运行时清单无效。请重新构建应用。"
      : "The Rabbisir built-in runtime manifest is invalid. Rebuild the app."
  }
  var runtimeComponentMissing: String {
    language == .chinese
      ? "Rabbisir 的内置运行时组件不完整。请重新构建应用。"
      : "The Rabbisir built-in runtime is incomplete. Rebuild the app."
  }
  var runtimeProvenanceInvalid: String {
    language == .chinese
      ? "Rabbisir 无法验证内置运行时的完整性。请重新构建应用。"
      : "Rabbisir could not verify the built-in runtime integrity. Rebuild the app."
  }
  var runtimeFailedToLaunch: String {
    language == .chinese
      ? "Rabbisir 无法启动内置运行时。请重试。" : "Rabbisir could not start its built-in runtime. Try again."
  }
  var runtimeExitedBeforeReady: String {
    language == .chinese
      ? "Rabbisir 的内置运行时在准备完成前退出。请重试。"
      : "The Rabbisir built-in runtime exited before it was ready. Try again."
  }
  var runtimeReadinessTimedOut: String {
    language == .chinese
      ? "Rabbisir 的内置运行时未能及时就绪。请重试。"
      : "The Rabbisir built-in runtime did not become ready in time. Try again."
  }
  var runtimeHealthCheckFailed: String {
    language == .chinese
      ? "Rabbisir 无法确认内置运行时状态。请重试。" : "Rabbisir could not verify its built-in runtime. Try again."
  }
  var runtimeStopped: String {
    language == .chinese ? "Rabbisir 的内置运行时已停止。" : "The Rabbisir built-in runtime has stopped."
  }
  var runtimeStoppedUnexpectedly: String {
    language == .chinese
      ? "Rabbisir 的内置运行时意外停止。" : "The Rabbisir built-in runtime stopped unexpectedly."
  }
  enum ConversationOperation: Sendable {
    case loadEarlier, loadImage, openFile, fork, load, connect, sync
  }
  func conversationOperation(_ operation: ConversationOperation) -> String {
    switch (language, operation) {
    case (.chinese, .loadEarlier): "载入更早消息"
    case (.english, .loadEarlier): "Load Earlier Messages"
    case (.chinese, .loadImage): "载入图片"
    case (.english, .loadImage): "Load Image"
    case (.chinese, .openFile): "打开文件"
    case (.english, .openFile): "Open File"
    case (.chinese, .fork): "创建对话分支"
    case (.english, .fork): "Create Conversation Branch"
    case (.chinese, .load): "载入会话"
    case (.english, .load): "Load Conversation"
    case (.chinese, .connect): "连接实时会话"
    case (.english, .connect): "Connect Live Conversation"
    case (.chinese, .sync): "同步会话"
    case (.english, .sync): "Sync Conversation"
    }
  }
  func conversationOperationFailed(_ operation: ConversationOperation, reason: String? = nil)
    -> String
  {
    let name = conversationOperation(operation)
    return switch (language, reason) {
    case (.chinese, .some(let reason)): "\(name)失败：\(reason)"
    case (.english, .some(let reason)): "\(name) Failed: \(reason)"
    case (.chinese, .none): "\(name)失败，请稍后重试。"
    case (.english, .none): "\(name) Failed. Try again later."
    }
  }
  var liveConversationInterrupted: String {
    language == .chinese ? "实时更新暂时中断，正在重新连接。" : "Live updates were interrupted. Reconnecting."
  }
  func liveConversationError(_ message: String) -> String {
    language == .chinese ? "实时会话错误：\(message)" : "Live Conversation Error: \(message)"
  }
  var liveConversationSyncUnavailable: String {
    language == .chinese
      ? "实时会话同步暂时不可用，正在等待重新连接。"
      : "Live conversation sync is temporarily unavailable. Waiting to reconnect."
  }
  var conversationImageFallback: String { language == .chinese ? "图片" : "Image" }
  func conversationQueueCount(_ count: Int) -> String {
    language == .chinese ? "待处理消息 \(count) 条" : "\(count) Queued Message\(count == 1 ? "" : "s")"
  }
  var conversationQueueEdit: String { language == .chinese ? "编辑排队消息" : "Edit Queued Message" }
  var conversationQueueSave: String { language == .chinese ? "保存" : "Save" }
  var conversationQueueEditUnavailable: String {
    language == .chinese ? "含图片的排队消息不能在此编辑" : "Queued messages with images cannot be edited here"
  }
  var conversationQueueRemove: String { language == .chinese ? "移除排队消息" : "Remove Queued Message" }
  var conversationQueueSteer: String { language == .chinese ? "引导当前轮次" : "Steer Current Turn" }
  var conversationQueueSteering: String {
    language == .chinese ? "正在引导当前轮次" : "Steering Current Turn"
  }
  var conversationApprovalTitle: String { language == .chinese ? "需要你的批准" : "Approval Required" }
  var conversationAllowOnce: String { language == .chinese ? "仅允许这一次" : "Allow Once" }
  var conversationReject: String { language == .chinese ? "拒绝" : "Reject" }
  var conversationQuestionTitle: String {
    language == .chinese ? "需要你的选择" : "Your Input Is Required"
  }
  var conversationQuestionOther: String { language == .chinese ? "其他回答" : "Other Answer" }
  var conversationQuestionSubmit: String { language == .chinese ? "提交回答" : "Submit Answers" }
  var conversationRetryingModel: String {
    language == .chinese ? "正在重试模型请求" : "Retrying Model Request"
  }
  var conversationWaitingToRetryModel: String {
    language == .chinese ? "等待重试模型请求" : "Waiting to Retry Model Request"
  }
  func conversationCompacted(itemCount: Int, tokenCount: Int) -> String {
    language == .chinese
      ? "已压缩 \(itemCount) 条历史记录（约 \(tokenCount) tokens）"
      : "Compacted \(itemCount) history items (about \(tokenCount) tokens)"
  }
  var conversationContextCompacted: String { language == .chinese ? "上下文已压缩" : "Context Compacted" }
  var conversationOutputLimitReached: String {
    language == .chinese ? "已达到输出 token 上限" : "Output Token Limit Reached"
  }
  var conversationOutputLimitDetail: String {
    language == .chinese
      ? "回答被截断，已有输出保留在对话中。发送“继续”可让模型接着输出。"
      : "The reply was truncated and existing output remains in the conversation. Send “continue” to resume."
  }
  var conversationRunFailed: String { language == .chinese ? "本轮运行失败" : "This Run Failed" }
  func toolTitle(_ toolName: String) -> String {
    switch (language, toolName) {
    case (_, "bash"): "Bash"
    case (_, "pwsh"): "Pwsh"
    case (.chinese, "read"): "读取"
    case (.english, "read"): "Read"
    case (.chinese, "web_fetch"): "获取网页"
    case (.english, "web_fetch"): "Fetch"
    case (.chinese, "web_search"): "搜索"
    case (.english, "web_search"): "Search"
    case (_, "grep"): "Grep"
    case (_, "glob"): "Glob"
    case (.chinese, "write"): "写入"
    case (.english, "write"): "Write"
    case (.chinese, "edit"): "编辑"
    case (.english, "edit"): "Edit"
    case (.chinese, "run_code"): "运行代码"
    case (.english, "run_code"): "Code"
    case (.chinese, "cordis_package_inspect"), (.chinese, "cordis_runtime_inspect"): "检查"
    case (.english, "cordis_package_inspect"), (.english, "cordis_runtime_inspect"): "Inspect"
    case (.chinese, "cordis_run"): "运行 Cordis 插件"
    case (.english, "cordis_run"): "Run Cordis Plugin"
    case (.chinese, "cordis_stop"): "停止 Cordis 插件"
    case (.english, "cordis_stop"): "Stop Cordis Plugin"
    case (.chinese, "cordis_undefine"): "移除 Cordis 插件"
    case (.english, "cordis_undefine"): "Remove Cordis Plugin"
    case (.chinese, _): "工具调用"
    case (.english, _): "Tool Call"
    }
  }
  var communityDisclaimer: String {
    language == .chinese ? "独立、非官方的社区增强版本。" : "Independent, non-official community enhancement."
  }
  var aboutAttributions: [String] {
    switch language {
    case .chinese:
      ["基于 DeepSeek Harness", "核心持续跟随 DeepSeek Harness。"]
    case .english:
      [RabbisirAppIdentity.upstreamAttribution, RabbisirAppIdentity.coreAttribution]
    }
  }
  func aboutVersion(shortVersion: String, buildVersion: String) -> String {
    language == .chinese
      ? "版本 \(shortVersion) · 构建 \(buildVersion)"
      : "Version \(shortVersion) · Build \(buildVersion)"
  }
  var aboutCopyright: String {
    language == .chinese
      ? "版权所有 © 2026 YelZap。保留所有权利。"
      : "Copyright © 2026 YelZap. All rights reserved."
  }
  func aboutAccessibility(
    version: String,
    attributions: [String],
    copyrightText: String
  ) -> String {
    "\(self[.about]), \(version), \(attributions.joined(separator: ", ")), \(communityDisclaimer), \(copyrightText)"
  }

  var plugins: RabbisirPluginCopy { RabbisirPluginCopy.resolve(language: language) }
  var agentPresets: RabbisirAgentPresetCopy { RabbisirAgentPresetCopy.resolve(language: language) }
  var artifacts: RabbisirArtifactCopy { RabbisirArtifactCopy.resolve(language: language) }
  var launch: RabbisirLaunchCopy { RabbisirLaunchCopy.resolve(language: language) }
  var navigationDialogs: RabbisirNavigationDialogCopy {
    RabbisirNavigationDialogCopy.resolve(language: language)
  }
  var menuBar: RabbisirMenuBarCopy { RabbisirMenuBarCopy.resolve(language: language) }
}

struct RabbisirMenuBarCopy: Equatable, Sendable {
  let language: RabbisirInterfaceLanguage
  let browserControl: String
  let browserIdle: String
  let browserActive: String
  let browserFailed: String
  let browserIdleDetail: String
  let browserActiveDetail: String
  let islandAccessibility: String

  static func resolve(language: RabbisirInterfaceLanguage) -> Self {
    switch language {
    case .chinese:
      Self(
        language: .chinese, browserControl: "浏览器控制",
        browserIdle: "即将推出", browserActive: "控制进行中", browserFailed: "控制失败",
        browserIdleDetail: "内置浏览器控制即将开放。", browserActiveDetail: "用户已发起浏览器控制，控制正在进行。",
        islandAccessibility: "Rabbisir 菜单栏交互岛")
    case .english:
      Self(
        language: .english, browserControl: "Browser Control", browserIdle: "Coming Soon",
        browserActive: "Control in Progress", browserFailed: "Control Failed",
        browserIdleDetail: "Built-in browser control is coming soon.",
        browserActiveDetail: "Browser control has been requested and is in progress.",
        islandAccessibility: "Rabbisir Menu Bar Controls")
    }
  }

  func browserFailureDetail(_ reason: String) -> String {
    switch language {
    case .chinese: "本次浏览器控制明确失败：\(reason)"
    case .english: "This browser-control attempt failed: \(reason)"
    }
  }

  func browserAccessibilityStatus(phase: BrowserControlPhase) -> String {
    switch phase {
    case .idle: browserIdle
    case .active: language == .chinese ? "进行中" : "In Progress"
    case .failed(let reason): language == .chinese ? "失败，\(reason)" : "Failed, \(reason)"
    }
  }

}

struct RabbisirNavigationDialogCopy: Equatable, Sendable {
  let editProject: String
  let projectName: String
  let projectRenameNote: String
  let deleteProjectNote: String
  let renameSession: String
  let sessionName: String
  let sessionRenameNote: String

  static func resolve(language: RabbisirInterfaceLanguage) -> Self {
    switch language {
    case .chinese:
      Self(
        editProject: "编辑项目名称", projectName: "项目名称", projectRenameNote: "名称会写回当前工作区。",
        deleteProjectNote: "此操作会从 Rabbisir 项目列表中移除该工作区，且不能一键撤销。项目目录和现有会话日志不会被删除；之后可重新添加目录。",
        renameSession: "重命名会话", sessionName: "会话名称", sessionRenameNote: "名称会写回当前会话。")
    case .english:
      Self(
        editProject: "Edit Project Name", projectName: "Project Name",
        projectRenameNote: "The name will be saved to the current workspace.",
        deleteProjectNote:
          "This removes the workspace from the Rabbisir project list and cannot be undone in one click. The project directory and existing conversation logs are not deleted; the directory can be added again later.",
        renameSession: "Rename Conversation", sessionName: "Conversation Name",
        sessionRenameNote: "The name will be saved to the current conversation.")
    }
  }
}

struct RabbisirPluginCopy: Equatable, Sendable {
  let pageTitle: String
  let pageSubtitle: String
  let viewLabel: String
  let configuration: String
  let inventory: String
  let noEditableSettings: String
  let terminalTitle: String
  let terminalDescription: String
  let timeoutLabel: String
  let timeoutHint: String
  let outputLimitLabel: String
  let outputLimitHint: String
  let agentLoopTitle: String
  let agentLoopDescription: String
  let parallelCallsLabel: String
  let parallelCallsHint: String
  let webSearchTitle: String
  let webSearchDescription: String
  let baseURLLabel: String
  let baseURLHint: String
  let maxUsesLabel: String
  let maxUsesHint: String
  let unsaved: String
  let expand: String
  let collapse: String
  let readOnly: String
  let discardChanges: String
  let saving: String
  let configured: String
  let notConfigured: String
  let enterAPIKey: String
  let credentialNote: String
  let overridden: String
  let restoreDefault: String
  let numberValidation: String
  let saved: String
  let search: String
  let readFailurePrefix: String
  let none: String
  let noMatches: String
  let enabled: String
  let disabled: String
  let configurationStatus: String
  let cordisStatus: String
  let pending: String
  let loading: String
  let active: String
  let failed: String
  let unloading: String
  let unmounted: String

  static func resolve(language: RabbisirInterfaceLanguage) -> Self {
    switch language {
    case .chinese:
      Self(
        pageTitle: "插件", pageSubtitle: "配置并查看 Rabbisir 当前安装的插件。", viewLabel: "插件视图",
        configuration: "插件配置", inventory: "插件列表", noEditableSettings: "当前没有可编辑的插件设置。",
        terminalTitle: "终端", terminalDescription: "限制 Agent 运行的每一条命令。",
        timeoutLabel: "命令超时（毫秒）", timeoutHint: "单条命令允许运行多久，超时即终止。",
        outputLimitLabel: "单流输出上限（字节）", outputLimitHint: "超出部分会转存到临时文件，而不是被丢弃。",
        agentLoopTitle: "Agent 循环", agentLoopDescription: "Agent 如何派发工具调用。",
        parallelCallsLabel: "并行工具调用数", parallelCallsHint: "同一步内最多同时运行多少个可并行的调用。",
        webSearchTitle: "网页搜索", webSearchDescription: "DeepSeek 搜索提供方。",
        baseURLLabel: "接口地址", baseURLHint: "留空则使用提供方默认地址。",
        maxUsesLabel: "单次请求最多搜索次数", maxUsesHint: "一次请求在必须作答前最多可以搜索多少次。",
        unsaved: "未保存", expand: "展开", collapse: "收起", readOnly: "当前设置为只读。",
        discardChanges: "放弃修改", saving: "保存中…", configured: "已配置", notConfigured: "未配置",
        enterAPIKey: "输入新的 API Key；留空保持当前值", credentialNote: "在 Rabbisir 中安全配置；已有 Key 不会显示。",
        overridden: "已覆盖", restoreDefault: "恢复默认", numberValidation: "请填数字；留空表示使用默认值。",
        saved: "插件设置已保存。", search: "搜索插件", readFailurePrefix: "暂时无法读取插件：",
        none: "暂无插件。", noMatches: "没有匹配的插件。", enabled: "已启用", disabled: "已停用",
        configurationStatus: "配置状态", cordisStatus: "Cordis 状态", pending: "等待依赖", loading: "加载中",
        active: "已挂载", failed: "挂载失败", unloading: "卸载中", unmounted: "未挂载"
      )
    case .english:
      Self(
        pageTitle: "Plugins",
        pageSubtitle: "Configure and inspect the plugins currently installed in Rabbisir.",
        viewLabel: "Plugin View",
        configuration: "Configuration", inventory: "Plugin List",
        noEditableSettings: "No editable plugin settings are currently available.",
        terminalTitle: "Terminal", terminalDescription: "Limit each command run by the Agent.",
        timeoutLabel: "Command Timeout (ms)",
        timeoutHint: "How long a command may run before it is terminated.",
        outputLimitLabel: "Per-stream Output Limit (bytes)",
        outputLimitHint: "Overflow is saved to a temporary file instead of being discarded.",
        agentLoopTitle: "Agent Loop", agentLoopDescription: "How the Agent dispatches tool calls.",
        parallelCallsLabel: "Parallel Tool Calls",
        parallelCallsHint: "Maximum number of parallel calls allowed within one step.",
        webSearchTitle: "Web Search", webSearchDescription: "DeepSeek search provider.",
        baseURLLabel: "Endpoint", baseURLHint: "Leave blank to use the provider default.",
        maxUsesLabel: "Maximum Searches per Request",
        maxUsesHint: "Maximum number of searches allowed before the request must be answered.",
        unsaved: "Unsaved", expand: "Expand", collapse: "Collapse",
        readOnly: "These settings are read-only.",
        discardChanges: "Discard Changes", saving: "Saving…", configured: "Configured",
        notConfigured: "Not Configured",
        enterAPIKey: "Enter a new API Key; leave blank to keep the current value",
        credentialNote: "Stored securely in Rabbisir; an existing key is never displayed.",
        overridden: "Overridden", restoreDefault: "Restore Default",
        numberValidation: "Enter a number, or leave blank to use the default.",
        saved: "Plugin settings saved.", search: "Search Plugins",
        readFailurePrefix: "Could not read plugins:",
        none: "No plugins are available.", noMatches: "No matching plugins.", enabled: "Enabled",
        disabled: "Disabled",
        configurationStatus: "Configuration Status", cordisStatus: "Cordis Status",
        pending: "Waiting for Dependencies", loading: "Loading",
        active: "Mounted", failed: "Mount Failed", unloading: "Unloading", unmounted: "Not Mounted"
      )
    }
  }
}

struct RabbisirAgentPresetCopy: Equatable, Sendable {
  let language: RabbisirInterfaceLanguage
  let pageTitle: String
  let pageSubtitle: String
  let none: String
  let builtIn: String
  let custom: String
  let deleteTitle: String
  let deleteMessage: String
  let noCustom: String
  let cannotCreate: String
  let current: String
  let loadFailed: String
  let setDefault: String
  let view: String
  let openDirectory: String
  let viewPath: String
  let presetFilePrefix: String
  let noDescription: String
  let assembly: String
  let copyTitlePrefix: String
  let copyDescription: String
  let identifierPlaceholder: String
  let namePlaceholder: String
  let identifierRequired: String
  let identifierInvalid: String
  let identifierUsed: String

  static func resolve(language: RabbisirInterfaceLanguage) -> Self {
    switch language {
    case .chinese:
      Self(
        language: .chinese, pageTitle: "智能体预设", pageSubtitle: "预设决定新会话使用的工具、提示词与能力；运行中的会话保持启动时的预设。",
        none: "当前没有可用的智能体预设。", builtIn: "内置", custom: "自定义", deleteTitle: "删除该预设？",
        deleteMessage: "预设目录将被删除。已使用它运行的会话不受影响；新会话将无法再选择它。", noCustom: "暂无自定义预设。",
        cannotCreate: "当前不可创建自定义预设。", current: "当前使用", loadFailed: "加载失败", setDefault: "设为默认",
        view: "查看", openDirectory: "打开目录", viewPath: "查看路径", presetFilePrefix: "预设文件：",
        noDescription: "暂无描述。", assembly: "组装（agent.cordis.yml）", copyTitlePrefix: "复制预设 · ",
        copyDescription: "整个预设会在本机复制一份。标识符将成为目录名，创建后无法修改。",
        identifierPlaceholder: "标识符（例如 my-agent）", namePlaceholder: "名称（可选）",
        identifierRequired: "请填写标识符。", identifierInvalid: "只能使用小写字母、数字与连字符，且以字母或数字开头。",
        identifierUsed: "该标识符已被占用。")
    case .english:
      Self(
        language: .english, pageTitle: "Agent Presets",
        pageSubtitle:
          "Presets determine the tools, prompts, and capabilities used by new conversations. Running conversations keep the preset they started with.",
        none: "No Agent presets are currently available.", builtIn: "Built-in", custom: "Custom",
        deleteTitle: "Delete This Preset?",
        deleteMessage:
          "The preset directory will be deleted. Existing conversations are unaffected; new conversations can no longer select it.",
        noCustom: "No custom presets.", cannotCreate: "Custom presets cannot currently be created.",
        current: "Current", loadFailed: "Load Failed", setDefault: "Set as Default", view: "View",
        openDirectory: "Open Directory", viewPath: "View Path", presetFilePrefix: "Preset File: ",
        noDescription: "No description.", assembly: "Assembly (agent.cordis.yml)",
        copyTitlePrefix: "Copy Preset · ",
        copyDescription:
          "A local copy of the entire preset will be created. Its identifier becomes the directory name and cannot be changed later.",
        identifierPlaceholder: "Identifier (for example, my-agent)",
        namePlaceholder: "Name (optional)", identifierRequired: "Enter an identifier.",
        identifierInvalid:
          "Use lowercase letters, numbers, and hyphens, beginning with a letter or number.",
        identifierUsed: "That identifier is already in use.")
    }
  }

  func builtInName(id: String, fallback: String) -> String {
    switch (language, id) {
    case (.chinese, "standard"): "标准模式"
    case (.english, "standard"): "Standard Mode"
    case (.chinese, "code"): "PTC 模式"
    case (.english, "code"): "PTC Mode"
    case (.chinese, "minimal"): "极简模式"
    case (.english, "minimal"): "Minimal Mode"
    case (.chinese, "cordis"): "创造模式"
    case (.english, "cordis"): "Creative Mode"
    default: fallback
    }
  }

  func localizedName(_ sourceName: String) -> String {
    guard let id = Self.builtInID(forName: sourceName) else { return sourceName }
    return builtInName(id: id, fallback: sourceName)
  }

  func builtInDescription(id: String, fallback: String) -> String {
    switch (language, id) {
    case (.chinese, "standard"):
      "功能完整的编码 Agent，支持文件编辑、Shell、文件与网页检索、Skills、计划、目标、子代理和工作流。"
    case (.english, "standard"):
      "A full-featured coding Agent with file editing, Shell, file and web search, Skills, plans, goals, subagents, and workflows."
    case (.chinese, "code"):
      "具备标准模式的全部能力，并通过 Code Mode SDK 呈现工具，让模型用一个 TypeScript 程序组合多步操作。"
    case (.english, "code"):
      "Includes every Standard Mode capability and presents tools through the Code Mode SDK, allowing the model to combine multiple steps in one TypeScript program."
    case (.chinese, "minimal"):
      "仅提供持久 bash 与 str_replace_editor 的双工具编码 Agent。"
    case (.english, "minimal"):
      "A two-tool coding Agent providing only persistent bash and str_replace_editor."
    case (.chinese, "cordis"):
      "用于创建自定义 Agent preset：具备标准模式的全部能力，并提供运行时检查、插件实验和 preset 创作指导。"
    case (.english, "cordis"):
      "Creates custom Agent presets with every Standard Mode capability, runtime inspection, plugin experimentation, and preset authoring guidance."
    default:
      fallback
    }
  }

  func localizedDescription(_ sourceDescription: String) -> String {
    guard let id = Self.builtInID(forDescription: sourceDescription) else {
      return sourceDescription
    }
    return builtInDescription(id: id, fallback: sourceDescription)
  }

  private static func builtInID(forName name: String) -> String? {
    switch name {
    case "标准模式", "Standard Mode": "standard"
    case "PTC 模式", "PTC Mode": "code"
    case "极简模式", "Minimal Mode": "minimal"
    case "创造模式", "Creative Mode": "cordis"
    default: nil
    }
  }

  private static func builtInID(forDescription description: String) -> String? {
    switch description {
    case "功能完整的编码 Agent，支持文件编辑、Shell、文件与网页检索、Skills、计划、目标、子代理和工作流。",
      "A full-featured coding Agent with file editing, Shell, file and web search, Skills, plans, goals, subagents, and workflows.":
      "standard"
    case "具备标准模式的全部能力，并通过 Code Mode SDK 呈现工具，让模型用一个 TypeScript 程序组合多步操作。",
      "Includes every Standard Mode capability and presents tools through the Code Mode SDK, allowing the model to combine multiple steps in one TypeScript program.":
      "code"
    case "仅提供持久 bash 与 str_replace_editor 的双工具编码 Agent。",
      "A two-tool coding Agent providing only persistent bash and str_replace_editor.":
      "minimal"
    case "用于创建自定义 Agent preset：具备标准模式的全部能力，并提供运行时检查、插件实验和 preset 创作指导。",
      "Creates custom Agent presets with every Standard Mode capability, runtime inspection, plugin experimentation, and preset authoring guidance.":
      "cordis"
    default:
      nil
    }
  }

}

struct RabbisirArtifactCopy: Equatable, Sendable {
  let workspace: String
  let viewPicker: String
  let saving: String
  let refreshing: String
  let plainView: String
  let markdownPreview: String
  let editor: String
  let exportFailed: String
  let editMode: String
  let plainMode: String
  let markdownMode: String
  let documentMode: String
  let pdfMode: String
  let documentPreview: String
  let pdfPreview: String
  let unsavedSwitchTitle: String
  let unsavedSwitchMessage: String
  let saveAndSwitch: String
  let discardAndSwitch: String
  let reloadDiscardTitle: String
  let reloadDiscardMessage: String
  let discardAndReload: String

  static func resolve(language: RabbisirInterfaceLanguage) -> Self {
    switch language {
    case .chinese:
      Self(
        workspace: "文件工作区", viewPicker: "文件视图", saving: "正在保存", refreshing: "正在刷新",
        plainView: "纯文本视图", markdownPreview: "Markdown 预览", editor: "文档编辑器",
        exportFailed: "导出文件失败，请重新选择保存位置。", editMode: "编辑", plainMode: "纯文本",
        markdownMode: "Markdown 版式", documentMode: "文稿", pdfMode: "PDF 版式", documentPreview: "文稿预览",
        pdfPreview: "PDF 预览", unsavedSwitchTitle: "保留未保存的修改？",
        unsavedSwitchMessage: "当前文档有未保存的修改。保存或放弃修改后才能切换文档。",
        saveAndSwitch: "保存并切换", discardAndSwitch: "放弃并切换",
        reloadDiscardTitle: "放弃未保存的修改？",
        reloadDiscardMessage: "重新载入会用磁盘内容替换当前未保存的修改。",
        discardAndReload: "放弃并重新载入")
    case .english:
      Self(
        workspace: "File Workspace", viewPicker: "File View", saving: "Saving",
        refreshing: "Refreshing", plainView: "Plain Text View", markdownPreview: "Markdown Preview",
        editor: "Document Editor",
        exportFailed: "Could not export the file. Choose another save location.", editMode: "Edit",
        plainMode: "Plain Text", markdownMode: "Markdown", documentMode: "Document", pdfMode: "PDF",
        documentPreview: "Document Preview", pdfPreview: "PDF Preview",
        unsavedSwitchTitle: "Keep Unsaved Changes?",
        unsavedSwitchMessage:
          "The current document has unsaved changes. Save or discard them before switching documents.",
        saveAndSwitch: "Save and Switch", discardAndSwitch: "Discard and Switch",
        reloadDiscardTitle: "Discard Unsaved Changes?",
        reloadDiscardMessage:
          "Reloading replaces the current unsaved changes with the content on disk.",
        discardAndReload: "Discard and Reload")
    }
  }
}

struct RabbisirLaunchCopy: Equatable, Sendable {
  let preview: String
  let exitPreview: String
  let exitPreviewHint: String
  let retry: String
  let retryHint: String
  let starting: String
  let progress: String
  let logo: String
  let loadingBrandAsset: String
  let brandAssetReady: String
  let workspaceReady: String
  let runtimeReady: String
  let completed: String
  let incomplete: String
  let panelAccessibility: String

  static func resolve(language: RabbisirInterfaceLanguage) -> Self {
    switch language {
    case .chinese:
      Self(
        preview: "启动页预览 · 固定进度", exitPreview: "退出预览", exitPreviewHint: "关闭 Rabbisir 启动页预览",
        retry: "重试", retryHint: "重新执行失败的启动阶段", starting: "Rabbisir 正在启动", progress: "Rabbisir 启动进度",
        logo: "Rabbisir 兔子 Logo", loadingBrandAsset: "正在载入 Rabbisir 资源", brandAssetReady: "品牌资源已就绪",
        workspaceReady: "原生工作区已准备", runtimeReady: "运行时已就绪", completed: "准备完成", incomplete: "启动未完成",
        panelAccessibility: "Rabbisir 启动进度")
    case .english:
      Self(
        preview: "Launch Preview · Fixed Progress", exitPreview: "Exit Preview",
        exitPreviewHint: "Close the Rabbisir launch preview", retry: "Retry",
        retryHint: "Retry the failed launch stage", starting: "Rabbisir Is Starting",
        progress: "Rabbisir Launch Progress", logo: "Rabbisir Rabbit Logo",
        loadingBrandAsset: "Loading Rabbisir Resources", brandAssetReady: "Brand Resources Ready",
        workspaceReady: "Native Workspace Ready", runtimeReady: "Runtime Ready", completed: "Ready",
        incomplete: "Launch Incomplete", panelAccessibility: "Rabbisir Launch Progress")
    }
  }
}

private struct RabbisirCopyEnvironmentKey: EnvironmentKey {
  static let defaultValue = RabbisirCopy(
    language: RabbisirInterfaceLanguage.resolve(preferredLanguages: Locale.preferredLanguages)
  )
}

extension EnvironmentValues {
  var rabbisirCopy: RabbisirCopy {
    get { self[RabbisirCopyEnvironmentKey.self] }
    set { self[RabbisirCopyEnvironmentKey.self] = newValue }
  }
}

struct RabbisirLocalizedRoot<Content: View>: View {
  @ObservedObject private var localization: RabbisirLocalization
  private let content: Content

  init(
    localization: RabbisirLocalization = .shared,
    @ViewBuilder content: () -> Content
  ) {
    self.localization = localization
    self.content = content()
  }

  var body: some View {
    content
      .environment(\.rabbisirCopy, RabbisirCopy(language: localization.language))
      .environment(\.locale, localization.language.locale)
  }
}

struct RabbisirApplicationMenuCopy: Equatable, Sendable {
  let settings: String
  let workspaceTour: String
  let showMainWindow: String
  let hideWorkspace: String
  let focusInput: String
  let quit: String
  let edit: String
  let undo: String
  let redo: String
  let cut: String
  let copy: String
  let paste: String
  let selectAll: String

  static func resolve(language: RabbisirInterfaceLanguage) -> Self {
    switch language {
    case .chinese:
      Self(
        settings: "设置…",
        workspaceTour: "重新打开界面导览",
        showMainWindow: "显示主窗口",
        hideWorkspace: "隐藏完整工作台",
        focusInput: "聚焦输入（⌃⌥Return）",
        quit: "退出 \(RabbisirAppIdentity.displayName)",
        edit: "编辑",
        undo: "撤销",
        redo: "重做",
        cut: "剪切",
        copy: "复制",
        paste: "粘贴",
        selectAll: "全选"
      )
    case .english:
      Self(
        settings: "Settings…",
        workspaceTour: "Show Interface Tour Again",
        showMainWindow: "Show Main Window",
        hideWorkspace: "Hide Workspace",
        focusInput: "Focus Input (⌃⌥Return)",
        quit: "Quit \(RabbisirAppIdentity.displayName)",
        edit: "Edit",
        undo: "Undo",
        redo: "Redo",
        cut: "Cut",
        copy: "Copy",
        paste: "Paste",
        selectAll: "Select All"
      )
    }
  }
}
