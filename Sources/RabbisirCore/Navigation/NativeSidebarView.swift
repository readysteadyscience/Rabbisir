import AppKit
import SwiftUI

struct NativeSidebarView: View {
  @Environment(\.rabbisirCopy) private var copy
  @ObservedObject var state: WorkspaceState
  @ObservedObject var runtimeBridge: RuntimeBridgeStore
  var onProjectRowHover: (String, Bool, CGRect) -> Void = { _, _, _ in }
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var expandedProjectIDs = NativeNavigationLayout.initialExpandedProjectIDs
  @State private var projectHoverPresentation = NavigationProjectHoverPresentationState()
  @State private var sessionHoverPresentation = NavigationSessionHoverPresentationState()
  @State private var actionFailure: String?
  @StateObject private var navigationScrollState = ScrollbarFreeScrollViewState()

  var body: some View {
    GeometryReader { geometry in
      ScrollViewReader { reader in
        let scrollViewportHeight = NativeNavigationLayout.scrollViewportHeight(
          totalViewportHeight: geometry.size.height
        )
        ZStack(alignment: .topLeading) {
          ScrollView(.vertical, showsIndicators: false) {
            navigationStack(reader: reader, viewportHeight: scrollViewportHeight)
          }
          .scrollIndicators(.hidden)
          .padding(.vertical, NativeNavigationLayout.safeVerticalInset)
          navigationOverflowControls(
            reader: reader,
            viewportSize: geometry.size
          )
        }
        .onChange(of: runtimeBridge.navigationSelectionRevision) { _, _ in
          revealCurrentSelection(using: reader, animated: true)
        }
      }
    }
    .coordinateSpace(name: "Rabbisir.sidebarNavigation")
    .background(Color.clear)
    .accessibilityElement(children: .contain)
    .accessibilityLabel(copy[.sidebarAccessibility])
    .task(id: state.webStatus.label(copy: copy)) {
      guard state.webStatus == .ready else { return }
      for _ in 0..<3 where runtimeBridge.navigationProjects.isEmpty {
        await runtimeBridge.refreshNavigationProjection()
        guard runtimeBridge.navigationProjects.isEmpty else { return }
        try? await Task.sleep(for: .seconds(1))
        guard !Task.isCancelled else { return }
      }
    }
  }

  @ViewBuilder
  private func navigationStack(
    reader: ScrollViewProxy,
    viewportHeight: CGFloat
  ) -> some View {
    navigationProjectStack(reader: reader, viewportHeight: viewportHeight)
  }

  private func navigationProjectStack(
    reader: ScrollViewProxy,
    viewportHeight: CGFloat
  ) -> some View {
    LazyVStack(alignment: .leading, spacing: NativeNavigationLayout.projectSpacing) {
      navigationContent(reader: reader, viewportHeight: viewportHeight)
    }
    .frame(
      minHeight: NativeNavigationLayout.minimumContentHeight(viewportHeight: viewportHeight),
      alignment: .center
    )
    .background(ScrollbarFreeScrollViewBridge(state: navigationScrollState))
    .padding(.trailing, NativeNavigationLayout.trailingInteractionReserve)
  }

  @ViewBuilder
  private func navigationOverflowControls(
    reader: ScrollViewProxy,
    viewportSize: CGSize
  ) -> some View {
    let visibility = navigationScrollState.overflowVisibility
    let navigationWidth = max(
      0,
      viewportSize.width - NativeNavigationLayout.trailingInteractionReserve
    )
    if visibility.hasHiddenAbove {
      NavigationOverflowButton(edge: .top) {
        scrollToNavigationBoundary(.top, using: reader)
      }
      .position(
        x: navigationWidth / 2,
        y: NativeNavigationLayout.overflowControlCenterY(
          edge: .top,
          viewportHeight: viewportSize.height
        )
      )
    }
    if visibility.hasHiddenBelow {
      NavigationOverflowButton(edge: .bottom) {
        scrollToNavigationBoundary(.bottom, using: reader)
      }
      .position(
        x: navigationWidth / 2,
        y: NativeNavigationLayout.overflowControlCenterY(
          edge: .bottom,
          viewportHeight: viewportSize.height
        )
      )
    }
  }

  @ViewBuilder
  private func navigationContent(
    reader: ScrollViewProxy,
    viewportHeight: CGFloat
  ) -> some View {
    if runtimeBridge.isNavigationLoading {
      statusRow(copy[.sidebarLoading], symbol: "arrow.triangle.2.circlepath")
    } else if runtimeBridge.navigationProjects.isEmpty {
      statusRow(
        runtimeBridge.navigationFailure ?? copy[.sidebarEmpty],
        symbol: "folder"
      )
    } else {
      ForEach(runtimeBridge.activeNavigationProjects) { project in
        projectSection(
          project,
          isArchived: false,
          reader: reader,
          viewportHeight: viewportHeight
        )
      }
      if !runtimeBridge.archivedNavigationProjects.isEmpty {
        statusRow(copy[.sidebarArchivedProjects], symbol: "archivebox")
        ForEach(runtimeBridge.archivedNavigationProjects) { project in
          projectSection(
            project,
            isArchived: true,
            reader: reader,
            viewportHeight: viewportHeight
          )
        }
      }
    }

    if let actionFailure {
      statusRow(actionFailure, symbol: "exclamationmark.circle")
        .conversationReadability(.failure)
    }
  }

