import AppKit
import CoreGraphics
import Foundation
import Testing

@testable import RabbisirCore

@Suite("Artifact workbench projections")
@MainActor
struct ArtifactWorkbenchProjectionTests {
  @Test("The native workbench preserves every original Web projection")
  func originalProjectionSet() {
    #expect(ArtifactWorkbenchMode.allCases == [.editor, .plain, .markdown, .document, .pdf])
    let copy = RabbisirCopy(language: .chinese).artifacts
    #expect(
      ArtifactWorkbenchMode.allCases.map { $0.title(copy: copy) } == [
        "编辑",
        "纯文本",
        "Markdown 版式",
        "文稿",
        "PDF 版式",
      ])
    #expect(
      ArtifactExportFormat.allCases.map { $0.title(copy: copy) } == [
        "Markdown (.md)",
        "纯文本 (.txt)",
        "文稿 (.doc)",
        "文稿 (.docx)",
        "PDF (.pdf)",
      ])
    #expect(ArtifactWorkbenchMode.allCases.filter(\.allowsEditing) == [.editor])
  }

  @Test("Plain text export removes Markdown presentation syntax")
  func plainTextExport() {
    let markdown = "# 标题\n\n**正文**与[链接](https://example.com)"
    let plain = ArtifactDocumentProjection.copyContent(
      for: .plain,
      markdown: markdown
    )

    #expect(plain.contains("标题"))
    #expect(plain.contains("正文"))
    #expect(plain.contains("链接"))
    #expect(!plain.contains("**"))
  }

  @Test("Layout projections keep the authoritative Markdown source")
  func layoutExportsKeepMarkdown() {
    let markdown = "# 标题\n\n正文"

    #expect(ArtifactDocumentProjection.copyContent(for: .editor, markdown: markdown) == markdown)
    #expect(ArtifactDocumentProjection.copyContent(for: .markdown, markdown: markdown) == markdown)
    #expect(ArtifactDocumentProjection.copyContent(for: .document, markdown: markdown) == markdown)
    #expect(ArtifactDocumentProjection.copyContent(for: .pdf, markdown: markdown) == markdown)
  }

  @Test("A4 layout adapts to the details panel without exceeding original size")
  func adaptiveA4Width() {
    #expect(ArtifactPageMetrics.resolvedWidth(available: 250) == ArtifactPageMetrics.minimumWidth)
    #expect(ArtifactPageMetrics.resolvedWidth(available: 650) == 618)
    #expect(ArtifactPageMetrics.resolvedWidth(available: 1_200) == ArtifactPageMetrics.maximumWidth)
  }

  @Test("The document editor exports real Word and PDF containers")
  func standardDocumentExports() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let markdown = "# Rabbisir 文稿\n\n这是导出验证，并包含 **加粗样式**。"
    let doc = directory.appendingPathComponent("report.doc")
    let docx = directory.appendingPathComponent("report.docx")
    let pdf = directory.appendingPathComponent("report.pdf")
    try ArtifactDocumentExporter.write(markdown: markdown, format: .wordLegacy, to: doc)
    try ArtifactDocumentExporter.write(markdown: markdown, format: .wordOpenXML, to: docx)
    try ArtifactDocumentExporter.write(markdown: markdown, format: .pdf, to: pdf)

    #expect((try Data(contentsOf: doc)).count > 0)
    #expect((try Data(contentsOf: docx)).starts(with: [0x50, 0x4b]))
    #expect((try Data(contentsOf: pdf)).starts(with: Array("%PDF".utf8)))
    let importedDoc = try NSAttributedString(url: doc, options: [:], documentAttributes: nil)
    let importedDocx = try NSAttributedString(url: docx, options: [:], documentAttributes: nil)
    #expect(importedDoc.string.contains("Rabbisir 文稿"))
    #expect(importedDoc.string.contains("这是导出验证"))
    #expect(importedDocx.string.contains("Rabbisir 文稿"))
    #expect(importedDocx.string.contains("这是导出验证"))
    let headingFont = try #require(
      importedDocx.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)
    #expect(headingFont.pointSize >= 20)
    let boldRange = (importedDocx.string as NSString).range(of: "加粗样式")
    let boldFont = try #require(
      importedDocx.attribute(.font, at: boldRange.location, effectiveRange: nil) as? NSFont)
    #expect(NSFontManager.shared.traits(of: boldFont).contains(.boldFontMask))
  }

  @Test("Every export format reads the same edited Markdown source")
  func oneSourceFeedsEveryExport() throws {
    let directory = FileManager.default.temporaryDirectory
      .appendingPathComponent(UUID().uuidString, isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let edited = "# 最新标题\n\n这是同一份已编辑正文。"
    for format in ArtifactExportFormat.allCases {
      let url = directory.appendingPathComponent("report.\(format.pathExtension)")
      try ArtifactDocumentExporter.write(markdown: edited, format: format, to: url)
      #expect(FileManager.default.fileExists(atPath: url.path))
      #expect((try Data(contentsOf: url)).isEmpty == false)
    }
    #expect(
      try String(contentsOf: directory.appendingPathComponent("report.md"), encoding: .utf8)
        == edited)
    #expect(
      try String(contentsOf: directory.appendingPathComponent("report.txt"), encoding: .utf8)
        .contains("同一份已编辑正文"))
  }

  @Test("Long PDF exports paginate on A4 paper")
  func longPDFPaginates() throws {
    let url = FileManager.default.temporaryDirectory
      .appendingPathComponent("\(UUID().uuidString).pdf")
    defer { try? FileManager.default.removeItem(at: url) }
    let paragraphs = (1...180).map { "## 第 \($0) 段\n\n这是用于验证 A4 分页的正文内容。" }
    try ArtifactDocumentExporter.write(
      markdown: paragraphs.joined(separator: "\n\n"),
      format: .pdf,
      to: url
    )

    let document = CGPDFDocument(url as CFURL)
    #expect(document != nil)
    #expect((document?.numberOfPages ?? 0) > 1)
    #expect(
      ArtifactDocumentPagination.pageCount(markdown: paragraphs.joined(separator: "\n\n")) > 1)
  }
}
