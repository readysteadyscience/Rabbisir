import AppKit
import Combine
import OSLog
import SwiftUI

enum ApplicationLaunchRoute: Equatable {
  case live
  case preview

  static func resolve(arguments: [String]) -> Self {
    arguments.contains("--launch-preview") ? .preview : .live
  }
}

public enum RabbisirApplication {
  @MainActor
  public static func run(identity: RabbisirLaunchIdentity) -> Never {
    ProcessInfo.processInfo.processName = identity.displayName
    let application = NSApplication.shared
    let delegate = ApplicationDelegate(identity: identity)
    application.setActivationPolicy(.regular)
    application.delegate = delegate
    application.run()
    fatalError("NSApplication.run() returned unexpectedly")
  }

  @MainActor
  public static func runOpenSource() -> Never {
    ProcessInfo.processInfo.processName = RabbisirOpenIdentity.displayName
    let application = NSApplication.shared
    let delegate = ApplicationDelegate(
      identity: .development,
      applicationSupportComponent: RabbisirOpenIdentity.applicationSupportComponent,
      isolatedHomeDirectory: RabbisirOpenIdentity.isolatedHome(
        environment: ProcessInfo.processInfo.environment
      )
    )
    application.setActivationPolicy(.regular)
    application.delegate = delegate
    application.run()
    fatalError("NSApplication.run() returned unexpectedly")
  }
}

@MainActor
private final class ApplicationDelegate: NSObject, NSApplicationDelegate {
  private let identity: RabbisirLaunchIdentity
  private let developmentReadinessFile: URL?
  private var currentCopy: RabbisirCopy {
    RabbisirCopy(language: RabbisirLocalization.shared.language)
  }
  private var workspaceCoordinator: SpatialWorkspaceCoordinator?
  private var overlayCoordinator: MenuBarOverlayCoordinator?
  private var commandTarget: ApplicationCommandTarget?
  private var launchCoordinator: LaunchSplashCoordinator?
  private var firstRunConfigurationCoordinator: FirstRunConfigurationWindowCoordinator?
  private var workspaceTourCoordinator: WorkspaceTourCoordinator?
  private let displayCoordinator = RabbisirDisplayMenuCoordinator.shared
  private let helpCoordinator = RabbisirHelpWindowCoordinator()
  private var state: WorkspaceState?
  private var runtimeBridge: RuntimeBridgeStore?
  private let managedRuntime: ManagedUpstreamRuntime
  private var globalHotKeys: GlobalHotKeyCoordinator?
  private var webReadinessCancellable: AnyCancellable?
  private var webReadinessTimeoutTask: Task<Void, Never>?
  private var assetLoadTask: Task<Void, Never>?
  private var runtimeStartTask: Task<Void, Never>?
  private var launchFailureSource: LaunchFailureSource?
  private var runtimeURL: URL?
  private var automaticRuntimeRestartCount = 0
  private var automaticReadinessRecoveryCount = 0
  private var didRevealWorkspace = false
  private var isLaunchPreview = false
  private var applicationIconObservation: NSKeyValueObservation?
  private let localization = RabbisirLocalization.shared

  init(
    identity: RabbisirLaunchIdentity,
    applicationSupportComponent: String? = nil,
    isolatedHomeDirectory: URL? = nil
  ) {
    self.identity = identity
    developmentReadinessFile =
      switch identity {
      case .development:
        RabbisirDevelopmentLaunchOptions.readinessFile(
          arguments: ProcessInfo.processInfo.arguments
        )
      case .production:
        nil
      }
    managedRuntime = ManagedUpstreamRuntime(
      identity: identity,
      applicationSupportComponent: applicationSupportComponent,
      isolatedHomeDirectory: isolatedHomeDirectory
    )
  }

  private enum LaunchFailureSource {
    case brandAsset
    case runtime
  }

  func applicationDidFinishLaunching(_ notification: Notification) {
    helpCoordinator.configure(
      screenProvider: { [weak self] in self?.displayCoordinator.targetScreen }
    )
    displayCoordinator.configure(
      canMigrate: { [weak self] in self?.hasManagedWindows == true },
      migrate: { [weak self] descriptor in
        self?.moveManagedWindows(to: descriptor) == true
      }
    )
    do {
      try updateApplicationIcon(for: NSApp.effectiveAppearance)
    } catch {
      let alert = NSAlert()
      alert.messageText = currentCopy.appIconLoadFailed
      alert.informativeText = currentCopy.brandIconUnreadable
      publishDevelopmentReadiness("failed")
      alert.runModal()
      NSApp.terminate(nil)
      return
    }
    applicationIconObservation = NSApp.observe(
      \.effectiveAppearance,
      options: [.new]
    ) { [weak self] application, _ in
      Task { @MainActor [weak self] in
        guard let self else { return }
        do {
          try self.updateApplicationIcon(for: application.effectiveAppearance)
        } catch {
          RabbisirLog.application.error(
            "Application icon update failed: \(error.localizedDescription, privacy: .private)"
          )
        }
      }
    }
    NSApp.activate(ignoringOtherApps: true)
    DispatchQueue.main.async { [weak self] in
      self?.launchNativeShell()
    }
  }

