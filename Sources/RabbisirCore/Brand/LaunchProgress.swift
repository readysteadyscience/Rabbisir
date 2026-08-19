import AppKit
import Combine

enum LaunchPhase: Int, CaseIterable, Sendable {
  case loadingBrandAsset
  case brandAssetReady
  case workspaceReady
  case runtimeReady
  case completed

  var progress: Double {
    switch self {
    case .loadingBrandAsset:
      0.08
    case .brandAssetReady:
      0.28
    case .workspaceReady:
      0.58
    case .runtimeReady:
      0.88
    case .completed:
      1
    }
  }

  func statusText(copy: RabbisirLaunchCopy) -> String {
    switch self {
    case .loadingBrandAsset:
      copy.loadingBrandAsset
    case .brandAssetReady:
      copy.brandAssetReady
    case .workspaceReady:
      copy.workspaceReady
    case .runtimeReady:
      copy.runtimeReady
    case .completed:
      copy.completed
    }
  }
}

@MainActor
final class LaunchProgressModel: ObservableObject {
  @Published private(set) var phase: LaunchPhase = .loadingBrandAsset
  @Published private(set) var logoImage: NSImage?
  @Published private(set) var failureMessage: String?

  var progress: Double { phase.progress }
  func statusText(copy: RabbisirLaunchCopy) -> String {
    failureMessage == nil ? phase.statusText(copy: copy) : copy.incomplete
  }
  var canRetry: Bool { failureMessage != nil }

  func restartAssetLoading() {
    phase = .loadingBrandAsset
    logoImage = nil
    failureMessage = nil
  }

  func brandAssetDidLoad(_ image: NSImage) {
    logoImage = image
    advance(to: .brandAssetReady)
  }

  func workspaceDidPrepare() {
    advance(to: .workspaceReady)
  }

  func restartRuntimeLoading() {
    phase = .workspaceReady
    failureMessage = nil
  }

  func runtimeDidBecomeReady() {
    advance(to: .runtimeReady)
  }

  func complete() {
    advance(to: .completed)
  }

  func fail(message: String) {
    failureMessage = message
  }

  private func advance(to nextPhase: LaunchPhase) {
    guard failureMessage == nil, nextPhase.rawValue >= phase.rawValue else { return }
    phase = nextPhase
  }
}
