/// What happens to the media playing on the Mac while a dictation records.
public enum MediaBehavior: String, CaseIterable, Sendable {
  /// It is paused, and resumes after.
  case pause
  /// It plays on, unheard.
  case mute
  /// It plays on, quieter.
  case lower
  /// It plays on.
  case keep

  public var title: String {
    switch self {
    case .pause: "Pause"
    case .mute: "Mute"
    case .lower: "Lower"
    case .keep: "Keep playing"
    }
  }
}

/// How the sound of the other apps is turned off, or down, while a dictation records.
public enum MediaMuting: Equatable, Sendable {
  /// The other apps alone, which macOS allows with the System Audio Recording permission.
  case apps
  /// Everything the Mac plays, by muting its output. It needs no permission.
  case output
  /// Everything the Mac plays, quieter, by turning its output down. It needs no permission.
  case lowerOutput

  /// How the output is kept quiet, when it is the output that is.
  public var hold: OutputHold.Kind? {
    switch self {
    case .apps: nil
    case .output: .mute
    case .lowerOutput: .lower
    }
  }
}

extension MediaBehavior {
  /// How to mute while recording, if at all. `appsAllowed` is whether macOS lets this app
  /// mute the other apps.
  ///
  /// Muting always mutes: without the permission, it mutes the output. Pausing mutes what
  /// it cannot pause only with the permission, and never asks for it: the media that
  /// matters is paused either way.
  public func muting(appsAllowed: Bool) -> MediaMuting? {
    switch self {
    case .pause: appsAllowed ? .apps : nil
    case .mute: appsAllowed ? .apps : .output
    case .lower: .lowerOutput
    case .keep: nil
    }
  }
}

/// Pauses or mutes the media playing on the Mac while a dictation records. After the
/// recording it gets sound back to normal, and resumes the media.
///
/// It resumes only what it paused: media that was not playing when the recording started
/// is left alone. Only the app macOS shows as playing can be paused, so the other apps are
/// muted meanwhile, and heard again with the media. Muting alone mutes every app, and
/// pauses none, and so does lowering, which turns them down.
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
  ///   - muteOthers: Mutes, or unmutes, what the other apps play. The app that was paused
  ///     is among them, with nothing to hear. It is asked to mute again by a dictation
  ///     that starts before the last one unmuted.
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

  /// A dictation starts: pause the media, if any is playing, or mute it, lower it, or
  /// leave it.
  public func pause(_ behavior: MediaBehavior = .pause) {
    // Media about to resume from the last dictation stays as it is for this one.
    resuming?.cancel()
    resuming = nil
    guard behavior != .keep else { return }
    isMuted = true
    muteOthers(true)
    guard behavior == .pause, check == nil, !didPause else { return }
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
      if isMuted {
        isMuted = false
        muteOthers(false)
      }
      guard didPause else { return }
      didPause = false
      send(.play)
    }
  }
}