  private func updateApplicationIcon(for appearance: NSAppearance) throws {
    let variant = RabbisirAppIconAppearance.resolve(appearance)
    NSApp.applicationIconImage = try RabbisirBrandAssets.loadAppIcon(for: variant)
  }

  private func launchNativeShell() {
    guard let mainScreen = RabbisirPrimaryScreen.current else {
      let alert = NSAlert()
      alert.messageText = currentCopy.mainScreenUnavailable
      alert.informativeText = currentCopy.noWindowCreated
      publishDevelopmentReadiness("failed")
      alert.runModal()
      NSApp.terminate(nil)
      return
    }

    let safeInsets = mainScreen.safeAreaInsets
    let auxiliaryLeft = mainScreen.auxiliaryTopLeftArea.map(NSStringFromRect) ?? "none"
    let auxiliaryRight = mainScreen.auxiliaryTopRightArea.map(NSStringFromRect) ?? "none"
    let focusScreenName = NSScreen.main?.localizedName ?? "none"
    RabbisirLog.application.debug(
      "Primary screen=\(mainScreen.localizedName, privacy: .private), focused screen=\(focusScreenName, privacy: .private), visible frame=\(NSStringFromRect(mainScreen.visibleFrame), privacy: .private), safe insets=\(String(describing: safeInsets), privacy: .private), auxiliary left=\(auxiliaryLeft, privacy: .private), auxiliary right=\(auxiliaryRight, privacy: .private)"
    )

    if ApplicationLaunchRoute.resolve(arguments: ProcessInfo.processInfo.arguments) == .preview {
      launchPreview(on: mainScreen)
      return
    }

    let launchCoordinator = LaunchSplashCoordinator(screen: mainScreen) { [weak self] in
      self?.retryLaunch()
    }
    self.launchCoordinator = launchCoordinator
    launchCoordinator.show()
    loadBrandAsset(on: mainScreen)
  }

  private func launchPreview(on screen: NSScreen) {
    do {
      let logo = try RabbisirBrandAssets.loadLogo()
      let launchCoordinator = LaunchSplashCoordinator(
        screen: screen,
        mode: .preview,
        retry: {},
        exitPreview: { NSApp.terminate(nil) }
      )
      launchCoordinator.model.brandAssetDidLoad(logo)
      self.launchCoordinator = launchCoordinator
      isLaunchPreview = true
      RabbisirMenuInstaller.install(PreviewApplicationMenu.make(target: self))
      launchCoordinator.show()
      RabbisirLog.application.info("Launch preview is ready")
    } catch {
      let alert = NSAlert()
      alert.messageText = currentCopy.launchPreviewUnavailable
      alert.informativeText = currentCopy.brandLogoUnreadable
      alert.runModal()
      NSApp.terminate(nil)
    }
  }

  @objc func exitLaunchPreview(_ sender: Any?) {
    NSApp.terminate(nil)
  }

  private func loadBrandAsset(on screen: NSScreen) {
    assetLoadTask?.cancel()
    launchFailureSource = nil
    launchCoordinator?.model.restartAssetLoading()
    assetLoadTask = Task { @MainActor [weak self] in
      await Task.yield()
      guard let self, !Task.isCancelled else { return }
      do {
        let logo = try RabbisirBrandAssets.loadLogo()
        launchCoordinator?.model.brandAssetDidLoad(logo)
        RabbisirLog.application.info("Brand assets are ready")
        prepareRuntime(on: screen)
      } catch {
        launchFailureSource = .brandAsset
        launchCoordinator?.model.fail(message: currentCopy.brandLogoUnreadable)
        publishDevelopmentReadiness("failed")
      }
    }
  }

