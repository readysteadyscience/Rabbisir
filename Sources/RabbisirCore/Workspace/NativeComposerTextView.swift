import AppKit
import SwiftUI

enum ComposerSubmitGesture: String, Equatable, Sendable {
  case enter
  case accelerated
  case button
}

enum ComposerTextKeyPolicy {
  static func gesture(
    keyCode: UInt16,
    modifiers: NSEvent.ModifierFlags,
    isRepeat: Bool
  ) -> ComposerSubmitGesture? {
    guard !isRepeat, keyCode == 36 || keyCode == 76 else { return nil }
    let active = modifiers.intersection(.deviceIndependentFlagsMask)
    guard !active.contains(.shift) else { return nil }
    return active.isDisjoint(with: [.command, .control]) ? .enter : .accelerated
  }
}

enum ComposerTextSelectionPolicy {
  static func clamped(_ selection: NSRange, utf16Length: Int) -> NSRange {
    let length = max(0, utf16Length)
    guard selection.location != NSNotFound else {
      return NSRange(location: length, length: 0)
    }
    let location = min(selection.location, length)
    let availableLength = length - location
    return NSRange(location: location, length: min(selection.length, availableLength))
  }
}

enum ComposerTextHitSurfaceStyle {
  /// Keeps transparent editor pixels in the AppKit hit region without adding a visible fill.
  static let backgroundColor = NSColor(deviceWhite: 1, alpha: 1 / 255)

  @MainActor
  static func install(in scrollView: NSScrollView, editor: NSView) {
    scrollView.drawsBackground = false
    scrollView.backgroundColor = .clear
    scrollView.contentView.drawsBackground = false
    scrollView.contentView.backgroundColor = .clear
    editor.wantsLayer = true
    editor.layer?.backgroundColor = backgroundColor.cgColor
  }
}

enum ComposerPlaceholderStyle {
  static let foregroundColor = NSColor.placeholderTextColor
}

final class ComposerTextView: NSTextView {
  var placeholder = "" {
    didSet { needsDisplay = true }
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard string.isEmpty, !placeholder.isEmpty else { return }
    let attributes: [NSAttributedString.Key: Any] = [
      .font: font ?? NSFont.systemFont(ofSize: NSFont.systemFontSize),
      .foregroundColor: ComposerPlaceholderStyle.foregroundColor,
    ]
    placeholder.draw(
      at: NSPoint(x: textContainerInset.width, y: textContainerInset.height),
      withAttributes: attributes
    )
  }

  override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

  override func resetCursorRects() {
    addCursorRect(bounds, cursor: .iBeam)
  }

  override func mouseDown(with event: NSEvent) {
    NSApp.activate(ignoringOtherApps: true)
    window?.makeKeyAndOrderFront(nil)
    super.mouseDown(with: event)
    if window?.firstResponder !== self {
      window?.makeFirstResponder(self)
    }
    clampSelectionToDocument()
    inputContext?.activate()
  }

  override func becomeFirstResponder() -> Bool {
    let accepted = super.becomeFirstResponder()
    if accepted {
      inputContext?.activate()
    }
    return accepted
  }

  func clampSelectionToDocument() {
    let selection = ComposerTextSelectionPolicy.clamped(
      selectedRange(),
      utf16Length: string.utf16.count
    )
    if selection != selectedRange() {
      setSelectedRange(selection)
    }
  }
}

struct NativeComposerTextView: NSViewRepresentable {
  @Binding var text: String
  let focusRequest: Int
  let placeholder: String
  let accessibilityLabel: String
  let onHeightChange: (CGFloat) -> Void
  let onSubmit: (ComposerSubmitGesture) -> Void

  func makeCoordinator() -> Coordinator {
    Coordinator(parent: self)
  }

