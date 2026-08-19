import AppKit
import QuartzCore
import SwiftUI

private final class ConversationDisplayObservationToken: @unchecked Sendable {
  let value: NSObjectProtocol

  init(_ value: NSObjectProtocol) {
    self.value = value
  }
}

@MainActor
enum ConversationTextAppearance: Equatable, Sendable {
  case body
  case detail
  case tool
  case error

  var font: NSFont {
    switch self {
    case .body, .error:
      .systemFont(ofSize: NSFont.systemFontSize)
    case .detail:
      .systemFont(ofSize: NSFont.smallSystemFontSize)
    case .tool:
      .monospacedSystemFont(ofSize: NSFont.smallSystemFontSize, weight: .regular)
    }
  }

  var color: NSColor {
    let style = ConversationReadabilityStyle.currentAppKit
    return switch self {
    case .body, .tool:
      style.nsColor(for: .primary)
    case .detail:
      style.nsColor(for: .secondary)
    case .error:
      style.nsColor(for: .failure)
    }
  }

  var swiftUIColor: Color { Color(nsColor: color) }
}

struct ConversationTextRegion: Equatable, Sendable {
  let id: String
  let text: String
  let appearance: ConversationTextAppearance
  let visibleFrame: CGRect
  let fullFrame: CGRect
}

struct ConversationActionRegion: Equatable, Sendable {
  let id: String
  let accessibilityLabel: String
  let accessibilityHelp: String
  let accessibilityIdentifier: String
  let visualState: ConversationActionVisualState
  let reduceMotion: Bool
  let visibleFrame: CGRect
}

enum ConversationActionVisualState: Equatable, Sendable {
  case idle
  case success
  case failure

  var symbolName: String {
    switch self {
    case .idle:
      "doc.on.doc"
    case .success:
      "checkmark"
    case .failure:
      "exclamationmark.triangle.fill"
    }
  }

  func accessibilityValue(copy: RabbisirCopy) -> String {
    switch self {
    case .idle:
      copy[.conversationCopyAvailable]
    case .success:
      copy[.artifactCopied]
    case .failure:
      copy[.conversationCopyFailed]
    }
  }

  @MainActor
  var nsColor: NSColor {
    let style = ConversationReadabilityStyle.currentAppKit
    return switch self {
    case .idle:
      style.nsColor(for: .secondary)
    case .success:
      style.nsColor(for: .success)
    case .failure:
      style.nsColor(for: .failure)
    }
  }

  @MainActor
  var swiftUIColor: Color {
    Color(nsColor: nsColor)
  }
}

enum ConversationHitIslandGeometry {
  static func visibleFrame(contentFrame: CGRect, clipFrame: CGRect) -> CGRect? {
    let intersection = contentFrame.intersection(clipFrame)
    guard !intersection.isNull, intersection.width >= 1, intersection.height >= 1 else {
      return nil
    }
    return intersection
  }
}

enum ConversationLinkDetection {
  @MainActor
  static func attributedString(
    text: String,
    appearance: ConversationTextAppearance,
    fileExists: (String) -> Bool = FileManager.default.fileExists(atPath:)
  ) -> NSAttributedString {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineBreakMode = .byWordWrapping
    let attributed = markdownAttributedString(text: text, appearance: appearance)
    let fullRange = NSRange(location: 0, length: attributed.length)
    attributed.addAttributes(
      [
        .foregroundColor: appearance.color,
        .paragraphStyle: paragraph,
        .shadow: ConversationReadabilityStyle.currentAppKit.tightShadow.nsShadow,
      ],
      range: fullRange
    )
    if let detector = try? NSDataDetector(
      types: NSTextCheckingResult.CheckingType.link.rawValue
    ) {
      detector.enumerateMatches(in: attributed.string, options: [], range: fullRange) {
        match, _, _ in
        guard let match, let url = match.url else { return }
        attributed.addAttribute(.link, value: url, range: match.range)
      }
    }

    for candidate in localFileCandidates(in: attributed.string) where fileExists(candidate.path) {
      attributed.addAttribute(
        .link,
        value: URL(fileURLWithPath: candidate.path),
        range: candidate.range
      )
    }
    return attributed
  }

