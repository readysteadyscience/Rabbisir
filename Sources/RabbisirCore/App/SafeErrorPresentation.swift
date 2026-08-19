import Foundation

enum RabbisirSafeErrorCategory: Equatable, Sendable {
  case cancelled
  case network
  case authentication
  case rateLimited
  case serviceUnavailable
  case invalidResponse
  case unknown
}

enum RabbisirSafeErrorContext: Equatable, Sendable {
  case general
  case modelCatalog
  case settings
  case pluginInventory
  case agentPresets
}

enum RabbisirSafeErrorPresentation {
  static func category(for error: any Error) -> RabbisirSafeErrorCategory {
    if error is CancellationError { return .cancelled }
    if let urlError = error as? URLError {
      return urlError.code == .userAuthenticationRequired ? .authentication : .network
    }
    if let transport = error as? UpstreamConversationTransportError {
      switch transport {
      case .carrierStatus(401), .carrierStatus(403): return .authentication
      case .carrierStatus(429): return .rateLimited
      case .carrierStatus(let status) where status >= 500: return .serviceUnavailable
      case .invalidBaseURL, .unsupportedWebSocketMessage, .cancellationRejected,
        .carrierStatus:
        return .invalidResponse
      }
    }
    if let wire = error as? UpstreamConversationWireError {
      switch wire {
      case .server(let error): return category(forRPCCode: error.code)
      case .invalidEnvelope, .rpcIDMismatch: return .invalidResponse
      }
    }
    if error is DecodingError { return .invalidResponse }
    return .unknown
  }

  static func category(forRPCCode code: String) -> RabbisirSafeErrorCategory {
    let normalized = code.lowercased()
    if normalized.contains("auth") || normalized.contains("credential")
      || normalized.contains("api-key") || normalized.contains("unauthorized")
      || normalized.contains("forbidden")
    {
      return .authentication
    }
    if normalized.contains("rate") || normalized.contains("quota")
      || normalized.contains("limit")
    {
      return .rateLimited
    }
    if normalized.contains("unavailable") || normalized.contains("timeout")
      || normalized.contains("overload")
    {
      return .serviceUnavailable
    }
    if normalized.contains("decode") || normalized.contains("invalid")
      || normalized.contains("protocol")
    {
      return .invalidResponse
    }
    return .unknown
  }

  static func message(
    for error: any Error,
    context: RabbisirSafeErrorContext = .general,
    copy: RabbisirCopy
  ) -> String {
    message(category: category(for: error), context: context, copy: copy)
  }

  static func message(
    category: RabbisirSafeErrorCategory,
    context: RabbisirSafeErrorContext = .general,
    copy: RabbisirCopy
  ) -> String {
    if context == .modelCatalog {
      return copy.language == .chinese
        ? "模型目录暂时不可用。请检查 API Key 和网络连接后重试。"
        : "The model catalog is temporarily unavailable. Check the API Key and network connection, then try again."
    }
    let detail: String =
      switch (copy.language, category) {
      case (.chinese, .cancelled): "操作已取消。"
      case (.english, .cancelled): "The operation was cancelled."
      case (.chinese, .network): "网络连接不可用。请检查连接后重试。"
      case (.english, .network):
        "The network connection is unavailable. Check the connection and try again."
      case (.chinese, .authentication): "DeepSeek 配置需要更新。请在设置中检查 API Key 和模型。"
      case (.english, .authentication):
        "The DeepSeek configuration needs attention. Check the API Key and model in Settings."
      case (.chinese, .rateLimited): "服务当前繁忙或额度受限。请稍后重试。"
      case (.english, .rateLimited): "The service is busy or rate limited. Try again later."
      case (.chinese, .serviceUnavailable): "服务暂时不可用。请稍后重试。"
      case (.english, .serviceUnavailable):
        "The service is temporarily unavailable. Try again later."
      case (.chinese, .invalidResponse): "收到无法验证的响应。请重试。"
      case (.english, .invalidResponse):
        "Rabbisir received a response it could not verify. Try again."
      case (.chinese, .unknown): "操作失败。请重试。"
      case (.english, .unknown): "The operation failed. Try again."
      }
    let prefix: String? =
      switch (copy.language, context) {
      case (_, .general), (_, .modelCatalog): nil
      case (.chinese, .settings): "设置"
      case (.english, .settings): "Settings"
      case (.chinese, .pluginInventory): "插件目录"
      case (.english, .pluginInventory): "Plugin Catalog"
      case (.chinese, .agentPresets): "智能体预设"
      case (.english, .agentPresets): "Agent Presets"
      }
    let separator = copy.language == .chinese ? "：" : ": "
    return prefix.map { "\($0)\(separator)\(detail)" } ?? detail
  }
}