  private func projectSection(
    _ project: RuntimeNavigationProject,
    isArchived: Bool,
    reader: ScrollViewProxy,
    viewportHeight: CGFloat
  ) -> some View {
    let isExpanded = expandedProjectIDs.contains(project.id)
    let isHovered = projectHoverPresentation.isPresented(for: project.id)
    let containsHoveredSession = project.sessions.contains {
      sessionHoverPresentation.isPresented(for: $0.id)
    }
    let projectSurfaceShape = NativeNavigationGroupShape(
      trailingRadius: NativeNavigationLayout.trailingRadius,
      projectRowHeight: NativeNavigationLayout.projectRowHeight,
      projectExtensionWidth: NativeNavigationMaterialPolicy.projectOwnerExtensionWidth(
        isHovered: isHovered
      )
    )
    return VStack(alignment: .leading, spacing: 0) {
      ProjectNavigationRow(
        project: project,
        isExpanded: isExpanded,
        isCurrent: project.containsSelectedSession,
        isHoverPresented: isHovered,
        isHandleHovered: state.sidebarHandleHoveredProjectID == project.id,
        actions: projectActions(project, isArchived: isArchived),
        onHoverChanged: { hovering in
          projectHoverPresentation.set(projectID: project.id, hovering: hovering)
        },
        onResizeHandleHoverChanged: { hovering, frame in
          onProjectRowHover(project.id, hovering, frame)
        }
      ) {
        toggle(project, reader: reader, viewportHeight: viewportHeight)
      }
      .frame(height: NativeNavigationLayout.projectRowHeight)
      .id(projectAnchorID(project.id))

      VStack(alignment: .leading, spacing: NativeNavigationLayout.childSpacing) {
        ForEach(project.sessions) { session in
          SessionNavigationRow(
            session: session,
            isHoverPresented: sessionHoverPresentation.isPresented(for: session.id),
            actions: sessionActions(session, in: project),
            moveTargets: sessionMoveTargets(session, excluding: project),
            onFork: {
              Task { @MainActor in
                actionFailure =
                  await runtimeBridge.forkNavigationSession(session)
                  ? nil : copy.sidebarFailure(.branch)
              }
            },
            onShowInFinder: {
              guard let cwd = session.cwd,
                NavigationSessionSystemActions.showInFinder(cwd)
              else {
                actionFailure = copy.sidebarFailure(.workingDirectory)
                return
              }
              actionFailure = nil
            },
            onCopyWorkingDirectory: {
              guard let cwd = session.cwd else { return }
              NavigationSessionSystemActions.copyWorkingDirectory(cwd)
              actionFailure = nil
            },
            onCopySessionID: {
              NavigationSessionSystemActions.copySessionID(session.id)
              actionFailure = nil
            },
            onHoverChanged: { hovering in
              sessionHoverPresentation.set(sessionID: session.id, hovering: hovering)
            }
          ) {
            openSession(session)
          }
          .frame(height: NativeNavigationLayout.sessionRowHeight)
          .id(session.id)
        }
      }
      .fixedSize(horizontal: false, vertical: true)
      .padding(.top, NativeNavigationLayout.childSpacing)
      .nativeNavigationChildGlass()
      .frame(
        height: NativeNavigationLayout.visibleChildSectionHeight(
          sessionCount: project.sessions.count,
          isExpanded: isExpanded
        ),
        alignment: .top
      )
      .navigationChildRevealClipped(!containsHoveredSession)
      .opacity(isExpanded ? 1 : 0)
      .allowsHitTesting(isExpanded)
      .accessibilityHidden(!isExpanded)
    }
    .navigationProjectGlassSurface(
      projectSurfaceShape,
      ownsSurface: NavigationHoverActionSurfaceStyle.project.usesOwnerGlassSurface
    )
    .animation(hoverExtensionAnimation, value: isHovered)
    .id(projectSectionID(project.id))
  }

  private func statusRow(_ text: String, symbol: String) -> some View {
    Label(text, systemImage: symbol)
      .font(.caption)
      .lineLimit(2)
      .padding(.horizontal, 8)
      .padding(.vertical, 7)
      .conversationReadability(.secondary)
  }

