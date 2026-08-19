import AppKit
import Combine
import Foundation
import SwiftUI

protocol FirstRunConfigurationTransporting: Sendable {
  func describeCredentials(references: [String]) async throws -> UpstreamCredentialDescription
  func describeHost() async throws -> UpstreamHostDescription
  func setCredential(reference: String, value: String) async throws
  func listModels() async throws -> UpstreamSettingsModelCatalog
}

extension UpstreamSettingsTransport: FirstRunConfigurationTransporting {}

@MainActor
protocol RabbisirExternalURLOpening: AnyObject {
  func open(_ url: URL) -> Bool
}

extension NSWorkspace: RabbisirExternalURLOpening {}

enum DeepSeekAPIKeyPortal {
  static let url = URL(string: "https://platform.deepseek.com/api_keys")!

  @MainActor
  static func open(using opener: any RabbisirExternalURLOpening = NSWorkspace.shared) -> Bool {
    opener.open(url)
  }
}

protocol DeepSeekConnectionTesting: Sendable {
  func test(apiKey: String) async -> Bool
}

struct DeepSeekConnectionTester: DeepSeekConnectionTesting, @unchecked Sendable {
  private let endpoint: URL
  private let session: URLSession

  init(
    endpoint: URL = URL(string: "https://api.deepseek.com/models")!,
    session: URLSession = .shared
  ) {
    self.endpoint = endpoint
    self.session = session
  }

  func test(apiKey: String) async -> Bool {
    var request = URLRequest(url: endpoint)
    request.httpMethod = "GET"
    request.timeoutInterval = 15
    request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { return false }
      let payload = try JSONDecoder().decode(DeepSeekModelListResponse.self, from: data)
      return payload.object == "list" && !payload.data.isEmpty
    } catch {
      return false
    }
  }
}

private struct DeepSeekModelListResponse: Decodable {
  struct Model: Decodable {
    let id: String
  }

  let object: String
  let data: [Model]
}

enum FirstRunConfigurationReadiness: Equatable, Sendable {
  case ready
  case requiresConfiguration
}

enum FirstRunConfigurationAttempt: Equatable, Sendable {
  case ready
  case emptyKey
  case failed
}

struct FirstRunConfigurationService: Sendable {
  private let transport: any FirstRunConfigurationTransporting
  private let connectionTester: any DeepSeekConnectionTesting

  init(
    transport: any FirstRunConfigurationTransporting,
    connectionTester: any DeepSeekConnectionTesting = DeepSeekConnectionTester()
  ) {
    self.transport = transport
    self.connectionTester = connectionTester
  }

  func checkReadiness() async -> FirstRunConfigurationReadiness {
    do {
      let credential = try await transport.describeCredentials(
        references: [NativeSettingsStore.deepSeekCredentialReference]
      ).credentials[NativeSettingsStore.deepSeekCredentialReference]
      guard credential?.configured == true else { return .requiresConfiguration }
      return try await hasUsableOfficialModel() ? .ready : .requiresConfiguration
    } catch {
      return .requiresConfiguration
    }
  }

  func saveAndTest(apiKey: String) async -> FirstRunConfigurationAttempt {
    let trimmed = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return .emptyKey }
    guard await connectionTester.test(apiKey: trimmed) else { return .failed }
    do {
      try await transport.setCredential(
        reference: NativeSettingsStore.deepSeekCredentialReference,
        value: trimmed
      )
      let credential = try await transport.describeCredentials(
        references: [NativeSettingsStore.deepSeekCredentialReference]
      ).credentials[NativeSettingsStore.deepSeekCredentialReference]
      guard credential?.configured == true, try await hasUsableOfficialModel() else {
        return .failed
      }
      return .ready
    } catch {
      return .failed
    }
  }

  private func hasUsableOfficialModel() async throws -> Bool {
    let catalog = try await transport.listModels()
    guard
      !catalog.failures.contains(where: { $0.id == DeepSeekFlashModelPolicy.officialProviderID })
    else {
      return false
    }
    let host = try await transport.describeHost()
    guard host.provider == DeepSeekFlashModelPolicy.officialProviderID,
      let modelID = host.model
    else {
      return false
    }
    return DeepSeekFlashModelPolicy.containsOfficialModel(id: modelID, in: catalog)
  }
}

@MainActor
final class FirstRunConfigurationModel: ObservableObject {
  enum Phase: Equatable {
    case awaitingInput
    case testing
    case failed
    case emptyKey
    case succeeded
  }

  @Published private(set) var phase: Phase = .awaitingInput

  private let service: FirstRunConfigurationService
  private let completion: @MainActor () -> Void