  func makeNSView(context: Context) -> NSScrollView {
    let scrollView = ComposerTextView.scrollableTextView()
    scrollView.borderType = .noBorder
    scrollView.hasHorizontalScroller = false
    scrollView.hasVerticalScroller = true
    scrollView.autohidesScrollers = true
    scrollView.scrollerStyle = .overlay

    guard let textView = scrollView.documentView as? ComposerTextView else {
      preconditionFailure("NSTextView.scrollableTextView() did not preserve the requested subclass")
    }
    ComposerTextHitSurfaceStyle.install(in: scrollView, editor: textView)
    textView.frame = scrollView.contentView.bounds
    textView.autoresizingMask = [.width, .height]
    textView.drawsBackground = false
    textView.isEditable = true
    textView.isSelectable = true
    textView.isRichText = false
    textView.importsGraphics = false
    textView.allowsUndo = true
    textView.isHorizontallyResizable = false
    textView.isVerticallyResizable = true
    textView.minSize = NSSize(width: 0, height: 0)
    textView.maxSize = NSSize(
      width: CGFloat.greatestFiniteMagnitude,
      height: CGFloat.greatestFiniteMagnitude
    )
    textView.textContainer?.widthTracksTextView = true
    textView.textContainer?.heightTracksTextView = false
    textView.textContainer?.containerSize = NSSize(
      width: scrollView.contentSize.width,
      height: .greatestFiniteMagnitude
    )
    textView.textContainer?.lineFragmentPadding = 0
    textView.textContainerInset = NSSize(width: 0, height: 1)
    textView.font = NSFont.systemFont(ofSize: NSFont.systemFontSize)
    textView.textColor = .labelColor
    textView.insertionPointColor = .labelColor
    textView.string = text
    textView.placeholder = placeholder
    textView.delegate = context.coordinator
    textView.setAccessibilityLabel(accessibilityLabel)
    context.coordinator.textView = textView
    context.coordinator.lastFocusRequest = focusRequest
    context.coordinator.updateDocumentGeometry(in: scrollView, followInsertionPoint: true)
    return scrollView
  }

  func updateNSView(_ scrollView: NSScrollView, context: Context) {
    context.coordinator.parent = self
    guard let textView = scrollView.documentView as? ComposerTextView else { return }
    if textView.string != text {
      textView.string = text
      textView.clampSelectionToDocument()
      textView.needsDisplay = true
    }
    textView.textColor = .labelColor
    textView.insertionPointColor = .labelColor
    textView.placeholder = placeholder
    textView.setAccessibilityLabel(accessibilityLabel)
    textView.needsDisplay = true
    context.coordinator.updateDocumentGeometry(in: scrollView, followInsertionPoint: false)
    guard context.coordinator.lastFocusRequest != focusRequest else { return }
    context.coordinator.lastFocusRequest = focusRequest
    DispatchQueue.main.async {
      textView.window?.makeFirstResponder(textView)
    }
  }

  @MainActor
  final class Coordinator: NSObject, NSTextViewDelegate {
    var parent: NativeComposerTextView
    weak var textView: NSTextView?
    var lastFocusRequest = 0

    init(parent: NativeComposerTextView) {
      self.parent = parent
    }

    func textDidChange(_ notification: Notification) {
      guard let textView = notification.object as? NSTextView else { return }
      parent.text = textView.string
      textView.needsDisplay = true
      guard let scrollView = textView.enclosingScrollView else { return }
      updateDocumentGeometry(in: scrollView, followInsertionPoint: true)
    }

    func updateDocumentGeometry(
      in scrollView: NSScrollView,
      followInsertionPoint: Bool
    ) {
      guard let textView = scrollView.documentView as? NSTextView,
        let layoutManager = textView.layoutManager,
        let textContainer = textView.textContainer
      else { return }
      layoutManager.ensureLayout(for: textContainer)
      let measuredHeight = ceil(
        layoutManager.usedRect(for: textContainer).height
          + textView.textContainerInset.height * 2
      )
      let viewportHeight = scrollView.contentSize.height
      let documentHeight = max(viewportHeight, measuredHeight)
      if abs(textView.frame.height - documentHeight) > 0.5 {
        textView.setFrameSize(NSSize(width: scrollView.contentSize.width, height: documentHeight))
      }
      parent.onHeightChange(measuredHeight)
      guard followInsertionPoint else { return }
      let insertion = NSRange(location: textView.string.utf16.count, length: 0)
      textView.scrollRangeToVisible(insertion)
    }

    func textView(_ textView: NSTextView, doCommandBy commandSelector: Selector) -> Bool {
      guard commandSelector == #selector(NSResponder.insertNewline(_:)),
        let event = NSApp.currentEvent,
        let gesture = ComposerTextKeyPolicy.gesture(
          keyCode: event.keyCode,
          modifiers: event.modifierFlags,
          isRepeat: event.isARepeat
        )
      else {
        return false
      }
      parent.onSubmit(gesture)
      return true
    }
  }
}
