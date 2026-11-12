import AVFoundation
import Observation
import VoiceCore

/// Records meetings: the microphone and what the Mac plays, transcribed live as two sides.
@MainActor @Observable
final class MeetingController {
  /// The meeting being recorded, as the server transcribes it.
  private(set) var live: LiveMeeting?
  /// Why a meeting could not start, shown for a moment.
  private(set) var failure: MeetingError?
  /// The meeting records the microphone alone: the Mac's sound could not be tapped.
  private(set) var isMissingSystemAudio = false
  /// The recording ended and the last segments are on their way.
  private(set) var isStopping = false

  @ObservationIgnored private let log = Log("meeting")
  @ObservationIgnored private let settings: Settings
  @ObservationIgnored private let store: MeetingStore
  @ObservationIgnored private let microphone = AudioCapture()
  @ObservationIgnored private let system = SystemAudioCapture()
  @ObservationIgnored private var link: MeetingLink?
  @ObservationIgnored private var streams: [Task<Void, Never>] = []
  @ObservationIgnored private var ticker: Task<Void, Never>?
  @ObservationIgnored private var dismissal: Task<Void, Never>?
  @ObservationIgnored private var startedAt = ContinuousClock.now
  /// Bytes of each channel sent so far: where its clock is.
  @ObservationIgnored private var sent: [Channel: Int] = [:]

  /// Bytes of audio a second: 16-bit mono at 24 kHz.
  private static let bytesPerSecond = AudioFormat.sampleRate * 2

  init(settings: Settings, store: MeetingStore) {
    self.settings = settings
    self.store = store
  }

  var isRecording: Bool {
    live != nil && !isStopping
  }

  /// How long the meeting has run, in seconds.
  var elapsed: TimeInterval {
    Double((ContinuousClock.now - startedAt) / .milliseconds(1)) / 1000
  }

  func start() {
    guard live == nil else { return }
    switch AVCaptureDevice.authorizationStatus(for: .audio) {
    case .authorized:
      break
    case .notDetermined:
      Task {
        if await AVCaptureDevice.requestAccess(for: .audio) { start() }
      }
      return
    default:
      return fail(.microphoneDenied)
    }

    let voice = microphone.start(with: settings.microphone)
    var played: AsyncStream<AudioChunk>?
    do {
      played = try system.start()
      isMissingSystemAudio = false
    } catch {
      isMissingSystemAudio = true
      log.error("system audio unavailable", ["error": "\(error)"])
    }

    let meeting = Meeting(date: .now)
    live = LiveMeeting(meeting)
    store.begin(meeting)
    startedAt = .now
    sent = [.me: 0, .others: 0]
    isStopping = false

    let link = MeetingLink(server: settings.serverURL, instructions: settings.instructions)
    link.nextId = { [weak self] in self?.live?.meeting.nextId ?? 1 }
    link.onMessage = { [weak self] message in self?.apply(message) }
    link.onReconnecting = { [weak self] in self?.live?.reconnecting() }
    link.onEnd = { [weak self] in self?.finish() }
    self.link = link
    link.start()

    streams = [Task { await self.stream(voice, as: .me) }]
    if let played { streams.append(Task { await self.stream(played, as: .others) }) }
    ticker = Task { [weak self] in
      var ticks = 0
      while !Task.isCancelled {
        try? await Task.sleep(for: .seconds(1))
        guard let self, !Task.isCancelled, let elapsed = live.map({ _ in self.elapsed }) else {
          return
        }
        live?.update(duration: elapsed)
        ticks += 1
        // Written now and then, so a meeting the app does not get to end keeps its length.
        if ticks % 30 == 0, let live { store.update(live.meeting) }
      }
    }
    log.info("started", ["system_audio": played != nil])
  }

  /// The meeting is over. The recording stops now; the text that is still on its way
  /// comes, then the meeting is kept as it ended.
  func stop() {
    guard live != nil, !isStopping else { return }
    isStopping = true
    microphone.stop()
    system.stop()
    ticker?.cancel()
    link?.stop()
    log.info("stopping", ["duration_ms": Int(elapsed * 1000)])
  }

  /// Sends a channel's audio as it comes, and keeps it.
  private func stream(_ chunks: AsyncStream<AudioChunk>, as channel: Channel) async {
    var isFirst = true
    for await chunk in chunks {
      guard let link else { return }
      if isFirst {
        isFirst = false
        align(channel, before: chunk)
      }
      let time = Double(sent[channel] ?? 0) / Self.bytesPerSecond
      sent[channel, default: 0] += chunk.pcm.count
      link.send(channel, chunk.pcm, at: time)
      store.append(channel, chunk.pcm)
    }
    guard channel == .me, !Task.isCancelled, live != nil, !isStopping else { return }
    if isFirst {
      // Nobody stopped the recording: the microphone did not start.
      abandon(.microphoneUnavailable)
    } else {
      // The microphone went away: the meeting ends with what it heard.
      log.error("microphone lost", ["duration_ms": Int(elapsed * 1000)])
      stop()
    }
  }

  /// A channel's first audio comes a moment after the meeting started, and each channel's
  /// moment differs. Silence stands in for it, so the two clocks agree.
  private func align(_ channel: Channel, before chunk: AudioChunk) {
    guard let link else { return }
    let expected = Int(elapsed * Self.bytesPerSecond) & ~1 - chunk.pcm.count
    guard expected > 0 else { return }
    let silence = Data(count: expected)
    link.send(channel, silence, at: 0)
    store.append(channel, silence)
    sent[channel] = expected
    log.debug(
      "aligned", ["channel": channel, "silence_ms": expected / Int(Self.bytesPerSecond / 1000)])
  }

  private func apply(_ message: MeetingServerMessage) {
    guard live != nil else { return }
    live?.apply(message)
    if case .segment = message, let live { store.update(live.meeting) }
  }

  /// The server is done with the meeting, or will not be heard from.
  private func finish() {
    guard var done = live else { return }
    done.end(duration: elapsed)
    store.end(done.meeting)
    log.info(
      "ended",
      [
        "duration_ms": Int(elapsed * 1000),
        "segments": done.meeting.segments.count,
        "cost": done.meeting.usage.cost,
      ])
    live = nil
    isStopping = false
    link = nil
    streams = []
  }

  /// The meeting could not record: nothing of it is kept.
  private func abandon(_ error: MeetingError) {
    guard let live else { return }
    system.stop()
    ticker?.cancel()
    for stream in streams { stream.cancel() }
    streams = []
    link?.cancel()
    link = nil
    store.discard(live.meeting.id)
    self.live = nil
    fail(error)
  }

  /// Shows the error for a moment.
  private func fail(_ error: MeetingError) {
    log.error("failed", ["reason": error])
    failure = error
    dismissal?.cancel()
    dismissal = Task {
      try? await Task.sleep(for: .seconds(3))
      if !Task.isCancelled { failure = nil }
    }
  }
}
