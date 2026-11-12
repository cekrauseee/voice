import Foundation
import Observation
import VoiceCore

/// Transcribes again the dictations that failed, from their recordings.
@MainActor @Observable
final class Retry {
  /// The transcriptions being tried again.
  private(set) var running: Set<Transcription.ID> = []

  @ObservationIgnored private let settings: Settings
  @ObservationIgnored private let history: HistoryStore
  @ObservationIgnored private let statistics: StatisticsStore
  @ObservationIgnored private let log = Log("retry")

  init(settings: Settings, history: HistoryStore, statistics: StatisticsStore) {
    self.settings = settings
    self.history = history
    self.statistics = statistics
  }

  /// Sends the recording of a transcription to the server again. When text comes back,
  /// the transcription gets it. When it fails again, it stays as it was.
  func start(_ id: Transcription.ID) {
    guard !running.contains(id), let url = history.recording(of: id),
      let pcm = (try? Data(contentsOf: url)).flatMap(WAV.pcm)
    else { return }
    running.insert(id)
    log.info("started", ["seconds": Int(Double(pcm.count) / 2 / AudioFormat.sampleRate)])

    let session = DictationSession(
      server: settings.serverURL, instructions: settings.instructions)
    session.onText = { [weak session, history, statistics, log] text, error in
      if let session, let usage = session.usage {
        statistics.record(text: text, seconds: session.recorded, usage: usage)
      }
      if error == nil, !text.isEmpty {
        history.resolve(id, text: text)
        log.info("finished", ["chars": text.count])
      } else {
        log.error("failed", ["reason": error.map { "\($0)" } ?? "no words"])
      }
    }
    // The session is held until it is over.
    session.onEnd = { [weak self] _ in
      self?.running.remove(id)
      _ = session
    }
    session.start()
    // The server takes the recording as fast as it comes, not at the pace it was spoken.
    let chunk = AudioFormat.chunkSamples * MemoryLayout<Int16>.size
    for offset in stride(from: 0, to: pcm.count, by: chunk) {
      session.send(
        pcm.subdata(
          in: (pcm.startIndex + offset)..<min(pcm.startIndex + offset + chunk, pcm.endIndex)))
    }
    session.stop()
  }
}
