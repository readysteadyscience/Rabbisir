import SwiftUI

private struct WorkspaceView: View {
  @ObservedObject var state: WorkspaceState
  @ObservedObject var runtimeBridge: RuntimeBridgeStore
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    GeometryReader { proxy in
      let layout = WorkspaceLayoutPolicy.resolve(
        width: proxy.size.width,
        detailsVisible: state.isDetailsVisible
      )

      ZStack(alignment: .topLeading) {
        RuntimeWorkspaceView(state: state, runtimeBridge: runtimeBridge)
          .frame(width: layout.centerWidth)
          .frame(maxHeight: .infinity)
          .offset(x: layout.centerOriginX)

        if state.isDetailsVisible {
          NativeDetailsView(state: state)
            .frame(width: layout.detailWidth)
            .frame(maxHeight: .infinity)
            .offset(x: layout.detailOriginX)
            .padding(.vertical, 12)
            .transition(detailTransition)
        }
      }
      .animation(layoutAnimation, value: layout)
    }
  }

  private var layoutAnimation: Animation {
    reduceMotion ? .linear(duration: 0.12) : .smooth(duration: 0.28)
  }

  private var detailTransition: AnyTransition {
    reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
  }
}

struct RuntimeWorkspaceView: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var state: WorkspaceState
  @ObservedObject var runtimeBridge: RuntimeBridgeStore

  var body: some View {
    ZStack(alignment: .top) {
      RuntimeBridgeView(store: runtimeBridge)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(12)
        .opacity(runtimeBridge.isRuntimeTransitionPresented ? 1 : 0)
        .allowsHitTesting(runtimeBridge.isRuntimeTransitionPresented)
        .accessibilityHidden(!runtimeBridge.isRuntimeTransitionPresented)

      NativeConversationView(model: runtimeBridge.conversation)
        .padding(.vertical, 12)
        .opacity(runtimeBridge.isRuntimeTransitionPresented ? 0 : 1)
        .allowsHitTesting(!runtimeBridge.isRuntimeTransitionPresented)
        .accessibilityHidden(runtimeBridge.isRuntimeTransitionPresented)

      if runtimeBridge.isRuntimeTransitionPresented {
        Button {
          runtimeBridge.dismissRuntimeTransition()
        } label: {
          Label(copy[.returnToNativeConversation], systemImage: "arrow.left")
            .font(.caption.weight(.medium))
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
        }
        .buttonStyle(.plain)
        .rabbisirGlassSurface(cornerRadius: 12, interactive: true)
        .padding(.top, 20)
        .accessibilityLabel(copy[.returnToNativeConversationHint])
      }

      if state.webStatus != .ready {
        Label(state.webStatus.label(copy: copy), systemImage: "network")
          .font(.caption)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .conversationReadability(.secondary)
          .padding(.top, 22)
          .accessibilityLabel(state.webStatus.label(copy: copy))
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(
      runtimeBridge.isRuntimeTransitionPresented
        ? copy.transitionalSettingsWorkspaceAccessibility
        : copy.nativeConversationAccessibility
    )
  }
}

struct NativeDetailsView: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var state: WorkspaceState

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if state.detailKind == .artifact, let document = state.artifactDocument {
        NativeArtifactWorkbench(state: state, document: document)
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
      } else if let failure = state.artifactFailureMessage,
        state.detailKind == .artifact
      {
        Label(failure, systemImage: "exclamationmark.triangle")
          .foregroundStyle(.red)
      } else {
        VStack(spacing: 6) {
          Text(copy[.detailsEmptyFormats])
            .font(.callout.weight(.medium))
          Text(copy[.detailsEmptyHint])
            .font(.caption)
        }
        .foregroundStyle(NativePanelContentPalette.secondary)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(copy[.detailsFormatsAccessibility])
      }
    }
    .nativePanelContentForeground()
    .padding(18)
    .padding(.leading, PanelResizeHandleMetrics.protrusion)
    .rabbisirMainPanelGlass(
      TrailingEdgePanelShape(),
      role: .details
    )
    .accessibilityElement(children: .contain)
    .accessibilityLabel(copy[.detailsAccessibility])
  }

}

