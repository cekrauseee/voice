import AVFoundation
import Observation
import VoiceCore

/// Runs dictations: records while a shortcut says so, and types what comes back.
@MainActor @Observable
final class DictationController {
  private(set) var pill: PillState = .hidden
  private(set) var transcript = Transcript()
  private(set) var mode: RecordingMode = .toggle
  /// Whether the dictation records without a connection. It is sent once it ends.
  private(set) var isOffline = false

  /// The microphone levels, for the waveform.
  @ObservationIgnored let levels = LevelFeed()

  @ObservationIgnored private let log = Log("dictation")
  @ObservationIgnored private let settings: Settings
  @ObservationIgnored private let history: HistoryStore
  @ObservationIgnored private let statistics: StatisticsStore
  @ObservationIgnored private let capture = AudioCapture()
  @ObservationIgnored private let inserter = TextInserter()
  @ObservationIgnored private let media: MediaPause
  @ObservationIgnored private let others = OtherAudio()
  /// The dictation the pill shows.
  @ObservationIgnored private var dictation: Dictation?
  @ObservationIgnored private var audio: Task<Void, Never>?
  @ObservationIgnored private var dismissal: Task<Void, Never>?
  /// Says the microphone is starting, when it does not deliver sound right away.
  @ObservationIgnored private var warming: Task<Void, Never>?
  @ObservationIgnored private var startedAt = ContinuousClock.now

  init(
    settings: Settings, permissions: Permissions, history: HistoryStore,
    statistics: StatisticsStore
  ) {
    self.settings = settings
    self.history = history
    self.statistics = statistics
    media = MediaPause(
      isPlaying: MediaControl.isPlaying, send: MediaControl.send,
      soundIsBack: { [capture, others] in
        others.recordingEnded()
        await MediaControl.soundIsBack(microphone: capture.device) {
          others.leavingCallQuality()
        }
      },
      muteOthers: { [others, settings, permissions] muted in
        guard muted else { return others.unmute() }
        let appsAllowed = permissions.systemAudio == .allowed
        let muting = settings.mediaBehavior.muting(
          appsAllowed: appsAllowed, lowered: settings.loweredVolume)
        if let muting { others.mute(muting, appsAllowed: appsAllowed) }
      })
  }

  var isRecording: Bool {
    pill.isRecording
  }

  var allowsShiftToStop: Bool {
    isRecording && dictation?.delivery.enterBehavior == .withShift
  }

  /// Whether a dictation is recording or finishing, so Escape can cancel it.
  var isActive: Bool {
    isRecording || pill == .finishing
  }

