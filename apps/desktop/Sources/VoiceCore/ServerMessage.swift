import Foundation

/// What a dictation used on the server, and what that costs.
public struct Usage: Codable, Equatable, Sendable {
  /// Seconds of audio that were transcribed.
  public var audioSeconds: Double
  /// Tokens the refinement read.
  public var inputTokens: Int
  /// Tokens the refinement wrote.
  public var outputTokens: Int
  /// The cost in US dollars, at the prices the server is configured with.
  public var cost: Double

  public init(
    audioSeconds: Double = 0, inputTokens: Int = 0, outputTokens: Int = 0, cost: Double = 0
  ) {
    self.audioSeconds = audioSeconds
    self.inputTokens = inputTokens
    self.outputTokens = outputTokens
    self.cost = cost
  }

  enum CodingKeys: String, CodingKey {
    case audioSeconds = "audio_seconds"
    case inputTokens = "input_tokens"
    case outputTokens = "output_tokens"
    case cost
  }
}

/// A message from the dictation server. The contract is docs/protocol.md.
public enum ServerMessage: Equatable, Sendable {
  case ready
  case delta(text: String)
  case done(text: String, usage: Usage)
  case error(code: String)

  /// The path of the dictation WebSocket on the server.
  public static let path = "/v1/dictation"

  public init?(json: String) {
    struct Wire: Decodable {
      var type: String
      var text: String?
      var code: String?
      var usage: Usage?
    }
    guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else { return nil }
    switch (wire.type, wire.text, wire.code) {
    case ("ready", _, _): self = .ready
    case ("delta", let text?, _): self = .delta(text: text)
    case ("done", let text?, _):
      // The text is typed even when the server does not say what it used.
      self = .done(text: text, usage: wire.usage ?? Usage())
    case ("error", _, let code?): self = .error(code: code)
    default: return nil
    }
  }
}

/// The codes of the errors the server ends a dictation with.
public enum ServerErrorCode {
  /// The app sent a message that is not part of the protocol, or out of order.
  public static let badRequest = "bad_request"
  /// The transcription provider failed or disconnected.
  public static let transcriptionFailed = "transcription_failed"
  /// The server could not reach the transcription provider.
  public static let unreachable = "unreachable"
  /// Transcription was not ready in time, or nothing was heard in time.
  public static let timeout = "timeout"

  /// The errors that, without live transcription, come only once the server has tried to
  /// transcribe the whole recording.
  public static let transcribedWhole: Set<String> = [transcriptionFailed, unreachable, timeout]
}

/// A message to the dictation server.
public enum ClientMessage: Equatable, Sendable {
  /// Opens the dictation, with how the speaker wants the text written, the language to write
  /// it in when it is not the one spoken, the names and terms the speaker uses, the text
  /// before the cursor in the field, whether the words are transcribed while they talk, what
  /// their recordings are like, and the languages they speak.
  case start(
    instructions: String, translateTo: String = "", vocabulary: [String] = [],
    context: String = "", live: Bool = false, transcriptionPrompt: String = "",
    languages: [String] = [])
  /// The speaker is done.
  case stop

  public var json: String {
    switch self {
    case .start(
      let instructions, let translateTo, let vocabulary, let context, let live,
      let transcriptionPrompt, let languages):
      struct Wire: Encodable {
        var type = "start"
        var instructions: String
        var translateTo: String
        var vocabulary: [String]
        var context: String
        var live: Bool
        var transcriptionPrompt: String
        var languages: [String]

        enum CodingKeys: String, CodingKey {
          case type, instructions, vocabulary, context, live, languages
          case translateTo = "translate_to"
          case transcriptionPrompt = "transcription_prompt"
        }
      }
      let encoder = JSONEncoder()
      encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
      let data = try? encoder.encode(
        Wire(
          instructions: instructions, translateTo: translateTo, vocabulary: vocabulary,
          context: context, live: live, transcriptionPrompt: transcriptionPrompt,
          languages: languages))
      return data.map { String(decoding: $0, as: UTF8.self) } ?? #"{"type":"start"}"#
    case .stop:
      return #"{"type":"stop"}"#
    }
  }
}

/// The profile as the conversation carries it: what the agent writes, and starts from.
public struct ProfileUpdate: Codable, Equatable, Sendable {
  public var instructions: String
  public var transcriptionPrompt: String
  public var languages: [String]
  /// Names and terms to suggest for the dictionary.
  public var terms: [String]

  public init(
    instructions: String = "", transcriptionPrompt: String = "", languages: [String] = [],
    terms: [String] = []
  ) {
    self.instructions = instructions
    self.transcriptionPrompt = transcriptionPrompt
    self.languages = languages
    self.terms = terms
  }

  enum CodingKeys: String, CodingKey {
    case instructions, languages, terms
    case transcriptionPrompt = "transcription_prompt"
  }
}

/// A message of a turn of the profile conversation, from the server. The contract is
/// docs/protocol.md.
public enum ProfileTurnMessage: Equatable, Sendable {
  case ready
  /// More of what the user says, heard while they talk.
  case delta(text: String)
  /// All of what the user said.
  case heard(text: String)
  /// More of the agent's reply, as it is written.
  case reply(text: String)
  /// The agent's whole reply, the profile when it changed it, and the terms the user asked
  /// to add to the dictionary.
  case done(reply: String, profile: ProfileUpdate?, addTerms: [String], usage: Usage)
  case error(code: String)

  /// The path of the WebSocket of a turn on the server.
  public static let path = "/v1/profile"

  public init?(json: String) {
    struct Wire: Decodable {
      var type: String
      var text: String?
      var reply: String?
      var profile: ProfileUpdate?
      var addTerms: [String]?
      var usage: Usage?
      var code: String?

      enum CodingKeys: String, CodingKey {
        case type, text, reply, profile, usage, code
        case addTerms = "add_terms"
      }
    }
    guard let wire = try? JSONDecoder().decode(Wire.self, from: Data(json.utf8)) else { return nil }
    switch wire.type {
    case "ready": self = .ready
    case "delta":
      guard let text = wire.text else { return nil }
      self = .delta(text: text)
    case "heard":
      guard let text = wire.text else { return nil }
      self = .heard(text: text)
    case "reply":
      guard let text = wire.text else { return nil }
      self = .reply(text: text)
    case "done":
      guard let reply = wire.reply else { return nil }
      self = .done(
        reply: reply, profile: wire.profile, addTerms: wire.addTerms ?? [],
        usage: wire.usage ?? Usage())
    case "error":
      guard let code = wire.code else { return nil }
      self = .error(code: code)
    default: return nil
    }
  }

  /// The message that opens a turn: the conversation so far, the profile as it is, and the
  /// dictionary.
  public static func start(
    history: [Conversation.Entry], profile: ProfileUpdate, vocabulary: [String]
  ) -> String {
    struct Wire: Encodable {
      var type = "start"
      var history: [Conversation.Entry]
      var profile: ProfileUpdate
      var vocabulary: [String]
    }
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
    let data = try? encoder.encode(
      Wire(history: history, profile: profile, vocabulary: vocabulary))
    return data.map { String(decoding: $0, as: UTF8.self) } ?? #"{"type":"start"}"#
  }
}