  private func toggle(
    _ project: RuntimeNavigationProject,
    reader: ScrollViewProxy,
    viewportHeight: CGFloat
  ) {
    let opening = !expandedProjectIDs.contains(project.id)
    withAnimation(treeAnimation) {
      if opening {
        expandedProjectIDs.insert(project.id)
      } else {
        expandedProjectIDs.remove(project.id)
      }
    }
    guard opening,
      let lastSessionID = project.sessions.last?.id,
      NativeNavigationLayout.expansionNeedsBottomReveal(
        projects: runtimeBridge.navigationProjects,
        expandedProjectIDs: expandedProjectIDs,
        viewportHeight: viewportHeight
      )
    else { return }
    Task { @MainActor in
      await Task.yield()
      withAnimation(treeAnimation) {
        reader.scrollTo(lastSessionID, anchor: .bottom)
      }
    }
  }

  private func revealCurrentSelection(using reader: ScrollViewProxy, animated: Bool) {
    guard
      let project = runtimeBridge.navigationProjects.first(where: { project in
        project.sessions.contains(where: \.isSelected)
      }),
      let session = project.sessions.first(where: \.isSelected)
    else { return }
    expandedProjectIDs.insert(project.id)
    Task { @MainActor in
      await Task.yield()
      if animated && !reduceMotion {
        withAnimation(treeAnimation) {
          reader.scrollTo(session.id, anchor: .center)
        }
      } else {
        reader.scrollTo(session.id, anchor: .center)
      }
    }
  }

  private func openSession(_ session: RuntimeNavigationSession) {
    guard !session.isSelected else { return }
    Task { @MainActor in
      actionFailure =
        await runtimeBridge.selectNavigationSession(session)
        ? nil
        : copy.sidebarFailure(.open)
    }
  }

  private func projectActions(
    _ project: RuntimeNavigationProject,
    isArchived: Bool
  ) -> [NavigationHoverActionConfiguration] {
    guard project.id != UpstreamNavigationProjection.ungroupedProjectID else { return [] }
    return [
      NavigationHoverActionConfiguration(
        id: "pin",
        symbol: "pin",
        accessibilityLabel: copy[.sidebarPinProject]
      ) {
        Task { @MainActor in
          actionFailure =
            await runtimeBridge.pinNavigationProject(project)
            ? nil : copy.sidebarFailure(.pinProject)
        }
      },
      NavigationHoverActionConfiguration(
        id: "edit",
        symbol: "pencil",
        accessibilityLabel: copy[.sidebarEditProject]
      ) {
        guard
          let title = NavigationProjectDialogs.requestedRename(
            currentTitle: project.title
          )
        else { return }
        Task { @MainActor in
          actionFailure =
            await runtimeBridge.renameNavigationProject(project, title: title)
            ? nil : copy.sidebarFailure(.renameProject)
        }
      },
      NavigationHoverActionConfiguration(
        id: "archive",
        symbol: isArchived ? "archivebox.fill" : "archivebox",
        accessibilityLabel:
          isArchived ? copy[.sidebarUnarchiveProject] : copy[.sidebarArchiveProject]
      ) {
        runtimeBridge.setNavigationProjectArchived(project, archived: !isArchived)
        actionFailure = nil
      },
      NavigationHoverActionConfiguration(
        id: "delete",
        symbol: "trash",
        accessibilityLabel: copy[.sidebarDeleteProject],
        role: .destructive
      ) {
        guard
          NavigationProjectDialogs.confirmsRegistrationDeletion(
            projectTitle: project.title
          )
        else { return }
        Task { @MainActor in
          actionFailure =
            await runtimeBridge.deleteNavigationProject(project)
            ? nil : copy.sidebarFailure(.deleteProject)
        }
      },
    ]
  }

  private func sessionActions(
    _ session: RuntimeNavigationSession,
    in project: RuntimeNavigationProject
  ) -> [NavigationHoverActionConfiguration] {
    let policy = NavigationSessionActionPolicy.hoverActions(
      belongsToDurableWorkspace: project.id != UpstreamNavigationProjection.ungroupedProjectID
    )
    return policy.map { capability in
      switch capability.kind {
      case .pin:
        NavigationHoverActionConfiguration(
          id: "pin",
          symbol: "pin",
          accessibilityLabel: copy[.sidebarPinSession],
          isEnabled: capability.isEnabled,
          disabledReason: copy.ungroupedSessionPinUnavailable
        ) {
          Task { @MainActor in
            actionFailure =
              await runtimeBridge.pinNavigationSession(session, in: project)
              ? nil : copy.sidebarFailure(.pinSession)
          }
        }
      case .rename:
        NavigationHoverActionConfiguration(
          id: "rename",
          symbol: "pencil",
          accessibilityLabel: copy[.sidebarRenameSession],
          isEnabled: capability.isEnabled
        ) {
          guard
            let title = NavigationProjectDialogs.requestedSessionRename(
              currentTitle: session.title
            )
          else { return }
          Task { @MainActor in
            actionFailure =
              await runtimeBridge.renameNavigationSession(session, title: title)
              ? nil : copy.sidebarFailure(.renameSession)
          }
        }
      case .archive:
        NavigationHoverActionConfiguration(
          id: "archive",
          symbol: "archivebox",
          accessibilityLabel: copy[.sidebarArchiveSession],
          isEnabled: capability.isEnabled
        ) {
          Task { @MainActor in
            actionFailure =
              await runtimeBridge.archiveNavigationSession(session)
              ? nil : copy.sidebarFailure(.archiveSession)
          }
        }
      case .delete:
        NavigationHoverActionConfiguration(
          id: "delete",
          symbol: "trash",
          accessibilityLabel: copy[.sidebarDeleteSession],
          isEnabled: false,
          disabledReason: copy.sessionDeletionUnavailable,
          role: .destructive
        ) {}
      default:
        preconditionFailure("Context-menu-only action reached hover policy")
      }
    }
  }

