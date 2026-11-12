import Foundation

/// A message from the dictation server. The contract is docs/protocol.md.
public enum ServerMessage: Equatable, Sendable {
  case ready
  case delta(text: String)
  case done(text: String)
  case error(code: String)

  /// The path of the dictation WebSocket on the server.
  public static let path = "/v1/dictation"

  public init?(json: String) {
    struct Wire: Decodable {
      var type: String
      var text: String?
      var code: String?
    }
    guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else { return nil }
    switch (wire.type, wire.text, wire.code) {
    case ("ready", _, _): self = .ready
    case ("delta", let text?, _): self = .delta(text: text)
    case ("done", let text?, _): self = .done(text: text)
    case ("error", _, let code?): self = .error(code: code)
    default: return nil
    }
  }
}

/// A message to the dictation server.
public enum ClientMessage: Equatable, Sendable {
  /// Opens the dictation, with how the speaker wants the text written.
  case start(instructions: String)
  /// The speaker is done.
  case stop

  public var json: String {
    switch self {
    case .start(let instructions):
      struct Wire: Encodable {
        var type = "start"
        var instructions: String
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let data = try? encoder.encode(Wire(instructions: instructions))
      return data.map { String(decoding: $0, as: UTF8.self) } ?? #"{"type":"start"}"#
    case .stop:
      return #"{"type":"stop"}"#
    }
  }
}
