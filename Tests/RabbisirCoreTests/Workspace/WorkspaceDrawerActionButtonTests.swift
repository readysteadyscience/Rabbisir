import AppKit
import Testing

@testable import RabbisirCore

@Suite("Workspace drawer action button")
struct WorkspaceDrawerActionButtonTests {
  @Test("Mouse and AX press use the same workspace creation action")
  @MainActor
  func pointerAndAccessibilityActivation() async {
    let (_, button) = mountedButton()
    var actionCount = 0
    button.actionHandler = { actionCount += 1 }

    #expect(button.acceptsFirstMouse(for: nil))
    #expect(!button.needsPanelToBecomeKey)
    #expect(button.acceptsFirstResponder)

    button.performClick(nil)
    #expect(actionCount == 1)
    #expect(button.accessibilityPerformPress())
    #expect(actionCount == 1)
    await Task.yield()
    #expect(actionCount == 2)
  }

  @Test("Space and Return activate workspace creation from the keyboard")
  @MainActor
  func keyboardActivation() throws {
    let (_, button) = mountedButton()
    var actionCount = 0
    button.actionHandler = { actionCount += 1 }

    button.keyDown(with: try #require(keyEvent(characters: " ", keyCode: 49)))
    button.keyDown(with: try #require(keyEvent(characters: "\r", keyCode: 36)))

    #expect(actionCount == 2)
  }

  @Test("Disabled workspace creation stays inert for every activation path")
  @MainActor
  func disabledActionIsInert() {
    let (_, button) = mountedButton()
    var actionCount = 0
    button.actionHandler = { actionCount += 1 }
    button.update(
      title: "新建工作区…",
      accessibilityLabel: "新建工作区",
      enabled: false
    )

    button.performClick(nil)
    #expect(!button.accessibilityPerformPress())
    #expect(actionCount == 0)
    #expect(!button.isEnabled)
    #expect(button.title == "新建工作区…")
    #expect(button.accessibilityLabel() == "新建工作区")
  }

  @MainActor
  private func mountedButton() -> (NSPanel, WorkspaceDrawerActionButton) {
    let panel = NSPanel(
      contentRect: CGRect(x: 0, y: 0, width: 260, height: 38),
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    let button = WorkspaceDrawerActionButton(
      frame: CGRect(x: 0, y: 0, width: 260, height: 38)
    )
    panel.contentView = button
    return (panel, button)
  }

  @MainActor
  private func keyEvent(characters: String, keyCode: UInt16) -> NSEvent? {
    NSEvent.keyEvent(
      with: .keyDown,
      location: .zero,
      modifierFlags: [],
      timestamp: 0,
      windowNumber: 0,
      context: nil,
      characters: characters,
      charactersIgnoringModifiers: characters,
      isARepeat: false,
      keyCode: keyCode
    )
  }
}