  private func prepareRuntime(on screen: NSScreen) {
    let state = state ?? WorkspaceState()
    #if DEBUG
      BrowserControlDevelopmentPreview.apply(
        arguments: ProcessInfo.processInfo.arguments,
        to: state
      )
    #endif
    #if DEBUG
      if ProcessInfo.processInfo.arguments.contains("--preview-details") {
        state.showDetails(.artifact)
      }
    #endif
    self.state = state
    managedRuntime.onUnexpectedExit = { [weak self] in
      self?.recoverUnexpectedRuntimeExit()
    }
    runtimeStartTask?.cancel()
    runtimeStartTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let url = try await startOwnedRuntime(restarting: false)
        guard !Task.isCancelled else { return }
        runtimeURL = url
        automaticRuntimeRestartCount = 0
        await routeAfterRuntimeStarted(state: state, url: url, on: screen)
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        launchFailureSource = .runtime
        launchCoordinator?.model.fail(message: Self.runtimeDiagnostic(for: error))
        publishDevelopmentReadiness("failed")
      }
    }
  }

  private func routeAfterRuntimeStarted(
    state: WorkspaceState,
    url: URL,
    on screen: NSScreen
  ) async {
    let service = FirstRunConfigurationService(
      transport: UpstreamSettingsTransport(baseURL: url)
    )
    #if DEBUG
      if RabbisirDevelopmentLaunchOptions.forcesFirstRunPreview(
        arguments: ProcessInfo.processInfo.arguments
      ) {
        presentFirstRunConfiguration(
          service: service,
          state: state,
          url: url,
          on: screen
        )
        return
      }
    #endif
    switch await service.checkReadiness() {
    case .ready:
      prepareWorkspace(state: state, url: url, on: screen)
    case .requiresConfiguration:
      presentFirstRunConfiguration(
        service: service,
        state: state,
        url: url,
        on: screen
      )
    }
  }

  private func presentFirstRunConfiguration(
    service: FirstRunConfigurationService,
    state: WorkspaceState,
    url: URL,
    on screen: NSScreen
  ) {
    launchCoordinator?.dismissForConfiguration()
    RabbisirMenuInstaller.install(
      FirstRunApplicationMenu.make(
        target: self,
        language: localization.language,
        displayCoordinator: displayCoordinator,
        helpCoordinator: helpCoordinator
      )
    )
    let coordinator = FirstRunConfigurationWindowCoordinator(
      service: service
    ) { [weak self] in
      guard let self else { return }
      firstRunConfigurationCoordinator?.closeAfterSuccess()
      firstRunConfigurationCoordinator = nil
      launchCoordinator?.show()
      prepareWorkspace(
        state: state,
        url: url,
        on: displayCoordinator.targetScreen ?? screen
      )
    }
    firstRunConfigurationCoordinator = coordinator
    coordinator.show(on: screen)
    publishDevelopmentReadiness("configuration-required")
    RabbisirLog.application.info(
      "First-run configuration is required; workspace windows were not created"
    )
  }

  @objc func firstRunSelectChinese(_ sender: Any?) {
    selectFirstRunLanguage(.chinese)
  }

  @objc func firstRunSelectEnglish(_ sender: Any?) {
    selectFirstRunLanguage(.english)
  }

  @objc func firstRunQuit(_ sender: Any?) {
    NSApp.terminate(nil)
  }

  private func selectFirstRunLanguage(_ language: RabbisirInterfaceLanguage) {
    localization.select(language)
    RabbisirMenuInstaller.install(
      FirstRunApplicationMenu.make(
        target: self,
        language: language,
        displayCoordinator: displayCoordinator,
        helpCoordinator: helpCoordinator
      )
    )
  }

  private func prepareWorkspace(state: WorkspaceState, url: URL, on screen: NSScreen) {
    let runtimeBridge = RuntimeBridgeStore(state: state, url: url)
    let workspaceCoordinator = SpatialWorkspaceCoordinator(
      state: state,
      runtimeBridge: runtimeBridge,
      launchScreen: screen
    )
    let commandTarget = ApplicationCommandTarget(
      state: state,
      workspaceCoordinator: workspaceCoordinator,
      runtimeBridge: runtimeBridge,
      runtimeURL: url,
      localization: localization,
      displayCoordinator: displayCoordinator,
      helpCoordinator: helpCoordinator
    )

    self.runtimeBridge = runtimeBridge
    self.workspaceCoordinator = workspaceCoordinator
    self.commandTarget = commandTarget
    let globalHotKeys = GlobalHotKeyCoordinator(
      toggleWorkspace: { [weak workspaceCoordinator] in
        workspaceCoordinator?.toggleFromGlobalShortcut()
      },
      focusInput: { [weak workspaceCoordinator] in
        workspaceCoordinator?.showAndFocusInput()
      }
    )
    let hotKeyFailures = globalHotKeys.start()
    self.globalHotKeys = globalHotKeys
    if hotKeyFailures.isEmpty {
      RabbisirLog.application.info(
        "Global shortcuts registered without content capture"
      )
    } else {
      let diagnostics =
        hotKeyFailures
        .sorted { $0.key.rawValue < $1.key.rawValue }
        .map { "\($0.key.displayName):\($0.value)" }
        .joined(separator: ",")
      RabbisirLog.application.error(
        "Global shortcut registration failed: \(diagnostics, privacy: .private)"
      )
    }
    RabbisirMenuInstaller.install(
      ApplicationMenu.make(
        target: commandTarget,
        language: localization.language,
        displayCoordinator: displayCoordinator,
        helpCoordinator: helpCoordinator
      )
    )
    RabbisirLog.application.debug(
      "Application menu installed: \(NSApp.mainMenu?.items.first?.title ?? "none", privacy: .public)"
    )
    workspaceCoordinator.prepareForLaunch()
    launchCoordinator?.show()
    launchCoordinator?.model.workspaceDidPrepare()
    RabbisirLog.application.info("Workspace windows are ready")
    observeRuntimeReadiness(state: state)
  }

  private func observeRuntimeReadiness(state: WorkspaceState) {
    webReadinessCancellable = state.$webStatus
      .removeDuplicates()
      .sink { [weak self] status in
        MainActor.assumeIsolated {
          self?.handleRuntimeStatus(status)
        }
      }
  }

  private func handleRuntimeStatus(_ status: WorkspaceState.WebStatus) {
    switch status {
    case .loading:
      startRuntimeReadinessTimeout()
    case .ready:
      webReadinessTimeoutTask?.cancel()
      webReadinessTimeoutTask = nil
      webReadinessCancellable?.cancel()
      webReadinessCancellable = nil
      launchFailureSource = nil
      automaticReadinessRecoveryCount = 0
      launchCoordinator?.model.runtimeDidBecomeReady()
      RabbisirLog.runtime.info("Runtime is ready")
      revealWorkspaceWhenReady()
    case .unavailable(let message):
      webReadinessTimeoutTask?.cancel()
      webReadinessTimeoutTask = nil
      if automaticReadinessRecoveryCount < 2 {
        automaticReadinessRecoveryCount += 1
        RabbisirLog.runtime.notice(
          "Automatic readiness recovery attempt \(self.automaticReadinessRecoveryCount)"
        )
        launchCoordinator?.model.restartRuntimeLoading()
        state?.webStatus = .loading
        retryManagedRuntime()
        return
      }
      launchFailureSource = .runtime
      launchCoordinator?.model.fail(message: message)
    }
  }

  private func startRuntimeReadinessTimeout() {
    webReadinessTimeoutTask?.cancel()
    webReadinessTimeoutTask = Task { @MainActor [weak self] in
      try? await Task.sleep(for: .seconds(20))
      guard let self, !Task.isCancelled, state?.webStatus == .loading else { return }
      state?.webStatus = .unavailable(
        currentCopy.internalWorkspaceUnavailable
      )
    }
  }

  private func revealWorkspaceWhenReady() {
    guard !didRevealWorkspace,
      let state,
      let workspaceCoordinator,
      let launchCoordinator
    else { return }
    didRevealWorkspace = true

    launchCoordinator.transitionToWorkspace { [weak self] duration in
      guard let self else { return }
      workspaceCoordinator.revealAll(duration: duration)
      publishDevelopmentReadiness("workspace-ready")
      let overlayCoordinator = MenuBarOverlayCoordinator(
        state: state,
        mainWindow: workspaceCoordinator.mainWindow,
        initiallyHidden: true,
        localization: localization,
        isWorkspaceVisible: { [weak workspaceCoordinator] in
          workspaceCoordinator?.isWorkspaceVisible == true
        },
        setWorkspaceVisible: { [weak workspaceCoordinator] shouldShow in
          if shouldShow {
            workspaceCoordinator?.showAll()
          } else {
            workspaceCoordinator?.hideAll()
          }
        }
      )
      self.overlayCoordinator = overlayCoordinator
      overlayCoordinator.reveal(duration: duration)

      let tourCoordinator = WorkspaceTourCoordinator(
        targetFrame: { [weak workspaceCoordinator, weak overlayCoordinator] step in
          if step == .island {
            workspaceCoordinator?.finishTourDetailsPreview()
            return overlayCoordinator?.tourTargetFrame
          }
          return workspaceCoordinator?.tourTargetFrame(for: step)
        },
        visibleFrame: { [weak workspaceCoordinator] in
          workspaceCoordinator?.mainWindow.screen?.visibleFrame
            ?? RabbisirPrimaryScreen.current?.visibleFrame
        },
        startPanelDemonstration: { [weak workspaceCoordinator] step in
          workspaceCoordinator?.startTourPanelDemonstration(for: step)
        },
        cancelPanelDemonstration: { [weak workspaceCoordinator] in
          workspaceCoordinator?.cancelTourPanelDemonstration()
          workspaceCoordinator?.finishTourDetailsPreview()
        }
      )
      self.workspaceTourCoordinator = tourCoordinator
      self.commandTarget?.reopenWorkspaceTour = {
        [weak workspaceCoordinator, weak tourCoordinator] in
        workspaceCoordinator?.showAll()
        tourCoordinator?.replay()
      }
      self.helpCoordinator.configure(
        screenProvider: { [weak self] in self?.displayCoordinator.targetScreen },
        replayTour: { [weak workspaceCoordinator, weak tourCoordinator] in
          workspaceCoordinator?.showAll()
          tourCoordinator?.replay()
        }
      )
      Task { @MainActor [weak tourCoordinator] in
        try? await Task.sleep(for: .milliseconds(Int(duration * 1_000) + 80))
        guard !Task.isCancelled else { return }
        tourCoordinator?.beginIfNeeded()
      }

      let window = workspaceCoordinator.mainWindow
      let finalScreenName = window.screen?.localizedName ?? "none"
      RabbisirLog.application.debug(
        "Final workspace frame=\(NSStringFromRect(window.frame), privacy: .private), screen=\(finalScreenName, privacy: .private)"
      )
    }
  }

  private func retryLaunch() {
    switch launchFailureSource {
    case .brandAsset:
      guard let screen = RabbisirPrimaryScreen.current else { return }
      loadBrandAsset(on: screen)
    case .runtime:
      launchFailureSource = nil
      launchCoordinator?.model.restartRuntimeLoading()
      retryManagedRuntime()
    case nil:
      break
    }
  }

  func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    false
  }

  func applicationWillTerminate(_ notification: Notification) {
    runtimeStartTask?.cancel()
    managedRuntime.stop()
    globalHotKeys?.stop()
  }

  func applicationShouldHandleReopen(
    _ sender: NSApplication,
    hasVisibleWindows flag: Bool
  ) -> Bool {
    if isLaunchPreview {
      launchCoordinator?.show()
    } else if let firstRunConfigurationCoordinator,
      let screen = displayCoordinator.targetScreen ?? RabbisirPrimaryScreen.current
    {
      firstRunConfigurationCoordinator.show(on: screen)
    } else {
      workspaceCoordinator?.showAll()
    }
    return true
  }

  private func retryManagedRuntime() {
    runtimeStartTask?.cancel()
    runtimeStartTask = Task { @MainActor [weak self] in
      guard let self else { return }
      do {
        let url = try await startOwnedRuntime(restarting: true)
        guard !Task.isCancelled else { return }
        if let runtimeBridge {
          guard runtimeURL?.port == url.port else {
            throw ManagedUpstreamRuntimeError.healthCheckFailed
          }
          runtimeURL = url
          state?.webStatus = .loading
          startRuntimeReadinessTimeout()
          runtimeBridge.retryLoad()
        } else if let state,
          let screen = displayCoordinator.targetScreen ?? RabbisirPrimaryScreen.current
        {
          runtimeURL = url
          await routeAfterRuntimeStarted(state: state, url: url, on: screen)
        }
      } catch is CancellationError {
        return
      } catch {
        guard !Task.isCancelled else { return }
        launchFailureSource = .runtime
        launchCoordinator?.model.fail(message: Self.runtimeDiagnostic(for: error))
        publishDevelopmentReadiness("failed")
      }
    }
  }

  private func startOwnedRuntime(restarting: Bool) async throws -> URL {
    for attempt in 1...3 {
      do {
        if restarting || attempt > 1 {
          return try await managedRuntime.restart()
        }
        return try await managedRuntime.start()
      } catch is CancellationError {
        throw CancellationError()
      } catch {
        guard attempt < 3 else { throw error }
        RabbisirLog.runtime.notice("Automatic startup recovery attempt \(attempt)")
        try await Task.sleep(for: .milliseconds(350))
      }
    }
    throw ManagedUpstreamRuntimeError.failedToLaunch
  }

  private func recoverUnexpectedRuntimeExit() {
    guard !isLaunchPreview else { return }
    state?.webStatus = .loading
    automaticRuntimeRestartCount += 1
    guard automaticRuntimeRestartCount <= 2 else {
      launchFailureSource = .runtime
      state?.webStatus = .unavailable(currentCopy.internalRuntimeUnavailable)
      launchCoordinator?.model.fail(message: currentCopy.internalRuntimeUnavailable)
      publishDevelopmentReadiness("failed")
      return
    }
    RabbisirLog.runtime.notice(
      "Automatic runtime recovery attempt \(self.automaticRuntimeRestartCount)"
    )
    retryManagedRuntime()
  }

  private static func runtimeDiagnostic(for error: any Error) -> String {
    if let error = error as? UpstreamRuntimeResolutionError {
      return error.localizedDescription
    }
    if let error = error as? ManagedUpstreamRuntimeError {
      return error.localizedDescription
    }
    return RabbisirCopy(language: RabbisirLocalization.shared.language).internalRuntimeUnavailable
  }

  private func publishDevelopmentReadiness(_ status: String) {
    guard let developmentReadinessFile else { return }
    do {
      try Data("\(status)\n".utf8).write(to: developmentReadinessFile, options: .atomic)
    } catch {
      RabbisirLog.application.error("DEV readiness status could not be published")
    }
  }

  private var hasManagedWindows: Bool {
    launchCoordinator?.isVisible == true
      || firstRunConfigurationCoordinator?.isVisible == true
      || workspaceCoordinator?.isWorkspaceVisible == true
      || commandTarget?.hasVisibleAuxiliaryWindows == true
      || helpCoordinator.isVisible
  }

  private func moveManagedWindows(to descriptor: RabbisirDisplayDescriptor) -> Bool {
    guard
      let screen = NSScreen.screens.first(where: {
        $0.rabbisirDisplayIdentifier == descriptor.identifier
      })
    else { return false }

    var moved = false
    if let launchCoordinator {
      launchCoordinator.move(to: screen)
      moved = true
    }
    if let firstRunConfigurationCoordinator {
      firstRunConfigurationCoordinator.move(to: screen)
      moved = true
    }
    if let workspaceCoordinator {
      workspaceCoordinator.move(to: screen)
      moved = true
    }
    if commandTarget?.moveAuxiliaryWindows(to: screen) == true {
      moved = true
    }
    if helpCoordinator.isVisible {
      helpCoordinator.move(to: screen)
      moved = true
    }
    overlayCoordinator?.repositionAndShowIfPossible()
    workspaceTourCoordinator?.refreshPlacement()
    return moved
  }
}

