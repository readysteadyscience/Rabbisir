import AppKit
import Combine
import SwiftUI

enum RabbisirHelpTopic: String, CaseIterable, Identifiable, Sendable {
  case quickStart
  case workspace
  case projectsAndConversations
  case settingsAndLanguage
  case windowsAndDisplays
  case communityAndLicense
  case privacy
  case shortcuts
  case troubleshooting

  var id: String { rawValue }
}

struct RabbisirHelpGroup: Equatable, Identifiable, Sendable {
  let id: String
  let title: String
  let bullets: [String]
}

struct RabbisirHelpArticle: Equatable, Identifiable, Sendable {
  var id: RabbisirHelpTopic { topic }
  let topic: RabbisirHelpTopic
  let title: String
  let summary: String
  let groups: [RabbisirHelpGroup]
  let externalLinks: [URL]

  var plainText: String {
    ([title, summary] + groups.flatMap { [$0.title] + $0.bullets }).joined(separator: "\n")
  }
}

struct RabbisirHelpCatalog: Equatable, Sendable {
  let language: RabbisirInterfaceLanguage
  let articles: [RabbisirHelpArticle]

  init(language: RabbisirInterfaceLanguage) {
    self.language = language
    articles = Self.makeArticles(language: language)
  }

  func article(for topic: RabbisirHelpTopic) throws -> RabbisirHelpArticle {
    guard let article = articles.first(where: { $0.topic == topic }) else {
      throw RabbisirHelpCatalogError.missingTopic(topic)
    }
    return article
  }

  private static func makeArticles(
    language: RabbisirInterfaceLanguage
  ) -> [RabbisirHelpArticle] {
    switch language {
    case .chinese: chineseArticles
    case .english: englishArticles
    }
  }

  private static func article(
    _ topic: RabbisirHelpTopic,
    _ title: String,
    _ summary: String,
    _ groups: [(String, [String])],
    links: [URL] = []
  ) -> RabbisirHelpArticle {
    RabbisirHelpArticle(
      topic: topic,
      title: title,
      summary: summary,
      groups: groups.enumerated().map { index, group in
        RabbisirHelpGroup(
          id: "\(topic.rawValue).\(index)",
          title: group.0,
          bullets: group.1
        )
      },
      externalLinks: links
    )
  }

