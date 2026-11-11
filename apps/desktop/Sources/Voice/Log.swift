import OSLog
import VoiceCore

/// Writes structured records to the system log, where Console and `pnpm dev` read them.
///
/// The scope names the part of the app. The message is a short lowercase phrase, and
/// everything that varies goes in the fields. Dictated text is never logged.
struct Log: Sendable {
  private let logger: Logger

  init(_ scope: String) {
    logger = Logger(subsystem: AppInfo.identifier, category: scope)
  }

  func debug(_ message: String, _ fields: KeyValuePairs<String, Any> = [:]) {
    logger.debug("\(logLine(message, fields), privacy: .public)")
  }

  func info(_ message: String, _ fields: KeyValuePairs<String, Any> = [:]) {
    logger.info("\(logLine(message, fields), privacy: .public)")
  }

  func error(_ message: String, _ fields: KeyValuePairs<String, Any> = [:]) {
    logger.error("\(logLine(message, fields), privacy: .public)")
  }
}
