import Foundation
import Observation
import VoiceCore

/// The conversation with the agent that writes the user's profile, for as long as the app
/// runs. It is held here and nowhere else: what the user says is never written down, not in
/// the history, the statistics, or the log. The profile the agent writes, and the terms the
/// user accepts, are all that is kept.
@MainActor @Observable
final class ProfileConversation {
  private(set) var conversation: Conversation

  @ObservationIgnored private let settings: Settings
  @ObservationIgnored private let log = Log("profile")
  /// The turn in progress, so a late message of an earlier one changes nothing.
  @ObservationIgnored private weak var current: ProfileTurnSession?

  init(settings: Settings) {
    self.settings = settings
    conversation = Conversation(opening: Self.opening(settings.profile))
  }

  /// Whether the user can speak to the agent now.
  var canTalk: Bool {
    conversation.canTalk
  }

  /// A turn starts as the user starts speaking: the session that carries what they say.
  func turn() -> ProfileTurnSession {
    let history = conversation.history
    let start = ProfileTurnMessage.start(
      history: history, profile: settings.profile.update(vocabulary: settings.vocabulary),
      vocabulary: settings.vocabulary)
    let session = ProfileTurnSession(server: settings.serverURL, start: start)
    session.onMessage = { [weak self, weak session] message in
      guard let self, let session, current === session else { return }
      apply(message)
    }
    current = session
    conversation.listen()
    log.info("turn started", ["history_messages": history.count])
    return session
  }

  /// The user stopped speaking: the agent answers.
  func stopped() {
    conversation.think()
  }

  /// The user cancelled the turn: it leaves nothing.
  func cancelled() {
    current = nil
    conversation.cancel()
    log.info("turn cancelled")
  }

  /// The turn could not go on: the microphone, or the connection. A failure the server
  /// reports comes as a message of the turn instead.
  func failed(_ error: DictationError) {
    current = nil
    conversation.fail(Conversation.Failure(error))
    log.error("turn failed", ["reason": error])
  }

  /// Adds suggested terms to the dictionary.
  func accept(_ terms: [String]) {
    settings.vocabulary = Vocabulary.adding(contentsOf: terms, to: settings.vocabulary)
    settings.profile.suggestions.removeAll { terms.contains($0) }
    log.info("terms added", ["count": terms.count])
  }

  /// Forgets the profile, and starts the conversation again. The dictionary stays.
  func clear() {
    settings.profile = Profile()
    restart()
    log.info("cleared")
  }

  /// Starts the conversation again, from the profile as it is.
  func restart() {
    current?.cancel()
    current = nil
    conversation = Conversation(opening: Self.opening(settings.profile))
  }

  private func apply(_ message: ProfileTurnMessage) {
    guard let outcome = conversation.apply(message) else {
      if case .failed(let failure) = conversation.state, case .done = message {
        log.info("turn ended", ["outcome": failure])
      } else if case .error(let code) = message {
        log.error("turn failed", ["code": code])
      }
      return
    }
    current = nil
    // The terms first, so the profile does not suggest them again.
    if !outcome.addTerms.isEmpty {
      accept(outcome.addTerms)
      let terms = outcome.addTerms.formatted(
        .list(type: .and).locale(Locale(identifier: "en_US")))
      conversation.note("Added \(terms) to your dictionary")
    }
    if let update = outcome.profile {
      settings.profile = settings.profile.applying(update, vocabulary: settings.vocabulary)
    }
    // What was said is only measured.
    log.info(
      "turn ended",
      [
        "outcome": "answered", "profile_changed": outcome.profile != nil,
        "added_terms": outcome.addTerms.count,
      ])
  }

  /// The question the agent opens with, in the language of the Mac.
  private static func opening(_ profile: Profile) -> String {
    Conversation.opening(
      language: Locale.preferredLanguages.first, hasProfile: profile.isWritten)
  }
}
