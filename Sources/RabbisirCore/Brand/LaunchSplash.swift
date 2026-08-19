import AppKit
import OSLog
import SwiftUI

enum LaunchPanelPlacement {
  static func frame(contentSize: CGSize, in visibleFrame: CGRect) -> CGRect {
    RabbisirWindowPlacement.frame(
      currentFrame: CGRect(origin: .zero, size: contentSize),
      minimumSize: .zero,
      sourceVisibleFrame: nil,
      targetVisibleFrame: visibleFrame
    )
  }
}

enum LaunchContentPlacement {
  static let brandSpacing: CGFloat = 16
  static let logoDisplaySize = CGSize(width: 125.8125, height: 176.90625)
  static let titleOpticalLeadingCorrection: CGFloat = -4

  static func centerX(in containerWidth: CGFloat) -> CGFloat {
    containerWidth / 2
  }

  static func centeredFrame(contentSize: CGSize, in containerWidth: CGFloat) -> CGRect {
    CGRect(
      x: centerX(in: containerWidth) - contentSize.width / 2,
      y: 0,
      width: contentSize.width,
      height: contentSize.height
    )
  }
}

enum LaunchPresentationMode: Equatable {
  case live
  case preview

  func displayedProgress(liveProgress: Double) -> Double {
    switch self {
    case .live:
      liveProgress
    case .preview:
      0.58
    }
  }

  func displayedStatus(liveStatus: String) -> String {
    switch self {
    case .live:
      liveStatus
    case .preview:
      "启动页预览 · 固定进度"
    }
  }

  func displayedStatus(liveStatus: String, copy: RabbisirLaunchCopy) -> String {
    switch self {
    case .live: liveStatus
    case .preview: copy.preview
    }
  }
}

@MainActor
private final class LaunchPanel: NSPanel {
  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class LaunchSplashCoordinator {
  let model = LaunchProgressModel()

  var isVisible: Bool { panel.isVisible }

  private let mode: LaunchPresentationMode
  private let panel: LaunchPanel
  private var intendedFrame: CGRect
  private var transitionTask: Task<Void, Never>?

  init(
    screen: NSScreen,
    mode: LaunchPresentationMode = .live,
    retry: @escaping @MainActor () -> Void,
    exitPreview: @escaping @MainActor () -> Void = {}
  ) {
    self.mode = mode
    let panelSize = CGSize(width: 760, height: 460)
    let frame = LaunchPanelPlacement.frame(
      contentSize: panelSize,
      in: screen.visibleFrame
    )
    intendedFrame = frame
    panel = LaunchPanel(
      contentRect: frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false,
      screen: screen
    )
    panel.identifier = NSUserInterfaceItemIdentifier("Rabbisir.launch")
    panel.level = .normal
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.hidesOnDeactivate = false
    panel.isMovable = false
    panel.collectionBehavior = mode == .preview ? [.canJoinAllSpaces] : []
    panel.isReleasedWhenClosed = false
    let hostingView = NSHostingView(
      rootView: RabbisirLocalizedRoot {
        RabbisirLaunchView(
          model: model,
          mode: mode,
          retry: retry,
          exitPreview: exitPreview
        )
      }
    )
    hostingView.frame = CGRect(origin: .zero, size: panelSize)
    hostingView.autoresizingMask = [.width, .height]
    hostingView.wantsLayer = true
    hostingView.layer?.backgroundColor = NSColor.clear.cgColor
    panel.contentView = hostingView
    panel.setFrame(frame, display: false)
    panel.setAccessibilityLabel(
      RabbisirCopy(language: RabbisirLocalization.shared.language).launch.panelAccessibility
    )
  }

  deinit {
    transitionTask?.cancel()
  }

  func show() {
    panel.setFrame(intendedFrame, display: true)
    panel.alphaValue = 1
    if mode == .preview {
      panel.orderFrontRegardless()
      NSApp.activate()
      panel.makeKeyAndOrderFront(nil)
    } else {
      panel.makeKeyAndOrderFront(nil)
    }
    let screenName = panel.screen?.localizedName ?? "none"
    let presentationMode = mode == .preview ? "preview" : "live"
    RabbisirLog.application.debug(
      "Splash frame=\(NSStringFromRect(self.panel.frame), privacy: .private), screen=\(screenName, privacy: .private), mode=\(presentationMode, privacy: .public)"
    )
  }

  func dismissForConfiguration() {
    transitionTask?.cancel()
    transitionTask = nil
    panel.orderOut(nil)
  }

  func move(to screen: NSScreen) {
    intendedFrame = LaunchPanelPlacement.frame(
      contentSize: intendedFrame.size,
      in: screen.visibleFrame
    )
    panel.setFrame(intendedFrame, display: panel.isVisible)
  }

  func transitionToWorkspace(
    reveal: @escaping @MainActor (_ duration: TimeInterval) -> Void
  ) {
    guard mode == .live, transitionTask == nil else { return }
    model.complete()
    RabbisirLog.application.info("Launch initialization completed")

    let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    let splashFadeDuration = reduceMotion ? 0.12 : 0.28
    let workspaceFadeDuration = reduceMotion ? 0.14 : 1.0

    transitionTask = Task { @MainActor [weak self] in
      guard let self else { return }
      try? await Task.sleep(for: .milliseconds(reduceMotion ? 20 : 120))
      guard !Task.isCancelled else { return }

      NSAnimationContext.beginGrouping()
      NSAnimationContext.current.duration = splashFadeDuration
      NSAnimationContext.current.allowsImplicitAnimation = true
      self.panel.animator().alphaValue = 0
      NSAnimationContext.endGrouping()
      try? await Task.sleep(for: .milliseconds(Int(splashFadeDuration * 1_000) + 20))
      guard !Task.isCancelled else { return }

      self.panel.orderOut(nil)
      reveal(workspaceFadeDuration)
    }
  }
}

private struct RabbisirLaunchView: View {
  @ObservedObject var model: LaunchProgressModel
  let mode: LaunchPresentationMode
  let retry: @MainActor () -> Void
  let exitPreview: @MainActor () -> Void

