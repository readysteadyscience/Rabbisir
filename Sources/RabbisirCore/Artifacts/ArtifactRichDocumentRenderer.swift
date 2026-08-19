import AppKit
import Foundation

/// Converts the workbench's authoritative Markdown source into a native document projection.
@MainActor
enum ArtifactRichDocumentRenderer {
  private static let bodyFont =
    NSFont(name: "Songti SC", size: 12)
    ?? NSFont.systemFont(ofSize: 12)
  private static let codeFont = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)

  static func attributedDocument(markdown: String) -> NSAttributedString {
    let output = NSMutableAttributedString()
    var insideCodeFence = false

    for line in markdown.components(separatedBy: .newlines) {
      if line.trimmingCharacters(in: .whitespaces).hasPrefix("```") {
        insideCodeFence.toggle()
        continue
      }

      let block = blockPresentation(for: line, insideCodeFence: insideCodeFence)
      let content =
        insideCodeFence
        ? NSAttributedString(string: block.text)
        : inlinePresentation(block.text, baseFont: block.font)
      let mutable = NSMutableAttributedString(attributedString: content)
      let fullRange = NSRange(location: 0, length: mutable.length)
      mutable.addAttributes(
        [
          .foregroundColor: block.color,
          .paragraphStyle: block.paragraphStyle,
        ], range: fullRange)
      if insideCodeFence {
        mutable.addAttribute(
          .backgroundColor, value: NSColor(calibratedWhite: 0.95, alpha: 1), range: fullRange)
      }
      output.append(mutable)
      output.append(
        NSAttributedString(
          string: "\n",
          attributes: [
            .font: block.font,
            .paragraphStyle: block.paragraphStyle,
          ]))
    }

    if output.length > 0 {
      output.deleteCharacters(in: NSRange(location: output.length - 1, length: 1))
    }
    return output
  }

  private static func inlinePresentation(_ source: String, baseFont: NSFont) -> NSAttributedString {
    guard
      let parsed = try? AttributedString(
        markdown: source,
        options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
      )
    else {
      return NSAttributedString(string: source, attributes: [.font: baseFont])
    }

    let result = NSMutableAttributedString(attributedString: NSAttributedString(parsed))
    let range = NSRange(location: 0, length: result.length)
    result.addAttribute(.font, value: baseFont, range: range)
    result.enumerateAttribute(.inlinePresentationIntent, in: range) { value, subrange, _ in
      let rawValue = (value as? NSNumber)?.intValue ?? 0
      var font = baseFont
      if rawValue & 2 != 0 {
        font = NSFontManager.shared.convert(font, toHaveTrait: .boldFontMask)
      }
      if rawValue & 1 != 0 {
        font = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask)
      }
      result.addAttribute(.font, value: rawValue & 8 != 0 ? codeFont : font, range: subrange)
      if rawValue & 4 != 0 {
        result.addAttribute(
          .strikethroughStyle, value: NSUnderlineStyle.single.rawValue, range: subrange)
      }
      if rawValue & 8 != 0 {
        result.addAttribute(
          .backgroundColor, value: NSColor(calibratedWhite: 0.95, alpha: 1), range: subrange)
      }
    }
    return result
  }

  private static func blockPresentation(
    for source: String,
    insideCodeFence: Bool
  ) -> (text: String, font: NSFont, color: NSColor, paragraphStyle: NSParagraphStyle) {
    let paragraph = NSMutableParagraphStyle()
    paragraph.lineSpacing = 4
    paragraph.paragraphSpacing = 8
    var text = source
    var font = insideCodeFence ? codeFont : bodyFont
    var color = NSColor.black

    if insideCodeFence {
      paragraph.firstLineHeadIndent = 8
      paragraph.headIndent = 8
    } else if let heading = heading(from: source) {
      text = heading.text
      font = NSFont.systemFont(
        ofSize: heading.level == 1 ? 23 : heading.level == 2 ? 18 : 15,
        weight: heading.level == 1 ? .bold : .semibold
      )
      paragraph.paragraphSpacingBefore = heading.level == 1 ? 8 : 12
      paragraph.paragraphSpacing = heading.level == 1 ? 16 : 10
    } else if source.hasPrefix("> ") {
      text = String(source.dropFirst(2))
      color = NSColor(calibratedWhite: 0.32, alpha: 1)
      paragraph.headIndent = 18
      paragraph.firstLineHeadIndent = 18
    } else if source.hasPrefix("- ") || source.hasPrefix("* ") {
      text = "• " + source.dropFirst(2)
      paragraph.headIndent = 18
      paragraph.firstLineHeadIndent = 4
      paragraph.paragraphSpacing = 4
    } else if let ordered = orderedListItem(from: source) {
      text = "\(ordered.index). \(ordered.text)"
      paragraph.headIndent = 24
      paragraph.firstLineHeadIndent = 4
      paragraph.paragraphSpacing = 4
    } else if source == "---" || source == "***" {
      text = "━━━━━━━━━━━━━━━━━━━━━━━━"
      color = NSColor(calibratedWhite: 0.68, alpha: 1)
      paragraph.alignment = .center
    }

    return (text, font, color, paragraph)
  }

  private static func heading(from source: String) -> (level: Int, text: String)? {
    let prefix = source.prefix { $0 == "#" }
    guard (1...6).contains(prefix.count), source.dropFirst(prefix.count).first == " " else {
      return nil
    }
    return (prefix.count, String(source.dropFirst(prefix.count + 1)))
  }

  private static func orderedListItem(from source: String) -> (index: String, text: String)? {
    guard let separator = source.firstIndex(of: "."),
      separator < source.endIndex,
      source[source.index(after: separator)...].first == " "
    else {
      return nil
    }
    let index = String(source[..<separator])
    guard !index.isEmpty, index.allSatisfy(\.isNumber) else { return nil }
    return (index, String(source[source.index(separator, offsetBy: 2)...]))
  }
}