  @MainActor
  private static func markdownAttributedString(
    text: String,
    appearance: ConversationTextAppearance
  ) -> NSMutableAttributedString {
    let result = NSMutableAttributedString()
    var inCodeFence = false
    let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
    for (index, sourceLine) in lines.enumerated() {
      let source = String(sourceLine)
      if source.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
        inCodeFence.toggle()
      } else if inCodeFence {
        result.append(
          NSAttributedString(
            string: source,
            attributes: [
              .font: NSFont.monospacedSystemFont(
                ofSize: appearance.font.pointSize,
                weight: .regular
              )
            ]
          ))
      } else {
        let block = markdownBlock(source, appearance: appearance)
        result.append(block)
      }
      if index < lines.index(before: lines.endIndex) {
        result.append(NSAttributedString(string: "\n"))
      }
    }
    return result
  }

  @MainActor
  private static func markdownBlock(
    _ source: String,
    appearance: ConversationTextAppearance
  ) -> NSAttributedString {
    var content = source
    var baseFont = appearance.font
    if let heading = headingLevel(source) {
      content = String(source.dropFirst(heading + 1))
      baseFont = NSFont.systemFont(
        ofSize: appearance.font.pointSize + CGFloat(max(0, 4 - heading)),
        weight: .semibold
      )
    } else if source.hasPrefix("- ") || source.hasPrefix("* ") {
      content = "• " + source.dropFirst(2)
    } else if source.hasPrefix("> ") {
      content = String(source.dropFirst(2))
    }
    let parsed =
      (try? AttributedString(
        markdown: content,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      )).map(NSAttributedString.init) ?? NSAttributedString(string: content)
    let mutable = NSMutableAttributedString(attributedString: parsed)
    let range = NSRange(location: 0, length: mutable.length)
    mutable.addAttribute(.font, value: baseFont, range: range)
    mutable.enumerateAttribute(.inlinePresentationIntent, in: range) { value, run, _ in
      guard let raw = value as? NSNumber else { return }
      let intent = raw.intValue
      if intent & 4 != 0 {
        mutable.addAttribute(
          .font,
          value: NSFont.monospacedSystemFont(ofSize: baseFont.pointSize, weight: .regular),
          range: run
        )
      } else if intent & 2 != 0 {
        mutable.addAttribute(
          .font,
          value: NSFontManager.shared.convert(baseFont, toHaveTrait: .boldFontMask),
          range: run
        )
      } else if intent & 1 != 0 {
        mutable.addAttribute(
          .font,
          value: NSFontManager.shared.convert(baseFont, toHaveTrait: .italicFontMask),
          range: run
        )
      }
    }
    return mutable
  }

  private static func headingLevel(_ line: String) -> Int? {
    let hashes = line.prefix(while: { $0 == "#" }).count
    guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
    return hashes
  }

  static func links(in attributedString: NSAttributedString) -> [URL] {
    var links: [URL] = []
    attributedString.enumerateAttribute(
      .link,
      in: NSRange(location: 0, length: attributedString.length)
    ) { value, _, _ in
      if let url = value as? URL {
        links.append(url)
      } else if let value = value as? String, let url = URL(string: value) {
        links.append(url)
      }
    }
    return links
  }

  private static func localFileCandidates(in text: String) -> [(path: String, range: NSRange)] {
    let pattern =
      #"(?:(?<=`)|(?<=\()|(?<=\s)|^)(/[\p{L}\p{N}._~+@%()\[\]{}' -]+(?:/[\p{L}\p{N}._~+@%()\[\]{}' -]+)+)(?=`|\)|\s|$)"#
    guard let expression = try? NSRegularExpression(pattern: pattern) else { return [] }
    let source = text as NSString
    let fullRange = NSRange(location: 0, length: source.length)
    return expression.matches(in: text, range: fullRange).compactMap { match in
      guard match.numberOfRanges > 1 else { return nil }
      let range = match.range(at: 1)
      return (source.substring(with: range), range)
    }
  }
}

@MainActor
private protocol ConversationInteractionRegionProviding: AnyObject {
  var conversationInteractionRegion: ConversationTextRegion? { get }
  func forwardConversationScroll(_ event: NSEvent)
}

@MainActor
private protocol ConversationActionRegionProviding: AnyObject {
  var conversationActionRegion: ConversationActionRegion? { get }
  func performConversationAction()
  func forwardConversationActionScroll(_ event: NSEvent)
}

@MainActor
final class ConversationInteractionSurfaceModel {
  private final class WeakProvider {
    weak var value: (any ConversationInteractionRegionProviding)?

    init(_ value: any ConversationInteractionRegionProviding) {
      self.value = value
    }
  }

  private final class WeakActionProvider {
    weak var value: (any ConversationActionRegionProviding)?

    init(_ value: any ConversationActionRegionProviding) {
      self.value = value
    }
  }

  var onRegionsChanged: (([ConversationTextRegion]) -> Void)? {
    didSet { publishTextRegions() }
  }
  var onActionRegionsChanged: (([ConversationActionRegion]) -> Void)? {
    didSet { publishActionRegions() }
  }
  private var textProviders: [String: WeakProvider] = [:]
  private var actionProviders: [String: WeakActionProvider] = [:]

  fileprivate func register(
    id: String,
    provider: any ConversationInteractionRegionProviding
  ) {
    textProviders[id] = WeakProvider(provider)
    publishTextRegions()
  }

