import AppKit
import Combine
import Foundation
import SwiftUI

enum WorkspaceTourStep: String, CaseIterable, Equatable, Sendable {
  case sidebar
  case conversation
  case details
  case island
}

final class WorkspaceTourPreferences {
  private static let completionKey = "rabbisir.onboarding.workspaceTourCompleted"
  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var isCompleted: Bool {
    defaults.bool(forKey: Self.completionKey)
  }

  func markCompleted() {
    defaults.set(true, forKey: Self.completionKey)
  }
}

final class WorkspaceTourProgress {
  private let preferences: WorkspaceTourPreferences
  private(set) var currentStep: WorkspaceTourStep?

  init(preferences: WorkspaceTourPreferences = WorkspaceTourPreferences()) {
    self.preferences = preferences
  }

  @discardableResult
  func beginIfNeeded() -> Bool {
    guard !preferences.isCompleted else { return false }
    currentStep = WorkspaceTourStep.allCases.first
    return currentStep != nil
  }

  func replay() {
    currentStep = WorkspaceTourStep.allCases.first
  }

  func skip() {
    preferences.markCompleted()
    currentStep = nil
  }

  @discardableResult
  func advance() -> Bool {
    guard let currentStep,
      let index = WorkspaceTourStep.allCases.firstIndex(of: currentStep)
    else { return false }
    let nextIndex = WorkspaceTourStep.allCases.index(after: index)
    guard nextIndex < WorkspaceTourStep.allCases.endIndex else {
      preferences.markCompleted()
      self.currentStep = nil
      return false
    }
    self.currentStep = WorkspaceTourStep.allCases[nextIndex]
    return true
  }
}

struct WorkspaceTourCopy: Equatable, Sendable {
  let language: RabbisirInterfaceLanguage

  func title(for step: WorkspaceTourStep) -> String {
    switch (language, step) {
    case (.chinese, .sidebar): "导航、项目与文件夹"
    case (.english, .sidebar): "Navigation, Projects, and Folders"
    case (.chinese, .conversation): "对话与输入"
    case (.english, .conversation): "Conversation and Input"
    case (.chinese, .details): "详情面板"
    case (.english, .details): "Details Panel"
    case (.chinese, .island): "顶部灵动岛"
    case (.english, .island): "Top Island"
    }
  }

  func body(for step: WorkspaceTourStep) -> String {
    switch (language, step) {
    case (.chinese, .sidebar): "左侧区域独立管理导航、项目、文件夹与会话。"
    case (.english, .sidebar):
      "The left region independently manages navigation, projects, folders, and conversations."
    case (.chinese, .conversation):
      "中间区域用于监看对话；底部输入区用于发送消息与命令，也可拖动边缘调整宽度。"
    case (.english, .conversation):
      "Monitor the conversation in the center, send from the composer below, and drag its edge to resize it."
    case (.chinese, .details):
      "右侧详情面板显示文稿、PDF、Markdown 与源码内容，可拖动边缘调整宽度。"
    case (.english, .details):
      "The right panel displays documents, PDFs, Markdown, and source content; drag its edge to resize it."
    case (.chinese, .island): "使用顶部灵动岛快速控制侧栏、详情与完整工作台。"
    case (.english, .island):
      "Use the top island to control the sidebar, details, and the complete workspace."
    }
  }

  var next: String { language == .chinese ? "下一步" : "Next" }
  var finish: String { language == .chinese ? "完成" : "Finish" }
  var skip: String { language == .chinese ? "跳过导览" : "Skip Tour" }
  var accessibility: String { language == .chinese ? "Rabbisir 界面导览" : "Rabbisir Interface Tour" }
}

enum WorkspaceTourPanelDemonstrationStage: CaseIterable, Equatable, Sendable {
  case conversationMaximum
  case conversationMinimum
  case detailsMaximum
  case restored
}

enum WorkspaceTourPanelDemonstrationPlan {
  static func stages(
    for step: WorkspaceTourStep,
    reduceMotion: Bool
  ) -> [WorkspaceTourPanelDemonstrationStage] {
    guard !reduceMotion else { return [] }
    return switch step {
    case .conversation:
      [.conversationMaximum, .conversationMinimum, .restored]
    case .details:
      [.detailsMaximum, .restored]
    case .sidebar, .island:
      []
    }
  }

