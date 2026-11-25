/// How one session with the server ended.
public enum SessionEnd: Equatable, Sendable {
  /// The server sent the text of the dictation.
  case done(String)
  /// The server could not be reached in time, or the connection to it dropped.
  case disconnected
  /// The server ended the dictation with an error. `afterStop` when it came once the app had
  /// told the server the speaker was done.
  case failed(code: String, afterStop: Bool)

  /// Whether it ended for want of a connection: from the app to the server, or from the
  /// server to OpenAI.
  public var isOffline: Bool {
    switch self {
    case .disconnected: true
    case .failed(let code, _): code == ServerErrorCode.unreachable
    case .done: false
    }
  }

  /// For the log.
  public var reason: String {
    switch self {
    case .done: "done"
    case .disconnected: "disconnected"
    case .failed(let code, _): code
    }
  }
}

/// What a dictation does next, once its session with the server is over and the recording
/// has ended.
public enum DictationStep: Equatable, Sendable {
  /// Types the text that came back.
  case type(String)
  /// Sends the whole recording again, as a new dictation that is not live.
  case resend
  /// Gives up: keeps the dictation in the history as not transcribed, with its recording,
  /// types the draft heard before the failure, if any, and says why. `offline` when the
  /// reason is that there was no connection.
  case save(draft: String, offline: Bool)
}

/// How a dictation gets its text when the connection fails on the way.
///
/// The recording never depends on the connection: whatever happens to the server, the
/// microphone records until the speaker stops. Then, if the dictation's session failed, the
/// whole recording is sent once more, as a dictation that is not live. If that fails too,
/// the dictation is kept in the history to be tried again by hand.
public struct DictationRecovery: Equatable, Sendable {
  /// Whether the dictation's session transcribes while the speaker talks.
  public let live: Bool
  /// The text heard before the session ended, typed when nothing better comes.
  public private(set) var draft = ""
  /// Whether the recording has ended.
  public private(set) var hasRecorded = false
  private var ended: SessionEnd?

  public init(live: Bool) {
    self.live = live
  }

  /// Whether the dictation records without a connection: its session ended for want of one,
  /// and the recording goes on.
  public var isOffline: Bool {
    !hasRecorded && ended?.isOffline == true
  }

  /// The dictation's session ended, with the text heard so far. Returns what to do, or nil
  /// while the recording goes on.
  public mutating func sessionEnded(_ end: SessionEnd, draft: String) -> DictationStep? {
    guard ended == nil else { return nil }
    ended = end
    self.draft = draft
    return hasRecorded ? next(after: end) : nil
  }

  /// The recording ended, all of it captured. Returns what to do, or nil until the session
  /// is over.
  public mutating func recordingEnded() -> DictationStep? {
    guard !hasRecorded else { return nil }
    hasRecorded = true
    return ended.map(next(after:))
  }

  /// The recording that was sent again came back with this. There is no other try.
  public func resent(_ end: SessionEnd) -> DictationStep {
    if case .done(let text) = end { return .type(text) }
    return .save(draft: draft, offline: end.isOffline)
  }

  private func next(after end: SessionEnd) -> DictationStep {
    switch end {
    case .done(let text):
      return .type(text)
    case .failed(let code, afterStop: true)
    where !live && ServerErrorCode.transcribedWhole.contains(code):
      // Without live, the server keeps the audio and transcribes it only once it is told the
      // speaker stopped. Its error then says the whole recording was tried, as sending it
      // again would: it is kept for later instead.
      return .save(draft: draft, offline: end.isOffline)
    default:
      // The server did not get all of the recording, or transcribed it live and failed.
      return .resend
    }
  }
}