@MainActor
private enum PreviewApplicationMenu {
  static func make(target: ApplicationDelegate) -> NSMenu {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    let menu = NSMenu()
    let appItem = NSMenuItem(title: RabbisirAppIdentity.displayName, action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: RabbisirAppIdentity.displayName)
    let quitItem = NSMenuItem(
      title: copy.exitLaunchPreview,
      action: #selector(ApplicationDelegate.exitLaunchPreview(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = target
    appMenu.addItem(quitItem)
    menu.addItem(appItem)
    menu.setSubmenu(appMenu, for: appItem)
    return menu
  }
}

@MainActor
private enum FirstRunApplicationMenu {
  static func make(
    target: ApplicationDelegate,
    language: RabbisirInterfaceLanguage,
    displayCoordinator: RabbisirDisplayMenuCoordinator,
    helpCoordinator: RabbisirHelpWindowCoordinator
  ) -> NSMenu {
    let copy = RabbisirApplicationMenuCopy.resolve(language: language)
    let menu = NSMenu()
    let appItem = NSMenuItem(title: RabbisirAppIdentity.displayName, action: nil, keyEquivalent: "")
    let appMenu = NSMenu(title: RabbisirAppIdentity.displayName)
    let quitItem = NSMenuItem(
      title: copy.quit,
      action: #selector(ApplicationDelegate.firstRunQuit(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = target
    appMenu.addItem(quitItem)
    menu.addItem(appItem)
    menu.setSubmenu(appMenu, for: appItem)

    StandardEditingMenu.add(to: menu, copy: copy)
    WindowMenu.add(
      to: menu,
      language: language,
      displayCoordinator: displayCoordinator
    )
    let languageTitle = language == .chinese ? "Language" : "语言"
    let languageItem = NSMenuItem(title: languageTitle, action: nil, keyEquivalent: "")
    let languageMenu = NSMenu(title: languageTitle)
    languageMenu.addItem(
      languageChoice(
        title: "中文",
        action: #selector(ApplicationDelegate.firstRunSelectChinese(_:)),
        selected: language == .chinese,
        target: target
      )
    )
    languageMenu.addItem(
      languageChoice(
        title: "English",
        action: #selector(ApplicationDelegate.firstRunSelectEnglish(_:)),
        selected: language == .english,
        target: target
      )
    )
    menu.addItem(languageItem)
    menu.setSubmenu(languageMenu, for: languageItem)
    HelpMenu.add(to: menu, coordinator: helpCoordinator, language: language)
    return menu
  }

  private static func languageChoice(
    title: String,
    action: Selector,
    selected: Bool,
    target: ApplicationDelegate
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = target
    item.state = selected ? .on : .off
    return item
  }
}

@MainActor
private final class ApplicationCommandTarget: NSObject, NSMenuItemValidation {
  private let state: WorkspaceState
  private weak var workspaceCoordinator: SpatialWorkspaceCoordinator?
  private let runtimeBridge: RuntimeBridgeStore
  private var aboutCoordinator: AboutPanelCoordinator?
  private var settingsCoordinator: NativeSettingsWindowCoordinator?
  private let runtimeURL: URL
  private let localization: RabbisirLocalization
  private let displayCoordinator: RabbisirDisplayMenuCoordinator
  private let helpCoordinator: RabbisirHelpWindowCoordinator
  var reopenWorkspaceTour: (() -> Void)?

