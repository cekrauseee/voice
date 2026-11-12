import Foundation

/// A message from the meeting server. The contract is docs/protocol.md.
public enum MeetingServerMessage: Equatable, Sendable {
  case ready
  /// The text heard on a channel that is not in a segment yet. It replaces the one before.
  case draft(channel: Channel, text: String)
  case segment(MeetingSegment)
  /// What the connection used so far.
  case usage(Usage)
  case done(usage: Usage)
  case error(code: String)

  /// The path of the meeting WebSocket on the server.
  public static let path = "/v1/meeting"

  public init?(json: String) {
    struct Wire: Decodable {
      var type: String
      var channel: Channel?
      var text: String?
      var id: Int?
      var start: Double?
      var end: Double?
      var code: String?
      var usage: Usage?
    }
    guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else { return nil }
    switch wire.type {
    case "ready":
      self = .ready
    case "draft":
      guard let channel = wire.channel, let text = wire.text else { return nil }
      self = .draft(channel: channel, text: text)
    case "segment":
      guard let id = wire.id, let channel = wire.channel, let start = wire.start,
        let end = wire.end, let text = wire.text
      else { return nil }
      self = .segment(MeetingSegment(id: id, channel: channel, start: start, end: end, text: text))
    case "usage":
      guard let usage = wire.usage else { return nil }
      self = .usage(usage)
    case "done":
      self = .done(usage: wire.usage ?? Usage())
    case "error":
      guard let code = wire.code else { return nil }
      self = .error(code: code)
    default:
      return nil
    }
  }
}

/// A message to the meeting server.
public enum MeetingClientMessage: Equatable, Sendable {
  /// Opens a connection of the meeting: the id of the next segment, and where each
  /// channel's clock starts, in seconds.
  case start(instructions: String, firstId: Int, offsets: [Channel: TimeInterval])
  /// The meeting is over.
  case stop

  public var json: String {
    switch self {
    case .start(let instructions, let firstId, let offsets):
      struct Offsets: Encodable {
        var me: Double
        var others: Double
      }
      struct Wire: Encodable {
        var type = "start"
        var instructions: String
        var firstId: Int
        var offsets: Offsets

        enum CodingKeys: String, CodingKey {
          case type, instructions, offsets
          case firstId = "first_id"
        }
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let wire = Wire(
        instructions: instructions, firstId: firstId,
        offsets: Offsets(me: offsets[.me] ?? 0, others: offsets[.others] ?? 0))
      let data = try? encoder.encode(wire)
      return data.map { String(decoding: $0, as: UTF8.self) } ?? #"{"type":"start"}"#
    case .stop:
      return #"{"type":"stop"}"#
    }
  }
}

/// A binary frame of a meeting: the channel, then its audio.
public enum AudioFrame {
  public static func make(_ channel: Channel, _ pcm: Data) -> Data {
    Data([channel.frameByte]) + pcm
  }
}
