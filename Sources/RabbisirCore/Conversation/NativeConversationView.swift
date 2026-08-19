import AppKit
import SwiftUI

struct NativeConversationRowLayout: Equatable, Sendable {
  static let horizontalContentInset: CGFloat = 18

  let leadingReserve: CGFloat
  let trailingReserve: CGFloat
  let maximumWidthFraction: CGFloat
  let maximumWidth: CGFloat?
  let hugsVisibleText: Bool

  func maximumContentWidth(in containerWidth: CGFloat) -> CGFloat {
    max(
      1,
      min(
        maximumWidth ?? .greatestFiniteMagnitude,
        containerWidth * maximumWidthFraction - leadingReserve - trailingReserve
      )
    )
  }

  func contentOriginX(containerWidth: CGFloat, contentWidth: CGFloat) -> CGFloat {
    if hugsVisibleText {
      return max(
        leadingReserve,
        containerWidth - trailingReserve - contentWidth
      )
    }
    return leadingReserve
  }

  static func resolve(kind: NativeConversationItem.Kind) -> Self {
    switch kind {
    case .user:
      Self(
        leadingReserve: 0,
        trailingReserve: 0,
        maximumWidthFraction: 0.82,
        maximumWidth: 525,
        hugsVisibleText: true
      )
    case .assistant, .image, .tool, .command, .compaction, .notice, .turnTail, .system,
      .error:
      Self(
        leadingReserve: 0,
        trailingReserve: 0,
        maximumWidthFraction: 1,
        maximumWidth: nil,
        hugsVisibleText: false
      )
    }
  }
}

private struct ConversationMessageLineLayout: Layout {
  let policy: NativeConversationRowLayout
  let spacing: CGFloat

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) -> CGSize {
    let availableWidth = max(1, proposal.width ?? 480)
    let maximumContentWidth = policy.maximumContentWidth(in: availableWidth)
    let sizes = measuredSizes(
      subviews: subviews,
      maximumContentWidth: maximumContentWidth
    )
    return CGSize(
      width: availableWidth,
      height: sizes.map(\.height).max() ?? 0
    )
  }

  func placeSubviews(
    in bounds: CGRect,
    proposal: ProposedViewSize,
    subviews: Subviews,
    cache: inout ()
  ) {
    let maximumContentWidth = policy.maximumContentWidth(in: bounds.width)
    let sizes = measuredSizes(
      subviews: subviews,
      maximumContentWidth: maximumContentWidth
    )
    let totalWidth =
      sizes.reduce(0) { $0 + $1.width }
      + spacing * CGFloat(max(0, sizes.count - 1))
    var x =
      bounds.minX
      + policy.contentOriginX(
        containerWidth: bounds.width,
        contentWidth: totalWidth
      )
    for (index, subview) in subviews.enumerated() {
      let size = sizes[index]
      subview.place(
        at: CGPoint(x: x, y: bounds.minY),
        anchor: .topLeading,
        proposal: ProposedViewSize(size)
      )
      x += size.width + spacing
    }
  }

  private func measuredSizes(
    subviews: Subviews,
    maximumContentWidth: CGFloat
  ) -> [CGSize] {
    var remainingWidth = maximumContentWidth
    return subviews.enumerated().map { index, subview in
      let reservedSpacing = index == 0 ? 0 : spacing
      remainingWidth = max(1, remainingWidth - reservedSpacing)
      let size = subview.sizeThatFits(
        ProposedViewSize(width: remainingWidth, height: nil)
      )
      remainingWidth = max(1, remainingWidth - size.width)
      return size
    }
  }
}

struct NativeConversationItem: Identifiable, Equatable, Sendable {
  enum Kind: String, Equatable, Sendable {
    case user
    case assistant
    case image
    case tool
    case command
    case compaction
    case notice
    case turnTail
    case system
    case error
  }

  struct Tool: Equatable, Sendable {
    let title: String
    let summary: String?
    let state: UpstreamToolPresentation.State
  }

  struct TurnTail: Equatable, Sendable {
    let durationMilliseconds: Double?
    let firstTokenLatencyMilliseconds: Double?
    let tokensPerSecond: Double?
    let producedFiles: [String]
    let branchSequence: Int?
    let isBranchUnavailable: Bool
  }

