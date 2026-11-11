import Foundation

/// A message from the dictation server. The contract is docs/protocol.md.
public enum ServerMessage: Equatable, Sendable {
  case ready
  case delta(segment: Int, text: String)
  case final(segment: Int, text: String)
  case refined(segment: Int, text: String)
  case done
  case error(code: String)

  /// The path of the dictation WebSocket on the server.
  public static let path = "/v1/dictation"
  /// The message that tells the server the speaker is done.
  public static let stop = #"{"type":"stop"}"#

  public init?(json: String) {
    struct Wire: Decodable {
      var type: String
      var segment: Int?
      var text: String?
      var code: String?
    }
    guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else { return nil }
    switch (wire.type, wire.segment, wire.text, wire.code) {
    case ("ready", _, _, _): self = .ready
    case ("delta", let segment?, let text?, _): self = .delta(segment: segment, text: text)
    case ("final", let segment?, let text?, _): self = .final(segment: segment, text: text)
    case ("refined", let segment?, let text?, _): self = .refined(segment: segment, text: text)
    case ("done", _, _, _): self = .done
    case ("error", _, _, let code?): self = .error(code: code)
    default: return nil
    }
  }
}