  init(
    service: FirstRunConfigurationService,
    completion: @escaping @MainActor () -> Void
  ) {
    self.service = service
    self.completion = completion
  }

  func saveAndTest(apiKey: String) async {
    guard phase != .testing else { return }
    phase = .testing
    switch await service.saveAndTest(apiKey: apiKey) {
    case .ready:
      phase = .succeeded
      try? await Task.sleep(for: .milliseconds(450))
      guard !Task.isCancelled else { return }
      completion()
    case .emptyKey:
      phase = .emptyKey
    case .failed:
      phase = .failed
    }
  }
}

struct FirstRunConfigurationCopy: Equatable, Sendable {
  let language: RabbisirInterfaceLanguage

  var windowTitle: String {
    language == .chinese ? "首次 API Key 配置" : "First API Key Setup"
  }

  var title: String {
    language == .chinese ? "先连接 DeepSeek" : "Connect DeepSeek First"
  }

  var explanation: String {
    language == .chinese
      ? "完成 API Key 保存与连通测试后，Rabbisir 才会打开主窗口。"
      : "Rabbisir opens the main workspace only after the API key is saved and the connection test succeeds."
  }

  var privacy: String {
    language == .chinese
      ? "Key 通过现有安全凭据通道单向保存，不会被读回、显示或写入日志。"
      : "The key is written one way through the existing secure credential channel. It is never read back, displayed, or logged."
  }

  var field: String {
    language == .chinese ? "DeepSeek API Key" : "DeepSeek API Key"
  }

  var action: String {
    language == .chinese ? "保存并测试连接" : "Save and Test Connection"
  }

  var getAPIKey: String {
    language == .chinese ? "获取 API Key" : "Get API Key"
  }

  var getAPIKeyExplanation: String {
    language == .chinese
      ? "前往 DeepSeek 官方平台，自行登录并创建 API Key。"
      : "Open the official DeepSeek Platform to sign in and create an API key."
  }

  var getAPIKeyFailure: String {
    language == .chinese
      ? "无法打开官方平台。你仍可手动粘贴已有 API Key。"
      : "The official platform could not be opened. You can still paste an existing API key."
  }

  var testing: String {
    language == .chinese ? "正在安全保存并测试连接…" : "Saving securely and testing the connection…"
  }

  var failed: String {
    language == .chinese
      ? "连接测试失败。请检查 Key 和网络后重试；主窗口尚未打开。"
      : "The connection test failed. Check the key and network, then try again. The main workspace remains closed."
  }

  var emptyKey: String {
    language == .chinese ? "请输入 API Key。" : "Enter an API key."
  }

  var succeeded: String {
    language == .chinese ? "连接测试成功，正在打开 Rabbisir…" : "Connection succeeded. Opening Rabbisir…"
  }
}

@MainActor
enum FirstRunConfigurationWindowPolicy {
  static func configure(_ window: NSWindow) {
    NativeSettingsMaterialPolicy.configure(window)
    for buttonType in [
      NSWindow.ButtonType.closeButton,
      .miniaturizeButton,
      .zoomButton,
    ] {
      window.standardWindowButton(buttonType)?.isHidden = true
    }
  }

  static func makeContainer(
    contentView: NSView
  ) -> NSView {
    NativeSettingsMaterialPolicy.makeContainer(contentView: contentView)
  }
}

@MainActor
final class FirstRunConfigurationWindowCoordinator: NSObject, NSWindowDelegate {
  private let model: FirstRunConfigurationModel
  private var window: NSWindow?
  private var languageSubscription: AnyCancellable?

  var isVisible: Bool { window?.isVisible == true }

  init(
    service: FirstRunConfigurationService,
    completion: @escaping @MainActor () -> Void
  ) {
    model = FirstRunConfigurationModel(service: service, completion: completion)
  }

  func show(on screen: NSScreen) {
    let window = window ?? makeWindow()
    self.window = window
    let size = CGSize(width: 560, height: 440)
    window.setFrame(
      LaunchPanelPlacement.frame(contentSize: size, in: screen.visibleFrame).integral,
      display: false
    )
    window.makeKeyAndOrderFront(nil)
    NSApp.activate(ignoringOtherApps: true)
  }

  func closeAfterSuccess() {
    window?.orderOut(nil)
    window = nil
    languageSubscription?.cancel()
    languageSubscription = nil
  }

  func move(to screen: NSScreen) {
    guard let window else { return }
    RabbisirWindowMover.move(window, to: screen)
  }