  fileprivate func unregister(id: String, provider: any ConversationInteractionRegionProviding) {
    guard textProviders[id]?.value === provider else { return }
    textProviders[id] = nil
    publishTextRegions()
  }

  fileprivate func regionDidChange() {
    publishTextRegions()
  }

  fileprivate func forwardScroll(_ event: NSEvent, regionID: String) {
    textProviders[regionID]?.value?.forwardConversationScroll(event)
  }

  fileprivate func registerAction(
    id: String,
    provider: any ConversationActionRegionProviding
  ) {
    actionProviders[id] = WeakActionProvider(provider)
    publishActionRegions()
  }

  fileprivate func unregisterAction(
    id: String,
    provider: any ConversationActionRegionProviding
  ) {
    guard actionProviders[id]?.value === provider else { return }
    actionProviders[id] = nil
    publishActionRegions()
  }

  fileprivate func actionRegionDidChange() {
    publishActionRegions()
  }

  fileprivate func performAction(regionID: String) {
    actionProviders[regionID]?.value?.performConversationAction()
  }

  fileprivate func forwardActionScroll(_ event: NSEvent, regionID: String) {
    actionProviders[regionID]?.value?.forwardConversationActionScroll(event)
  }

  private func publishTextRegions() {
    var next: [ConversationTextRegion] = []
    var expired: [String] = []
    for (id, box) in textProviders {
      guard let provider = box.value else {
        expired.append(id)
        continue
      }
      if let region = provider.conversationInteractionRegion {
        next.append(region)
      }
    }
    for id in expired {
      textProviders[id] = nil
    }
    next.sort { $0.id < $1.id }
    onRegionsChanged?(next)
  }

  private func publishActionRegions() {
    var next: [ConversationActionRegion] = []
    var expired: [String] = []
    for (id, box) in actionProviders {
      guard let provider = box.value else {
        expired.append(id)
        continue
      }
      if let region = provider.conversationActionRegion {
        next.append(region)
      }
    }
    for id in expired {
      actionProviders[id] = nil
    }
    next.sort { $0.id < $1.id }
    onActionRegionsChanged?(next)
  }
}

@MainActor
struct ConversationMessageText: NSViewRepresentable {
  let id: String
  let text: String
  let appearance: ConversationTextAppearance
  let interactionSurface: ConversationInteractionSurfaceModel?

  func makeNSView(context: Context) -> ConversationMessageProbeView {
    ConversationMessageProbeView(
      id: id,
      text: text,
      appearance: appearance,
      interactionSurface: interactionSurface
    )
  }

  func updateNSView(_ nsView: ConversationMessageProbeView, context: Context) {
    nsView.update(
      id: id,
      text: text,
      appearance: appearance,
      interactionSurface: interactionSurface
    )
  }

  func sizeThatFits(
    _ proposal: ProposedViewSize,
    nsView: ConversationMessageProbeView,
    context: Context
  ) -> CGSize? {
    nsView.preferredSize(for: max(1, proposal.width ?? 480))
  }

  static func dismantleNSView(_ nsView: ConversationMessageProbeView, coordinator: Void) {
    nsView.detach()
  }
}

@MainActor
struct ConversationActionHitIsland: NSViewRepresentable {
  let id: String
  let accessibilityLabel: String
  let accessibilityHelp: String
  let accessibilityIdentifier: String
  let visualState: ConversationActionVisualState
  let reduceMotion: Bool
  let interactionSurface: ConversationInteractionSurfaceModel
  let action: @MainActor () -> Void

  func makeNSView(context: Context) -> ConversationActionProbeView {
    ConversationActionProbeView(
      id: id,
      accessibilityLabel: accessibilityLabel,
      accessibilityHelp: accessibilityHelp,
      accessibilityIdentifier: accessibilityIdentifier,
      visualState: visualState,
      reduceMotion: reduceMotion,
      interactionSurface: interactionSurface,
      action: action
    )
  }

  func updateNSView(_ nsView: ConversationActionProbeView, context: Context) {
    nsView.update(
      id: id,
      accessibilityLabel: accessibilityLabel,
      accessibilityHelp: accessibilityHelp,
      accessibilityIdentifier: accessibilityIdentifier,
      visualState: visualState,
      reduceMotion: reduceMotion,
      interactionSurface: interactionSurface,
      action: action
    )
  }

  static func dismantleNSView(_ nsView: ConversationActionProbeView, coordinator: Void) {
    nsView.detach()
  }
}

@MainActor
final class ConversationActionProbeView: NSView, ConversationActionRegionProviding {
  private var regionID: String
  private var regionAccessibilityLabel: String
  private var regionAccessibilityHelp: String
  private var regionAccessibilityIdentifier: String
  private var regionVisualState: ConversationActionVisualState
  private var regionReduceMotion: Bool
  private weak var interactionSurface: ConversationInteractionSurfaceModel?
  private var action: @MainActor () -> Void
  private var clipObserver: NSObjectProtocol?
  private var windowObservers: [NSObjectProtocol] = []

