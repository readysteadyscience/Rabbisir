import CoreGraphics
import Foundation

struct RabbisirWorkspaceWidthPreferences: Equatable, Sendable {
  var sidebar: CGFloat?
  var conversation: CGFloat?
  var details: CGFloat?

  init(
    sidebar: CGFloat? = nil,
    conversation: CGFloat? = nil,
    details: CGFloat? = nil
  ) {
    self.sidebar = sidebar
    self.conversation = conversation
    self.details = details
  }
}

enum RabbisirInterfacePreferenceKey {
  static let schemaVersion = "rabbisir.interfacePreferences.schemaVersion"
  static let sidebarWidth = "rabbisir.interfacePreferences.sidebarWidth"
  static let conversationWidth = "rabbisir.interfacePreferences.conversationWidth"
  static let detailsWidth = "rabbisir.interfacePreferences.detailsWidth"
  static let settingsWidth = "rabbisir.interfacePreferences.settingsWidth"
  static let settingsHeight = "rabbisir.interfacePreferences.settingsHeight"
  static let helpWidth = "rabbisir.interfacePreferences.helpWidth"
  static let helpHeight = "rabbisir.interfacePreferences.helpHeight"
}

final class RabbisirInterfacePreferencesStore {
  static let schemaVersion = 1

  private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
  }

  var workspaceWidths: RabbisirWorkspaceWidthPreferences {
    guard hasCurrentSchema else { return RabbisirWorkspaceWidthPreferences() }
    return RabbisirWorkspaceWidthPreferences(
      sidebar: read(
        RabbisirInterfacePreferenceKey.sidebarWidth,
        range: SpatialWorkspaceLayoutPolicy
          .minimumSidebarWidth...SpatialWorkspaceLayoutPolicy.maximumSidebarWidth
      ),
      conversation: read(
        RabbisirInterfacePreferenceKey.conversationWidth,
        range: SpatialWorkspaceLayoutPolicy
          .minimumInputWidth...SpatialWorkspaceLayoutPolicy.maximumConversationWidth
      ),
      details: read(
        RabbisirInterfacePreferenceKey.detailsWidth,
        range: SpatialWorkspaceLayoutPolicy
          .minimumDetailsWidth...SpatialWorkspaceLayoutPolicy.maximumStoredDetailsWidth
      )
    )
  }

  var settingsWindowSize: CGSize? {
    guard hasCurrentSchema,
      let width = read(
        RabbisirInterfacePreferenceKey.settingsWidth,
        range: NativeSettingsWindowLayout.minimumSize
          .width...NativeSettingsWindowLayout.maximumStoredSize.width
      ),
      let height = read(
        RabbisirInterfacePreferenceKey.settingsHeight,
        range: NativeSettingsWindowLayout.minimumSize
          .height...NativeSettingsWindowLayout.maximumStoredSize.height
      )
    else { return nil }
    return CGSize(width: width, height: height)
  }

  var helpWindowSize: CGSize? {
    guard hasCurrentSchema,
      let width = read(
        RabbisirInterfacePreferenceKey.helpWidth,
        range: RabbisirHelpWindowLayout.minimumSize
          .width...RabbisirHelpWindowLayout.maximumStoredSize.width
      ),
      let height = read(
        RabbisirInterfacePreferenceKey.helpHeight,
        range: RabbisirHelpWindowLayout.minimumSize
          .height...RabbisirHelpWindowLayout.maximumStoredSize.height
      )
    else { return nil }
    return CGSize(width: width, height: height)
  }

  func setSidebarWidth(_ width: CGFloat?) {
    write(
      width,
      key: RabbisirInterfacePreferenceKey.sidebarWidth,
      range: SpatialWorkspaceLayoutPolicy
        .minimumSidebarWidth...SpatialWorkspaceLayoutPolicy.maximumSidebarWidth
    )
  }

  func setConversationWidth(_ width: CGFloat?) {
    write(
      width,
      key: RabbisirInterfacePreferenceKey.conversationWidth,
      range: SpatialWorkspaceLayoutPolicy
        .minimumInputWidth...SpatialWorkspaceLayoutPolicy.maximumConversationWidth
    )
  }

  func setDetailsWidth(_ width: CGFloat?) {
    write(
      width,
      key: RabbisirInterfacePreferenceKey.detailsWidth,
      range: SpatialWorkspaceLayoutPolicy
        .minimumDetailsWidth...SpatialWorkspaceLayoutPolicy.maximumStoredDetailsWidth
    )
  }

  func setSettingsWindowSize(_ size: CGSize?) {
    guard let size, size.width.isFinite, size.height.isFinite else {
      defaults.removeObject(forKey: RabbisirInterfacePreferenceKey.settingsWidth)
      defaults.removeObject(forKey: RabbisirInterfacePreferenceKey.settingsHeight)
      return
    }
    ensureCurrentSchema()
    defaults.set(
      min(
        max(size.width, NativeSettingsWindowLayout.minimumSize.width),
        NativeSettingsWindowLayout.maximumStoredSize.width
      ),
      forKey: RabbisirInterfacePreferenceKey.settingsWidth
    )
    defaults.set(
      min(
        max(size.height, NativeSettingsWindowLayout.minimumSize.height),
        NativeSettingsWindowLayout.maximumStoredSize.height
      ),
      forKey: RabbisirInterfacePreferenceKey.settingsHeight
    )
  }

  func setHelpWindowSize(_ size: CGSize?) {
    guard let size, size.width.isFinite, size.height.isFinite else {
      defaults.removeObject(forKey: RabbisirInterfacePreferenceKey.helpWidth)
      defaults.removeObject(forKey: RabbisirInterfacePreferenceKey.helpHeight)
      return
    }
    ensureCurrentSchema()
    defaults.set(
      min(
        max(size.width, RabbisirHelpWindowLayout.minimumSize.width),
        RabbisirHelpWindowLayout.maximumStoredSize.width
      ),
      forKey: RabbisirInterfacePreferenceKey.helpWidth
    )
    defaults.set(
      min(
        max(size.height, RabbisirHelpWindowLayout.minimumSize.height),
        RabbisirHelpWindowLayout.maximumStoredSize.height
      ),
      forKey: RabbisirInterfacePreferenceKey.helpHeight
    )
  }

  private var hasCurrentSchema: Bool {
    defaults.object(forKey: RabbisirInterfacePreferenceKey.schemaVersion) is NSNumber
      && defaults.integer(forKey: RabbisirInterfacePreferenceKey.schemaVersion)
        == Self.schemaVersion
  }

  private func ensureCurrentSchema() {
    if !hasCurrentSchema {
      clearStoredGeometry()
      defaults.set(Self.schemaVersion, forKey: RabbisirInterfacePreferenceKey.schemaVersion)
    }
  }

  private func read(_ key: String, range: ClosedRange<CGFloat>) -> CGFloat? {
    guard let number = defaults.object(forKey: key) as? NSNumber else { return nil }
    let value = CGFloat(number.doubleValue)
    guard value.isFinite, range.contains(value) else { return nil }
    return value
  }

  private func write(_ value: CGFloat?, key: String, range: ClosedRange<CGFloat>) {
    guard let value, value.isFinite else {
      defaults.removeObject(forKey: key)
      return
    }
    ensureCurrentSchema()
    defaults.set(min(max(value, range.lowerBound), range.upperBound), forKey: key)
  }

  private func clearStoredGeometry() {
    for key in [
      RabbisirInterfacePreferenceKey.sidebarWidth,
      RabbisirInterfacePreferenceKey.conversationWidth,
      RabbisirInterfacePreferenceKey.detailsWidth,
      RabbisirInterfacePreferenceKey.settingsWidth,
      RabbisirInterfacePreferenceKey.settingsHeight,
      RabbisirInterfacePreferenceKey.helpWidth,
      RabbisirInterfacePreferenceKey.helpHeight,
    ] {
      defaults.removeObject(forKey: key)
    }
  }
}
