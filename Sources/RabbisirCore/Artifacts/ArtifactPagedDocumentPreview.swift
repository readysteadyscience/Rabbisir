import AppKit
import CoreText
import SwiftUI

/// A4 preview variants that render the same authoritative document source.
enum ArtifactPagedPreviewStyle: Sendable {
  case document
  case pdf

  func title(copy: RabbisirArtifactCopy) -> String {
    switch self {
    case .document: "A4 · \(copy.documentPreview)"
    case .pdf: "A4 · \(copy.pdfPreview)"
    }
  }

  func accessibilityLabel(copy: RabbisirArtifactCopy) -> String {
    switch self {
    case .document: copy.documentPreview
    case .pdf: copy.pdfPreview
    }
  }
}

/// Read-only native pagination used by both the document and PDF projections.
@MainActor
struct ArtifactPagedDocumentPreview: View {
  let markdown: String
  let style: ArtifactPagedPreviewStyle
  @Environment(\.rabbisirCopy) private var copy

  var body: some View {
    GeometryReader { proxy in
      let width = ArtifactPageMetrics.resolvedWidth(available: proxy.size.width)
      let pageCount = ArtifactDocumentPagination.pageCount(markdown: markdown)
      let height = ArtifactDocumentPagination.previewHeight(
        pageCount: pageCount,
        previewWidth: width
      )

      ScrollView([.horizontal, .vertical], showsIndicators: false) {
        VStack(spacing: 10) {
          Text(style.title(copy: copy.artifacts))
            .font(.caption.weight(.semibold))
            .foregroundStyle(NativePanelContentPalette.secondary)

          ArtifactPagedCanvas(markdown: markdown)
            .frame(width: width, height: height)
            .accessibilityLabel(style.accessibilityLabel(copy: copy.artifacts))
        }
        .frame(minWidth: proxy.size.width, minHeight: proxy.size.height, alignment: .top)
        .padding(16)
      }
      .scrollIndicators(.hidden)
      .background(Color.black.opacity(0.035))
    }
  }
}

@MainActor
enum ArtifactDocumentPagination {
  static let pageSize = CGSize(
    width: ArtifactPageMetrics.maximumWidth,
    height: ArtifactPageMetrics.maximumWidth * ArtifactPageMetrics.aspectRatio
  )
  static let pageGap: CGFloat = 24

  static func pageCount(markdown: String) -> Int {
    pageRanges(for: ArtifactRichDocumentRenderer.attributedDocument(markdown: markdown)).count
  }

  static func previewHeight(pageCount: Int, previewWidth: CGFloat) -> CGFloat {
    let resolvedCount = max(pageCount, 1)
    let scale = previewWidth / pageSize.width
    return
      (CGFloat(resolvedCount) * pageSize.height
      + CGFloat(resolvedCount - 1) * pageGap) * scale
  }

  static func pageRanges(for document: NSAttributedString) -> [CFRange] {
    guard document.length > 0 else { return [CFRange(location: 0, length: 0)] }
    let contentRect = CGRect(
      x: 0,
      y: 0,
      width: pageSize.width - ArtifactPageMetrics.horizontalPadding * 2,
      height: pageSize.height - ArtifactPageMetrics.verticalPadding * 2
    )
    let path = CGPath(rect: contentRect, transform: nil)
    let framesetter = CTFramesetterCreateWithAttributedString(document)
    var location = 0
    var pages: [CFRange] = []

    while location < document.length {
      let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: location, length: 0),
        path,
        nil
      )
      let visible = CTFrameGetVisibleStringRange(frame)
      guard visible.length > 0 else { break }
      pages.append(visible)
      location += visible.length
    }
    return pages.isEmpty ? [CFRange(location: 0, length: 0)] : pages
  }
}

private struct ArtifactPagedCanvas: NSViewRepresentable {
  let markdown: String

  func makeNSView(context: Context) -> ArtifactPagedCanvasView {
    ArtifactPagedCanvasView()
  }

  func updateNSView(_ view: ArtifactPagedCanvasView, context: Context) {
    view.update(markdown: markdown)
  }
}

private final class ArtifactPagedCanvasView: NSView {
  private var document = NSAttributedString()
  private var pageRanges: [CFRange] = []

  override var isFlipped: Bool { false }

  func update(markdown: String) {
    document = ArtifactRichDocumentRenderer.attributedDocument(markdown: markdown)
    pageRanges = ArtifactDocumentPagination.pageRanges(for: document)
    needsDisplay = true
  }

  override func draw(_ dirtyRect: NSRect) {
    super.draw(dirtyRect)
    guard let context = NSGraphicsContext.current?.cgContext else { return }
    let pageSize = ArtifactDocumentPagination.pageSize
    let scale = bounds.width / pageSize.width
    guard scale > 0 else { return }

    context.saveGState()
    context.scaleBy(x: scale, y: scale)
    let unscaledHeight = bounds.height / scale
    let framesetter = CTFramesetterCreateWithAttributedString(document)

    for (index, range) in pageRanges.enumerated() {
      let pageY =
        unscaledHeight - pageSize.height
        - CGFloat(index) * (pageSize.height + ArtifactDocumentPagination.pageGap)
      let pageRect = CGRect(origin: CGPoint(x: 0, y: pageY), size: pageSize)

      context.saveGState()
      context.setShadow(
        offset: CGSize(width: 0, height: -2), blur: 7,
        color: NSColor.black.withAlphaComponent(0.2).cgColor)
      context.setFillColor(NSColor.white.cgColor)
      context.fill(pageRect)
      context.restoreGState()

      let textRect = pageRect.insetBy(
        dx: ArtifactPageMetrics.horizontalPadding,
        dy: ArtifactPageMetrics.verticalPadding
      )
      let path = CGPath(rect: textRect, transform: nil)
      let frame = CTFramesetterCreateFrame(framesetter, range, path, nil)
      CTFrameDraw(frame, context)

      let pageNumber = NSAttributedString(
        string: "\(index + 1)",
        attributes: [
          .font: NSFont.systemFont(ofSize: 10),
          .foregroundColor: NSColor.secondaryLabelColor,
        ]
      )
      let numberSize = pageNumber.size()
      pageNumber.draw(
        at: CGPoint(
          x: pageRect.midX - numberSize.width / 2,
          y: pageRect.minY + 14
        ))
    }
    context.restoreGState()
  }
}