  init(
    id: String,
    accessibilityLabel: String,
    accessibilityHelp: String,
    accessibilityIdentifier: String,
    visualState: ConversationActionVisualState,
    reduceMotion: Bool,
    interactionSurface: ConversationInteractionSurfaceModel,
    action: @escaping @MainActor () -> Void
  ) {
    regionID = id
    regionAccessibilityLabel = accessibilityLabel
    regionAccessibilityHelp = accessibilityHelp
    regionAccessibilityIdentifier = accessibilityIdentifier
    regionVisualState = visualState
    regionReduceMotion = reduceMotion
    self.interactionSurface = interactionSurface
    self.action = action
    super.init(frame: .zero)
    interactionSurface.registerAction(id: id, provider: self)
    setAccessibilityHidden(true)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    if interactionSurface != nil {
      installGeometryObservers()
    } else {
      removeGeometryObservers()
    }
    publishRegion()
  }

  override func layout() {
    super.layout()
    publishRegion()
  }

  func update(
    id: String,
    accessibilityLabel: String,
    accessibilityHelp: String,
    accessibilityIdentifier: String,
    visualState: ConversationActionVisualState,
    reduceMotion: Bool,
    interactionSurface: ConversationInteractionSurfaceModel,
    action: @escaping @MainActor () -> Void
  ) {
    if regionID != id || self.interactionSurface !== interactionSurface {
      self.interactionSurface?.unregisterAction(id: regionID, provider: self)
      regionID = id
      self.interactionSurface = interactionSurface
      interactionSurface.registerAction(id: id, provider: self)
    }
    regionAccessibilityLabel = accessibilityLabel
    regionAccessibilityHelp = accessibilityHelp
    regionAccessibilityIdentifier = accessibilityIdentifier
    regionVisualState = visualState
    regionReduceMotion = reduceMotion
    self.action = action
    publishRegion()
  }

  func detach() {
    interactionSurface?.unregisterAction(id: regionID, provider: self)
    interactionSurface = nil
    removeGeometryObservers()
  }

  var conversationActionRegion: ConversationActionRegion? {
    guard let window else { return nil }
    let clippedInView: CGRect
    if let clipView = enclosingScrollView?.contentView {
      clippedInView = bounds.intersection(convert(clipView.bounds, from: clipView))
    } else {
      clippedInView = bounds
    }
    guard !clippedInView.isNull, clippedInView.width >= 1, clippedInView.height >= 1 else {
      return nil
    }
    let screenFrame = window.convertToScreen(convert(clippedInView, to: nil))
    return ConversationActionRegion(
      id: regionID,
      accessibilityLabel: regionAccessibilityLabel,
      accessibilityHelp: regionAccessibilityHelp,
      accessibilityIdentifier: regionAccessibilityIdentifier,
      visualState: regionVisualState,
      reduceMotion: regionReduceMotion,
      visibleFrame: screenFrame
    )
  }

  func performConversationAction() {
    action()
  }

  func forwardConversationActionScroll(_ event: NSEvent) {
    enclosingScrollView?.scrollWheel(with: event)
  }

  private func installGeometryObservers() {
    removeGeometryObservers()
    if let clipView = enclosingScrollView?.contentView {
      clipView.postsBoundsChangedNotifications = true
      clipObserver = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification,
        object: clipView,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.publishRegion() }
      }
    }
    if let window {
      for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
        windowObservers.append(
          NotificationCenter.default.addObserver(
            forName: name,
            object: window,
            queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishRegion() }
          }
        )
      }
    }
  }

  private func publishRegion() {
    interactionSurface?.actionRegionDidChange()
  }

  private func removeGeometryObservers() {
    if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
    for observer in windowObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    clipObserver = nil
    windowObservers = []
  }
}

@MainActor
final class ConversationMessageProbeView: NSTextView, ConversationInteractionRegionProviding {
  private var regionID: String
  private var textAppearance: ConversationTextAppearance
  private weak var interactionSurface: ConversationInteractionSurfaceModel?
  private var clipObserver: NSObjectProtocol?
  private var windowObservers: [NSObjectProtocol] = []

  init(
    id: String,
    text: String,
    appearance: ConversationTextAppearance,
    interactionSurface: ConversationInteractionSurfaceModel?
  ) {
    regionID = id
    textAppearance = appearance
    self.interactionSurface = interactionSurface
    let textStorage = NSTextStorage()
    let layoutManager = NSLayoutManager()
    let textContainer = NSTextContainer(
      containerSize: NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)
    )
    textStorage.addLayoutManager(layoutManager)
    layoutManager.addTextContainer(textContainer)
    super.init(frame: .zero, textContainer: textContainer)
    configure()
    apply(text: text, appearance: appearance)
    interactionSurface?.register(id: id, provider: self)
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func viewDidMoveToWindow() {
    super.viewDidMoveToWindow()
    installGeometryObservers()
    publishRegion()
  }