  static func layout(
    for stage: WorkspaceTourPanelDemonstrationStage,
    visibleFrame: CGRect,
    navigationBarBottomY: CGFloat,
    snapshot: RabbisirWorkspaceWidthPreferences,
    detailsVisible: Bool
  ) -> SpatialWorkspaceLayout {
    let conversationWidth: CGFloat? =
      switch stage {
      case .conversationMaximum:
        SpatialWorkspaceLayoutPolicy.maximumConversationWidth
      case .conversationMinimum:
        SpatialWorkspaceLayoutPolicy.minimumInputWidth
      case .detailsMaximum, .restored:
        snapshot.conversation
      }
    let detailsWidth: CGFloat? =
      switch stage {
      case .detailsMaximum:
        SpatialWorkspaceLayoutPolicy.maximumStoredDetailsWidth
      case .conversationMaximum, .conversationMinimum:
        SpatialWorkspaceLayoutPolicy.minimumDetailsWidth
      case .restored:
        snapshot.details
      }

    return SpatialWorkspaceLayoutPolicy.resolve(
      visibleFrame: visibleFrame,
      detailsVisible: detailsVisible,
      navigationBarBottomY: navigationBarBottomY,
      preferredSidebarWidth: snapshot.sidebar,
      preferredConversationWidth: conversationWidth,
      preferredDetailsWidth: detailsWidth
    )
  }
}

enum WorkspaceTourPlacement {
  static let bubbleSize = CGSize(width: 340, height: 190)

  static func highlightFrame(target: CGRect, visibleFrame: CGRect) -> CGRect {
    let safeFrame = CGRect(
      x: visibleFrame.minX,
      y: visibleFrame.minY + 4,
      width: visibleFrame.width - 4,
      height: visibleFrame.height - 8
    )

    return
      target
      .insetBy(dx: -6, dy: -6)
      .intersection(safeFrame)
      .integral
  }

  static func bubbleFrame(
    target: CGRect,
    step: WorkspaceTourStep,
    visibleFrame: CGRect
  ) -> CGRect {
    let spacing: CGFloat = 18
    var origin: CGPoint
    switch step {
    case .sidebar:
      origin = CGPoint(x: target.maxX + spacing, y: target.midY - bubbleSize.height / 2)
    case .conversation:
      origin = CGPoint(x: target.midX - bubbleSize.width / 2, y: target.maxY - bubbleSize.height)
    case .details:
      origin = CGPoint(
        x: target.minX - bubbleSize.width - spacing, y: target.midY - bubbleSize.height / 2)
    case .island:
      origin = CGPoint(
        x: target.midX - bubbleSize.width / 2, y: target.minY - bubbleSize.height - spacing)
    }
    origin.x = min(max(origin.x, visibleFrame.minX + 12), visibleFrame.maxX - bubbleSize.width - 12)
    origin.y = min(
      max(origin.y, visibleFrame.minY + 12), visibleFrame.maxY - bubbleSize.height - 12)
    return CGRect(origin: origin, size: bubbleSize).integral
  }
}

@MainActor
private final class WorkspaceTourPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class WorkspaceTourCoordinator {
  private let progress: WorkspaceTourProgress
  private let targetFrame: (WorkspaceTourStep) -> CGRect?
  private let visibleFrame: () -> CGRect?
  private let startPanelDemonstration: (WorkspaceTourStep) -> Void
  private let cancelPanelDemonstration: () -> Void
  private let bubblePanel: WorkspaceTourPanel
  private let highlightPanel: NSPanel
  private var languageSubscription: AnyCancellable?