  private static let chineseArticles: [RabbisirHelpArticle] = [
    article(
      .quickStart,
      "快速开始",
      "先完成安全配置，再进入 Rabbisir 工作台。",
      [
        (
          "首次 API 配置",
          [
            "首次启动且没有可用配置时，只会显示独立的 API Key 配置窗口。",
            "填写 Key、保存并通过模型连通测试后，主工作台才会打开。失败时会停留在配置窗口。",
            "Rabbisir 不会在帮助、日志或界面中回显已保存的 Key。",
          ]
        ),
        (
          "第一次进入工作台",
          [
            "四步界面导览依次说明左侧导航、中间对话与输入、右侧详情和顶部灵动岛。",
            "可从帮助菜单或 App 菜单重新开始导览。",
          ]
        ),
      ]
    ),
    article(
      .workspace,
      "主工作台",
      "Rabbisir 使用互相协调的原生分体窗口，而不是单个网页界面。",
      [
        ("左侧", ["管理项目、文件夹关联与会话导航；悬停时显示当前可用操作。"]),
        ("中间", ["查看对话内容；在底部输入区发送消息并选择模型、推理、权限或命令选项。"]),
        ("右侧", ["查看会话产生的文稿、Markdown、PDF、图片或源码等详情内容。"]),
        ("顶部灵动岛", ["显示和隐藏工作台区域，并保持常用面板操作随时可达。"]),
      ]
    ),
    article(
      .projectsAndConversations,
      "项目、文件夹与对话",
      "导航操作以当前运行时提供的稳定项目和会话身份为准。",
      [
        (
          "项目",
          [
            "可添加工作区，展开项目后选择会话，并使用界面中实际启用的置顶、重命名、归档或移除操作。",
            "从 Rabbisir 移除项目只移除导航注册，不会删除对应的本地文件夹。",
          ]
        ),
        (
          "会话",
          [
            "可新建、选择、重命名、归档、分支或移动会话；不可用操作会保持禁用。",
            "会话存在工作目录时，可使用 Finder 入口；不要在求助时公开私有路径或会话内容。",
          ]
        ),
        ("输入", ["Return 发送；Shift-Return 插入换行。发送前确认当前项目、模型、推理和权限选项。"]),
      ]
    ),
    article(
      .settingsAndLanguage,
      "设置与语言",
      "设置窗口管理当前运行时可用的模型与偏好。",
      [
        ("设置", ["使用 Rabbisir 菜单中的“设置…”打开。需要运行时的设置项仅在运行时就绪后可用。"]),
        ("语言", ["从菜单栏的 Language / 语言菜单切换中文或英文；选择会在下次启动时恢复。"]),
        ("界面尺寸", ["侧栏、对话区、详情区和设置窗口的用户调整会在 DEV 的后续启动中恢复，并按当前屏幕安全约束。"]),
      ]
    ),
    article(
      .windowsAndDisplays,
      "窗口与多显示器",
      "“窗口”菜单列出当前 Mac 可用的显示器。",
      [
        ("移动全部界面", ["选择显示器后，Rabbisir 管理的工作台、设置、首配、About、帮助和导览会迁移到目标屏幕。"]),
        ("安全适配", ["窗口会按目标显示器的可见工作区重新布局，不会依赖显示器名称或把内部标识显示给用户。"]),
        ("显示器变化", ["连接、断开或参数变化时菜单会刷新；目标消失时会安全回到可用屏幕。"]),
      ]
    ),
    article(
      .communityAndLicense,
      "创作者、社区与反馈",
      "公开版保留清晰的创作者归属、社区入口、许可证与反馈渠道。",
      [
        ("创作者", ["Rabbisir 由 YelZap 创建；About 面板中的创作者入口指向 Rabbisir GitHub 仓库。"]),
        ("Discord 社区", ["About 面板中的社区入口指向 Rabbisir Discord。加入社区不授予发布或维护权限。"]),
        ("GitHub 反馈", ["可在 Rabbisir 仓库的 Issues 页面提交可复现的问题；不要附带 API Key、私有路径或完整会话。"]),
        ("许可证", ["Rabbisir 自有源码采用 MIT License；DeepSeek Harness 上游许可和归属独立记录，且不表示官方合作、赞助或背书。"]),
      ],
      links: [
        URL(string: "https://github.com/readysteadyscience/Rabbisir")!,
        URL(string: "https://github.com/readysteadyscience/Rabbisir/issues")!,
        URL(string: "https://discord.gg/gT4TUHGkQm")!,
      ]
    ),
    article(
      .privacy,
      "隐私与凭据安全",
      "只在 App 提供的安全配置界面中处理凭据。",
      [
        ("API Key", ["Rabbisir 通过运行时的只写凭据路径保存 Key，不显示、打印、导出或复制已保存值。"]),
        ("对话", ["界面只接收批准的用户可见内容；系统/开发者上下文、隐藏内容、原始工具载荷和未知节点不会进入可见对话。"]),
        ("求助", ["不要发送 Key、令牌、Cookie、私有路径、完整会话或含敏感内容的日志。"]),
      ]
    ),
    article(
      .shortcuts,
      "键盘快捷方式",
      "常用命令保持原生菜单和全局快捷键可达。",
      [
        ("全局", ["⌃⌥Space：显示或隐藏完整工作台。", "⌃⌥Return：显示工作台并聚焦输入区。"]),
        ("App", ["⌘,：打开设置。", "⌘0：显示主窗口。", "⌘H：隐藏工作台。", "⌘Q：退出 Rabbisir。"]),
        ("输入", ["Return：发送。", "Shift-Return：插入换行。"]),
      ]
    ),
    article(
      .troubleshooting,
      "常见问题",
      "先确认当前界面状态，再采用最小恢复动作。",
      [
        ("主窗口没有出现", ["若首次配置尚未成功，请留在配置窗口完成保存与连通测试。已有配置时可用 ⌃⌥Space 或“显示主窗口”。"]),
        ("窗口不在当前屏幕", ["打开“窗口”菜单并选择所需显示器；Rabbisir 会迁移全部受管窗口。"]),
        ("浏览器控制", ["即将推出。当前显示 Coming Soon，不会控制外部浏览器。"]),
      ]
    ),
  ]