struct SpatialMainView: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var state: WorkspaceState
  @ObservedObject var runtimeBridge: RuntimeBridgeStore

  var body: some View {
    RuntimeWorkspaceView(
      state: state,
      runtimeBridge: runtimeBridge
    )
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .background(Color.clear)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(copy.mainConversationAccessibility)
  }
}

struct SpatialSidebarView: View {
  @ObservedObject var state: WorkspaceState
  @ObservedObject var runtimeBridge: RuntimeBridgeStore
  var onProjectRowHover: (String, Bool, CGRect) -> Void = { _, _, _ in }

  var body: some View {
    NativeSidebarView(
      state: state,
      runtimeBridge: runtimeBridge,
      onProjectRowHover: onProjectRowHover
    )
    .background(Color.clear)
  }
}

enum ModelPickerPresentationMetrics {
  static let panelWidth: CGFloat = 280
  static let rowHeight: CGFloat = 36

  static func submenuHeight(optionCount: Int, visibleHeight: CGFloat) -> CGFloat {
    let count = CGFloat(max(optionCount, 1))
    let idealHeight = 12 + count * (rowHeight + 6)
    let safeMaximum = max(110, min(260, visibleHeight * 0.18))
    return min(idealHeight, safeMaximum)
  }
}

private struct ModelPickerRowChrome: ViewModifier {
  let selected: Bool
  @State private var hovering = false

  func body(content: Content) -> some View {
    content
      .frame(minHeight: ModelPickerPresentationMetrics.rowHeight)
      .background(background, in: RoundedRectangle(cornerRadius: 9))
      .contentShape(RoundedRectangle(cornerRadius: 9))
      .onHover { hovering = $0 }
  }

  private var background: Color {
    if selected { return Color.accentColor.opacity(0.16) }
    if hovering { return Color.primary.opacity(0.085) }
    return Color.primary.opacity(0.045)
  }
}

struct SpatialInputView: View {
  @Environment(\.rabbisirCopy) private var copy
  private enum ModelPickerPane {
    case root
    case model
    case reasoning
  }

  @ObservedObject var state: WorkspaceState
  @ObservedObject var runtimeBridge: RuntimeBridgeStore
  @ObservedObject var conversation: NativeConversationStore
  @ObservedObject var workspaceDrawer: WorkspaceDrawerModel
  @ObservedObject var resizeGripVisualState: ComposerResizeGripVisualState
  @State private var actionFailure: String?
  @State private var isCreationModePresented = false
  @State private var isCommandsPresented = false
  @State private var isPermissionPresented = false
  @State private var isModelPresented = false
  @State private var modelPickerPane: ModelPickerPane = .root
  @State private var upstreamOptions: [RuntimeComposerChoiceKind: [RuntimeComposerOption]] = [:]
  @State private var loadingOptions: Set<RuntimeComposerChoiceKind> = []
  @State private var isSubmitting = false