  let id: String
  let kind: Kind
  let text: String
  let detail: String?
  let images: [UpstreamImageAttachmentReference]
  let isStreaming: Bool
  let turn: Int?
  let turnStartedAt: Double?
  let turnEndedAt: Double?
  let copyText: String?
  let tool: Tool?
  let turnTail: TurnTail?

  var isUserVisible: Bool {
    switch kind {
    case .user, .assistant, .image:
      true
    case .tool, .command:
      tool != nil
    case .compaction, .notice:
      true
    case .turnTail:
      turnTail != nil
    case .error:
      detail != nil
    case .system:
      false
    }
  }

  init(
    id: String,
    kind: Kind,
    text: String,
    detail: String? = nil,
    images: [UpstreamImageAttachmentReference] = [],
    isStreaming: Bool = false,
    turn: Int? = nil,
    turnStartedAt: Double? = nil,
    turnEndedAt: Double? = nil,
    copyText: String? = nil,
    allowsCopy: Bool = true,
    tool: Tool? = nil,
    turnTail: TurnTail? = nil
  ) {
    self.id = id
    self.kind = kind
    self.text = text
    self.detail = detail
    self.images = images
    self.isStreaming = isStreaming
    self.turn = turn
    self.turnStartedAt = turnStartedAt
    self.turnEndedAt = turnEndedAt
    self.copyText =
      allowsCopy && (kind == .user || kind == .assistant || kind == .turnTail)
      ? (copyText ?? text)
      : nil
    self.tool = tool
    self.turnTail = turnTail
  }
}

enum ConversationUIIdentity {
  static func scoped(sessionID: String?, messageID: String) -> String {
    "\(sessionID ?? "no-session")::\(messageID)"
  }
}

private struct ScopedNativeConversationItem: Identifiable {
  let item: NativeConversationItem
  let id: String

  init(sessionID: String?, item: NativeConversationItem) {
    self.item = item
    id = ConversationUIIdentity.scoped(sessionID: sessionID, messageID: item.id)
  }
}

@MainActor
protocol NativeConversationViewModel: AnyObject, ObservableObject {
  var selectedSessionID: String? { get }
  var items: [NativeConversationItem] { get }
  var updateRevision: UInt64 { get }
  var isLoadingInitialHistory: Bool { get }
  var isLoadingOlderHistory: Bool { get }
  var hasMoreHistory: Bool { get }
  var failureMessage: String? { get }
  var isGenerationRunning: Bool { get }
  var queueItems: [UpstreamQueueItem] { get }
  var pendingApproval: UpstreamApprovalRequest? { get }
  var pendingQuestion: UpstreamQuestionRequest? { get }
  var isInteractionResponsePending: Bool { get }

  func ensureConversationLoaded() async
  func loadOlderHistory() async
  func imageData(for attachmentID: String) -> Data?
  func ensureImageLoaded(_ image: UpstreamImageAttachmentReference) async
  func openProducedFile(_ path: String) async
  func forkConversation(at sequence: Int) async
  func updateQueueItem(_ itemID: String, action: UpstreamQueueAction) async -> Bool
  func respondToApproval(_ outcome: UpstreamApprovalOutcome) async -> Bool
  func respondToQuestion(_ answer: UpstreamQuestionAnswer) async -> Bool
}

@MainActor
struct NativeConversationView<Model: NativeConversationViewModel>: View {
  @Environment(\.rabbisirCopy) private var copy
  private static var bottomAnchorID: String { "Rabbisir.nativeConversation.bottom" }
  private static var coordinateSpaceName: String { "Rabbisir.nativeConversation.scrollSpace" }

  @ObservedObject var model: Model
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var scrollPolicy = ConversationScrollPolicy()
  @State private var renderedItemIDs: [String] = []
  @State private var pendingScroll: Task<Void, Never>?
  @State private var olderLoadTask: Task<Void, Never>?
  @State private var measuredContentHeight: CGFloat = 0
  @StateObject private var copyController: ConversationCopyController