  init(
    state: WorkspaceState,
    workspaceCoordinator: SpatialWorkspaceCoordinator,
    runtimeBridge: RuntimeBridgeStore,
    runtimeURL: URL,
    localization: RabbisirLocalization,
    displayCoordinator: RabbisirDisplayMenuCoordinator,
    helpCoordinator: RabbisirHelpWindowCoordinator
  ) {
    self.state = state
    self.workspaceCoordinator = workspaceCoordinator
    self.runtimeBridge = runtimeBridge
    self.runtimeURL = runtimeURL
    self.localization = localization
    self.displayCoordinator = displayCoordinator
    self.helpCoordinator = helpCoordinator
  }

  @objc func showMainWindow(_ sender: Any?) {
    workspaceCoordinator?.showAll()
  }

  @objc func hideMainWindow(_ sender: Any?) {
    workspaceCoordinator?.hideAll()
  }

  @objc func focusInput(_ sender: Any?) {
    workspaceCoordinator?.showAndFocusInput()
  }

  @objc func showAbout(_ sender: Any?) {
    if aboutCoordinator == nil {
      aboutCoordinator = try? AboutPanelCoordinator()
    }
    aboutCoordinator?.show(on: displayCoordinator.targetScreen)
  }

  @objc func showSessionLog(_ sender: Any?) {
    workspaceCoordinator?.showAll()
    Task { @MainActor [weak self] in
      guard let self else { return }
      guard await runtimeBridge.openSessionLog() else {
        presentUnavailable(
          title: RabbisirCopy(language: localization.language).sessionLogUnavailable,
          detail: RabbisirCopy(language: localization.language).sessionLogRejected
        )
        return
      }
    }
  }