  private func sessionMoveTargets(
    _ session: RuntimeNavigationSession,
    excluding currentProject: RuntimeNavigationProject
  ) -> [NavigationSessionMoveTarget] {
    activeNavigationProjectsExceptUngrouped
      .filter { $0.id != currentProject.id }
      .map { project in
        NavigationSessionMoveTarget(id: project.id, title: project.title) {
          Task { @MainActor in
            actionFailure =
              await runtimeBridge.moveNavigationSession(session, to: project)
              ? nil : copy.sidebarFailure(.moveSession)
          }
        }
      }
  }

  private var activeNavigationProjectsExceptUngrouped: [RuntimeNavigationProject] {
    runtimeBridge.activeNavigationProjects.filter {
      $0.id != UpstreamNavigationProjection.ungroupedProjectID
    }
  }

  private func projectAnchorID(_ projectID: String) -> String {
    "project.\(projectID)"
  }

  private func projectSectionID(_ projectID: String) -> String {
    "navigation-project.\(projectID)"
  }

  private func scrollToNavigationBoundary(
    _ edge: NativeNavigationOverflowEdge,
    using reader: ScrollViewProxy
  ) {
    let projects = runtimeBridge.activeNavigationProjects + runtimeBridge.archivedNavigationProjects
    guard let project = edge == .top ? projects.first : projects.last else { return }
    withAnimation(treeAnimation) {
      reader.scrollTo(
        projectSectionID(project.id),
        anchor: edge == .top ? .top : .bottom
      )
    }
  }

  private var treeAnimation: Animation? {
    reduceMotion
      ? .linear(duration: RabbisirMotionToken.statusFeedback.duration)
      : .easeInOut(duration: RabbisirMotionToken.sidebarShowHide.duration)
  }

  private var hoverExtensionAnimation: Animation {
    reduceMotion
      ? .linear(duration: RabbisirMotionToken.statusFeedback.duration)
      : .smooth(duration: RabbisirMotionToken.navigationRowHandleReveal.duration)
  }
}

private struct NavigationOverflowButton: View {
  @Environment(\.rabbisirCopy) private var copy
  let edge: NativeNavigationOverflowEdge
  let action: () -> Void
  @State private var hovering = false
  @Environment(\.navigationOverflowPressed) private var navigationOverflowPressed

  var body: some View {
    Button(action: action) {
      ZStack {
        Image(systemName: edge == .top ? "arrow.up" : "arrow.down")
          .font(.system(size: 12, weight: .semibold))
          .foregroundStyle(
            hovering ? Color(nsColor: .systemGreen) : NativeNavigationStyle.foreground
          )
          .opacity(hovering ? 1 : 0.78)
          .offset(y: navigationOverflowPressed ? (edge == .top ? -0.75 : 0.75) : 0)
      }
      .frame(
        width: NativeNavigationLayout.overflowControlDiameter,
        height: NativeNavigationLayout.overflowControlDiameter
      )
      .rabbisirGlassSurface(
        Circle(),
        role: .interactiveControl,
        interactive: true
      )
      .contentShape(Circle())
    }
    .buttonStyle(NavigationOverflowPressButtonStyle())
    .onHover { hovering = $0 }
    .accessibilityLabel(
      edge == .top ? copy[.sidebarScrollTop] : copy[.sidebarScrollBottom]
    )
  }
}

private struct NavigationOverflowPressedKey: EnvironmentKey {
  static let defaultValue = false
}

extension EnvironmentValues {
  fileprivate var navigationOverflowPressed: Bool {
    get { self[NavigationOverflowPressedKey.self] }
    set { self[NavigationOverflowPressedKey.self] = newValue }
  }
}

private struct NavigationOverflowPressButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .environment(\.navigationOverflowPressed, configuration.isPressed)
  }
}

private struct ProjectNavigationRow: View {
  @Environment(\.rabbisirCopy) private var copy
  let project: RuntimeNavigationProject
  let isExpanded: Bool
  let isCurrent: Bool
  let isHoverPresented: Bool
  let isHandleHovered: Bool
  let actions: [NavigationHoverActionConfiguration]
  let onHoverChanged: (Bool) -> Void
  let onResizeHandleHoverChanged: (Bool, CGRect) -> Void
  let action: () -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var hoverState = NavigationProjectHoverState()
  @State private var hoverDismissTask: Task<Void, Never>?