  init(
    progress: WorkspaceTourProgress = WorkspaceTourProgress(),
    targetFrame: @escaping (WorkspaceTourStep) -> CGRect?,
    visibleFrame: @escaping () -> CGRect?,
    startPanelDemonstration: @escaping (WorkspaceTourStep) -> Void = { _ in },
    cancelPanelDemonstration: @escaping () -> Void = {}
  ) {
    self.progress = progress
    self.targetFrame = targetFrame
    self.visibleFrame = visibleFrame
    self.startPanelDemonstration = startPanelDemonstration
    self.cancelPanelDemonstration = cancelPanelDemonstration
    bubblePanel = WorkspaceTourPanel(
      contentRect: CGRect(origin: .zero, size: WorkspaceTourPlacement.bubbleSize),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    highlightPanel = NSPanel(
      contentRect: .zero,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    configurePanels()
    languageSubscription = RabbisirLocalization.shared.$language
      .removeDuplicates()
      .sink { [weak self] _ in self?.presentCurrentStep(startsDemonstration: false) }
  }

  func beginIfNeeded() {
    guard progress.beginIfNeeded() else { return }
    cancelPanelDemonstration()
    presentCurrentStep(startsDemonstration: true)
  }

  func replay() {
    cancelPanelDemonstration()
    progress.replay()
    presentCurrentStep(startsDemonstration: true)
  }

  func refreshPlacement() {
    guard progress.currentStep != nil else { return }
    cancelPanelDemonstration()
    presentCurrentStep(startsDemonstration: false)
  }

  private func configurePanels() {
    for panel in [bubblePanel, highlightPanel] {
      panel.level = .popUpMenu
      panel.isOpaque = false
      panel.backgroundColor = .clear
      panel.hasShadow = false
      panel.hidesOnDeactivate = false
      panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary, .ignoresCycle]
    }
    bubblePanel.hasShadow = true
    highlightPanel.ignoresMouseEvents = true
  }

  private func presentCurrentStep(startsDemonstration: Bool) {
    guard let step = progress.currentStep,
      let target = targetFrame(step),
      let visible = visibleFrame()
    else {
      cancelPanelDemonstration()
      closePanels()
      return
    }

    let highlighted = WorkspaceTourPlacement.highlightFrame(
      target: target,
      visibleFrame: visible
    )
    highlightPanel.setFrame(highlighted, display: true)
    highlightPanel.contentView = NSHostingView(
      rootView: RoundedRectangle(cornerRadius: 18, style: .continuous)
        .stroke(Color.accentColor, lineWidth: 3)
        .shadow(color: Color.accentColor.opacity(0.35), radius: 8)
        .padding(EdgeInsets(top: 3, leading: 0, bottom: 3, trailing: 3))
    )
    highlightPanel.setAccessibilityLabel(
      WorkspaceTourCopy(language: RabbisirLocalization.shared.language).title(for: step)
    )
    highlightPanel.orderFrontRegardless()

    let bubbleFrame = WorkspaceTourPlacement.bubbleFrame(
      target: target,
      step: step,
      visibleFrame: visible
    )
    bubblePanel.setFrame(bubbleFrame, display: true)
    bubblePanel.contentView = NSHostingView(
      rootView: RabbisirLocalizedRoot {
        WorkspaceTourBubbleView(
          step: step,
          advance: { [weak self] in self?.advance() },
          skip: { [weak self] in self?.skip() }
        )
      }
    )
    bubblePanel.setAccessibilityLabel(
      WorkspaceTourCopy(language: RabbisirLocalization.shared.language).accessibility
    )
    bubblePanel.makeKeyAndOrderFront(nil)
    if startsDemonstration {
      startPanelDemonstration(step)
    }
  }

  private func advance() {
    cancelPanelDemonstration()
    guard progress.advance() else {
      closePanels()
      return
    }
    presentCurrentStep(startsDemonstration: true)
  }

  private func skip() {
    cancelPanelDemonstration()
    progress.skip()
    closePanels()
  }

  private func closePanels() {
    bubblePanel.orderOut(nil)
    highlightPanel.orderOut(nil)
  }
}

private struct WorkspaceTourBubbleView: View {
  @Environment(\.rabbisirCopy) private var appCopy
  let step: WorkspaceTourStep
  let advance: () -> Void
  let skip: () -> Void

  private var copy: WorkspaceTourCopy {
    WorkspaceTourCopy(language: appCopy.language)
  }

  private var isLast: Bool {
    step == WorkspaceTourStep.allCases.last
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      Text("\((WorkspaceTourStep.allCases.firstIndex(of: step) ?? 0) + 1) / 4")
        .font(.caption.monospacedDigit())
        .foregroundStyle(.secondary)
      Text(copy.title(for: step))
        .font(.title3.bold())
      Text(copy.body(for: step))
        .font(.body)
        .foregroundStyle(.secondary)
        .fixedSize(horizontal: false, vertical: true)
      Spacer(minLength: 0)
      HStack {
        Button(copy.skip, action: skip)
          .keyboardShortcut(.cancelAction)
        Spacer()
        Button(isLast ? copy.finish : copy.next, action: advance)
          .keyboardShortcut(.defaultAction)
      }
    }
    .padding(22)
    .frame(
      width: WorkspaceTourPlacement.bubbleSize.width,
      height: WorkspaceTourPlacement.bubbleSize.height
    )
    .rabbisirGlassSurface(cornerRadius: 20)
  }
}
