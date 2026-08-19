import AppKit
import Combine

/// Publishes one application-level activation value for every Rabbisir glass window.
@MainActor
final class RabbisirApplicationActivity: NSObject, ObservableObject {
  static let shared = RabbisirApplicationActivity()

  @Published private(set) var appearsActive: Bool

  private let notificationCenter: NotificationCenter

  init(
    notificationCenter: NotificationCenter = .default,
    initiallyActive: Bool? = nil
  ) {
    self.notificationCenter = notificationCenter
    appearsActive = initiallyActive ?? NSApp.isActive
    super.init()
    notificationCenter.addObserver(
      self,
      selector: #selector(applicationDidBecomeActive),
      name: NSApplication.didBecomeActiveNotification,
      object: nil
    )
    notificationCenter.addObserver(
      self,
      selector: #selector(applicationDidResignActive),
      name: NSApplication.didResignActiveNotification,
      object: nil
    )
  }

  deinit {
    notificationCenter.removeObserver(self)
  }

  @objc private func applicationDidBecomeActive() {
    appearsActive = true
  }

  @objc private func applicationDidResignActive() {
    appearsActive = false
  }
}
