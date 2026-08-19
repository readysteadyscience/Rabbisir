import AppKit

enum RabbisirAppIconAppearance: String, CaseIterable, Sendable {
  case light = "AppIconLight"
  case dark = "AppIconDark"

  static func resolve(_ appearance: NSAppearance) -> Self {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }
}

enum RabbisirBrandAssets {
  static var logoURL: URL? {
    RabbisirResourceBundle.current.url(
      forResource: "RabbisirLogoTight",
      withExtension: "png",
      subdirectory: "Brand"
    )
  }

  static func loadLogo() throws -> NSImage {
    guard let logoURL else {
      throw RabbisirBrandAssetError.logoMissing
    }
    guard let image = NSImage(contentsOf: logoURL), image.isValid else {
      throw RabbisirBrandAssetError.logoUnreadable
    }
    return image
  }

  static func loadAboutImage(named name: String, extension fileExtension: String = "png") throws
    -> NSImage
  {
    guard let url = aboutImageURL(named: name, extension: fileExtension) else {
      throw RabbisirBrandAssetError.aboutAssetMissing
    }
    guard let image = NSImage(contentsOf: url), image.isValid else {
      throw RabbisirBrandAssetError.aboutAssetUnreadable
    }
    image.isTemplate = false
    return image
  }

  static func aboutImageURL(named name: String, extension fileExtension: String) -> URL? {
    RabbisirResourceBundle.current.url(
      forResource: name,
      withExtension: fileExtension,
      subdirectory: "Brand"
    )
  }

  static func appIconURL(for appearance: RabbisirAppIconAppearance) -> URL? {
    RabbisirResourceBundle.current.url(
      forResource: appearance.rawValue,
      withExtension: "icns",
      subdirectory: "Brand"
    )
  }

  static func loadAppIcon(for appearance: RabbisirAppIconAppearance) throws -> NSImage {
    guard let appIconURL = appIconURL(for: appearance) else {
      throw RabbisirBrandAssetError.appIconMissing
    }
    guard let image = NSImage(contentsOf: appIconURL), image.isValid else {
      throw RabbisirBrandAssetError.appIconUnreadable
    }
    return image
  }
}

enum RabbisirBrandAssetError: LocalizedError {
  case logoMissing
  case logoUnreadable
  case appIconMissing
  case appIconUnreadable
  case aboutAssetMissing
  case aboutAssetUnreadable

  var errorDescription: String? {
    let copy = RabbisirCopy(language: RabbisirInterfaceLanguage.currentPreference())
    return switch self {
    case .logoMissing:
      copy.brandLogoMissing
    case .logoUnreadable:
      copy.brandLogoUnreadable
    case .appIconMissing:
      copy.brandIconMissing
    case .appIconUnreadable:
      copy.brandIconUnreadable
    case .aboutAssetMissing:
      "A required About panel image is missing. Rebuild the app."
    case .aboutAssetUnreadable:
      "A required About panel image could not be read. Rebuild the app."
    }
  }
}