  override func layout() {
    super.layout()
    publishRegion()
  }

  func update(
    id: String,
    text: String,
    appearance: ConversationTextAppearance,
    interactionSurface: ConversationInteractionSurfaceModel?
  ) {
    let didChangeInteractionMode = self.interactionSurface !== interactionSurface
    if regionID != id || self.interactionSurface !== interactionSurface {
      self.interactionSurface?.unregister(id: regionID, provider: self)
      regionID = id
      self.interactionSurface = interactionSurface
      interactionSurface?.register(id: id, provider: self)
      configureInteractionMode()
      if interactionSurface != nil {
        installGeometryObservers()
      } else {
        removeGeometryObservers()
      }
    }
    if string != text || textAppearance != appearance || didChangeInteractionMode {
      textAppearance = appearance
      apply(text: text, appearance: appearance)
      invalidateIntrinsicContentSize()
    }
    publishRegion()
  }

  func detach() {
    interactionSurface?.unregister(id: regionID, provider: self)
    interactionSurface = nil
    removeGeometryObservers()
  }

  func preferredSize(for width: CGFloat) -> CGSize {
    guard let textContainer, let layoutManager else {
      return CGSize(width: width, height: textAppearance.font.pointSize * 1.35)
    }
    textContainer.containerSize = NSSize(width: width, height: .greatestFiniteMagnitude)
    layoutManager.ensureLayout(for: textContainer)
    let used = layoutManager.usedRect(for: textContainer)
    return CGSize(
      width: min(width, max(1, ceil(used.width))),
      height: max(ceil(used.height), ceil(textAppearance.font.pointSize * 1.35))
    )
  }

  var conversationInteractionRegion: ConversationTextRegion? {
    guard let window, let textContainer, let layoutManager else { return nil }
    layoutManager.ensureLayout(for: textContainer)
    var used = layoutManager.usedRect(for: textContainer)
    guard used.width >= 1, used.height >= 1 else { return nil }
    used.origin.x += textContainerOrigin.x
    used.origin.y += textContainerOrigin.y

    let clippedInView: CGRect
    if let clipView = enclosingScrollView?.contentView {
      let clipBounds = convert(clipView.bounds, from: clipView)
      clippedInView = used.intersection(clipBounds)
    } else {
      clippedInView = used.intersection(bounds)
    }
    guard !clippedInView.isNull, clippedInView.width >= 1, clippedInView.height >= 1 else {
      return nil
    }

    let fullWindowFrame = convert(used, to: nil)
    let clippedWindowFrame = convert(clippedInView, to: nil)
    let fullScreenFrame = window.convertToScreen(fullWindowFrame)
    let clippedScreenFrame = window.convertToScreen(clippedWindowFrame)
    guard
      let visibleFrame = ConversationHitIslandGeometry.visibleFrame(
        contentFrame: fullScreenFrame,
        clipFrame: clippedScreenFrame
      )
    else { return nil }
    return ConversationTextRegion(
      id: regionID,
      text: string,
      appearance: textAppearance,
      visibleFrame: visibleFrame,
      fullFrame: fullScreenFrame
    )
  }

  func forwardConversationScroll(_ event: NSEvent) {
    enclosingScrollView?.scrollWheel(with: event)
  }

  private func configure() {
    drawsBackground = false
    backgroundColor = .clear
    isEditable = false
    isRichText = true
    isHorizontallyResizable = false
    isVerticallyResizable = false
    setContentCompressionResistancePriority(.required, for: .vertical)
    textContainerInset = .zero
    textContainer?.lineFragmentPadding = 0
    textContainer?.widthTracksTextView = true
    textContainer?.heightTracksTextView = false
    configureInteractionMode()
  }

  private func apply(text: String, appearance: ConversationTextAppearance) {
    textStorage?.setAttributedString(
      ConversationLinkDetection.attributedString(text: text, appearance: appearance)
    )
    guard interactionSurface != nil else { return }
    textStorage?.addAttribute(
      .foregroundColor,
      value: NSColor.clear,
      range: NSRange(location: 0, length: textStorage?.length ?? 0)
    )
  }

  private func configureInteractionMode() {
    let usesDetachedPanel = interactionSurface != nil
    isSelectable = !usesDetachedPanel
    insertionPointColor = usesDetachedPanel ? .clear : textAppearance.color
    textColor = usesDetachedPanel ? .clear : textAppearance.color
    linkTextAttributes =
      usesDetachedPanel
      ? [
        .foregroundColor: NSColor.clear,
        .underlineColor: NSColor.clear,
      ]
      : [
        .foregroundColor: ConversationDisplayPalette.linkNSColor,
        .underlineStyle: NSUnderlineStyle.single.rawValue,
      ]
    setAccessibilityHidden(usesDetachedPanel)
  }