  private static let englishArticles: [RabbisirHelpArticle] = [
    article(
      .quickStart,
      "Quick Start",
      "Complete secure configuration before entering the Rabbisir workspace.",
      [
        (
          "First API configuration",
          [
            "On first launch without a usable configuration, Rabbisir shows only the separate API Key setup window.",
            "Save the Key and pass the model connectivity test before the workspace can open. A failed test keeps setup visible.",
            "Rabbisir does not reveal a saved Key in help, logs, or the interface.",
          ]
        ),
        (
          "First workspace entry",
          [
            "The four-step tour introduces navigation, conversation and input, details, and the top island.",
            "Restart the tour from the Help menu or the application menu.",
          ]
        ),
      ]
    ),
    article(
      .workspace,
      "Workspace",
      "Rabbisir coordinates native spatial windows instead of presenting a single web page.",
      [
        (
          "Left",
          [
            "Navigate projects, folder associations, and conversations; hover to reveal actions that are currently available."
          ]
        ),
        (
          "Center",
          [
            "Read the conversation and send messages from the composer while choosing available model, reasoning, permission, or command options."
          ]
        ),
        (
          "Right",
          [
            "Inspect documents, Markdown, PDFs, images, source, and other details produced by the conversation."
          ]
        ),
        (
          "Top island",
          [
            "Show or hide workspace regions while keeping common panel controls available."
          ]
        ),
      ]
    ),
    article(
      .projectsAndConversations,
      "Projects, Folders, and Conversations",
      "Navigation follows stable project and conversation identities supplied by the current runtime.",
      [
        (
          "Projects",
          [
            "Add a workspace, expand a project, select a conversation, and use only the pin, rename, archive, or remove actions that are enabled.",
            "Removing a project from Rabbisir removes its navigation registration; it does not delete the local folder.",
          ]
        ),
        (
          "Conversations",
          [
            "Create, select, rename, archive, fork, or move conversations when the corresponding action is available.",
            "A conversation with a working directory can expose a Finder action. Do not share private paths or conversation content when asking for help.",
          ]
        ),
        (
          "Composer",
          [
            "Return sends and Shift-Return inserts a line break. Confirm the current project, model, reasoning, and permission before sending."
          ]
        ),
      ]
    ),
    article(
      .settingsAndLanguage,
      "Settings and Language",
      "Settings presents runtime-supported model preferences.",
      [
        (
          "Settings",
          [
            "Open Settings… from the Rabbisir menu. Runtime-backed settings are enabled only after the runtime is ready."
          ]
        ),
        (
          "Language",
          [
            "Switch Chinese or English from the Language / 语言 menu. The explicit choice is restored at the next launch."
          ]
        ),
        (
          "Interface sizes",
          [
            "User-adjusted sidebar, conversation, details, and Settings sizes are restored in later DEV launches and constrained to the current display."
          ]
        ),
      ]
    ),
    article(
      .windowsAndDisplays,
      "Windows and Displays",
      "The Window menu lists displays currently available to this Mac.",
      [
        (
          "Move every surface",
          [
            "Choosing a display moves the workspace, Settings, first-run setup, About, Help, and the tour to that display."
          ]
        ),
        (
          "Safe fitting",
          [
            "Windows are recomputed inside the target visible work area. Rabbisir does not rely only on names or expose internal display identifiers."
          ]
        ),
        (
          "Display changes",
          [
            "The menu refreshes after display connection, removal, or parameter changes and falls back safely if a target disappears."
          ]
        ),
      ]
    ),
    article(
      .communityAndLicense,
      "Creator, Community, and Feedback",
      "The public App keeps creator attribution, community access, licensing, and feedback clear.",
      [
        (
          "Creator",
          [
            "Rabbisir is created by YelZap. The creator link in About opens the Rabbisir GitHub repository."
          ]
        ),
        (
          "Discord Community",
          [
            "The community link in About opens the Rabbisir Discord. Community access does not grant release or maintainer authority."
          ]
        ),
        (
          "GitHub Feedback",
          [
            "Use the Rabbisir repository Issues page for reproducible feedback. Never attach an API Key, private path, or complete conversation."
          ]
        ),
        (
          "License",
          [
            "Rabbisir-owned source uses the MIT License. DeepSeek Harness licensing and attribution are recorded separately and do not imply affiliation, sponsorship, or endorsement."
          ]
        ),
      ],
      links: [
        URL(string: "https://github.com/readysteadyscience/Rabbisir")!,
        URL(string: "https://github.com/readysteadyscience/Rabbisir/issues")!,
        URL(string: "https://discord.gg/gT4TUHGkQm")!,
      ]
    ),
    article(
      .privacy,
      "Privacy and Credential Safety",
      "Handle credentials only in the secure configuration surface provided by the App.",
      [
        (
          "API Key",
          [
            "Rabbisir saves a Key through the runtime's write-only credential path and never displays, prints, exports, or copies the stored value."
          ]
        ),
        (
          "Conversation",
          [
            "Only approved user-visible content enters the native conversation. System or developer context, hidden content, raw tool payloads, and unknown nodes are excluded."
          ]
        ),
        (
          "Getting help",
          [
            "Never send a Key, token, cookie, private path, complete conversation, or log containing sensitive content."
          ]
        ),
      ]
    ),
    article(
      .shortcuts,
      "Keyboard Shortcuts",
      "Common commands remain available through native menus and global shortcuts.",
      [
        (
          "Global",
          [
            "⌃⌥Space: show or hide the complete workspace.",
            "⌃⌥Return: show the workspace and focus the composer.",
          ]
        ),
        (
          "App",
          [
            "⌘,: open Settings.", "⌘0: show the main window.", "⌘H: hide the workspace.",
            "⌘Q: quit Rabbisir.",
          ]
        ),
        ("Composer", ["Return: send.", "Shift-Return: insert a line break."]),
      ]
    ),
    article(
      .troubleshooting,
      "Troubleshooting",
      "Confirm the visible state first, then use the smallest recovery action.",
      [
        (
          "The workspace did not open",
          [
            "If first-run configuration is incomplete, remain in setup and finish saving and testing. Otherwise use ⌃⌥Space or Show Main Window."
          ]
        ),
        (
          "A window is on another display",
          [
            "Open the Window menu and choose a display. Rabbisir moves every managed window together."
          ]
        ),
        (
          "Browser control",
          ["Coming Soon. The current indicator does not control an external browser."]
        ),
      ]
    ),
  ]
}

