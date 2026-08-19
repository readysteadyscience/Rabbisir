import Foundation

public enum RabbisirAppIdentity {
  public static var displayName: String {
    resolve(processName: ProcessInfo.processInfo.processName)
  }

  static func resolve(processName: String) -> String {
    switch processName {
    case RabbisirOpenIdentity.displayName:
      RabbisirOpenIdentity.displayName
    case RabbisirLaunchIdentity.development.displayName:
      RabbisirLaunchIdentity.development.displayName
    default:
      RabbisirLaunchIdentity.production.displayName
    }
  }
  public static let upstreamAttribution = "Built on DeepSeek Harness"
  public static let coreAttribution = "Core follows DeepSeek Harness"
}

public enum RabbisirOpenIdentity {
  public static let displayName = "Rabbisir Open"
  public static let bundleIdentifier = "com.rabbisir.desktop.open"
  static let applicationSupportComponent = "Rabbisir Open"
  static let isolatedHomeEnvironmentKey = "RABBISIR_OPEN_ISOLATED_HOME"

  static func isolatedHome(
    environment: [String: String],
    temporaryDirectory: URL = FileManager.default.temporaryDirectory
  ) -> URL? {
    guard let value = environment[isolatedHomeEnvironmentKey], value.hasPrefix("/"),
      !value.contains("\0")
    else { return nil }
    let root = temporaryDirectory.resolvingSymlinksInPath().standardizedFileURL
    let candidate = URL(fileURLWithPath: value, isDirectory: true)
      .resolvingSymlinksInPath().standardizedFileURL
    guard candidate.path.hasPrefix(root.path + "/") else { return nil }
    return candidate
  }
}

public enum RabbisirLaunchIdentity: Sendable {
  case production
  case development

  public var displayName: String {
    switch self {
    case .production: "Rabbisir"
    case .development: "Rabbisir DEV"
    }
  }

  public var bundleIdentifier: String {
    switch self {
    case .production: "com.rabbisir.desktop"
    case .development: "com.rabbisir.desktop.dev"
    }
  }

  var applicationSupportComponent: String {
    switch self {
    case .production: "Rabbisir"
    case .development: "Rabbisir DEV"
    }
  }
}

public enum RabbisirVersion {
  public static let upstreamCompatibleVersion = "0.1.0-rc.5"
  public static let upstreamCompatibleCommit = "47f943859bef60e4160492346772ded9b24f765a"
  public static let displayVersion = "0.1.0"
  public static let appleShortVersion = "0.1.0"
  public static let appleBuildVersion = "1"
}