  private func installGeometryObservers() {
    removeGeometryObservers()

    if let clipView = enclosingScrollView?.contentView {
      clipView.postsBoundsChangedNotifications = true
      clipObserver = NotificationCenter.default.addObserver(
        forName: NSView.boundsDidChangeNotification,
        object: clipView,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated { self?.publishRegion() }
      }
    }
    if let window {
      for name in [NSWindow.didMoveNotification, NSWindow.didResizeNotification] {
        windowObservers.append(
          NotificationCenter.default.addObserver(
            forName: name,
            object: window,
            queue: .main
          ) { [weak self] _ in
            MainActor.assumeIsolated { self?.publishRegion() }
          }
        )
      }
    }
  }

  private func publishRegion() {
    interactionSurface?.regionDidChange()
  }

  private func removeGeometryObservers() {
    if let clipObserver { NotificationCenter.default.removeObserver(clipObserver) }
    for observer in windowObservers {
      NotificationCenter.default.removeObserver(observer)
    }
    clipObserver = nil
    windowObservers = []
  }
}

@MainActor
private final class ConversationInteractiveTextView: NSTextView {
  var onScrollWheel: ((NSEvent) -> Void)?

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func scrollWheel(with event: NSEvent) {
    onScrollWheel?(event)
  }
}

@MainActor
private final class ConversationInteractionPanelContentView: NSView {
  private let textView = ConversationInteractiveTextView(frame: .zero)

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    wantsLayer = true
    layer?.backgroundColor = NSColor.clear.cgColor
    addSubview(textView)
    textView.drawsBackground = false
    textView.backgroundColor = .clear
    textView.isEditable = false
    textView.isSelectable = true
    textView.isRichText = true
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = false
    textView.textContainerInset = .zero
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = true
    textView.linkTextAttributes = [
      .foregroundColor: ConversationDisplayPalette.linkNSColor,
      .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  func update(region: ConversationTextRegion, onScrollWheel: @escaping (NSEvent) -> Void) {
    let readability = ConversationReadabilityStyle.currentAppKit
    textView.linkTextAttributes = [
      .foregroundColor: readability.nsColor(for: .link),
      .underlineColor: readability.nsColor(for: .link),
      .underlineStyle: NSUnderlineStyle.single.rawValue,
    ]
    textView.textStorage?.setAttributedString(
      ConversationLinkDetection.attributedString(
        text: region.text,
        appearance: region.appearance
      )
    )
    textView.onScrollWheel = onScrollWheel
    let origin = CGPoint(
      x: region.fullFrame.minX - region.visibleFrame.minX,
      y: region.fullFrame.minY - region.visibleFrame.minY
    )
    textView.frame = CGRect(origin: origin, size: region.fullFrame.size)
    textView.setAccessibilityLabel(region.text)
  }
}

@MainActor
private final class ConversationInteractionPanel: NSPanel {
  let regionContentView = ConversationInteractionPanelContentView(frame: .zero)

  init(frame: CGRect) {
    super.init(
      contentRect: frame,
      styleMask: [.borderless],
      backing: .buffered,
      defer: false
    )
    isOpaque = false
    backgroundColor = .clear
    hasShadow = false
    isFloatingPanel = false
    hidesOnDeactivate = false
    level = .normal
    collectionBehavior = [.ignoresCycle]
    isReleasedWhenClosed = false
    isExcludedFromWindowsMenu = true
    contentView = regionContentView
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

@MainActor
final class ConversationActionButton: NSButton {
  var actionHandler: (() -> Void)?
  var scrollHandler: ((NSEvent) -> Void)?
  private var trackingAreaReference: NSTrackingArea?
  private var visualState = ConversationActionVisualState.idle
  private var reduceMotion = false
  private var isHovered = false
  private var isPressedVisual = false

  override init(frame frameRect: NSRect) {
    super.init(frame: frameRect)
    title = ""
    isBordered = false
    isTransparent = false
    imagePosition = .imageOnly
    imageScaling = .scaleProportionallyDown
    setButtonType(.momentaryPushIn)
    wantsLayer = true
    layer?.cornerRadius = 6
    target = self
    action = #selector(performAction)
    refreshVisuals()
  }

  @available(*, unavailable)
  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
  override var needsPanelToBecomeKey: Bool { false }
  override var acceptsFirstResponder: Bool { true }

  override func updateTrackingAreas() {
    if let trackingAreaReference {
      removeTrackingArea(trackingAreaReference)
    }
    let trackingArea = NSTrackingArea(
      rect: bounds,
      options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
      owner: self,
      userInfo: nil
    )
    addTrackingArea(trackingArea)
    trackingAreaReference = trackingArea
    super.updateTrackingAreas()
  }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .pointingHand)
  }

