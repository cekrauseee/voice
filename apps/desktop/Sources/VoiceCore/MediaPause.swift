/// Pauses the media playing on the Mac while a dictation records. After the recording it
/// gets sound back to normal, and resumes the media.
///
/// It resumes only what it paused: media that was not playing when the recording started
/// is left alone. Only the app macOS shows as playing can be paused, so the other apps are
/// muted meanwhile, and heard again with the media.
@MainActor
public final class MediaPause {
  public enum Command: Equatable, Sendable {
    case pause
    case play
  }

  private let isPlaying: @Sendable () async -> Bool
  private let send: (Command) -> Void
  private let soundIsBack: @Sendable () async -> Void
  private let muteOthers: (Bool) -> Void
  /// The question of whether media is playing, while it is still out.
  private var check: Task<Void, Never>?
  /// Sound getting back to normal, before the media resumes.
  private var resuming: Task<Void, Never>?
  private var didPause = false
  private var isMuted = false

  /// - Parameters:
  ///   - isPlaying: Whether an app is playing media now.
  ///   - send: Sends a command to the app playing media.
  ///   - soundIsBack: Gets sound back to normal after a recording, and returns once it
  ///     is. A Bluetooth headset has to leave call quality.
  ///   - muteOthers: Mutes, or unmutes, what the apps other than the one playing media
  ///     play.
  public init(
    isPlaying: @escaping @Sendable () async -> Bool,
    send: @escaping (Command) -> Void,
    soundIsBack: @escaping @Sendable () async -> Void = {},
    muteOthers: @escaping (Bool) -> Void = { _ in }
  ) {
    self.isPlaying = isPlaying
    self.send = send
    self.soundIsBack = soundIsBack
    self.muteOthers = muteOthers
  }

  /// A dictation starts: pause the media, if any is playing.
  public func pause() {
    // Media about to resume from the last dictation stays paused for this one.
    resuming?.cancel()
    resuming = nil
    if !isMuted {
      isMuted = true
      muteOthers(true)
    }
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

  /// The recording is over: get sound back to normal, then resume the media, if this
  /// paused it.
  public func resume() {
    // A recording that ends before the answer came has paused nothing.
    check?.cancel()
    check = nil
    guard resuming == nil else { return }
    resuming = Task { [soundIsBack] in
      await soundIsBack()
      guard !Task.isCancelled else { return }
      resuming = nil
      isMuted = false
      muteOthers(false)
      guard didPause else { return }
      didPause = false
      send(.play)
    }
  }
}