  private func makeWindow() -> NSWindow {
    let size = CGSize(width: 560, height: 440)
    let window = NSWindow(
      contentRect: CGRect(origin: .zero, size: size),
      styleMask: [.titled, .miniaturizable, .fullSizeContentView],
      backing: .buffered,
      defer: false
    )
    window.identifier = NSUserInterfaceItemIdentifier("Rabbisir.firstRunConfiguration")
    window.isReleasedWhenClosed = false
    window.titleVisibility = .visible
    window.isMovableByWindowBackground = true
    FirstRunConfigurationWindowPolicy.configure(window)
    window.collectionBehavior = [.moveToActiveSpace]
    let materialContainer = FirstRunConfigurationWindowPolicy.makeContainer(
      contentView: NSHostingView(
        rootView: RabbisirLocalizedRoot {
          FirstRunConfigurationView(model: model)
        }
      )
    )
    window.contentView = materialContainer
    updateWindowCopy(window, language: RabbisirLocalization.shared.language)
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
    let copy = FirstRunConfigurationCopy(language: language)
    window.title = copy.windowTitle
    window.setAccessibilityLabel(copy.windowTitle)
  }
}

private struct FirstRunConfigurationView: View {
  @Environment(\.rabbisirCopy) private var appCopy
  @ObservedObject var model: FirstRunConfigurationModel
  @State private var apiKey = ""
  @State private var portalOpenFailed = false

  private var copy: FirstRunConfigurationCopy {
    FirstRunConfigurationCopy(language: appCopy.language)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 18) {
      VStack(alignment: .leading, spacing: 8) {
        Text(copy.title)
          .font(.system(size: 30, weight: .bold, design: .rounded))
        Text(copy.explanation)
          .font(.body)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 9) {
        Text(copy.field).font(.headline)
        SecureField(copy.field, text: $apiKey)
          .textFieldStyle(.roundedBorder)
          .disabled(model.phase == .testing || model.phase == .succeeded)
          .accessibilityLabel(copy.field)
        Text(copy.privacy)
          .font(.caption)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      VStack(alignment: .leading, spacing: 5) {
        FirstRunExternalLinkButton(
          title: copy.getAPIKey,
          accessibilityHint: copy.getAPIKeyExplanation
        ) {
          portalOpenFailed = !DeepSeekAPIKeyPortal.open()
        }
        .fixedSize()

        Text(copy.getAPIKeyExplanation)
          .font(.caption2)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }

      statusView

      HStack {
        Spacer()
        Button {
          let submitted = apiKey
          Task {
            await model.saveAndTest(apiKey: submitted)
            apiKey = ""
          }
        } label: {
          if model.phase == .testing {
            ProgressView().controlSize(.small)
          } else {
            Text(copy.action)
          }
        }
        .keyboardShortcut(.defaultAction)
        .accessibilityLabel(copy.action)
        .disabled(
          apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || model.phase == .testing
            || model.phase == .succeeded
        )
      }
    }
    .padding(40)
    .frame(width: 560, height: 440)
  }

  @ViewBuilder
  private var statusView: some View {
    if portalOpenFailed {
      Label(copy.getAPIKeyFailure, systemImage: "exclamationmark.triangle.fill")
        .foregroundStyle(.orange)
    } else {
      switch model.phase {
      case .awaitingInput:
        Color.clear.frame(height: 22)
      case .testing:
        Label(copy.testing, systemImage: "network")
          .foregroundStyle(.secondary)
      case .failed:
        Label(copy.failed, systemImage: "xmark.circle.fill")
          .foregroundStyle(.red)
      case .emptyKey:
        Label(copy.emptyKey, systemImage: "exclamationmark.circle.fill")
          .foregroundStyle(.orange)
      case .succeeded:
        Label(copy.succeeded, systemImage: "checkmark.circle.fill")
          .foregroundStyle(.green)
      }
    }
  }
}

private struct FirstRunExternalLinkButton: NSViewRepresentable {
  let title: String
  let accessibilityHint: String
  let action: @MainActor () -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(action: action)
  }

  func makeNSView(context: Context) -> NSButton {
    let button = NSButton(
      title: title,
      target: context.coordinator,
      action: #selector(Coordinator.performAction(_:))
    )
    button.bezelStyle = .rounded
    button.setAccessibilityLabel(title)
    button.setAccessibilityHelp(accessibilityHint)
    return button
  }

  func updateNSView(_ button: NSButton, context: Context) {
    context.coordinator.action = action
    button.title = title
    button.setAccessibilityLabel(title)
    button.setAccessibilityHelp(accessibilityHint)
  }

  @MainActor
  final class Coordinator: NSObject {
    var action: @MainActor () -> Void

    init(action: @escaping @MainActor () -> Void) {
      self.action = action
    }

    @objc func performAction(_ sender: Any?) {
      action()
    }
  }
}
