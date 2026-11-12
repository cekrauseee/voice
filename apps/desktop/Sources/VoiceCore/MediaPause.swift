/// Pauses the media playing on the Mac for the length of a dictation, and resumes it after.
///
/// It resumes only what it paused: media that was not playing when the dictation started
/// is left alone.
@MainActor
public final class MediaPause {
  public enum Command: Equatable, Sendable {
    case pause
    case play
  }

  private let isPlaying: @Sendable () async -> Bool
  private let send: (Command) -> Void
  private let soundIsBack: @Sendable () async -> Void
  /// The question of whether media is playing, while it is still out.
  private var check: Task<Void, Never>?
  /// The wait for sound to be back, before the media resumes.
  private var resuming: Task<Void, Never>?
  private var didPause = false

  /// - Parameters:
  ///   - isPlaying: Whether an app is playing media now.
  ///   - send: Sends a command to the app playing media.
  ///   - soundIsBack: Returns once sound plays normally again after a recording. A
  ///     Bluetooth headset takes a moment to leave call quality.
  public init(
    isPlaying: @escaping @Sendable () async -> Bool,
    send: @escaping (Command) -> Void,
    soundIsBack: @escaping @Sendable () async -> Void = {}
  ) {
    self.isPlaying = isPlaying
    self.send = send
    self.soundIsBack = soundIsBack
  }

  /// A dictation starts: pause the media, if any is playing.
  public func pause() {
    // Media about to resume from the last dictation stays paused for this one.
    resuming?.cancel()
    resuming = nil
    guard check == nil, !didPause else { return }
    check = Task { [isPlaying] in
      let playing = await isPlaying()
      guard !Task.isCancelled else { return }
      check = nil
      if playing {
        send(.pause)
        didPause = true
      }
    }
  }

  /// The dictation is over: resume the media, if this paused it.
  public func resume() {
    // A dictation that ends before the answer came has paused nothing.
    check?.cancel()
    check = nil
    guard didPause, resuming == nil else { return }
    resuming = Task { [soundIsBack] in
      await soundIsBack()
      guard !Task.isCancelled else { return }
      resuming = nil
      didPause = false
      send(.play)
    }
  }
}