  func handle(_ action: HotkeyEngine.Action, shiftHeld: Bool = false) {
    switch action {
    case .pushStart:
      start(.push)
    case .pushEnd:
      if isRecording && mode == .push { stop(shiftHeld: shiftHeld) }
    case .pushLock:
      if isRecording && mode == .push {
        mode = .toggle
      } else {
        handle(.toggle, shiftHeld: shiftHeld)
      }
    case .pushCancel:
      if isRecording && mode == .push { cancel() }
    case .toggle:
      if isRecording { stop(shiftHeld: shiftHeld) } else { start(.toggle) }
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
    // is ready waits for it on the way. Should the server not be there, the recording goes
    // on all the same, and is sent once it ends.
    self.mode = mode
    transcript = Transcript()
    isOffline = false
    dismissal?.cancel()
    pill = .listening
    startedAt = .now
    let chunks = capture.start(with: settings.microphone)
    // Read once the microphone is opening, so the recording does not wait for it.
    var context = ""
    if settings.usesFieldText {
      let reading = ContinuousClock.now
      context = FocusedField.textBeforeCursor()
      log.debug("field read", ["field_ms": Int((ContinuousClock.now - reading) / .milliseconds(1))])
    }

    let dictation = Dictation(
      server: settings.serverURL, instructions: settings.instructions,
      translateTo: settings.translateTo, vocabulary: settings.vocabulary, context: context,
      live: settings.transcribesLive,
      delivery: DictationDelivery(
        keepOnClipboard: settings.keepOnClipboard, enterBehavior: settings.enterBehavior))
    let session = dictation.session(live: dictation.recovery.live)
    session.onReady = { [weak self] in
      guard let self, self.dictation === dictation else { return }
      log.debug("ready", ["connect_ms": elapsed])
    }
    session.onChange = { [weak self, weak session] in
      guard let self, let session, self.dictation === dictation else { return }
      transcript = session.transcript
    }
    session.onEnd = { [weak self, weak session] end in
      dictation.usage = session?.usage
      self?.sessionEnded(dictation, end, draft: session?.transcript.typed ?? "")
    }
    dictation.sending = session
    session.start()
    self.dictation = dictation
    media.pause(settings.mediaBehavior)
    log.info("started", ["mode": mode, "context_chars": context.count])

    // The Mac's own microphone delivers sound in about a tenth of a second, a Bluetooth
    // headset in about a second, while it switches to call quality. When it takes longer
    // than a moment, the pill says the microphone is starting, until the sound comes.
    warming = Task {
      try? await Task.sleep(for: .milliseconds(250))
      if !Task.isCancelled, self.dictation === dictation, pill == .listening { pill = .starting }
    }

    audio = Task {
      var isLive = false
      for await chunk in chunks {
        // Until then the microphone is starting: what it delivers is nothing at all.
        if !isLive, !Level.isZero(chunk.pcm) {
          isLive = true
          warming?.cancel()
          if pill == .starting { pill = .listening }
          log.debug("recording", ["microphone_ms": elapsed])
        }
        dictation.recording.append(chunk.pcm)
        dictation.sending?.send(chunk.pcm)
        levels.push(chunk.level)
      }
      guard !Task.isCancelled else { return }
      if self.dictation === dictation, pill.isRecording {
        // Nobody stopped the recording: the microphone did not start.
        dictation.sending?.cancel()
        dictation.sending = nil
        self.dictation = nil
        finish(.microphoneUnavailable)
      } else {
        // The recording ended, all of it captured.
        recordingEnded(dictation)
      }
    }
  }

  private func stop(shiftHeld: Bool) {
    dictation?.delivery.stop(shiftHeld: shiftHeld)
    release()
    pill = .finishing
  }

  private func cancel() {
    if isRecording {
      audio?.cancel()
      release()
    }
    dictation?.sending?.cancel()
    dictation?.sending = nil
    dictation = nil
    isOffline = false
    pill = .hidden
    log.info("cancelled", ["duration_ms": elapsed])
  }

  /// A session of the dictation ended. While the speaker talks, the recording goes on.
  private func sessionEnded(_ dictation: Dictation, _ end: SessionEnd, draft: String) {
    dictation.sending = nil
    if case .done = end {
    } else {
      log.warn(
        "session failed", ["reason": end.reason, "recording": !dictation.recovery.hasRecorded])
    }
    let step = dictation.recovery.sessionEnded(end, draft: draft)
    if self.dictation === dictation { isOffline = dictation.recovery.isOffline }
    if let step { take(step, for: dictation) }
  }

  /// The recording ended: the dictation gets its text, or waits for it.
  private func recordingEnded(_ dictation: Dictation) {
    if self.dictation === dictation { isOffline = false }
    if let step = dictation.recovery.recordingEnded() {
      take(step, for: dictation)
    } else {
      // All of the recording is sent. The text follows.
      dictation.sending?.stop()
    }
  }

  private func take(_ step: DictationStep, for dictation: Dictation) {
    switch step {
    case .type(let text):
      deliver(text, of: dictation, failed: false)
      conclude(dictation, nil, chars: text.count)
    case .resend:
      // Once, not live, as fast as the server takes it.
      log.info("resending", ["seconds": Int(dictation.recorded)])
      let session = dictation.session(live: false)
      session.onEnd = { [weak self, weak session] end in
        dictation.usage = session?.usage
        dictation.sending = nil
        if case .done = end {
        } else {
          self?.log.warn("resend failed", ["reason": end.reason])
        }
        self?.take(dictation.recovery.resent(end), for: dictation)
      }
      dictation.sending = session
      session.start()
      session.send(recording: dictation.recording)
    case .save(let draft, let offline):
      // What was heard is typed, and all of it is kept to be tried again.
      let saved = deliver(draft, of: dictation, failed: true)
      conclude(
        dictation,
        offline ? .offline(saved: saved) : .transcriptionFailed(saved: saved),
        chars: draft.count)
    }
  }

  /// Types the text, and keeps the dictation in the history. Returns whether it was kept.
  @discardableResult
  private func deliver(_ text: String, of dictation: Dictation, failed: Bool) -> Bool {
    let delivery = dictation.delivery
    if !text.isEmpty {
      inserter.insert(
        text, keepOnClipboard: delivery.keepOnClipboard,
        pressEnter: delivery.pressesEnter(text: text, failed: failed))
      log.debug("typed", ["chars": text.count])
    }
    // Kept without the space that joined it to the field.
    let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
    let kept = history.add(
      text: text, duration: dictation.recorded, recording: dictation.recording, failed: failed)
    if !failed, let usage = dictation.usage {
      statistics.record(text: text, seconds: dictation.recorded, usage: usage)
    }
    return kept
  }

  /// The dictation is over. The pill shows it, unless another dictation has started since.
  private func conclude(_ dictation: Dictation, _ error: DictationError?, chars: Int) {
    guard self.dictation === dictation else { return }
    self.dictation = nil
    if let error {
      fail(error)
    } else {
      pill = .hidden
      log.info("finished", ["duration_ms": elapsed, "chars": chars])
    }
  }

  /// The dictation the pill shows is over before its recording ended.
  private func finish(_ error: DictationError) {
    if isRecording {
      audio?.cancel()
      release()
    }
    fail(error)
  }

  /// Closes the microphone and gives the sound back. The media does not wait for the text.
  private func release() {
    warming?.cancel()
    capture.stop()
    media.resume()
  }

  /// Milliseconds since the dictation started.
  private var elapsed: Int {
    Int((ContinuousClock.now - startedAt) / .milliseconds(1))
  }

  /// Shows the error for a moment.
  private func fail(_ error: DictationError) {
    log.error("failed", ["reason": error.reason])
    pill = .failed(error)
    dismissal?.cancel()
    dismissal = Task {
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled { pill = .hidden }
    }
  }
}

/// One dictation, from the shortcut to its text: what it was started with, its recording, and
/// the session sending it.
@MainActor
private final class Dictation {
  let delivery: DictationDelivery
  var recovery: DictationRecovery
  /// The audio recorded: 16-bit mono PCM at 24 kHz.
  var recording = Data()
  /// The session that has the dictation now: its own, then the one that sends it again.
  var sending: DictationSession?
  /// What the dictation used on the server, once it has its text.
  var usage: Usage?

  private let server: URL
  private let instructions: String
  private let translateTo: String
  private let vocabulary: [String]
  /// The text before the cursor in the field the text goes into, if known.
  private let context: String

  init(
    server: URL, instructions: String, translateTo: String, vocabulary: [String],
    context: String, live: Bool, delivery: DictationDelivery
  ) {
    self.server = server
    self.instructions = instructions
    self.translateTo = translateTo
    self.vocabulary = vocabulary
    self.context = context
    self.delivery = delivery
    recovery = DictationRecovery(live: live)
  }

  /// How long the recording is, in seconds.
  var recorded: TimeInterval {
    Double(recording.count / MemoryLayout<Int16>.size) / AudioFormat.sampleRate
  }

  /// A session with the server for this dictation, with what it was started with.
  func session(live: Bool) -> DictationSession {
    DictationSession(
      server: server, instructions: instructions, translateTo: translateTo,
      vocabulary: vocabulary, context: context, live: live)
  }
}