  init(
    model: Model,
    clipboardWriter: ConversationClipboardWriter = .system
  ) {
    self.model = model
    _copyController = StateObject(
      wrappedValue: ConversationCopyController(clipboardWriter: clipboardWriter)
    )
  }

  var body: some View {
    GeometryReader { viewport in
      ScrollViewReader { proxy in
        let backdropHeight = ConversationBackdropLayout.height(
          visibleMessageCount: visibleItems.count,
          measuredContentHeight: measuredContentHeight,
          viewportHeight: viewport.size.height
        )
        ZStack(alignment: .bottom) {
          if backdropHeight > 0 {
            ConversationContrastBackdrop()
              .frame(height: backdropHeight)
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
              .allowsHitTesting(false)
              .accessibilityHidden(true)
          }
          conversationScroll(proxy: proxy, viewportHeight: viewport.size.height)
          conversationStateOverlay
        }
        .animation(
          reduceMotion
            ? .linear(duration: 0.12)
            : .easeInOut(duration: RabbisirMotionToken.sidebarShowHide.duration),
          value: backdropHeight
        )
        .onAppear {
          reconcileContent(using: proxy)
        }
        .onChange(of: model.selectedSessionID) { _, _ in
          pendingScroll?.cancel()
          scrollPolicy.resetForSession()
          renderedItemIDs = []
          copyController.resetFeedback()
        }
        .onChange(of: model.updateRevision) { _, _ in
          reconcileContent(using: proxy)
        }
        .onDisappear {
          pendingScroll?.cancel()
          olderLoadTask?.cancel()
        }
      }
    }
    .task(id: model.selectedSessionID) {
      await model.ensureConversationLoaded()
    }
    .conversationReadability(.primary)
    .tint(ConversationDisplayPalette.primaryColor)
    .accessibilityElement(children: .contain)
    .accessibilityIdentifier("Rabbisir.nativeConversation")
    .accessibilityLabel(copy[.conversationMessages])
  }

  private func conversationScroll(
    proxy: ScrollViewProxy,
    viewportHeight: CGFloat
  ) -> some View {
    ScrollView(.vertical, showsIndicators: false) {
      LazyVStack(alignment: .leading, spacing: 14) {
        historyControl

        ForEach(scopedItems) { scopedItem in
          NativeConversationRow(
            item: scopedItem.item,
            interactionIDPrefix: scopedItem.id,
            copyController: copyController,
            imageData: { model.imageData(for: $0) },
            loadImage: { await model.ensureImageLoaded($0) },
            openProducedFile: { await model.openProducedFile($0) },
            forkConversation: { await model.forkConversation(at: $0) }
          )
          .id(scopedItem.id)
        }

        if !model.queueItems.isEmpty {
          NativeQueueDock(model: model)
        }

        if let approval = model.pendingApproval {
          NativeApprovalCard(model: model, request: approval)
        }

        if let question = model.pendingQuestion {
          NativeQuestionCard(model: model, request: question)
        }

        Color.clear
          .frame(height: 1)
          .id(Self.bottomAnchorID)
          .accessibilityHidden(true)
      }
      .padding(.horizontal, NativeConversationRowLayout.horizontalContentInset)
      .padding(.vertical, 18)
      .background {
        GeometryReader { content in
          Color.clear
            .preference(
              key: ConversationContentFramePreferenceKey.self,
              value: content.frame(in: .named(Self.coordinateSpaceName))
            )
            .allowsHitTesting(false)
        }
      }
      .frame(minHeight: viewportHeight, alignment: .bottom)
    }
    .coordinateSpace(name: Self.coordinateSpaceName)
    .onPreferenceChange(ConversationContentFramePreferenceKey.self) { frame in
      guard !frame.isNull else { return }
      measuredContentHeight = frame.height
      let shouldLoadOlder = scrollPolicy.viewportDidUpdate(
        distanceFromBottom: max(0, frame.maxY - viewportHeight),
        contentTopOffset: frame.minY
      )
      if shouldLoadOlder {
        requestOlderHistory()
      }
    }
    .accessibilityIdentifier("Rabbisir.nativeConversation.scroll")
  }

