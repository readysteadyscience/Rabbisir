import Foundation

/// User-visible projections provided by the original Rabbisir Markdown workbench.
enum ArtifactWorkbenchMode: String, CaseIterable, Identifiable, Sendable {
  case editor
  case plain
  case markdown
  case document
  case pdf

  var id: Self { self }

  var allowsEditing: Bool { self == .editor }

  func title(copy: RabbisirArtifactCopy) -> String {
    switch self {
    case .editor: copy.editMode
    case .plain: copy.plainMode
    case .markdown: copy.markdownMode
    case .document: copy.documentMode
    case .pdf: copy.pdfMode
    }
  }
}

/// Standard files the native document editor can generate without automating another app.
enum ArtifactExportFormat: String, CaseIterable, Identifiable, Sendable {
  case markdown
  case plainText
  case wordLegacy
  case wordOpenXML
  case pdf

  var id: Self { self }

  func title(copy: RabbisirArtifactCopy) -> String {
    switch self {
    case .markdown: "Markdown (.md)"
    case .plainText: "\(copy.plainMode) (.txt)"
    case .wordLegacy: "\(copy.documentMode) (.doc)"
    case .wordOpenXML: "\(copy.documentMode) (.docx)"
    case .pdf: "PDF (.pdf)"
    }
  }

  var pathExtension: String {
    switch self {
    case .markdown: "md"
    case .plainText: "txt"
    case .wordLegacy: "doc"
    case .wordOpenXML: "docx"
    case .pdf: "pdf"
    }
  }
}

/// Pure transformations shared by the native projections and their tests.
enum ArtifactDocumentProjection {
  static func plainText(from markdown: String) -> String {
    guard
      let attributed = try? AttributedString(
        markdown: markdown,
        options: .init(interpretedSyntax: .full)
      )
    else {
      return markdown
    }
    return String(attributed.characters)
      .replacingOccurrences(of: "\n\n\n", with: "\n\n")
      .trimmingCharacters(in: .whitespacesAndNewlines)
  }

  static func copyContent(
    for mode: ArtifactWorkbenchMode,
    markdown: String
  ) -> String {
    mode == .plain ? plainText(from: markdown) : markdown
  }
}

/// Stable page sizing inherited from the original A4 portrait projections.
enum ArtifactPageMetrics {
  static let aspectRatio = 1123.0 / 794.0
  static let maximumWidth = 794.0
  static let minimumWidth = 320.0
  static let horizontalPadding = 48.0
  static let verticalPadding = 56.0

  static func resolvedWidth(available: Double) -> Double {
    min(max(available - 32, minimumWidth), maximumWidth)
  }
}
