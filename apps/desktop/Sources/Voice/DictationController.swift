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
  @ObservationIgnored private let history: HistoryStore
  @ObservationIgnored private let statistics: StatisticsStore
  @ObservationIgnored private let capture = AudioCapture()
  @ObservationIgnored private let inserter = TextInserter()
  @ObservationIgnored private let media: MediaPause
  /// The dictation the pill shows.
  @ObservationIgnored private var session: DictationSession?
  @ObservationIgnored private var audio: Task<Void, Never>?
  @ObservationIgnored private var dismissal: Task<Void, Never>?
  @ObservationIgnored private var startedAt = ContinuousClock.now

  init(settings: Settings, history: HistoryStore, statistics: StatisticsStore) {
    self.settings = settings
    self.history = history
    self.statistics = statistics
    media = MediaPause(
      isPlaying: MediaControl.isPlaying, send: MediaControl.send,
      soundIsBack: { [capture] in await MediaControl.soundIsBack(microphone: capture.device) })
  }

  var isRecording: Bool {
    pill == .listening
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

    // The pill shows at once. The microphone opens behind it, and the recording does not
    // wait for the server: the audio is sent as it comes, and what comes before the server
    // is ready waits for it on the way.
    self.mode = mode
    transcript = Transcript()
    dismissal?.cancel()
    pill = .listening
    startedAt = .now
    let chunks = capture.start(with: settings.microphone)

    let session = DictationSession(
      server: settings.serverURL, instructions: settings.instructions)
    session.onReady = { [weak self, weak session] in
      guard let self, self.session === session else { return }
      log.debug("ready", ["connect_ms": elapsed])
    }
    session.onChange = { [weak self, weak session] in
      guard let self, let session, self.session === session else { return }
      transcript = session.transcript
    }
    session.onText = { [weak session, inserter, history, statistics, log] text, error in
      if !text.isEmpty {
        inserter.insert(text)
        log.debug("typed", ["chars": text.count])
      }
      guard let session else { return }
      history.add(
        text: text, duration: session.recorded, recording: session.recording,
        failed: error != nil)
      if let usage = session.usage {
        statistics.record(text: text, seconds: session.recorded, usage: usage)
      }
    }
    session.onEnd = { [weak self, weak session] error in
      guard let self, self.session === session else { return }
      finish(error)
    }
    session.start()
    self.session = session
    media.pause()
    log.info("started", ["mode": mode])

    audio = Task {
      var isLive = false
      for await chunk in chunks {
        // Until then the microphone is starting: what it delivers is nothing at all.
        if !isLive, !Level.isZero(chunk.pcm) {
          isLive = true
          log.debug("recording", ["microphone_ms": elapsed])
        }
        session.send(chunk.pcm)
        levels.push(chunk.level)
      }
      guard !Task.isCancelled else { return }
      if self.session === session, pill == .listening {
        // Nobody stopped the recording: the microphone did not start.
        session.cancel()
        finish(.microphoneUnavailable)
      } else {
        // The recording ended and all of it is sent.
        session.stop()
      }
    }
  }

  private func stop() {
    release()
    pill = .finishing
  }

  private func cancel() {
    if isRecording {
      audio?.cancel()
      release()
    }
    session?.cancel()
    session = nil
    pill = .hidden
    log.info("cancelled", ["duration_ms": elapsed])
  }

  /// The dictation the pill shows is over.
  private func finish(_ error: DictationError?) {
    if isRecording {
      audio?.cancel()
      release()
    }
    session = nil
    if let error {
      fail(error)
    } else {
      pill = .hidden
      log.info("finished", ["duration_ms": elapsed, "chars": transcript.text.count])
    }
  }

  /// Closes the microphone and gives the sound back. The media does not wait for the text.
  private func release() {
    capture.stop()
    media.resume()
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
