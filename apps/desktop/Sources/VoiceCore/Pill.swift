/// What a meeting is up to, as far as the pill shows it.
public enum MeetingStatus: Equatable, Sendable {
  case idle
  /// Another app is in a call, and the user is offered to record it.
  case offered(MicrophoneUser)
  case recording
  /// The recording ended, and the last of the text is on its way.
  case finishing
  /// A meeting could not start, shown for a moment.
  case failed(MeetingError)
}

/// What the pill shows: a dictation, a meeting, or the offer to record one.
///
/// A dictation shows over a meeting: it is the one in hand, and the meeting comes back
/// once the dictation is over.
public enum PillContent: Equatable, Sendable {
  case hidden
  case dictation(PillState)
  case offer(MicrophoneUser)
  case meeting(isFinishing: Bool)
  case meetingFailed(MeetingError)

  public init(dictation: PillState, meeting: MeetingStatus) {
    guard dictation == .hidden else {
      self = .dictation(dictation)
      return
    }
    self =
      switch meeting {
      case .idle: .hidden
      case .offered(let user): .offer(user)
      case .recording: .meeting(isFinishing: false)
      case .finishing: .meeting(isFinishing: true)
      case .failed(let error): .meetingFailed(error)
      }
  }

  /// Whether the pill has buttons, and so takes clicks. A dictation's pill never does: it
  /// comes and goes under the pointer.
  public var takesClicks: Bool {
    switch self {
    case .offer, .meeting: true
    case .hidden, .dictation, .meetingFailed: false
    }
  }
}