  @objc func showSettings(_ sender: Any?) {
    if settingsCoordinator == nil {
      settingsCoordinator = NativeSettingsWindowCoordinator(runtimeURL: runtimeURL)
    }
    settingsCoordinator?.show(on: displayCoordinator.targetScreen)
  }

  @objc func showWorkspaceTour(_ sender: Any?) {
    reopenWorkspaceTour?()
  }

  func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
    switch menuItem.action {
    case #selector(showSessionLog(_:)), #selector(showSettings(_:)):
      state.webStatus == .ready
    default:
      true
    }
  }

  @objc func quit(_ sender: Any?) {
    NSApp.terminate(nil)
  }

  @objc func selectChinese(_ sender: Any?) {
    selectLanguage(.chinese)
  }

  @objc func selectEnglish(_ sender: Any?) {
    selectLanguage(.english)
  }

  private func selectLanguage(_ language: RabbisirInterfaceLanguage) {
    localization.select(language)
    RabbisirMenuInstaller.install(
      ApplicationMenu.make(
        target: self,
        language: language,
        displayCoordinator: displayCoordinator,
        helpCoordinator: helpCoordinator
      )
    )
  }

  var hasVisibleAuxiliaryWindows: Bool {
    aboutCoordinator?.isVisible == true || settingsCoordinator?.isVisible == true
  }

