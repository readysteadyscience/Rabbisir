import AppKit

@MainActor
enum NavigationProjectDialogs {
  static func requestedRename(currentTitle: String) -> String? {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    let alert = NSAlert()
    alert.messageText = copy.navigationDialogs.editProject
    alert.informativeText = copy.navigationDialogs.projectRenameNote
    alert.alertStyle = .informational
    alert.addButton(withTitle: copy[.save])
    alert.addButton(withTitle: copy[.cancel])
    alert.buttons[1].keyEquivalent = "\u{1b}"

    let field = NSTextField(string: currentTitle)
    field.frame = CGRect(x: 0, y: 0, width: 320, height: 24)
    field.placeholderString = copy.navigationDialogs.projectName
    field.selectText(nil)
    alert.accessoryView = field

    NSApp.activate(ignoringOtherApps: true)
    alert.window.center()
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return nil }
    let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? nil : title
  }

  static func confirmsRegistrationDeletion(projectTitle: String) -> Bool {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    let alert = NSAlert()
    alert.messageText = copy.deleteProjectConfirmation(projectTitle)
    alert.informativeText = copy.navigationDialogs.deleteProjectNote
    alert.alertStyle = .critical
    alert.addButton(withTitle: copy[.delete])
    alert.addButton(withTitle: copy[.cancel])
    alert.buttons[0].hasDestructiveAction = true
    alert.buttons[1].keyEquivalent = "\u{1b}"

    NSApp.activate(ignoringOtherApps: true)
    alert.window.center()
    return alert.runModal() == .alertFirstButtonReturn
  }

  static func requestedSessionRename(currentTitle: String) -> String? {
    let copy = RabbisirCopy(language: RabbisirLocalization.shared.language)
    let alert = NSAlert()
    alert.messageText = copy.navigationDialogs.renameSession
    alert.informativeText = copy.navigationDialogs.sessionRenameNote
    alert.alertStyle = .informational
    alert.addButton(withTitle: copy[.save])
    alert.addButton(withTitle: copy[.cancel])
    alert.buttons[1].keyEquivalent = "\u{1b}"

    let field = NSTextField(string: currentTitle)
    field.frame = CGRect(x: 0, y: 0, width: 320, height: 24)
    field.placeholderString = copy.navigationDialogs.sessionName
    field.selectText(nil)
    alert.accessoryView = field

    NSApp.activate(ignoringOtherApps: true)
    alert.window.center()
    let response = alert.runModal()
    guard response == .alertFirstButtonReturn else { return nil }
    let title = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
    return title.isEmpty ? nil : title
  }
}
