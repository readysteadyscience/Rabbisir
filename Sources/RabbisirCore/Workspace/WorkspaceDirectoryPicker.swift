import AppKit
import Foundation

@MainActor
protocol WorkspaceDirectoryPicking: AnyObject {
  func pickDirectory() async -> URL?
}

@MainActor
protocol WorkspaceAdopting: AnyObject {
  func adoptWorkspace(at directory: URL) async -> Bool
}

@MainActor
final class AppKitWorkspaceDirectoryPicker: WorkspaceDirectoryPicking {
  func pickDirectory() async -> URL? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.canCreateDirectories = true
    panel.resolvesAliases = true
    panel.title = localizedTitle
    panel.prompt = localizedPrompt

    let response = await withCheckedContinuation { continuation in
      panel.begin { continuation.resume(returning: $0) }
    }
    guard response == .OK else { return nil }
    return validatedDirectory(panel.url)
  }

  private var localizedTitle: String {
    switch RabbisirLocalization.shared.language {
    case .chinese: "选择工作区文件夹"
    case .english: "Select Workspace Folder"
    }
  }

  private var localizedPrompt: String {
    switch RabbisirLocalization.shared.language {
    case .chinese: "选择"
    case .english: "Choose"
    }
  }

  private func validatedDirectory(_ url: URL?) -> URL? {
    guard let url, url.isFileURL else { return nil }
    var isDirectory: ObjCBool = false
    guard
      FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory),
      isDirectory.boolValue
    else { return nil }
    return url.standardizedFileURL
  }
}