enum RabbisirHelpCatalogError: Error, Equatable {
  case missingTopic(RabbisirHelpTopic)
}

enum RabbisirHelpWindowLayout {
  static let defaultSize = CGSize(width: 920, height: 680)
  static let minimumSize = CGSize(width: 760, height: 560)
  static let maximumStoredSize = CGSize(width: 10_000, height: 10_000)

  static func size(preferred: CGSize, visibleFrame: CGRect) -> CGSize {
    let visible = visibleFrame.standardized
    guard visible.width > 0, visible.height > 0 else { return defaultSize }
    return CGSize(
      width: min(max(preferred.width, min(minimumSize.width, visible.width)), visible.width),
      height: min(max(preferred.height, min(minimumSize.height, visible.height)), visible.height)
    )
  }

  static func minimumSize(for visibleFrame: CGRect) -> CGSize {
    let visible = visibleFrame.standardized
    guard visible.width > 0, visible.height > 0 else { return minimumSize }
    return CGSize(
      width: min(minimumSize.width, visible.width),
      height: min(minimumSize.height, visible.height)
    )
  }
}

@MainActor
private final class RabbisirHelpViewModel: ObservableObject {
  @Published var language: RabbisirInterfaceLanguage
  @Published var selectedTopic: RabbisirHelpTopic

  init(
    language: RabbisirInterfaceLanguage,
    selectedTopic: RabbisirHelpTopic = .quickStart
  ) {
    self.language = language
    self.selectedTopic = selectedTopic
  }

  var catalog: RabbisirHelpCatalog { RabbisirHelpCatalog(language: language) }
}

@MainActor
enum RabbisirHelpMaterialPolicy {
  static let cornerRadius: CGFloat = 24