  override func mouseEntered(with event: NSEvent) {
    isHovered = true
    refreshVisuals()
  }

  override func mouseExited(with event: NSEvent) {
    isHovered = false
    refreshVisuals()
  }

  override func mouseDown(with event: NSEvent) {
    isPressedVisual = true
    refreshVisuals()
    defer {
      isPressedVisual = false
      refreshVisuals()
    }
    super.mouseDown(with: event)
  }

  override func keyDown(with event: NSEvent) {
    switch event.charactersIgnoringModifiers {
    case " ", "\r", "\n":
      performClick(nil)
    default:
      super.keyDown(with: event)
    }
  }

  override func accessibilityPerformPress() -> Bool {
    performClick(nil)
    return true
  }

  override func scrollWheel(with event: NSEvent) {
    scrollHandler?(event)
  }

  func update(visualState: ConversationActionVisualState, reduceMotion: Bool) {
    self.visualState = visualState
    self.reduceMotion = reduceMotion
    refreshVisuals()
  }

  @objc private func performAction() {
    actionHandler?()
  }

  private func refreshVisuals() {
    let readability = ConversationReadabilityStyle.currentAppKit
    image = NSImage(
      systemSymbolName: visualState.symbolName,
      accessibilityDescription: nil
    )?.withSymbolConfiguration(
      NSImage.SymbolConfiguration(pointSize: 12, weight: .regular)
    )
    contentTintColor = visualState.nsColor
    layer?.shadowColor = NSColor.black.cgColor
    layer?.shadowOpacity = Float(readability.tightShadow.opacity)
    layer?.shadowRadius = readability.tightShadow.radius
    layer?.shadowOffset = CGSize(
      width: readability.tightShadow.x,
      height: readability.tightShadow.y
    )

    let scale: CGFloat
    if reduceMotion {
      scale = 1
    } else if isPressedVisual {
      scale = 0.92
    } else {
      scale = isHovered ? 1.04 : 1
    }
    let highlightAlpha: CGFloat = isHovered || isPressedVisual ? 0.10 : 0

    CATransaction.begin()
    CATransaction.setDisableActions(reduceMotion)
    if !reduceMotion {
      CATransaction.setAnimationDuration(isPressedVisual ? 0.08 : 0.12)
      CATransaction.setAnimationTimingFunction(
        CAMediaTimingFunction(name: .easeOut)
      )
    }
    layer?.backgroundColor = visualState.nsColor.withAlphaComponent(highlightAlpha).cgColor
    layer?.setAffineTransform(CGAffineTransform(scaleX: scale, y: scale))
    CATransaction.commit()
  }
}

@MainActor
final class ConversationActionPanel: NSPanel {
  let button = ConversationActionButton(frame: .zero)

  init(frame: CGRect) {
    super.init(
      contentRect: frame,
      styleMask: [.borderless, .nonactivatingPanel],
      backing: .buffered,
      defer: false
    )
    isOpaque = false
    backgroundColor = .clear
    ignoresMouseEvents = false
    hasShadow = false
    isFloatingPanel = false
    hidesOnDeactivate = false
    level = .normal
    collectionBehavior = [.ignoresCycle]
    isReleasedWhenClosed = false
    isExcludedFromWindowsMenu = true
    becomesKeyOnlyIfNeeded = true
    acceptsMouseMovedEvents = true
    contentView = button
  }

  override var canBecomeKey: Bool { true }
  override var canBecomeMain: Bool { false }
}

enum ConversationInteractionWindowPresentation: Equatable, Sendable {
  case hidden
  case aboveParent(windowNumber: Int)
}

enum ConversationInteractionWindowLifecycle {
  static func presentation(
    isEnabled: Bool,
    isWorkspaceVisible: Bool,
    isParentVisible: Bool,
    parentWindowNumber: Int
  ) -> ConversationInteractionWindowPresentation {
    guard isEnabled,
      isWorkspaceVisible,
      isParentVisible,
      parentWindowNumber > 0
    else { return .hidden }
    return .aboveParent(windowNumber: parentWindowNumber)
  }
}

@MainActor
final class ConversationInteractionPanelController {
  private weak var parentWindow: NSWindow?
  private let surface: ConversationInteractionSurfaceModel
  private var panels: [String: ConversationInteractionPanel] = [:]
  private var actionPanels: [String: ConversationActionPanel] = [:]
  private var latestRegions: [ConversationTextRegion] = []
  private var latestActionRegions: [ConversationActionRegion] = []
  private var isEnabled = true
  private var isWorkspaceVisible = false
  private var alphaValue: CGFloat = 1
  private var displayOptionsObserver: ConversationDisplayObservationToken?

