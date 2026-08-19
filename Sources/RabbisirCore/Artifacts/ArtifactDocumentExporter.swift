import AppKit
import CoreText
import Foundation

/// Writes standard document formats using public macOS text and printing APIs.
@MainActor
enum ArtifactDocumentExporter {
  static func write(
    markdown: String,
    format: ArtifactExportFormat,
    to url: URL
  ) throws {
    switch format {
    case .markdown:
      try markdown.write(to: url, atomically: true, encoding: .utf8)
    case .plainText:
      try ArtifactDocumentProjection.plainText(from: markdown)
        .write(to: url, atomically: true, encoding: .utf8)
    case .wordLegacy:
      try writeAttributed(markdown: markdown, type: .docFormat, to: url)
    case .wordOpenXML:
      try writeAttributed(markdown: markdown, type: .officeOpenXML, to: url)
    case .pdf:
      try writePDF(markdown: markdown, to: url)
    }
  }

  private static func attributedDocument(markdown: String) -> NSAttributedString {
    ArtifactRichDocumentRenderer.attributedDocument(markdown: markdown)
  }

  private static func writeAttributed(
    markdown: String,
    type: NSAttributedString.DocumentType,
    to url: URL
  ) throws {
    let document = attributedDocument(markdown: markdown)
    let data = try document.data(
      from: NSRange(location: 0, length: document.length),
      documentAttributes: [.documentType: type]
    )
    try data.write(to: url, options: .atomic)
  }

  private static func writePDF(markdown: String, to url: URL) throws {
    let document = attributedDocument(markdown: markdown)
    var mediaBox = CGRect(x: 0, y: 0, width: 595, height: 842)
    let textRect = mediaBox.insetBy(dx: 40, dy: 54)
    let data = NSMutableData()
    guard let consumer = CGDataConsumer(data: data as CFMutableData),
      let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)
    else {
      throw CocoaError(.fileWriteUnknown)
    }

    let framesetter = CTFramesetterCreateWithAttributedString(document)
    var location = 0
    repeat {
      context.beginPDFPage(nil)
      context.setFillColor(NSColor.white.cgColor)
      context.fill(mediaBox)
      let path = CGPath(rect: textRect, transform: nil)
      let frame = CTFramesetterCreateFrame(
        framesetter,
        CFRange(location: location, length: 0),
        path,
        nil
      )
      CTFrameDraw(frame, context)
      let visibleRange = CTFrameGetVisibleStringRange(frame)
      context.endPDFPage()
      guard visibleRange.length > 0 || document.length == 0 else {
        throw CocoaError(.fileWriteUnknown)
      }
      location += visibleRange.length
    } while location < document.length
    context.closePDF()

    try (data as Data).write(to: url, options: .atomic)
  }
}