  @ViewBuilder
  private var historyControl: some View {
    if model.hasMoreHistory || model.isLoadingOlderHistory {
      HStack {
        Spacer(minLength: 0)
        if model.isLoadingOlderHistory {
          ProgressView()
            .controlSize(.small)
            .accessibilityLabel(copy[.conversationLoadingEarlier])
        } else {
          Button(copy[.conversationLoadEarlier]) {
            requestOlderHistory()
          }
          .buttonStyle(.plain)
          .font(.caption)
          .conversationReadability(.secondary)
          .accessibilityIdentifier("Rabbisir.nativeConversation.loadOlder")
        }
        Spacer(minLength: 0)
      }
      .frame(minHeight: 24)
    }
  }

  @ViewBuilder
  private var conversationStateOverlay: some View {
    Group {
      if model.isLoadingInitialHistory && visibleItems.isEmpty {
        ProgressView(copy[.conversationLoading])
          .controlSize(.small)
          .accessibilityIdentifier("Rabbisir.nativeConversation.loading")
      } else if let failureMessage = model.failureMessage, visibleItems.isEmpty {
        ContentUnavailableView {
          Label(copy[.conversationLoadFailed], systemImage: "exclamationmark.triangle")
        } description: {
          Text(failureMessage)
        } actions: {
          Button(copy[.conversationRetry]) {
            Task { await model.ensureConversationLoaded() }
          }
        }
        .accessibilityIdentifier("Rabbisir.nativeConversation.failure")
      }
    }
    .conversationReadability(.primary)
  }

  private func reconcileContent(using proxy: ScrollViewProxy) {
    let currentIDs = currentItemIDs()
    let action = scrollPolicy.contentDidChange(
      previousIDs: renderedItemIDs,
      currentIDs: currentIDs
    )
    renderedItemIDs = currentIDs
    perform(action, using: proxy)
  }

  private func currentItemIDs() -> [String] {
    let currentItems = scopedItems
    guard
      renderedItemIDs.count == currentItems.count,
      renderedItemIDs.first == currentItems.first?.id,
      renderedItemIDs.last == currentItems.last?.id
    else {
      return currentItems.map(\.id)
    }
    return renderedItemIDs
  }

  private var visibleItems: [NativeConversationItem] {
    model.items.filter(\.isUserVisible)
  }

  private var scopedItems: [ScopedNativeConversationItem] {
    visibleItems.map {
      ScopedNativeConversationItem(sessionID: model.selectedSessionID, item: $0)
    }
  }

  private func perform(
    _ action: ConversationScrollAction,
    using proxy: ScrollViewProxy
  ) {
    pendingScroll?.cancel()
    switch action {
    case .none:
      pendingScroll = nil
    case .followTail(let animated):
      pendingScroll = Task { @MainActor in
        await Task.yield()
        guard !Task.isCancelled else { return }
        if animated && !reduceMotion {
          withAnimation(.easeOut(duration: 0.16)) {
            proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
          }
        } else {
          proxy.scrollTo(Self.bottomAnchorID, anchor: .bottom)
        }
      }
    case .preserveAnchor(let id):
      pendingScroll = Task { @MainActor in
        await Task.yield()
        guard !Task.isCancelled else { return }
        proxy.scrollTo(id, anchor: .top)
      }
    }
  }

  private func requestOlderHistory() {
    guard model.hasMoreHistory, !model.isLoadingOlderHistory else { return }
    olderLoadTask?.cancel()
    olderLoadTask = Task { @MainActor in
      await model.loadOlderHistory()
    }
  }
}

