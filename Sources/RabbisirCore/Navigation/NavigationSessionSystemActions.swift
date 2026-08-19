import AppKit

/// Performs local macOS actions for durable session metadata without reading session content.
@MainActor
enum NavigationSessionSystemActions {
  static func copySessionID(_ sessionID: String) {
    copy(sessionID)
  }

  static func copyWorkingDirectory(_ workingDirectory: String) {
    copy(workingDirectory)
  }

  static func showInFinder(_ workingDirectory: String) -> Bool {
    var isDirectory: ObjCBool = false
    guard FileManager.default.fileExists(atPath: workingDirectory, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return false }
    NSWorkspace.shared.activateFileViewerSelecting([
      URL(fileURLWithPath: workingDirectory, isDirectory: true)
    ])
    return true
  }

  private static func copy(_ value: String) {
    let pasteboard = NSPasteboard.general
    pasteboard.clearContents()
    pasteboard.setString(value, forType: .string)
  }
}