  var body: some View {
    GeometryReader { proxy in
      ZStack(alignment: .topLeading) {
        composerBody
          .frame(
            width: proxy.size.width,
            height: composerInputLayout.surfaceHeight,
            alignment: .topLeading
          )
          .offset(
            y: WorkspaceDrawerLayout.composerOriginY(
              containerHeight: proxy.size.height,
              composerHeight: composerInputLayout.surfaceHeight
            )
          )

        if workspaceDrawer.isContentVisible {
          WorkspaceDrawerView(
            model: workspaceDrawer
          )
          .frame(
            width: InputComposerShape.tabRight,
            height: workspaceDrawerLayout.expansionHeight,
            alignment: .topLeading
          )
          .offset(
            y: WorkspaceDrawerLayout.drawerOriginY(
              containerHeight: proxy.size.height,
              composerHeight: composerInputLayout.surfaceHeight,
              drawerHeight: workspaceDrawerLayout.expansionHeight
            )
          )
        }
      }
      .frame(width: proxy.size.width, height: proxy.size.height, alignment: .topLeading)
      .clipped()
    }
    .nativePanelContentForeground()
    .padding(.trailing, PanelResizeHandleMetrics.protrusion)
    .rabbisirMainPanelGlass(
      InputComposerShape(composerSurfaceHeight: composerInputLayout.surfaceHeight),
      role: .conversation
    )
    .padding(.top, InputComposerShape.outerTopInset)
    .padding(.bottom, InputComposerShape.outerBottomInset)
    .padding(.leading, 8)
    .background(Color.clear)
    .overlay {
      GeometryReader { proxy in
        ComposerResizeGripDots(state: resizeGripVisualState)
          .position(
            x: proxy.size.width - PanelResizeHandleVariant.composer.size.width / 2,
            y: InputComposerShape.resizeGripTopOffset(
              containerHeight: proxy.size.height,
              composerSurfaceHeight: composerInputLayout.surfaceHeight
            ) + PanelResizeHandleVariant.composer.size.height / 2
          )
      }
    }
    .overlay(alignment: .top) {
      if let actionFailure {
        Label(actionFailure, systemImage: "exclamationmark.circle.fill")
          .font(.caption)
          .foregroundStyle(.orange)
          .padding(.horizontal, 12)
          .padding(.vertical, 7)
          .rabbisirGlassSurface(cornerRadius: 14)
          .offset(y: -34)
          .transition(.opacity)
          .accessibilityLabel(copy.composerStatus(actionFailure))
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(copy.composerPanelAccessibility)
    .task {
      while !Task.isCancelled {
        await runtimeBridge.refreshComposerProjection()
        try? await Task.sleep(for: .milliseconds(750))
      }
    }
    .onChange(of: runtimeBridge.composerProjection.workspace) {
      Task { await runtimeBridge.refreshNavigationProjection() }
    }
    .task(id: actionFailure) {
      guard actionFailure != nil else { return }
      try? await Task.sleep(for: .seconds(4))
      guard !Task.isCancelled else { return }
      actionFailure = nil
    }
  }

  private var visibleScreenHeight: CGFloat {
    runtimeBridge.webView.window?.screen?.visibleFrame.height ?? 900
  }

  private var workspaceDrawerLayout: WorkspaceDrawerLayout {
    WorkspaceDrawerLayout.addWorkspaceOnly()
  }

  private var composerInputLayout: ComposerInputLayout {
    ComposerInputLayout.resolve(
      measuredTextHeight: state.composerTextHeight,
      visibleHeight: visibleScreenHeight
    )
  }

  private var composerBody: some View {
    VStack(alignment: .leading, spacing: 0) {
      HStack(spacing: 12) {
        workspaceButton
      }
      .padding(.leading, 18)
      .padding(.trailing, 12)
      .frame(width: InputComposerShape.tabRight, height: 34, alignment: .leading)

      VStack(alignment: .leading, spacing: 8) {
        NativeComposerTextView(
          text: $state.inputDraft,
          focusRequest: state.inputFocusRequest,
          placeholder: copy[.composerPlaceholder],
          accessibilityLabel: copy[.composerInputAccessibility],
          onHeightChange: state.updateComposerTextHeight,
          onSubmit: submit
        )
        .frame(maxWidth: .infinity, alignment: .leading)
        .frame(height: composerInputLayout.textViewportHeight)
        .contentShape(Rectangle())

        HStack(alignment: .center, spacing: 10) {
          commandsButton
          composerControl(
            title: copy.composerPermissionName(runtimeBridge.composerProjection.permission),
            systemImage: "checkmark.shield",
            control: .permission,
            accessibilityLabel: copy[.composerCurrentPermission]
          )
          creationModeButton
          Spacer()
          composerControl(
            title: runtimeBridge.composerProjection.modelAndReasoning,
            systemImage: nil,
            control: .modelAndReasoning,
            accessibilityLabel: copy[.composerCurrentModelReasoning]
          )

          generationActionButton
        }
        .offset(y: ComposerInputLayout.controlRowOffsetY)
      }
      .padding(.horizontal, 18)
      .padding(.vertical, 12)
    }
  }

  private var workspaceButton: some View {
    Button {
      workspaceDrawer.toggle()
    } label: {
      HStack(alignment: .center, spacing: 5) {
        Image(systemName: "folder")
          .resizable()
          .scaledToFit()
          .frame(width: 12, height: 10)
          .frame(width: 14, height: 16, alignment: .center)
        Text(runtimeBridge.currentWorkspaceDisplayName)
          .font(.system(size: 12))
          .lineLimit(1)
          .frame(height: 16, alignment: .center)
        Image(
          systemName: WorkspaceDrawerPresentationPolicy.triggerSymbolName(
            isPresented: workspaceDrawer.isPresented
          )
        )
        .resizable()
        .scaledToFit()
        .frame(width: 7, height: 4)
        .frame(width: 9, height: 16, alignment: .center)
        .foregroundStyle(NativePanelContentPalette.secondary)
      }
      .frame(height: 20, alignment: .center)
    }
    .buttonStyle(RabbisirStablePressButtonStyle())
    .accessibilityLabel(copy.currentWorkspace(runtimeBridge.currentWorkspaceDisplayName))
    .accessibilityHint(copy[.composerWorkspaceHint])
  }

  private var generationActionState: ComposerGenerationActionState {
    ComposerGenerationActionPolicy.state(
      isRunning: conversation.isGenerationRunning,
      isCancellationPending: conversation.isGenerationCancellationPending
    )
  }

  @ViewBuilder
  private var generationActionButton: some View {
    switch generationActionState {
    case .send:
      Button(action: { submit(.button) }) {
        Image(systemName: "arrow.up.circle.fill")
          .resizable()
          .scaledToFit()
          .frame(width: 24, height: 24)
          .frame(width: 28, height: 28)
      }
      .buttonStyle(.plain)
      .disabled(
        state.inputDraft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
          || !runtimeBridge.composerProjection.canSubmit
          || isSubmitting
      )
      .accessibilityLabel(copy[.composerSendCurrent])
    case .stop:
      Button(action: stopGeneration) {
        Label(copy[.composerStopGeneration], systemImage: "stop.circle.fill")
          .font(.system(size: 12, weight: .medium))
          .lineLimit(1)
      }
      .buttonStyle(.borderless)
      .keyboardShortcut(".", modifiers: [.command])
      .help(copy[.composerStopGenerationHint])
      .accessibilityLabel(copy[.composerStopGeneration])
      .accessibilityHint(copy[.composerStopGenerationHint])
    case .stopping:
      Label(copy[.composerStoppingGeneration], systemImage: "stop.circle")
        .font(.system(size: 12, weight: .medium))
        .foregroundStyle(NativePanelContentPalette.secondary)
        .lineLimit(1)
        .accessibilityLabel(copy[.composerStoppingGeneration])
    }
  }

  private var commandsButton: some View {
    Button {
      isCommandsPresented = true
      loadOptions(.commands)
    } label: {
      ZStack {
        Circle()
          .fill(.white.opacity(0.14))
        Image(systemName: "plus")
          .resizable()
          .scaledToFit()
          .frame(width: 10, height: 10)
      }
      .frame(width: 28, height: 28)
    }
    .buttonStyle(.plain)
    .disabled(!runtimeBridge.composerProjection.isAvailable)
    .popover(isPresented: $isCommandsPresented, arrowEdge: .top) {
      optionPopover(
        title: copy[.composerCommandsAndAdd],
        kind: .commands,
        minimumWidth: 260
      )
    }
    .accessibilityLabel(copy[.composerCommands])
    .accessibilityHint(copy[.composerCommandsHint])
  }

  private var creationModeButton: some View {
    Button {
      isCreationModePresented = true
      loadOptions(.agentPreset)
    } label: {
      composerChoiceLabel(
        title: creationModeDisplayTitle,
        systemImage: "wand.and.stars"
      )
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
    .disabled(!runtimeBridge.composerProjection.isAgentPresetAvailable)
    .popover(isPresented: $isCreationModePresented, arrowEdge: .top) {
      optionPopover(
        title: copy[.agentPresets],
        kind: .agentPreset,
        minimumWidth: 280
      )
    }
    .accessibilityLabel("\(copy[.agentPresets])：\(creationModeDisplayTitle)")
    .accessibilityHint(copy[.composerAgentPresetHint])
  }

  private var creationModeDisplayTitle: String {
    copy.agentPresets.localizedName(runtimeBridge.composerProjection.agentPreset)
  }

  private func composerControl(
    title: String,
    systemImage: String?,
    control: RuntimeComposerControl,
    accessibilityLabel: String
  ) -> some View {
    Button {
      switch control {
      case .permission:
        isPermissionPresented = true
        loadOptions(.permission)
      case .modelAndReasoning:
        modelPickerPane = .root
        isModelPresented = true
        loadModelAndReasoningOptions()
      case .commands:
        isCommandsPresented = true
        loadOptions(.commands)
      }
    } label: {
      composerChoiceLabel(title: title, systemImage: systemImage)
    }
    .buttonStyle(.borderless)
    .controlSize(.small)
    .disabled(!runtimeBridge.composerProjection.isAvailable)
    .popover(
      isPresented: control == .permission ? $isPermissionPresented : $isModelPresented,
      arrowEdge: .top
    ) {
      if control == .permission {
        optionPopover(
          title: copy[.permissions],
          kind: .permission,
          minimumWidth: 250
        )
      } else {
        modelAndReasoningPopover
      }
    }
    .accessibilityLabel("\(accessibilityLabel)：\(title)")
    .accessibilityHint(copy[.composerOptionsHint])
  }

  private func composerChoiceLabel(
    title: String,
    systemImage: String?
  ) -> some View {
    HStack(alignment: .center, spacing: 5) {
      if let systemImage {
        Image(systemName: systemImage)
          .resizable()
          .scaledToFit()
          .frame(width: 12, height: 12)
          .frame(width: 14, height: 16, alignment: .center)
      }
      Text(title)
        .font(.system(size: 13))
        .frame(height: 16, alignment: .center)
      Image(systemName: "chevron.up")
        .resizable()
        .scaledToFit()
        .frame(width: 7, height: 4)
        .frame(width: 9, height: 16, alignment: .center)
        .foregroundStyle(NativePanelContentPalette.secondary)
    }
    .lineLimit(1)
    .frame(height: 28, alignment: .center)
  }

  private var modelAndReasoningPopover: some View {
    VStack(spacing: 6) {
      modelRootRow(
        title: copy[.model],
        value: selectedOptionLabel(for: .model),
        destination: .model
      )
      modelRootRow(
        title: copy[.settingsReasoningLevel],
        value: selectedOptionLabel(for: .reasoning),
        destination: .reasoning
      )
    }
    .padding(8)
    .frame(width: ModelPickerPresentationMetrics.panelWidth)
    .rabbisirGlassSurface(cornerRadius: 13, interactive: true)
    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    .presentationBackground(.clear)
    .accessibilityElement(children: .contain)
  }

  private func modelRootRow(
    title: String,
    value: String,
    destination: ModelPickerPane
  ) -> some View {
    Button {
      modelPickerPane = modelPickerPane == destination ? .root : destination
    } label: {
      HStack(spacing: 10) {
        Text(title)
          .font(.system(size: 13, weight: .medium))
        Spacer(minLength: 18)
        Text(value)
          .font(.system(size: 13))
          .foregroundStyle(NativePanelContentPalette.secondary)
          .lineLimit(1)
        Image(systemName: "chevron.right")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(NativePanelContentPalette.secondary)
      }
      .padding(.horizontal, 10)
      .modifier(ModelPickerRowChrome(selected: modelPickerPane == destination))
    }
    .buttonStyle(.plain)
    .popover(
      isPresented: submenuBinding(for: destination),
      arrowEdge: .trailing
    ) {
      modelSubmenu(
        title: destination == .model ? copy[.model] : copy[.settingsReasoningLevel],
        kind: destination == .model ? .model : .reasoning
      )
    }
    .accessibilityLabel("\(title)：\(value)")
    .accessibilityHint(copy.submenuHint(title))
  }

  private func submenuBinding(for destination: ModelPickerPane) -> Binding<Bool> {
    Binding(
      get: { modelPickerPane == destination },
      set: { isPresented in
        if isPresented {
          modelPickerPane = destination
        } else if modelPickerPane == destination {
          modelPickerPane = .root
        }
      }
    )
  }

  private func modelSubmenu(
    title: String,
    kind: RuntimeComposerChoiceKind
  ) -> some View {
    let optionCount = upstreamOptions[kind, default: []].count
    let visibleHeight = runtimeBridge.webView.window?.screen?.visibleFrame.height ?? 900
    let listHeight = ModelPickerPresentationMetrics.submenuHeight(
      optionCount: optionCount,
      visibleHeight: visibleHeight
    )

    return ScrollView(.vertical, showsIndicators: false) {
      modelOptionSection(kind: kind)
        .padding(8)
    }
    .frame(width: ModelPickerPresentationMetrics.panelWidth, height: listHeight)
    .rabbisirGlassSurface(cornerRadius: 13, interactive: true)
    .shadow(color: .black.opacity(0.16), radius: 16, y: 8)
    .presentationBackground(.clear)
    .accessibilityLabel(copy.submenuOptions(title))
  }

  @ViewBuilder
  private func modelOptionSection(
    kind: RuntimeComposerChoiceKind
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      if loadingOptions.contains(kind) {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(copy[.composerCurrentOptionsLoading])
            .font(.system(size: 12))
            .foregroundStyle(NativePanelContentPalette.secondary)
        }
        .frame(minHeight: ModelPickerPresentationMetrics.rowHeight)
        .padding(.horizontal, 8)
      } else if upstreamOptions[kind, default: []].isEmpty {
        Text(copy[.composerNoOptions])
          .font(.system(size: 12))
          .foregroundStyle(NativePanelContentPalette.secondary)
          .frame(minHeight: ModelPickerPresentationMetrics.rowHeight)
          .padding(.horizontal, 8)
      } else {
        ForEach(upstreamOptions[kind, default: []]) { option in
          modelOptionButton(option, kind: kind)
        }
      }
    }
  }

  private func modelOptionButton(
    _ option: RuntimeComposerOption,
    kind: RuntimeComposerChoiceKind
  ) -> some View {
    Button {
      chooseComposerOption(option, kind: kind)
    } label: {
      HStack(alignment: .center, spacing: 8) {
        VStack(alignment: .leading, spacing: 1) {
          Text(option.label)
            .font(.system(size: 13, weight: option.isSelected ? .medium : .regular))
            .frame(maxWidth: .infinity, alignment: .leading)
          if let detail = option.detail {
            Text(detail)
              .font(.system(size: 11))
              .foregroundStyle(NativePanelContentPalette.secondary)
              .lineLimit(1)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        if option.isSelected {
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(.tint)
        }
      }
      .padding(.horizontal, 10)
      .modifier(ModelPickerRowChrome(selected: option.isSelected))
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      option.isSelected ? "\(option.label)，\(copy[.composerSelected])" : option.label
    )
  }

  private func selectedOptionLabel(for kind: RuntimeComposerChoiceKind) -> String {
    if let selected = upstreamOptions[kind, default: []].first(where: \.isSelected) {
      return selected.label
    }
    let parts = runtimeBridge.composerProjection.modelAndReasoning
      .split(separator: "·", maxSplits: 1)
      .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    switch kind {
    case .model:
      return parts.first ?? copy.sessionModelFallback
    case .reasoning:
      return parts.count > 1 ? parts[1] : copy.defaultFallback
    default:
      return ""
    }
  }

  private func optionPopover(
    title: String,
    kind: RuntimeComposerChoiceKind,
    minimumWidth: CGFloat
  ) -> some View {
    ScrollView {
      optionSection(title: title, kind: kind)
    }
    .padding(12)
    .frame(minWidth: minimumWidth, maxWidth: 360)
    .frame(maxHeight: 390)
    .accessibilityLabel(copy.pullUpOptions(title))
  }

  @ViewBuilder
  private func optionSection(
    title: String,
    kind: RuntimeComposerChoiceKind
  ) -> some View {
    VStack(alignment: .leading, spacing: 6) {
      Text(title)
        .font(.caption.weight(.semibold))
        .foregroundStyle(NativePanelContentPalette.secondary)

      if loadingOptions.contains(kind) {
        HStack(spacing: 8) {
          ProgressView()
            .controlSize(.small)
          Text(copy[.composerCurrentOptionsLoading])
            .font(.caption)
            .foregroundStyle(NativePanelContentPalette.secondary)
        }
        .padding(.vertical, 6)
      } else if upstreamOptions[kind, default: []].isEmpty {
        Text(copy[.composerNoOptions])
          .font(.caption)
          .foregroundStyle(NativePanelContentPalette.secondary)
          .padding(.vertical, 6)
      } else {
        ForEach(upstreamOptions[kind, default: []]) { option in
          optionButton(option, kind: kind)
        }
      }
    }
  }

  private func optionButton(
    _ option: RuntimeComposerOption,
    kind: RuntimeComposerChoiceKind
  ) -> some View {
    Button {
      chooseComposerOption(option, kind: kind)
    } label: {
      HStack(alignment: .top, spacing: 8) {
        VStack(alignment: .leading, spacing: 2) {
          Text(optionLabel(option, kind: kind))
            .frame(maxWidth: .infinity, alignment: .leading)
          if let detail = option.detail {
            Text(optionDetail(detail, kind: kind))
              .font(.caption)
              .foregroundStyle(NativePanelContentPalette.secondary)
              .frame(maxWidth: .infinity, alignment: .leading)
          }
        }
        if option.isSelected {
          Image(systemName: "checkmark")
            .foregroundStyle(.tint)
        }
      }
      .contentShape(Rectangle())
      .padding(.horizontal, 8)
      .padding(.vertical, 6)
    }
    .buttonStyle(.plain)
    .accessibilityLabel(
      option.isSelected
        ? "\(optionLabel(option, kind: kind))，\(copy[.composerSelected])"
        : optionLabel(option, kind: kind)
    )
  }

  private func optionLabel(
    _ option: RuntimeComposerOption,
    kind: RuntimeComposerChoiceKind
  ) -> String {
    switch kind {
    case .agentPreset:
      copy.agentPresets.localizedName(option.label)
    case .permission:
      copy.composerPermissionName(option.label)
    default:
      option.label
    }
  }

  private func optionDetail(
    _ detail: String,
    kind: RuntimeComposerChoiceKind
  ) -> String {
    guard kind == .agentPreset else { return detail }
    return copy.agentPresets.localizedDescription(detail)
  }

  private func loadOptions(_ kind: RuntimeComposerChoiceKind) {
    guard !loadingOptions.contains(kind) else { return }
    loadingOptions.insert(kind)
    Task { @MainActor in
      let options = await runtimeBridge.composerOptions(for: kind)
      upstreamOptions[kind] = options
      loadingOptions.remove(kind)
      if options.isEmpty {
        actionFailure = copy.optionUnavailable(optionKindLabel(kind))
      } else {
        actionFailure = nil
      }
    }
  }

  private func loadModelAndReasoningOptions() {
    guard !loadingOptions.contains(.model),
      !loadingOptions.contains(.reasoning)
    else { return }
    loadingOptions.insert(.model)
    loadingOptions.insert(.reasoning)
    Task { @MainActor in
      let models = await runtimeBridge.composerOptions(for: .model)
      upstreamOptions[.model] = models
      loadingOptions.remove(.model)

      let reasoning = await runtimeBridge.composerOptions(for: .reasoning)
      upstreamOptions[.reasoning] = reasoning
      loadingOptions.remove(.reasoning)

      actionFailure =
        models.isEmpty && reasoning.isEmpty
        ? copy[.composerNoModelReasoning]
        : nil
    }
  }

  private func chooseComposerOption(
    _ option: RuntimeComposerOption,
    kind: RuntimeComposerChoiceKind
  ) {
    Task { @MainActor in
      let result = await runtimeBridge.selectComposerOption(option, kind: kind)
      guard result.accepted else {
        actionFailure = copy.optionRejected(optionKindLabel(kind))
        return
      }
      switch kind {
      case .workspace:
        break
      case .agentPreset:
        isCreationModePresented = false
      case .commands:
        if let draft = result.draft {
          state.inputDraft = draft
        }
        isCommandsPresented = false
        state.requestInputFocus()
      case .permission:
        isPermissionPresented = false
      case .model, .reasoning:
        modelPickerPane = .root
      }
      actionFailure =
        result.requiresUpstreamConfirmation
        ? copy[.composerConfirmationRequired]
        : nil
      await runtimeBridge.refreshComposerProjection()
      if kind == .model || kind == .reasoning {
        upstreamOptions[.model] = await runtimeBridge.composerOptions(for: .model)
        upstreamOptions[.reasoning] = await runtimeBridge.composerOptions(for: .reasoning)
      } else {
        upstreamOptions[kind] = await runtimeBridge.composerOptions(for: kind)
      }
    }
  }

  private func optionKindLabel(_ kind: RuntimeComposerChoiceKind) -> String {
    switch kind {
    case .workspace:
      copy[.workspace]
    case .agentPreset:
      copy[.agentPresets]
    case .commands:
      copy[.composerCommands]
    case .permission:
      copy[.permissions]
    case .model:
      copy[.model]
    case .reasoning:
      copy[.settingsReasoningLevel]
    }
  }

  private func submit(_ gesture: ComposerSubmitGesture) {
    guard !isSubmitting else { return }
    let draft = state.inputDraft
    guard !draft.isEmpty || gesture == .accelerated else { return }
    isSubmitting = true
    Task { @MainActor in
      defer { isSubmitting = false }
      if await runtimeBridge.submitInput(draft, gesture: gesture) {
        state.inputDraft = ""
        actionFailure = nil
      } else {
        actionFailure = copy[.composerSubmitRejected]
      }
    }
  }

  private func stopGeneration() {
    guard generationActionState == .stop else { return }
    Task { @MainActor in
      if await runtimeBridge.cancelCurrentGeneration() {
        actionFailure = nil
      } else {
        actionFailure = copy[.composerStopRejected]
      }
    }
  }
}

struct SpatialDetailsView: View {
  @ObservedObject var state: WorkspaceState

  var body: some View {
    NativeDetailsView(state: state)
      .background(Color.clear)
  }
}