  static func configure(_ window: NSWindow) {
    NativeSettingsMaterialPolicy.configure(window)
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
final class RabbisirHelpWindowCoordinator: NSObject, NSWindowDelegate, NSMenuItemValidation {
  private let model: RabbisirHelpViewModel
  private var screenProvider: @MainActor () -> NSScreen?
  private var window: NSWindow?
  private var replayTourAction: (@MainActor () -> Void)?
  private var languageSubscription: AnyCancellable?
  private let windowAnimationBehavior: NSWindow.AnimationBehavior
  private let windowPresenter: @MainActor (NSWindow) -> Void
  private let interfacePreferences: RabbisirInterfacePreferencesStore

  init(
    screenProvider: @escaping @MainActor () -> NSScreen? = {
      RabbisirPrimaryScreen.current
    },
    interfacePreferences: RabbisirInterfacePreferencesStore = RabbisirInterfacePreferencesStore(),
    windowAnimationBehavior: NSWindow.AnimationBehavior = .default,
    windowPresenter: @escaping @MainActor (NSWindow) -> Void = { window in
      window.makeKeyAndOrderFront(nil)
      NSApp.activate(ignoringOtherApps: true)
    }
  ) {
    self.screenProvider = screenProvider
    self.interfacePreferences = interfacePreferences
    self.windowAnimationBehavior = windowAnimationBehavior
    self.windowPresenter = windowPresenter
    model = RabbisirHelpViewModel(language: RabbisirLocalization.shared.language)
    super.init()
    languageSubscription = RabbisirLocalization.shared.$language
      .removeDuplicates()
      .sink { [weak self] language in self?.updateLanguage(language) }
  }

  var isVisible: Bool { window?.isVisible == true }
  var selectedTopic: RabbisirHelpTopic { model.selectedTopic }
  var windowAccessibilityLabel: String? { window?.accessibilityLabel() }
  var canReplayTour: Bool { replayTourAction != nil }

  func configure(
    screenProvider: @escaping @MainActor () -> NSScreen?,
    replayTour: (@MainActor () -> Void)? = nil
  ) {
    self.screenProvider = screenProvider
    replayTourAction = replayTour
  }

  func updateLanguage(_ language: RabbisirInterfaceLanguage) {
    model.language = language
    updateWindowCopy()
  }

  @objc func showHelp(_ sender: Any?) {
    show(topic: .quickStart)
  }

  @objc func showQuickStart(_ sender: Any?) {
    show(topic: .quickStart)
  }

  @objc func showKeyboardShortcuts(_ sender: Any?) {
    show(topic: .shortcuts)
  }

  @objc func showPrivacy(_ sender: Any?) {
    show(topic: .privacy)
  }

  @objc func replayTour(_ sender: Any?) {
    replayTourAction?()
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    menuItem.action == #selector(replayTour(_:)) ? canReplayTour : true
  }

  func move(to screen: NSScreen) {
    guard let window else { return }
    place(window, on: screen)
  }

  func close() {
    window?.performClose(nil)
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow,
      window === self.window,
      window.inLiveResize
    else { return }
    interfacePreferences.setHelpWindowSize(window.frame.size)
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === self.window else { return }
    interfacePreferences.setHelpWindowSize(window.frame.size)
  }

  func windowDidChangeScreen(_ notification: Notification) {
    guard let window = notification.object as? NSWindow,
      window === self.window,
      let screen = window.screen ?? screenProvider()
    else { return }
    place(window, on: screen)
  }

  private func show(topic: RabbisirHelpTopic) {
    model.selectedTopic = topic
    let window = window ?? makeWindow()
    self.window = window
    if let screen = screenProvider() {
      place(window, on: screen)
    }
    windowPresenter(window)
  }

  private func makeWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: CGRect(
        origin: .zero,
        size: interfacePreferences.helpWindowSize ?? RabbisirHelpWindowLayout.defaultSize
      ),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    window.identifier = NSUserInterfaceItemIdentifier("Rabbisir.help")
    window.isReleasedWhenClosed = false
    window.minSize = RabbisirHelpWindowLayout.minimumSize
    window.collectionBehavior = [.moveToActiveSpace]
    window.animationBehavior = windowAnimationBehavior
    RabbisirHelpMaterialPolicy.configure(window)
    let materialContainer = RabbisirHelpMaterialPolicy.makeContainer(
      contentView: NSHostingView(
        rootView: RabbisirLocalizedRoot {
          RabbisirHelpView(
            model: model,
            canReplayTour: { [weak self] in self?.canReplayTour == true },
            replayTour: { [weak self] in self?.replayTourAction?() }
          )
        }
      )
    )
    window.contentView = materialContainer
    window.delegate = self
    updateWindowCopy(window)
    return window
  }

  private func place(_ window: NSWindow, on screen: NSScreen) {
    let visibleFrame = screen.visibleFrame
    window.minSize = RabbisirHelpWindowLayout.minimumSize(for: visibleFrame)
    let preferred = RabbisirHelpWindowLayout.size(
      preferred: window.frame.size,
      visibleFrame: visibleFrame
    )
    let frame = RabbisirWindowPlacement.frame(
      currentFrame: CGRect(origin: window.frame.origin, size: preferred),
      minimumSize: window.minSize,
      sourceVisibleFrame: window.screen?.visibleFrame,
      targetVisibleFrame: visibleFrame
    )
    window.setFrame(frame, display: window.isVisible)
  }

  private func updateWindowCopy(_ window: NSWindow? = nil) {
    guard let window = window ?? self.window else { return }
    let title = model.language == .chinese ? "Rabbisir 帮助" : "Rabbisir Help"
    window.title = title
    window.setAccessibilityLabel(title)
  }
}

@MainActor
private struct RabbisirHelpView: View {
  @ObservedObject var model: RabbisirHelpViewModel
  let canReplayTour: () -> Bool
  let replayTour: () -> Void