  func moveAuxiliaryWindows(to screen: NSScreen) -> Bool {
    var moved = false
    if let aboutCoordinator {
      aboutCoordinator.move(to: screen)
      moved = true
    }
    if let settingsCoordinator {
      settingsCoordinator.move(to: screen)
      moved = true
    }
    return moved
  }

  private func presentUnavailable(title: String, detail: String) {
    let alert = NSAlert()
    alert.messageText = title
    alert.informativeText = detail
    if let window = workspaceCoordinator?.mainWindow {
      alert.beginSheetModal(for: window)
    } else {
      alert.runModal()
    }
  }
}

@MainActor
private enum RabbisirMenuInstaller {
  static func install(_ menu: NSMenu) {
    NSApp.mainMenu = menu
    NSApp.helpMenu =
      menu.items.first(where: {
        $0.title == "帮助" || $0.title == "Help"
      })?.submenu
  }
}

@MainActor
enum ApplicationMenu {
  static func make(
    target: AnyObject,
    language: RabbisirInterfaceLanguage = .chinese,
    displayCoordinator: RabbisirDisplayMenuCoordinator = .shared,
    helpCoordinator: RabbisirHelpWindowCoordinator = RabbisirHelpWindowCoordinator()
  ) -> NSMenu {
    let menu = NSMenu()
    let copy = RabbisirApplicationMenuCopy.resolve(language: language)

    let appItem = NSMenuItem()
    appItem.title = RabbisirAppIdentity.displayName
    let appMenu = NSMenu(title: RabbisirAppIdentity.displayName)
    let aboutItem = NSMenuItem(
      title: RabbisirCopy(language: language)[.about],
      action: #selector(ApplicationCommandTarget.showAbout(_:)),
      keyEquivalent: ""
    )
    aboutItem.target = target
    appMenu.addItem(aboutItem)
    appMenu.addItem(.separator())

    let settingsItem = NSMenuItem(
      title: copy.settings,
      action: #selector(ApplicationCommandTarget.showSettings(_:)),
      keyEquivalent: ","
    )
    settingsItem.target = target
    appMenu.addItem(settingsItem)

    let sessionLogItem = NSMenuItem(
      title: RabbisirCopy(language: language)[.sessionLog],
      action: #selector(ApplicationCommandTarget.showSessionLog(_:)),
      keyEquivalent: ""
    )
    sessionLogItem.target = target
    appMenu.addItem(sessionLogItem)

    let tourItem = NSMenuItem(
      title: copy.workspaceTour,
      action: #selector(ApplicationCommandTarget.showWorkspaceTour(_:)),
      keyEquivalent: ""
    )
    tourItem.target = target
    appMenu.addItem(tourItem)

    appMenu.addItem(.separator())

    let showItem = NSMenuItem(
      title: copy.showMainWindow,
      action: #selector(ApplicationCommandTarget.showMainWindow(_:)),
      keyEquivalent: "0"
    )
    showItem.target = target
    appMenu.addItem(showItem)

    let hideItem = NSMenuItem(
      title: copy.hideWorkspace,
      action: #selector(ApplicationCommandTarget.hideMainWindow(_:)),
      keyEquivalent: "h"
    )
    hideItem.target = target
    appMenu.addItem(hideItem)

    let focusInputItem = NSMenuItem(
      title: copy.focusInput,
      action: #selector(ApplicationCommandTarget.focusInput(_:)),
      keyEquivalent: "\r"
    )
    focusInputItem.target = target
    focusInputItem.keyEquivalentModifierMask = [.control, .option]
    appMenu.addItem(focusInputItem)

    appMenu.addItem(.separator())

    let quitItem = NSMenuItem(
      title: copy.quit,
      action: #selector(ApplicationCommandTarget.quit(_:)),
      keyEquivalent: "q"
    )
    quitItem.target = target
    appMenu.addItem(quitItem)

    menu.addItem(appItem)
    menu.setSubmenu(appMenu, for: appItem)
    StandardEditingMenu.add(to: menu, copy: copy)
    WindowMenu.add(
      to: menu,
      language: language,
      displayCoordinator: displayCoordinator
    )
    LanguageMenu.add(to: menu, target: target, language: language)
    HelpMenu.add(to: menu, coordinator: helpCoordinator, language: language)
    return menu
  }
}

@MainActor
private enum HelpMenu {
  static func add(
    to menu: NSMenu,
    coordinator: RabbisirHelpWindowCoordinator,
    language: RabbisirInterfaceLanguage
  ) {
    let title = language == .chinese ? "帮助" : "Help"
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: title)
    submenu.addItem(
      actionItem(
        language == .chinese ? "Rabbisir 帮助" : "Rabbisir Help",
        action: #selector(RabbisirHelpWindowCoordinator.showHelp(_:)),
        target: coordinator,
        keyEquivalent: "?"
      )
    )
    submenu.addItem(
      actionItem(
        language == .chinese ? "快速开始" : "Quick Start",
        action: #selector(RabbisirHelpWindowCoordinator.showQuickStart(_:)),
        target: coordinator
      )
    )
    submenu.addItem(
      actionItem(
        language == .chinese ? "键盘快捷键" : "Keyboard Shortcuts",
        action: #selector(RabbisirHelpWindowCoordinator.showKeyboardShortcuts(_:)),
        target: coordinator
      )
    )
    submenu.addItem(
      actionItem(
        language == .chinese ? "隐私与凭据安全" : "Privacy and Credential Safety",
        action: #selector(RabbisirHelpWindowCoordinator.showPrivacy(_:)),
        target: coordinator
      )
    )
    submenu.addItem(.separator())
    let tour = actionItem(
      language == .chinese ? "重新开始界面导览" : "Restart Interface Tour",
      action: #selector(RabbisirHelpWindowCoordinator.replayTour(_:)),
      target: coordinator
    )
    tour.isEnabled = coordinator.canReplayTour
    tour.toolTip =
      language == .chinese
      ? "主工作台打开后可使用界面导览。"
      : "The interface tour is available after the workspace opens."
    submenu.addItem(tour)
    menu.addItem(item)
    menu.setSubmenu(submenu, for: item)
  }