private struct NativeQueueDock<Model: NativeConversationViewModel>: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var model: Model
  @State private var editingID: String?
  @State private var editText = ""
  @State private var busyID: String?

  private var visibleItems: [UpstreamQueueItem] {
    model.queueItems.filter { $0.placement != .context }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      Label(
        copy.conversationQueueCount(visibleItems.count),
        systemImage: "text.line.first.and.arrowtriangle.forward"
      )
      .font(.caption.weight(.semibold))
      ForEach(visibleItems) { item in
        HStack(alignment: .center, spacing: 8) {
          if editingID == item.id {
            TextField(copy.conversationQueueEdit, text: $editText)
              .textFieldStyle(.roundedBorder)
              .onSubmit { apply(item, action: .edit(text: editText)) }
            Button(copy.conversationQueueSave) {
              apply(item, action: .edit(text: editText))
            }
            .disabled(editText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button(copy[.cancel]) { editingID = nil }
          } else {
            Text(item.preview)
              .font(.caption)
              .lineLimit(2)
              .frame(maxWidth: .infinity, alignment: .leading)
            if item.placement == .queued {
              Button {
                editingID = item.id
                editText = item.editableText ?? ""
              } label: {
                Image(systemName: "pencil")
              }
              .disabled(item.editableText == nil || busyID != nil)
              .help(
                item.editableText == nil
                  ? copy.conversationQueueEditUnavailable : copy.conversationQueueEdit
              )
              .accessibilityLabel(copy.conversationQueueEdit)
              Button {
                apply(item, action: .remove)
              } label: {
                Image(systemName: "trash")
              }
              .disabled(busyID != nil)
              .help(copy.conversationQueueRemove)
              .accessibilityLabel(copy.conversationQueueRemove)
              Button {
                apply(item, action: .steer)
              } label: {
                Image(systemName: "arrow.turn.up.right")
              }
              .disabled(!model.isGenerationRunning || busyID != nil)
              .help(copy.conversationQueueSteer)
              .accessibilityLabel(copy.conversationQueueSteer)
            } else {
              Text(copy.conversationQueueSteering)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            }
          }
        }
        .accessibilityElement(children: .contain)
      }
    }
    .padding(12)
    .rabbisirGlassSurface(cornerRadius: 14, interactive: true)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(copy.conversationQueueCount(visibleItems.count))
  }

  private func apply(_ item: UpstreamQueueItem, action: UpstreamQueueAction) {
    guard busyID == nil else { return }
    busyID = item.id
    Task { @MainActor in
      let accepted = await model.updateQueueItem(item.id, action: action)
      if accepted { editingID = nil }
      busyID = nil
    }
  }
}

private struct NativeApprovalCard<Model: NativeConversationViewModel>: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var model: Model
  let request: UpstreamApprovalRequest

  var body: some View {
    VStack(alignment: .leading, spacing: 10) {
      Label(copy.conversationApprovalTitle, systemImage: "hand.raised.fill")
        .font(.callout.weight(.semibold))
      Text(copy.toolTitle(request.toolName))
        .font(.caption.weight(.medium))
      if let reason = request.reason, !reason.isEmpty {
        Text(reason)
          .font(.caption)
          .textSelection(.enabled)
      }
      HStack {
        Button(copy.conversationAllowOnce) { respond(.allowedOnce) }
          .keyboardShortcut(.defaultAction)
        Button(copy.conversationReject, role: .destructive) { respond(.rejected) }
          .keyboardShortcut(.cancelAction)
      }
      .disabled(model.isInteractionResponsePending)
    }
    .padding(14)
    .rabbisirGlassSurface(cornerRadius: 14, interactive: true)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(copy.conversationApprovalTitle)
  }

  private func respond(_ outcome: UpstreamApprovalOutcome) {
    Task { _ = await model.respondToApproval(outcome) }
  }
}

