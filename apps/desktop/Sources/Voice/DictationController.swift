import AVFoundation
import Observation
import VoiceCore

/// Runs dictations: records while a shortcut says so, and types what comes back.
@MainActor @Observable
final class DictationController {
  private(set) var pill: PillState = .hidden
  private(set) var transcript = Transcript()
  private(set) var mode: RecordingMode = .toggle

  /// The microphone levels, for the waveform.
  @ObservationIgnored let levels = LevelFeed()

  @ObservationIgnored private let log = Log("dictation")
  @ObservationIgnored private let settings: Settings
  @ObservationIgnored private let capture = AudioCapture()
  @ObservationIgnored private let inserter = TextInserter()
  /// The dictation the pill shows.
  @ObservationIgnored private var session: DictationSession?
  @ObservationIgnored private var audio: Task<Void, Never>?
  @ObservationIgnored private var dismissal: Task<Void, Never>?
  @ObservationIgnored private var startedAt = ContinuousClock.now

  init(settings: Settings) {
    self.settings = settings
  }

  var isRecording: Bool {
    pill == .connecting || pill == .listening
  }

  /// Whether a dictation is recording or finishing, so Escape can cancel it.
  var isActive: Bool {
    isRecording || pill == .finishing
  }

  func handle(_ action: HotkeyEngine.Action) {
    switch action {
    case .pushStart:
      start(.push)
    case .pushEnd:
      if isRecording && mode == .push { stop() }
    case .pushCancel:
      if isRecording && mode == .push { cancel() }
    case .toggle:
      if isRecording { stop() } else { start(.toggle) }
    case .cancel:
      cancel()
    }
  }

  private func start(_ mode: RecordingMode) {
    guard !isRecording else { return }
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      break
    case .notDetermined:
      // Answering the system prompt takes a while: a held key is long released by then.
      Task {
        if await AVCaptureDevice.requestAccess(for: .audio), mode == .toggle { start(mode) }
      }
      return
    default:
      return fail(.microphoneDenied)
    }

    let chunks: AsyncStream<AudioChunk>
    do {
      chunks = try capture.start()
    } catch {
      return fail(.microphoneUnavailable)
    }

    let session = DictationSession(
      server: settings.serverURL, instructions: settings.instructions)
    session.onReady = { [weak self, weak session] in
      guard let self, self.session === session, pill == .connecting else { return }
      pill = .listening
      log.debug("ready", ["connect_ms": elapsed])
    }
    session.onChange = { [weak self, weak session] in
      guard let self, let session, self.session === session else { return }
      transcript = session.transcript
    }
    session.onText = { [inserter, log] text in
      inserter.insert(text)
      log.debug("typed", ["chars": text.count])
    }
    session.onEnd = { [weak self, weak session] error in
      guard let self, self.session === session else { return }
      finish(error)
    }
    session.start()

    self.session = session
    self.mode = mode
    transcript = Transcript()
    dismissal?.cancel()
    pill = .connecting
    startedAt = .now
    log.info("started", ["mode": mode])

    audio = Task {
      for await chunk in chunks {
        session.send(chunk.pcm)
        levels.push(chunk.level)
      }
      // The recording ended and all of it is sent.
      if !Task.isCancelled { session.stop() }
    }
  }

  private func stop() {
    capture.stop()
    pill = .finishing
  }

  private func cancel() {
    audio?.cancel()
    capture.stop()
    session?.cancel()
    session = nil
    pill = .hidden
    log.info("cancelled", ["duration_ms": elapsed])
  }

  /// The dictation the pill shows is over.
  private func finish(_ error: DictationError?) {
    if isRecording {
      audio?.cancel()
      capture.stop()
    }
    session = nil
    if let error {
      fail(error)
    } else {
      pill = .hidden
      log.info("finished", ["duration_ms": elapsed, "chars": transcript.text.count])
    }
  }

  /// Milliseconds since the dictation started.
  private var elapsed: Int {
    Int((ContinuousClock.now - startedAt) / .milliseconds(1))
  }

  /// Shows the error for a moment.
  private func fail(_ error: DictationError) {
    log.error("failed", ["reason": error])
    pill = .failed(error)
    dismissal?.cancel()
    dismissal = Task {
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled { pill = .hidden }
    }
  }
}