  private static func actionItem(
    _ title: String,
    action: Selector,
    target: AnyObject,
    keyEquivalent: String = ""
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
    item.target = target
    return item
  }
}

@MainActor
private enum WindowMenu {
  static func add(
    to menu: NSMenu,
    language: RabbisirInterfaceLanguage,
    displayCoordinator: RabbisirDisplayMenuCoordinator
  ) {
    let title = language == .chinese ? "窗口" : "Window"
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let submenu = displayCoordinator.makeMenu(language: language)
    menu.addItem(item)
    menu.setSubmenu(submenu, for: item)
  }
}

@MainActor
private enum LanguageMenu {
  static func add(
    to menu: NSMenu,
    target: AnyObject,
    language: RabbisirInterfaceLanguage
  ) {
    let title = language == .chinese ? "Language" : "语言"
    let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
    let submenu = NSMenu(title: title)
    submenu.addItem(
      languageItem(
        title: "中文",
        action: #selector(ApplicationCommandTarget.selectChinese(_:)),
        target: target,
        selected: language == .chinese
      )
    )
    submenu.addItem(
      languageItem(
        title: "English",
        action: #selector(ApplicationCommandTarget.selectEnglish(_:)),
        target: target,
        selected: language == .english
      )
    )
    menu.addItem(item)
    menu.setSubmenu(submenu, for: item)
  }

  private static func languageItem(
    title: String,
    action: Selector,
    target: AnyObject,
    selected: Bool
  ) -> NSMenuItem {
    let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
    item.target = target
    item.state = selected ? .on : .off
    return item
  }
}

@MainActor
private enum StandardEditingMenu {
  static func add(to menu: NSMenu, copy: RabbisirApplicationMenuCopy) {
    let editItem = NSMenuItem(title: copy.edit, action: nil, keyEquivalent: "")
    let editMenu = NSMenu(title: copy.edit)
    editMenu.addItem(
      withTitle: copy.undo,
      action: Selector(("undo:")),
      keyEquivalent: "z"
    )
    let redo = editMenu.addItem(
      withTitle: copy.redo,
      action: Selector(("redo:")),
      keyEquivalent: "Z"
    )
    redo.keyEquivalentModifierMask = [.command, .shift]
    editMenu.addItem(.separator())
    editMenu.addItem(
      withTitle: copy.cut,
      action: #selector(NSText.cut(_:)),
      keyEquivalent: "x"
    )
    editMenu.addItem(
      withTitle: copy.copy,
      action: #selector(NSText.copy(_:)),
      keyEquivalent: "c"
    )
    editMenu.addItem(
      withTitle: copy.paste,
      action: #selector(NSText.paste(_:)),
      keyEquivalent: "v"
    )
    editMenu.addItem(.separator())
    editMenu.addItem(
      withTitle: copy.selectAll,
      action: #selector(NSText.selectAll(_:)),
      keyEquivalent: "a"
    )
    menu.addItem(editItem)
    menu.setSubmenu(editMenu, for: editItem)
  }
}