  var body: some View {
    GeometryReader { geometry in
      Button(action: action) {
        HStack(spacing: 8) {
          RuntimeWorkspaceFolderIcon(expanded: isExpanded)
            .frame(width: 16, height: 16)
          Text(project.title)
            .font(.system(size: 13, weight: .semibold))
            .lineLimit(1)
            .truncationMode(.tail)
          Spacer(minLength: 4)
          Image(systemName: "chevron.right")
            .font(.system(size: 10, weight: .semibold))
            .rotationEffect(.degrees(isExpanded ? 90 : 0))
        }
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
        .nativePanelContentForeground()
      }
      .buttonStyle(RabbisirStablePressButtonStyle())
      .onHover { hovering in
        updateHover(
          source: .row,
          hovering,
          frame: geometry.frame(in: .named("Rabbisir.sidebarNavigation"))
        )
      }
      .onDisappear {
        hoverDismissTask?.cancel()
        hoverState.reset()
        guard isHoverPresented else { return }
        onHoverChanged(false)
        onResizeHandleHoverChanged(
          false,
          geometry.frame(in: .named("Rabbisir.sidebarNavigation"))
        )
      }
      .onChange(of: isHandleHovered) { _, hovering in
        updateHover(
          source: .resizeHandle,
          hovering,
          frame: geometry.frame(in: .named("Rabbisir.sidebarNavigation"))
        )
      }
      .accessibilityLabel(
        "\(project.title)，\(isCurrent ? "\(copy[.sidebarCurrentWorkspace])，" : "")\(isExpanded ? copy[.sidebarExpanded] : copy[.sidebarCollapsed])"
      )
      .accessibilityHint(copy[.sidebarToggleWorkspace])
      .background(alignment: .trailing) {
        NavigationHoverActionSlots(
          isPresented: isHoverPresented,
          rowHeight: NativeNavigationLayout.projectRowHeight,
          includesExtensionSurface:
            NavigationHoverActionSurfaceStyle.project.includesExtensionSurface,
          surfaceStyle: .project,
          actions: actions,
          onHoverChanged: { hovering in
            updateHover(
              source: .actionSlots,
              hovering,
              frame: geometry.frame(in: .named("Rabbisir.sidebarNavigation"))
            )
          }
        )
        .offset(x: NativeNavigationLayout.trailingInteractionReserve)
      }
    }
  }

  private func updateHover(
    source: NavigationProjectHoverSource,
    _ hovering: Bool,
    frame: CGRect
  ) {
    let wasDismissing = hoverDismissTask != nil
    hoverDismissTask?.cancel()
    hoverDismissTask = nil
    hoverState.set(source, hovering: hovering)
    if hovering {
      if !isHoverPresented {
        onHoverChanged(true)
        onResizeHandleHoverChanged(true, frame)
      } else if wasDismissing {
        // Re-entry must invalidate an AppKit fade that may already have begun.
        onResizeHandleHoverChanged(true, frame)
      }
      return
    }
    guard !hoverState.isActive else { return }
    hoverDismissTask = Task { @MainActor in
      try? await Task.sleep(
        for: .seconds(NavigationHoverExitPolicy.boundaryGraceDuration)
      )
      guard !Task.isCancelled, isHoverPresented, !hoverState.isActive else { return }
      // The grip panel becomes non-interactive and fades before the row retracts.
      onResizeHandleHoverChanged(false, frame)
      try? await Task.sleep(
        for: .seconds(
          NavigationHoverExitPolicy.gripDismissDuration(reduceMotion: reduceMotion)
        )
      )
      guard !Task.isCancelled, isHoverPresented, !hoverState.isActive else { return }
      onHoverChanged(false)
      hoverDismissTask = nil
    }
  }
}

private struct SessionNavigationRow: View {
  @Environment(\.rabbisirCopy) private var copy
  let session: RuntimeNavigationSession
  let isHoverPresented: Bool
  let actions: [NavigationHoverActionConfiguration]
  let moveTargets: [NavigationSessionMoveTarget]
  let onFork: () -> Void
  let onShowInFinder: () -> Void
  let onCopyWorkingDirectory: () -> Void
  let onCopySessionID: () -> Void
  let onHoverChanged: (Bool) -> Void
  let action: () -> Void
  @Environment(\.colorScheme) private var colorScheme
  @State private var hoverDismissTask: Task<Void, Never>?