  private var catalog: RabbisirHelpCatalog { model.catalog }
  private var article: RabbisirHelpArticle {
    (try? catalog.article(for: model.selectedTopic)) ?? catalog.articles[0]
  }

  var body: some View {
    NavigationSplitView {
      List(catalog.articles, selection: $model.selectedTopic) { article in
        Label(article.title, systemImage: symbol(for: article.topic))
          .tag(article.topic)
      }
      .navigationTitle(model.language == .chinese ? "帮助主题" : "Help Topics")
      .accessibilityLabel(model.language == .chinese ? "帮助主题" : "Help Topics")
      .frame(minWidth: 250)
      .scrollContentBackground(.hidden)
      .background(Color.clear)
    } detail: {
      ScrollView {
        VStack(alignment: .leading, spacing: 24) {
          VStack(alignment: .leading, spacing: 8) {
            Text(article.title)
              .font(.system(size: 30, weight: .bold, design: .rounded))
            Text(article.summary)
              .font(.title3)
              .foregroundStyle(.secondary)
          }

          ForEach(article.groups) { group in
            VStack(alignment: .leading, spacing: 10) {
              Text(group.title).font(.headline)
              ForEach(Array(group.bullets.enumerated()), id: \.offset) { _, bullet in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                  Image(systemName: "circle.fill")
                    .font(.system(size: 5))
                    .foregroundStyle(.secondary)
                  Text(bullet)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                }
              }
            }
          }

          ForEach(article.externalLinks, id: \.absoluteString) { url in
            Link(destination: url) {
              Label(url.host ?? url.absoluteString, systemImage: "arrow.up.right.square")
            }
            .accessibilityHint(
              model.language == .chinese ? "在默认浏览器中打开" : "Opens in the default browser"
            )
          }

          if article.topic == .quickStart || article.topic == .workspace {
            Button(
              model.language == .chinese ? "重新开始界面导览" : "Restart Interface Tour",
              action: replayTour
            )
            .disabled(!canReplayTour())
            .accessibilityHint(
              model.language == .chinese
                ? "主工作台打开后可用"
                : "Available after the workspace opens"
            )
          }
        }
        .frame(maxWidth: 680, alignment: .leading)
        .padding(32)
      }
      .navigationTitle(article.title)
      .background(Color.clear)
    }
    .background(Color.clear)
  }

  private func symbol(for topic: RabbisirHelpTopic) -> String {
    switch topic {
    case .quickStart: "sparkles"
    case .workspace: "rectangle.3.group"
    case .projectsAndConversations: "folder"
    case .settingsAndLanguage: "gearshape"
    case .windowsAndDisplays: "display.2"
    case .communityAndLicense: "person.2.badge.gearshape"
    case .privacy: "lock.shield"
    case .shortcuts: "keyboard"
    case .troubleshooting: "wrench.and.screwdriver"
    }
  }
}
