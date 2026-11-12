import Foundation

/// The server the production app runs on this Mac, unless another server is set. It starts with
/// the app and stops with it. Its port is not the development server's, so both can run at once.
public enum LocalServer {
  public static let port = 8788
  public static let url = URL(string: "ws://127.0.0.1:\(port)")!

  /// Where Node.js is installed by Homebrew on Apple silicon, and by Homebrew on Intel or the
  /// installer from nodejs.org. An app opened from Finder does not get the shell's PATH.
  public static let nodePaths = ["/opt/homebrew/bin/node", "/usr/local/bin/node"]

  /// The first Node.js found.
  public static func node(isExecutable: (String) -> Bool) -> String? {
    nodePaths.first(where: isExecutable)
  }

  /// Runs the server's code with the variables of `environmentFile`, the server's `.env`.
  public static func arguments(script: String, environmentFile: String) -> [String] {
    ["--env-file=\(environmentFile)", script]
  }

  /// What the app sets for the server. These win over the `.env`, which the development server
  /// reads too. The server stops when the app's end closes its standard input.
  public static let environment = [
    "HOST": "127.0.0.1",
    "PORT": "\(port)",
    "LOG_FORMAT": "json",
    "STOP_WITH_PARENT": "1",
  ]
}

/// Why the server stopped, from the last error in its log.
public struct ServerFailure: Equatable, Sendable {
  public let message: String
  public let hint: String?

  public init(message: String, hint: String? = nil) {
    self.message = message
    self.hint = hint
  }

  /// Reads the server's log, one JSON record per line. Lines that are not records, such as a
  /// crash from Node.js itself, are skipped.
  public init?(log: String) {
    let errors = log.split(separator: "\n").compactMap { line -> ServerFailure? in
      guard
        let record = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
        record["level"] as? String == "error",
        let message = record["message"] as? String
      else { return nil }
      return ServerFailure(message: message, hint: record["hint"] as? String)
    }
    guard let last = errors.last else { return nil }
    self = last
  }

  /// The failure in sentences: `OPENAI_API_KEY is not set. Add your key to apps/server/.env.`
  public var text: String {
    [message, hint].compactMap { $0.map(Self.sentence) }.joined(separator: " ")
  }

  private static func sentence(_ phrase: String) -> String {
    let capitalized = phrase.prefix(1).uppercased() + phrase.dropFirst()
    return capitalized.hasSuffix(".") ? capitalized : "\(capitalized)."
  }
}
