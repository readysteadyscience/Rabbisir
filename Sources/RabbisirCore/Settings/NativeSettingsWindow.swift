import AppKit
import Combine
import SwiftUI

enum NativeSettingsWindowLayout {
  static let defaultSize = CGSize(width: 980, height: 700)
  static let minimumSize = CGSize(width: 880, height: 620)
  static let maximumStoredSize = CGSize(width: 10_000, height: 10_000)
}

@MainActor
enum NativeSettingsMaterialPolicy {
  static let cornerRadius: CGFloat = 24

  static func configure(_ window: NSWindow) {
    window.styleMask.insert(.fullSizeContentView)
    window.isOpaque = false
    window.backgroundColor = .clear
    window.titlebarAppearsTransparent = true
    window.hasShadow = false
  }

  static func makeContainer(
    contentView: NSView
  ) -> NSView {
    RabbisirGlassAppKitAdapter.makeContainer(
      contentView: contentView,
      cornerRadius: cornerRadius,
      role: .settings
    )
  }
}

@MainActor
final class NativeSettingsWindowCoordinator: NSObject, NSWindowDelegate {
  private let store: NativeSettingsStore
  private let interfacePreferences: RabbisirInterfacePreferencesStore
  private var window: NSWindow?
  private var languageSubscription: AnyCancellable?

  init(
    runtimeURL: URL,
    interfacePreferences: RabbisirInterfacePreferencesStore = RabbisirInterfacePreferencesStore()
  ) {
    store = NativeSettingsStore(transport: UpstreamSettingsTransport(baseURL: runtimeURL))
    self.interfacePreferences = interfacePreferences
  }

  func show(on requestedScreen: NSScreen? = nil) {
    let window = window ?? makeWindow()
    self.window = window
    if let screen = requestedScreen ?? RabbisirPrimaryScreen.current {
      place(window, on: screen)
    }
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
    Task { await store.load() }
  }

  func close() {
    window?.performClose(nil)
  }

  func move(to screen: NSScreen) {
    guard let window else { return }
    RabbisirWindowMover.move(window, to: screen)
  }

  var isVisible: Bool { window?.isVisible == true }

  func windowWillClose(_ notification: Notification) {
    window = nil
    languageSubscription?.cancel()
    languageSubscription = nil
  }

  func windowDidResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow,
      window === self.window,
      window.inLiveResize
    else { return }
    interfacePreferences.setSettingsWindowSize(window.frame.size)
  }

  func windowDidEndLiveResize(_ notification: Notification) {
    guard let window = notification.object as? NSWindow, window === self.window else { return }
    interfacePreferences.setSettingsWindowSize(window.frame.size)
  }

  private func makeWindow() -> NSWindow {
    let size = interfacePreferences.settingsWindowSize ?? NativeSettingsWindowLayout.defaultSize
    let content = NativeSettingsRootView(
      store: store,
      close: { [weak self] in self?.close() }
    )
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false
    )
    updateWindowCopy(window, language: RabbisirLocalization.shared.language)
    window.titleVisibility = .visible
    window.isReleasedWhenClosed = false
    NativeSettingsMaterialPolicy.configure(window)
    window.level = .normal
    window.collectionBehavior = [.moveToActiveSpace]
    window.minSize = NativeSettingsWindowLayout.minimumSize
    let materialContainer = NativeSettingsMaterialPolicy.makeContainer(
      contentView: NSHostingView(
        rootView: RabbisirLocalizedRoot { content }
      )
    )
    window.contentView = materialContainer
    languageSubscription = RabbisirLocalization.shared.$language
      .removeDuplicates()
      .sink { [weak self, weak window] language in
        guard let self, let window else { return }
        self.updateWindowCopy(window, language: language)
      }
    window.delegate = self
    return window
  }

  private func updateWindowCopy(
    _ window: NSWindow,
    language: RabbisirInterfaceLanguage
  ) {
    let copy = RabbisirCopy(language: language)
    window.title = "\(RabbisirAppIdentity.displayName) \(copy[.settings])"
    window.setAccessibilityLabel(window.title)
  }

  private func place(_ window: NSWindow, on screen: NSScreen) {
    let frame = RabbisirWindowPlacement.frame(
      currentFrame: window.frame,
      minimumSize: window.minSize,
      sourceVisibleFrame: nil,
      targetVisibleFrame: screen.visibleFrame
    )
    window.setFrame(frame, display: false)
  }
}
