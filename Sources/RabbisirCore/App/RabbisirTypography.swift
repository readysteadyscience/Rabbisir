import SwiftUI

enum RabbisirTypographyTextStyle: Equatable, Sendable {
  case title
  case title2
  case title3
  case headline
  case body
  case callout
  case caption
  case caption2
}

enum RabbisirTypographyWeight: Equatable, Sendable {
  case medium
  case semibold
}

enum RabbisirTypographyDesign: Equatable, Sendable {
  case `default`
  case monospaced
}

enum RabbisirTypographyRole: Equatable, Sendable {
  case pageTitle
  case sheetTitle
  case sectionTitle
  case headline
  case body
  case callout
  case caption
  case badge
  case codeBody
  case codeCaption

  var textStyle: RabbisirTypographyTextStyle {
    switch self {
    case .pageTitle: .title
    case .sheetTitle: .title2
    case .sectionTitle: .title3
    case .headline: .headline
    case .body, .codeBody: .body
    case .callout: .callout
    case .caption, .codeCaption: .caption
    case .badge: .caption2
    }
  }

  var weight: RabbisirTypographyWeight? {
    switch self {
    case .pageTitle, .sheetTitle, .sectionTitle: .semibold
    case .badge: .medium
    case .headline, .body, .callout, .caption, .codeBody, .codeCaption: nil
    }
  }

  var design: RabbisirTypographyDesign {
    switch self {
    case .codeBody, .codeCaption: .monospaced
    default: .default
    }
  }

  fileprivate var font: Font {
    var font: Font
    switch textStyle {
    case .title: font = .title
    case .title2: font = .title2
    case .title3: font = .title3
    case .headline: font = .headline
    case .body: font = .body
    case .callout: font = .callout
    case .caption: font = .caption
    case .caption2: font = .caption2
    }

    switch weight {
    case .medium: font = font.weight(.medium)
    case .semibold: font = font.weight(.semibold)
    case nil: break
    }

    if design == .monospaced { font = font.monospaced() }
    return font
  }
}

extension View {
  func rabbisirTypography(_ role: RabbisirTypographyRole) -> some View {
    font(role.font)
  }
}