  var body: some View {
    Button(action: action) {
      HStack(spacing: 0) {
        Text(session.title)
          .font(.system(size: 12.5, weight: session.isSelected ? .semibold : .regular))
          .lineLimit(1)
          .truncationMode(.tail)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      .padding(.leading, 32)
      .padding(.trailing, 8)
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(rowBackground)
      .overlay(alignment: .leading) {
        if session.isSelected {
          Capsule()
            .fill(NativeNavigationStyle.selectionIndicator)
            .frame(width: 2.5, height: 18)
            .padding(.leading, 5)
        }
      }
      .contentShape(Rectangle())
      .nativePanelContentForeground()
    }
    .buttonStyle(RabbisirStablePressButtonStyle())
    .onHover(perform: updateHover)
    .onDisappear {
      hoverDismissTask?.cancel()
      guard isHoverPresented else { return }
      onHoverChanged(false)
    }
    .accessibilityLabel(
      session.isSelected
        ? "\(copy[.sidebarCurrentSession])：\(session.title)"
        : "\(copy[.sidebarOpenSession])：\(session.title)"
    )
    .accessibilityAddTraits(session.isSelected ? .isSelected : [])
    .contextMenu {
      Button(copy[.sidebarForkSession], systemImage: "arrow.triangle.branch", action: onFork)
      if !moveTargets.isEmpty {
        Menu(copy[.sidebarMoveToProject], systemImage: "folder") {
          ForEach(moveTargets) { target in
            Button(target.title, action: target.action)
          }
        }
      }
      Divider()
      if session.cwd != nil {
        Button(copy[.showInFinder], systemImage: "folder.badge.magnifyingglass") {
          onShowInFinder()
        }
        Button(copy[.sidebarCopyWorkingDirectory], systemImage: "doc.on.doc") {
          onCopyWorkingDirectory()
        }
      }
      Button(copy[.sidebarCopySessionID], systemImage: "number") {
        onCopySessionID()
      }
    }
    .background(alignment: .trailing) {
      NavigationHoverActionSlots(
        isPresented: isHoverPresented,
        rowHeight: NativeNavigationLayout.sessionRowHeight,
        includesExtensionSurface: false,
        surfaceStyle: .session,
        actions: actions,
        onHoverChanged: updateHover
      )
      .offset(x: NativeNavigationLayout.trailingInteractionReserve)
    }
  }

  private var rowBackground: Color {
    if session.isSelected { return NativeNavigationStyle.selectionFill }
    if isHoverPresented { return NativeNavigationStyle.interactionFill(for: colorScheme) }
    return .clear
  }

  private func updateHover(_ hovering: Bool) {
    hoverDismissTask?.cancel()
    if hovering {
      onHoverChanged(true)
      return
    }
    hoverDismissTask = Task { @MainActor in
      try? await Task.sleep(for: .milliseconds(120))
      guard !Task.isCancelled, isHoverPresented else { return }
      onHoverChanged(false)
    }
  }

}

private struct NavigationHoverActionSlots: View {
  let isPresented: Bool
  let rowHeight: CGFloat
  let includesExtensionSurface: Bool
  let surfaceStyle: NavigationHoverActionSurfaceStyle
  let actions: [NavigationHoverActionConfiguration]
  let onHoverChanged: (Bool) -> Void
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.colorScheme) private var colorScheme
  @Namespace private var glassNamespace