  init(parentWindow: NSWindow, surface: ConversationInteractionSurfaceModel) {
    self.parentWindow = parentWindow
    self.surface = surface
    surface.onRegionsChanged = { [weak self] regions in
      self?.apply(regions)
    }
    surface.onActionRegionsChanged = { [weak self] regions in
      self?.applyActionRegions(regions)
    }
    displayOptionsObserver = ConversationDisplayObservationToken(
      NSWorkspace.shared.notificationCenter.addObserver(
        forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification,
        object: nil,
        queue: .main
      ) { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.apply(self.latestRegions)
          self.applyActionRegions(self.latestActionRegions)
        }
      })
  }

  deinit {
    if let displayOptionsObserver {
      NSWorkspace.shared.notificationCenter.removeObserver(displayOptionsObserver.value)
    }
  }

  func setEnabled(_ enabled: Bool) {
    isEnabled = enabled
    apply(latestRegions)
    applyActionRegions(latestActionRegions)
  }

  func setWorkspaceVisible(_ visible: Bool) {
    isWorkspaceVisible = visible
    apply(latestRegions)
    applyActionRegions(latestActionRegions)
  }

  func setAlpha(_ alpha: CGFloat, animated: Bool = false) {
    alphaValue = alpha
    for panel in panels.values {
      if animated {
        panel.animator().alphaValue = alpha
      } else {
        panel.alphaValue = alpha
      }
    }
    for panel in actionPanels.values {
      if animated {
        panel.animator().alphaValue = alpha
      } else {
        panel.alphaValue = alpha
      }
    }
  }

  func removeAll() {
    for panel in panels.values {
      panel.orderOut(nil)
    }
    panels = [:]
    for panel in actionPanels.values {
      panel.orderOut(nil)
    }
    actionPanels = [:]
  }

  private func apply(_ regions: [ConversationTextRegion]) {
    latestRegions = regions
    let activeIDs = Set(regions.map(\.id))
    let staleIDs = panels.keys.filter { !activeIDs.contains($0) }
    for id in staleIDs {
      guard let panel = panels[id] else { continue }
      panel.orderOut(nil)
      panels[id] = nil
    }
    for region in regions {
      let panel: ConversationInteractionPanel
      if let current = panels[region.id] {
        panel = current
      } else {
        panel = ConversationInteractionPanel(frame: region.visibleFrame)
        panels[region.id] = panel
      }
      panel.setFrame(region.visibleFrame, display: true)
      panel.regionContentView.frame = CGRect(origin: .zero, size: region.visibleFrame.size)
      panel.regionContentView.update(region: region) { [weak surface] event in
        surface?.forwardScroll(event, regionID: region.id)
      }
      present(panel)
    }
  }

  private func applyActionRegions(_ regions: [ConversationActionRegion]) {
    latestActionRegions = regions
    let activeIDs = Set(regions.map(\.id))
    let staleIDs = actionPanels.keys.filter { !activeIDs.contains($0) }
    for id in staleIDs {
      guard let panel = actionPanels[id] else { continue }
      panel.orderOut(nil)
      actionPanels[id] = nil
    }
    for region in regions {
      let panel: ConversationActionPanel
      if let current = actionPanels[region.id] {
        panel = current
      } else {
        panel = ConversationActionPanel(frame: region.visibleFrame)
        actionPanels[region.id] = panel
      }
      panel.setFrame(region.visibleFrame, display: true)
      panel.button.frame = CGRect(origin: .zero, size: region.visibleFrame.size)
      panel.button.setAccessibilityLabel(region.accessibilityLabel)
      panel.button.setAccessibilityHelp(region.accessibilityHelp)
      panel.button.setAccessibilityValue(
        region.visualState.accessibilityValue(
          copy: RabbisirCopy(language: RabbisirLocalization.shared.language)
        )
      )
      panel.button.setAccessibilityIdentifier(region.accessibilityIdentifier)
      panel.button.update(
        visualState: region.visualState,
        reduceMotion: region.reduceMotion
      )
      panel.button.actionHandler = { [weak surface] in
        surface?.performAction(regionID: region.id)
      }
      panel.button.scrollHandler = { [weak surface] event in
        surface?.forwardActionScroll(event, regionID: region.id)
      }
      present(panel)
    }
  }

  private func present(_ panel: NSWindow) {
    guard let parentWindow else {
      panel.orderOut(nil)
      return
    }
    let presentation = ConversationInteractionWindowLifecycle.presentation(
      isEnabled: isEnabled,
      isWorkspaceVisible: isWorkspaceVisible,
      isParentVisible: parentWindow.isVisible,
      parentWindowNumber: parentWindow.windowNumber
    )
    switch presentation {
    case .hidden:
      panel.orderOut(nil)
    case .aboveParent(let windowNumber):
      panel.level = parentWindow.level
      panel.collectionBehavior = parentWindow.collectionBehavior.union(.ignoresCycle)
      panel.alphaValue = alphaValue
      panel.order(.above, relativeTo: windowNumber)
    }
  }
}