  @Environment(\.accessibilityReduceMotion) private var reduceMotion
  @Environment(\.rabbisirCopy) private var copy
  @State private var isVisible = false

  private var displayedProgress: Double {
    mode.displayedProgress(liveProgress: model.progress)
  }

  private var displayedStatus: String {
    mode.displayedStatus(liveStatus: model.statusText(copy: copy.launch), copy: copy.launch)
  }

  var body: some View {
    VStack(spacing: 0) {
      GeometryReader { row in
        HStack(alignment: .center, spacing: LaunchContentPlacement.brandSpacing) {
          if let logoImage = model.logoImage {
            HighQualityLogoView(
              image: logoImage,
              readabilityShadow: LaunchReadabilityStyle.darkLogo
            )
            .frame(
              width: LaunchContentPlacement.logoDisplaySize.width,
              height: LaunchContentPlacement.logoDisplaySize.height
            )
            .accessibilityLabel(copy.launch.logo)
          }

          VStack(alignment: .leading, spacing: 7) {
            RabbisirBrandTitleView(
              content: .current,
              font: .system(size: 77.03, weight: .semibold, design: .rounded),
              color: .white
            )
            .launchReadability(.lightForeground)
            .offset(x: LaunchContentPlacement.titleOpticalLeadingCorrection)
            Group {
              Text(RabbisirAppIdentity.upstreamAttribution)
              Text(RabbisirAppIdentity.coreAttribution)
            }
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(.white)
            .launchReadability(.lightForeground)
          }
          .fixedSize()
        }
        .fixedSize()
        .position(
          x: LaunchContentPlacement.centerX(in: row.size.width),
          y: 120
        )
      }
      .frame(height: 240)

      GeometryReader { row in
        ZStack(alignment: .leading) {
          Capsule()
            .fill(.white.opacity(0.22))
          Capsule()
            .fill(.white)
            .frame(width: 420 * displayedProgress)
        }
        .frame(width: 420, height: 4)
        .launchReadability(.lightForeground)
        .position(
          x: LaunchContentPlacement.centerX(in: row.size.width),
          y: 2
        )
      }
      .frame(height: 4)
      .padding(.top, 24)
      .animation(
        reduceMotion ? nil : .linear(duration: 0.18),
        value: displayedProgress
      )
      .accessibilityLabel(copy.launch.progress)
      .accessibilityValue("\(Int(displayedProgress * 100))%")

      Text(displayedStatus)
        .font(.caption)
        .foregroundStyle(.white)
        .launchReadability(.lightForeground)
        .padding(.top, 8)

      if mode == .preview {
        Button(copy.launch.exitPreview, action: exitPreview)
          .buttonStyle(.plain)
          .font(.caption.weight(.medium))
          .foregroundStyle(.white)
          .launchReadability(.lightForeground)
          .padding(.top, 14)
          .keyboardShortcut(.cancelAction)
          .accessibilityHint(copy.launch.exitPreviewHint)
      }

      if mode == .live, let failureMessage = model.failureMessage {
        VStack(spacing: 9) {
          Text(failureMessage)
            .font(.caption)
            .foregroundStyle(.red)
            .launchReadability(.lightForeground)
            .multilineTextAlignment(.center)
          Button(copy.launch.retry, action: retry)
            .foregroundStyle(.white)
            .launchReadability(.lightForeground)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint(copy.launch.retryHint)
        }
        .padding(.top, 16)
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .opacity(isVisible ? 1 : 0)
    .onAppear {
      withAnimation(.easeOut(duration: reduceMotion ? 0.12 : 0.34)) {
        isVisible = true
      }
    }
    .accessibilityElement(children: .contain)
    .accessibilityLabel(copy.launch.starting)
  }
}