  var body: some View {
    Group {
      if #available(macOS 26.0, *) {
        liquidGlassSlots
      } else {
        fallbackSlots
      }
    }
    .frame(
      width: NativeNavigationLayout.trailingInteractionReserve
        + NativeNavigationLayout.trailingRadius,
      height: rowHeight,
      alignment: .leading
    )
    .contentShape(Rectangle())
    .allowsHitTesting(isPresented)
    .onHover(perform: onHoverChanged)
    .id("navigation-hover-actions.\(colorScheme)")
  }

  @available(macOS 26.0, *)
  @ViewBuilder
  private var liquidGlassSlots: some View {
    Group {
      if surfaceStyle.ownsGlassContainer {
        GlassEffectContainer(spacing: NativeNavigationLayout.hoverActionSpacing) {
          liquidGlassSlotContent
        }
      } else {
        liquidGlassSlotContent
      }
    }
    .animation(extensionAnimation, value: isPresented)
  }

  @available(macOS 26.0, *)
  @ViewBuilder
  private var liquidGlassSlotContent: some View {
    if isPresented {
      ZStack(alignment: .leading) {
        if includesExtensionSurface {
          let shape = NavigationRowExtensionShape(
            radius: NativeNavigationLayout.trailingRadius
          )
          NavigationRowExtensionShape(radius: NativeNavigationLayout.trailingRadius)
            .frame(
              width: NativeNavigationLayout.trailingRadius
                + NativeNavigationLayout.resizeExtensionWidth + 2,
              height: rowHeight
            )
            .rabbisirGlassSurface(
              shape,
              role: .auxiliary,
              clipsToShape: false
            )
            .glassEffectID("navigation-row-extension", in: glassNamespace)
            .glassEffectTransition(.matchedGeometry)
        }

        HStack(spacing: NativeNavigationLayout.hoverActionSpacing) {
          ForEach(0..<NativeNavigationLayout.hoverActionCount, id: \.self) { index in
            hoverSlot(at: index)
              .glassEffectID("navigation-action-\(index)", in: glassNamespace)
              .glassEffectTransition(.matchedGeometry)
          }
        }
        .offset(
          x: NativeNavigationLayout.trailingRadius
            + NativeNavigationLayout.resizeExtensionWidth + 5
        )
        .transition(slotTransition)
      }
      .transition(extensionTransition)
    }
  }

  private var fallbackSlots: some View {
    Group {
      if isPresented {
        ZStack(alignment: .leading) {
          if includesExtensionSurface {
            let shape = NavigationRowExtensionShape(
              radius: NativeNavigationLayout.trailingRadius
            )
            Color.clear
              .frame(
                width: NativeNavigationLayout.trailingRadius
                  + NativeNavigationLayout.resizeExtensionWidth + 2,
                height: rowHeight
              )
              .rabbisirGlassSurface(
                shape,
                role: .auxiliary,
                clipsToShape: false
              )
          }
          HStack(spacing: NativeNavigationLayout.hoverActionSpacing) {
            ForEach(0..<NativeNavigationLayout.hoverActionCount, id: \.self) { index in
              hoverSlot(at: index)
            }
          }
          .offset(
            x: NativeNavigationLayout.trailingRadius
              + NativeNavigationLayout.resizeExtensionWidth + 5
          )
        }
        .transition(extensionTransition)
      }
    }
    .animation(extensionAnimation, value: isPresented)
  }

  private var extensionTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .scale(scale: 0.2, anchor: .leading).combined(with: .opacity)
  }

  @ViewBuilder
  private func hoverSlot(at index: Int) -> some View {
    if actions.indices.contains(index) {
      let action = actions[index]
      if surfaceStyle == .project {
        ProjectNavigationHoverActionButton(
          action: action
        )
      } else {
        Button(role: action.role, action: action.action) {
          Image(systemName: action.symbol)
            .font(.system(size: 10.5, weight: .semibold))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .nativePanelContentForeground()
        .frame(
          width: NativeNavigationLayout.hoverActionDiameter,
          height: NativeNavigationLayout.hoverActionDiameter
        )
        .rabbisirGlassSurface(Circle(), interactive: true)
        .disabled(!action.isEnabled)
        .help(action.disabledReason ?? action.accessibilityLabel)
        .accessibilityLabel(action.accessibilityLabel)
        .accessibilityHint(action.disabledReason ?? "")
      }
    } else {
      Circle()
        .fill(Color.clear)
        .frame(
          width: NativeNavigationLayout.hoverActionDiameter,
          height: NativeNavigationLayout.hoverActionDiameter
        )
        .rabbisirGlassSurface(Circle(), interactive: false)
        .allowsHitTesting(false)
    }
  }

  private var slotTransition: AnyTransition {
    reduceMotion
      ? .opacity
      : .offset(x: -10)
        .combined(with: .scale(scale: 0.42, anchor: .leading))
        .combined(with: .opacity)
  }

  private var extensionAnimation: Animation {
    reduceMotion
      ? .linear(duration: RabbisirMotionToken.statusFeedback.duration)
      : .smooth(duration: RabbisirMotionToken.navigationRowHandleReveal.duration)
  }
}

enum NavigationHoverActionSurfaceStyle {
  case project
  case session

  var ownsGlassContainer: Bool {
    false
  }

  var usesOwnerGlassSurface: Bool {
    self == .project
  }

  var includesExtensionSurface: Bool {
    false
  }
}

private struct ProjectNavigationHoverActionButton: View {
  let action: NavigationHoverActionConfiguration
  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @State private var isHovered = false

  var body: some View {
    Button(role: action.role, action: action.action) {
      Image(systemName: action.symbol)
        .font(.system(size: 10.5, weight: .semibold))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Circle())
    }
    .buttonStyle(
      ProjectNavigationActionButtonStyle(
        isHovered: isHovered,
        isEnabled: action.isEnabled,
        isDestructive: action.role == .destructive,
        reduceMotion: reduceMotion
      )
    )
    .frame(
      width: NativeNavigationLayout.hoverActionDiameter,
      height: NativeNavigationLayout.hoverActionDiameter
    )
    .rabbisirGlassSurface(
      Circle(),
      role: NativeNavigationMaterialPolicy.projectActionSurfaceRole,
      interactive: NativeNavigationMaterialPolicy.projectActionIsInteractive
    )
    .disabled(!action.isEnabled)
    .onHover { isHovered = $0 }
    .help(action.disabledReason ?? action.accessibilityLabel)
    .accessibilityLabel(action.accessibilityLabel)
    .accessibilityHint(action.disabledReason ?? "")
  }
}

private struct ProjectNavigationActionButtonStyle: ButtonStyle {
  let isHovered: Bool
  let isEnabled: Bool
  let isDestructive: Bool
  let reduceMotion: Bool

