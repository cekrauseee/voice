import Foundation

/// The conversation with the agent that writes the user's profile.
///
/// It is held in memory, and nowhere else: it is not `Codable`, and what the user says is
/// never written down. Only what the agent writes, the profile, is kept. Each turn sends the
/// conversation so far, so the server keeps nothing either.
public struct Conversation: Equatable, Sendable {
  public struct Message: Identifiable, Equatable, Sendable {
    public enum Role: Equatable, Sendable {
      case user
      case agent
      /// Something that happened, such as words added to the dictionary. Not part of what the
      /// agent is sent.
      case note
    }

    public let id: Int
    public let role: Role
    public fileprivate(set) var text: String
    /// The profile the agent wrote with this message, when it changed it.
    public fileprivate(set) var profile: ProfileUpdate?
  }

  /// A message of the conversation as the agent is sent it.
  public struct Entry: Encodable, Equatable, Sendable {
    public let role: String
    public let text: String
    public let profile: ProfileUpdate?
  }

  public enum State: Equatable, Sendable {
    /// Waiting for the user to speak.
    case idle
    /// The user speaks: their message fills in as they are heard.
    case listening
    /// The user stopped, and the agent has not answered yet.
    case thinking
    /// The agent's reply is coming in.
    case replying
    /// The last turn did not work out. The user can speak again.
    case failed(Failure)
  }

  public enum Failure: Equatable, Sendable {
    /// Nothing was heard.
    case notHeard
    case microphoneDenied
    case microphoneUnavailable
    /// No connection: to the server, or from the server to OpenAI.
    case unreachable
    /// The transcription failed.
    case notTranscribed
    /// The agent did not answer.
    case notAnswered

    public init(_ error: DictationError) {
      switch error {
      case .microphoneDenied: self = .microphoneDenied
      case .microphoneUnavailable: self = .microphoneUnavailable
      case .offline: self = .unreachable
      case .transcriptionFailed: self = .notTranscribed
      }
    }

    public var message: String {
      switch self {
      case .notHeard: "Didn't catch that. Try again."
      case .microphoneDenied: "Microphone access needed"
      case .microphoneUnavailable: "No microphone found"
      case .unreachable: "No connection. Try again."
      case .notTranscribed: "Couldn't hear you. Try again."
      case .notAnswered: "Couldn't answer. Try again."
      }
    }
  }

  /// What a turn ended with, for the profile and the dictionary.
  public struct Outcome: Equatable, Sendable {
    /// The whole profile, when the agent changed it.
    public var profile: ProfileUpdate?
    /// Terms the user asked to add to the dictionary.
    public var addTerms: [String]
  }

  public private(set) var messages: [Message]
  public private(set) var state = State.idle
  /// The messages of the turn in progress.
  private var turnUser: Int?
  private var turnAgent: Int?
  private var nextID = 0

  /// A conversation that the agent opens with a question, asked at once, without a model.
  public init(opening: String) {
    messages = []
    append(.agent, opening)
  }

  /// Whether the user can speak: the agent is not hearing or answering them.
  public var canTalk: Bool {
    switch state {
    case .idle, .failed: true
    case .listening, .thinking, .replying: false
    }
  }

  /// Whether there is more than the opening.
  public var hasStarted: Bool {
    messages.count > 1
  }

  /// The conversation so far, as the agent is sent it.
  public var history: [Entry] {
    messages.compactMap { message in
      switch message.role {
      case .user: Entry(role: "user", text: message.text, profile: nil)
      case .agent: Entry(role: "assistant", text: message.text, profile: message.profile)
      case .note: nil
      }
    }
  }

  /// The user starts speaking: their message, empty for now.
  public mutating func listen() {
    guard canTalk else { return }
    turnUser = append(.user, "")
    turnAgent = nil
    state = .listening
  }

  /// The user stopped speaking.
  public mutating func think() {
    if state == .listening { state = .thinking }
  }