private struct NativeQuestionCard<Model: NativeConversationViewModel>: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var model: Model
  let request: UpstreamQuestionRequest
  @State private var selected: [String: Set<String>] = [:]
  @State private var custom: [String: String] = [:]

  var body: some View {
    VStack(alignment: .leading, spacing: 14) {
      ForEach(request.questions) { question in
        VStack(alignment: .leading, spacing: 8) {
          if let header = question.header, !header.isEmpty {
            Text(header).font(.caption.weight(.semibold))
          }
          Text(question.question).font(.callout.weight(.semibold))
          if let detail = question.detail, !detail.isEmpty {
            Text(detail).font(.caption).textSelection(.enabled)
          }
          ForEach(question.options ?? [], id: \.label) { option in
            Toggle(isOn: optionBinding(question: question, label: option.label)) {
              VStack(alignment: .leading, spacing: 2) {
                Text(option.label)
                if let description = option.description, !description.isEmpty {
                  Text(description).font(.caption).foregroundStyle(.secondary)
                }
              }
            }
            .toggleStyle(.checkbox)
          }
          TextField(
            copy.conversationQuestionOther,
            text: customBinding(questionID: question.id)
          )
          .textFieldStyle(.roundedBorder)
          .accessibilityLabel(copy.conversationQuestionOther)
        }
      }
      Button(copy.conversationQuestionSubmit) { submit() }
        .keyboardShortcut(.defaultAction)
        .disabled(!canSubmit || model.isInteractionResponsePending)
    }
    .padding(14)
    .rabbisirGlassSurface(cornerRadius: 14, interactive: true)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(copy.conversationQuestionTitle)
  }

  private var canSubmit: Bool {
    request.questions.allSatisfy { question in
      !(selected[question.id] ?? []).isEmpty
        || !(custom[question.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
  }

  private func optionBinding(question: UpstreamQuestionItem, label: String) -> Binding<Bool> {
    Binding(
      get: { selected[question.id, default: []].contains(label) },
      set: { enabled in
        var values = selected[question.id, default: []]
        if enabled {
          if question.multiSelect != true { values.removeAll() }
          values.insert(label)
        } else {
          values.remove(label)
        }
        selected[question.id] = values
      }
    )
  }

  private func customBinding(questionID: String) -> Binding<String> {
    Binding(
      get: { custom[questionID] ?? "" },
      set: { custom[questionID] = $0 }
    )
  }

  private func submit() {
    let answer = UpstreamQuestionAnswer(
      answers: request.questions.map { question in
        let customText = custom[question.id]?.trimmingCharacters(in: .whitespacesAndNewlines)
        return UpstreamQuestionAnswerItem(
          id: question.id,
          selected: Array(selected[question.id, default: []]).sorted(),
          custom: customText?.isEmpty == false ? customText : nil
        )
      }
    )
    Task { _ = await model.respondToQuestion(answer) }
  }
}

private struct NativeConversationRow: View {
  @Environment(\.rabbisirCopy) private var copy
  let item: NativeConversationItem
  let interactionIDPrefix: String
  @ObservedObject var copyController: ConversationCopyController
  let imageData: (String) -> Data?
  let loadImage: (UpstreamImageAttachmentReference) async -> Void
  let openProducedFile: (String) async -> Void
  let forkConversation: (Int) async -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isExpanded = false

  var body: some View {
    let layout = NativeConversationRowLayout.resolve(kind: item.kind)
    VStack(alignment: .leading, spacing: 6) {
      switch item.kind {
      case .tool, .command:
        semanticDisclosure(
          title: item.tool?.title ?? item.text,
          summary: item.tool?.summary,
          detail: item.detail ?? ""
        )
      case .compaction:
        semanticDisclosure(title: item.text, summary: nil, detail: item.detail ?? "")
      case .notice, .error:
        semanticDisclosure(title: item.text, summary: nil, detail: item.detail ?? "")
      case .turnTail:
        turnTail
      case .image:
        imageGallery
      case .user:
        ConversationMessageLineLayout(policy: layout, spacing: 8) {
          VStack(alignment: .trailing, spacing: 8) {
            if !item.images.isEmpty {
              imageGallery
            }
            if !item.text.isEmpty {
              conversationBody
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(
                  Color.accentColor.opacity(0.12),
                  in: RoundedRectangle(cornerRadius: 22, style: .continuous)
                )
            }
          }
        }
        .frame(maxWidth: .infinity)
      default:
        ConversationMessageLineLayout(policy: layout, spacing: 8) {
          conversationBody

          if item.isStreaming {
            ProgressView()
              .controlSize(.mini)
              .tint(ConversationDisplayPalette.secondaryColor)
              .conversationReadability(.secondary)
              .accessibilityLabel(copy[.conversationReplyStreaming])
          }
        }
        .frame(maxWidth: .infinity)
      }

      if item.copyText != nil && item.kind != .turnTail {
        HStack(spacing: 0) {
          if item.kind == .user {
            Spacer(minLength: 0)
          }
          NativeConversationCopyButton(
            item: item,
            copyController: copyController
          )
          if item.kind != .user {
            Spacer(minLength: 0)
          }
        }
      }
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
    .accessibilityIdentifier("Rabbisir.nativeConversation.row.\(item.id)")
  }

  private var bodyAppearance: ConversationTextAppearance {
    switch item.kind {
    case .tool, .command:
      .tool
    case .error:
      .error
    default:
      .body
    }
  }

  @ViewBuilder
  private var imageGallery: some View {
    HStack(spacing: 8) {
      ForEach(Array(item.images.enumerated()), id: \.offset) { _, image in
        ConversationResolvedImage(
          reference: image,
          data: imageData(image.attachmentID),
          load: loadImage
        )
      }
    }
  }

  private func semanticDisclosure(
    title: String,
    summary: String?,
    detail: String
  ) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Button {
        if reduceMotion {
          isExpanded.toggle()
        } else {
          withAnimation(
            .easeInOut(duration: RabbisirMotionToken.conversationDisclosure.duration)
          ) {
            isExpanded.toggle()
          }
        }
      } label: {
        HStack(spacing: 6) {
          Image(systemName: disclosureSymbolName)
            .font(.caption)
          Text(title)
            .font(.callout)
          if let summary, !summary.isEmpty {
            Text("·")
              .font(.callout)
            Text(summary)
              .font(.callout)
              .lineLimit(1)
              .truncationMode(.tail)
          }
          if item.isStreaming {
            ProgressView().controlSize(.mini)
          }
          Image(systemName: "chevron.right")
            .font(.caption2.weight(.semibold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .conversationReadability(.secondary)
      }
      .buttonStyle(.plain)
      .accessibilityValue(
        isExpanded ? copy[.conversationExpanded] : copy[.conversationCollapsed]
      )

      if isExpanded, !detail.isEmpty {
        conversationText(
          id: "\(interactionIDPrefix).detail",
          text: detail,
          appearance: .detail
        )
        .padding(.top, 5)
        .transition(.opacity)
      }
    }
    .animation(
      reduceMotion
        ? nil
        : .easeInOut(duration: RabbisirMotionToken.conversationDisclosure.duration),
      value: isExpanded
    )
  }

  private var toolSymbolName: String {
    switch item.tool?.state {
    case .succeeded: "checkmark.circle"
    case .failed: "exclamationmark.triangle"
    case .stopped: "stop.circle"
    case .running, nil: "wrench.and.screwdriver"
    }
  }

  private var disclosureSymbolName: String {
    switch item.kind {
    case .tool, .command: toolSymbolName
    case .compaction: "square.stack.3d.down.right"
    case .notice: "info.circle"
    case .error: "exclamationmark.triangle"
    default: "chevron.right"
    }
  }

  @ViewBuilder
  private var turnTail: some View {
    HStack(spacing: 10) {
      if let milliseconds = item.turnTail?.durationMilliseconds {
        Text(ConversationRunDurationFormatter.string(seconds: milliseconds / 1_000, copy: copy))
          .font(.caption)
          .conversationReadability(.secondary)
      }
      if let milliseconds = item.turnTail?.firstTokenLatencyMilliseconds {
        Text("TTFT \(String(format: "%.2fs", milliseconds / 1_000))")
          .font(.caption)
          .conversationReadability(.secondary)
      }
      if let tokensPerSecond = item.turnTail?.tokensPerSecond {
        Text("\(String(format: "%.1f", tokensPerSecond)) tok/s")
          .font(.caption)
          .conversationReadability(.secondary)
      }
      ForEach(Array((item.turnTail?.producedFiles ?? []).prefix(6)), id: \.self) { path in
        Button {
          Task { await openProducedFile(path) }
        } label: {
          Label(path, systemImage: "doc")
        }
        .buttonStyle(.plain)
        .font(.caption)
        .lineLimit(1)
        .conversationReadability(.secondary)
        .help(copy.openPath(path))
      }
      Spacer(minLength: 0)
      if let sequence = item.turnTail?.branchSequence {
        Button {
          Task { await forkConversation(sequence) }
        } label: {
          Image(systemName: "arrow.triangle.branch")
        }
        .buttonStyle(.plain)
        .disabled(item.turnTail?.isBranchUnavailable == true)
        .conversationReadability(.secondary)
        .help(copy[.conversationForkHere])
        .accessibilityLabel(copy[.conversationForkHere])
      }
      if item.copyText != nil {
        NativeConversationCopyButton(
          item: item,
          copyController: copyController
        )
      }
    }
    .padding(.top, 2)
  }

  private var conversationBody: some View {
    conversationText(
      id: "\(interactionIDPrefix).body",
      text: item.text,
      appearance: bodyAppearance
    )
    .fixedSize(horizontal: false, vertical: true)
    .layoutPriority(1)
  }

  @ViewBuilder
  private func conversationText(
    id: String,
    text: String,
    appearance: ConversationTextAppearance
  ) -> some View {
    ConversationMessageText(
      id: id,
      text: text,
      appearance: appearance,
      interactionSurface: nil
    )
  }

  private func tone(
    for appearance: ConversationTextAppearance
  ) -> ConversationReadabilityTone {
    switch appearance {
    case .body, .tool:
      .primary
    case .detail:
      .secondary
    case .error:
      .failure
    }
  }
}

private struct ConversationResolvedImage: View {
  @Environment(\.rabbisirCopy) private var copy
  let reference: UpstreamImageAttachmentReference
  let data: Data?
  let load: (UpstreamImageAttachmentReference) async -> Void

  var body: some View {
    Group {
      if let data, let image = NSImage(data: data) {
        Image(nsImage: image)
          .resizable()
          .scaledToFit()
      } else {
        ProgressView()
          .controlSize(.small)
          .frame(minWidth: 80, minHeight: 56)
      }
    }
    .frame(maxWidth: 360, maxHeight: 280)
    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    .task(id: reference.attachmentID) {
      if data == nil { await load(reference) }
    }
    .accessibilityLabel(reference.name ?? copy[.conversationImage])
  }
}

@MainActor
private struct NativeConversationCopyButton: View {
  @Environment(\.rabbisirCopy) private var copy
  let item: NativeConversationItem
  @ObservedObject var copyController: ConversationCopyController
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovered = false

  var body: some View {
    let visualState = copyController.visualState(for: item)
    Button {
      copyController.copyVisibleText(from: item)
    } label: {
      Image(systemName: visualState.symbolName)
        .font(.caption)
        .conversationReadability(tone(for: visualState))
        .frame(width: 20, height: 18)
        .contentShape(Rectangle())
    }
    .buttonStyle(
      ConversationCopyIconButtonStyle(
        visualState: visualState,
        isHovered: isHovered,
        reduceMotion: reduceMotion
      )
    )
    .padding(.horizontal, 4)
    .padding(.vertical, 2)
    .accessibilityLabel(copy[.conversationCopyMessage])
    .accessibilityHint(copy.conversationCopyHelp(kind: item.kind))
    .accessibilityValue(visualState.accessibilityValue(copy: copy))
    .accessibilityIdentifier(
      ConversationCopyPresentation.accessibilityIdentifier(for: item)
    )
    .onHover { hovering in
      isHovered = hovering
    }
  }

  private func tone(
    for visualState: ConversationActionVisualState
  ) -> ConversationReadabilityTone {
    switch visualState {
    case .idle:
      .secondary
    case .success:
      .success
    case .failure:
      .failure
    }
  }
}

private struct ConversationCopyIconButtonStyle: ButtonStyle {
  let visualState: ConversationActionVisualState
  let isHovered: Bool
  let reduceMotion: Bool

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .background {
        RoundedRectangle(cornerRadius: 6, style: .continuous)
          .fill(
            visualState.swiftUIColor.opacity(
              isHovered || configuration.isPressed ? 0.10 : 0
            )
          )
      }
      .scaleEffect(scale(isPressed: configuration.isPressed))
      .animation(
        reduceMotion ? nil : .easeOut(duration: 0.10),
        value: configuration.isPressed
      )
      .animation(
        reduceMotion ? nil : .easeOut(duration: 0.12),
        value: isHovered
      )
  }

  private func scale(isPressed: Bool) -> CGFloat {
    guard !reduceMotion else { return 1 }
    if isPressed { return 0.92 }
    return isHovered ? 1.04 : 1
  }
}

private struct ConversationContentFramePreferenceKey: PreferenceKey {
  static let defaultValue = CGRect.null

  static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
    value = nextValue()
  }
}