  func makeBody(configuration: Configuration) -> some View {
    let presentation = NativeNavigationStyle.projectActionPresentation(
      isHovered: isHovered,
      isPressed: configuration.isPressed,
      isEnabled: isEnabled,
      reduceMotion: reduceMotion
    )
    configuration.label
      .foregroundStyle(
        isDestructive ? Color(nsColor: .systemRed) : NativeNavigationStyle.foreground
      )
      .opacity(presentation.foregroundOpacity)
      .background {
        Circle()
          .fill(NativeNavigationStyle.foreground.opacity(presentation.overlayOpacity))
      }
      .overlay {
        Circle()
          .stroke(
            NativeNavigationStyle.foreground.opacity(presentation.strokeOpacity),
            lineWidth: 0.75
          )
      }
      .scaleEffect(presentation.scale)
      .animation(feedbackAnimation, value: isHovered)
      .animation(feedbackAnimation, value: configuration.isPressed)
  }

  private var feedbackAnimation: Animation {
    reduceMotion
      ? .linear(duration: RabbisirMotionToken.statusFeedback.duration)
      : .easeOut(duration: RabbisirMotionToken.buttonPress.duration)
  }
}

private struct NavigationHoverActionConfiguration: Identifiable {
  let id: String
  let symbol: String
  let accessibilityLabel: String
  let isEnabled: Bool
  let disabledReason: String?
  let role: ButtonRole?
  let action: () -> Void

  init(
    id: String,
    symbol: String,
    accessibilityLabel: String,
    isEnabled: Bool = true,
    disabledReason: String? = nil,
    role: ButtonRole? = nil,
    action: @escaping () -> Void
  ) {
    self.id = id
    self.symbol = symbol
    self.accessibilityLabel = accessibilityLabel
    self.isEnabled = isEnabled
    self.disabledReason = disabledReason
    self.role = role
    self.action = action
  }
}

extension View {
  @ViewBuilder
  fileprivate func navigationChildRevealClipped(_ shouldClip: Bool) -> some View {
    if shouldClip {
      clipped()
    } else {
      self
    }
  }

  @ViewBuilder
  fileprivate func navigationProjectGlassSurface(
    _ shape: NativeNavigationGroupShape,
    ownsSurface: Bool
  ) -> some View {
    if ownsSurface {
      let reservedWidth = NativeNavigationLayout.requiredTrailingInteractionWidth
      let visibleShape = NativeNavigationGroupShape(
        trailingRadius: shape.trailingRadius,
        projectRowHeight: shape.projectRowHeight,
        projectExtensionWidth: shape.projectExtensionWidth,
        baseWidth: shape.baseWidth,
        reservedTrailingWidth: reservedWidth
      )
      padding(.trailing, reservedWidth)
        .background {
          GeometryReader { geometry in
            let opticalHeight = max(
              geometry.size.height,
              NativeNavigationMaterialPolicy.opticalReferenceHeight
            )
            let opticalShape = NativeNavigationGroupShape(
              trailingRadius: shape.trailingRadius,
              projectRowHeight: shape.projectRowHeight,
              projectExtensionWidth: NativeNavigationLayout.resizeExtensionWidth,
              baseWidth: shape.baseWidth,
              reservedTrailingWidth: reservedWidth
            )
            Color.clear
              .frame(
                width: geometry.size.width,
                height: opticalHeight,
                alignment: .topLeading
              )
              .rabbisirGlassSurface(
                opticalShape,
                role: .navigation,
                clipsToShape: false
              )
              .mask(alignment: .topLeading) {
                visibleShape
                  .fill(Color.white)
                  .frame(
                    width: geometry.size.width,
                    height: geometry.size.height,
                    alignment: .topLeading
                  )
              }
          }
          .allowsHitTesting(false)
        }
        .padding(.trailing, -NativeNavigationLayout.requiredTrailingInteractionWidth)
    } else {
      self
    }
  }

}

private struct NavigationSessionMoveTarget: Identifiable {
  let id: String
  let title: String
  let action: () -> Void
}

private struct NavigationRowExtensionShape: Shape {
  let radius: CGFloat

  func path(in rect: CGRect) -> Path {
    let resolvedRadius = min(radius, rect.width, rect.height / 2)
    var path = Path()
    path.move(to: CGPoint(x: rect.minX, y: rect.minY))
    path.addLine(to: CGPoint(x: rect.maxX - resolvedRadius, y: rect.minY))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX, y: rect.minY + resolvedRadius),
      control: CGPoint(x: rect.maxX, y: rect.minY)
    )
    path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - resolvedRadius))
    path.addQuadCurve(
      to: CGPoint(x: rect.maxX - resolvedRadius, y: rect.maxY),
      control: CGPoint(x: rect.maxX, y: rect.maxY)
    )
    path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    path.closeSubpath()
    return path
  }
}

private struct RuntimeWorkspaceFolderIcon: View {
  let expanded: Bool

  var body: some View {
    Image(systemName: expanded ? "folder.fill" : "folder")
      .symbolRenderingMode(.monochrome)
      .accessibilityHidden(true)
  }
}