  /// Applies a message of the turn in progress. Returns what the turn ended with, when it
  /// ends with an answer.
  public mutating func apply(_ message: ProfileTurnMessage) -> Outcome? {
    guard let user = turnUser else { return nil }
    switch message {
    case .ready:
      break
    case .delta(let text):
      if state == .listening || state == .thinking { edit(user) { $0.text += text } }
    case .heard(let text):
      edit(user) { $0.text = text }
    case .reply(let text):
      state = .replying
      if let agent = turnAgent {
        edit(agent) { $0.text += text }
      } else {
        turnAgent = append(.agent, text)
      }
    case .done(let reply, let profile, let addTerms, _):
      if text(of: user).isEmpty || reply.isEmpty {
        end(text(of: user).isEmpty ? .notHeard : .notAnswered)
        return nil
      }
      if let agent = turnAgent {
        edit(agent) {
          $0.text = reply
          $0.profile = profile
        }
      } else {
        turnAgent = append(.agent, reply, profile: profile)
      }
      turnUser = nil
      turnAgent = nil
      state = .idle
      return Outcome(profile: profile, addTerms: addTerms)
    case .error(let code):
      switch code {
      case "agent_failed": end(.notAnswered)
      case ServerErrorCode.unreachable: end(.unreachable)
      default: end(.notTranscribed)
      }
    }
    return nil
  }

  /// The turn failed before it ended, or could not start.
  public mutating func fail(_ failure: Failure) {
    end(failure)
  }

  /// The user cancelled the turn: it leaves nothing.
  public mutating func cancel() {
    drop()
    state = .idle
  }

  /// Notes something that happened, such as words added to the dictionary.
  public mutating func note(_ text: String) {
    append(.note, text)
  }

  /// A failed turn leaves only the failure: what was half heard or answered goes.
  private mutating func end(_ failure: Failure) {
    drop()
    state = .failed(failure)
  }

  private mutating func drop() {
    messages.removeAll { $0.id == turnUser || $0.id == turnAgent }
    turnUser = nil
    turnAgent = nil
  }

  @discardableResult
  private mutating func append(
    _ role: Message.Role, _ text: String, profile: ProfileUpdate? = nil
  ) -> Int {
    nextID += 1
    messages.append(Message(id: nextID, role: role, text: text, profile: profile))
    return nextID
  }

  private mutating func edit(_ id: Int, _ change: (inout Message) -> Void) {
    guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
    change(&messages[index])
  }

  private func text(of id: Int) -> String {
    messages.first { $0.id == id }?.text ?? ""
  }
}

extension Conversation {
  /// The question the agent opens with, in the language of the Mac when it knows it, or in
  /// English. With a profile, it asks what to change.
  public static func opening(language: String?, hasProfile: Bool) -> String {
    let openings: [String: (new: String, existing: String)] = [
      "en": (
        "Hi! Tell me about yourself: what do you do, and what do you usually dictate?",
        "This is your profile. What would you like to change?"
      ),
      "pt": (
        "Oi! Me conta sobre você: o que você faz e o que costuma ditar?",
        "Esse é o seu perfil. O que você quer mudar?"
      ),
      "es": (
        "¡Hola! Cuéntame de ti: ¿a qué te dedicas y qué sueles dictar?",
        "Este es tu perfil. ¿Qué quieres cambiar?"
      ),
      "fr": (
        "Bonjour ! Parlez-moi de vous : que faites-vous, et que dictez-vous d'habitude ?",
        "Voici votre profil. Que voulez-vous changer ?"
      ),
      "de": (
        "Hallo! Erzählen Sie von sich: Was machen Sie, und was diktieren Sie meistens?",
        "Das ist Ihr Profil. Was möchten Sie ändern?"
      ),
      "it": (
        "Ciao! Parlami di te: che lavoro fai e cosa detti di solito?",
        "Ecco il tuo profilo. Cosa vuoi cambiare?"
      ),
    ]
    let code = language.map { Locale(identifier: $0).language.languageCode?.identifier ?? $0 }
    let opening = code.flatMap { openings[$0] } ?? openings["en"]!
    return hasProfile ? opening.existing : opening.new
  }
}

/// Where a shortcut sends what is said.
public enum ShortcutTarget: Equatable, Sendable {
  /// To the focused field, as a dictation.
  case dictation
  /// To the agent, as a turn of the profile conversation.
  case conversation
  /// Nowhere: the profile page is in front, but the agent is still on the last turn.
  case none

  /// Where a recording that starts now goes. While the app's window is in front on the
  /// profile page, to the agent: the page has no field to type in. Anywhere else, it is a
  /// dictation. A recording keeps its target until it ends.
  public static func forRecording(
    isAppActive: Bool, isWindowKey: Bool, showsProfile: Bool, canTalk: Bool
  ) -> ShortcutTarget {
    guard isAppActive, isWindowKey, showsProfile else { return .dictation }
    return canTalk ? .conversation : .none
  }

  /// Whether what is recorded is typed, kept in the history with its recording, and counted
  /// in the statistics. What is said to the agent is none of these.
  public var keepsRecording: Bool {
    self == .dictation
  }
}
