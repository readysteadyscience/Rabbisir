import OSLog

/// Centralized system-log categories for Rabbisir-owned processes.
enum RabbisirLog {
  private static let subsystem = "com.rabbisir.app"

  static let application = Logger(subsystem: subsystem, category: "application")
  static let runtime = Logger(subsystem: subsystem, category: "runtime")
}
