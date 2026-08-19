import AppKit
import SwiftUI

@MainActor
final class WorkspaceDrawerActionButton: NSButton {
  var actionHandler: (() -> Void)?

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    isBordered = false
    isTransparent = false
    setButtonType(.momentaryPushIn)
    image = NSImage(
      systemSymbolName: "plus",
      accessibilityDescription: nil
    )
    imagePosition = .imageLeading
    imageScaling = .scaleProportionallyDown
    alignment = .left
    font = .systemFont(ofSize: NSFont.systemFontSize)
    focusRingType = .default
    target = self
    action = #selector(performAction)
    setAccessibilityIdentifier("Rabbisir.workspace.new")
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var needsPanelToBecomeKey: Bool { false }
  override var acceptsFirstResponder: Bool { true }

  override func keyDown(with event: NSEvent) {
    guard isEnabled else {
      super.keyDown(with: event)
      return
    }
    switch event.charactersIgnoringModifiers {
    case " ", "\r", "\n":
      performClick(nil)
    default:
      super.keyDown(with: event)
    }
  }

  override func accessibilityPerformPress() -> Bool {
    guard isEnabled, !isHidden else { return false }
    DispatchQueue.main.async { [weak self] in
      self?.performClick(nil)
    }
    return true
  }

  func update(title: String, accessibilityLabel: String, enabled: Bool) {
    self.title = title
    setAccessibilityLabel(accessibilityLabel)
    isEnabled = enabled
  }

  @objc private func performAction() {
    guard isEnabled else { return }
    actionHandler?()
  }
}

struct WorkspaceDrawerActionButtonView: NSViewRepresentable {
  let title: String
  let accessibilityLabel: String
  let enabled: Bool
  let action: () -> Void

  func makeNSView(context: Context) -> WorkspaceDrawerActionButton {
    let button = WorkspaceDrawerActionButton(frame: .zero)
    button.actionHandler = action
    return button
  }

  func updateNSView(_ button: WorkspaceDrawerActionButton, context: Context) {
    button.actionHandler = action
    button.update(
      title: title,
      accessibilityLabel: accessibilityLabel,
      enabled: enabled
    )
  }

  static func dismantleNSView(_ button: WorkspaceDrawerActionButton, coordinator: ()) {
    button.actionHandler = nil
  }
}
