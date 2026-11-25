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
    let seconds = Double(pcm.count / MemoryLayout<Int16>.size) / AudioFormat.sampleRate
    log.info("started", ["seconds": Int(seconds)])

    // Without the field's text: the field focused now is not the one dictated into, and the
    // text is not typed anywhere.
    // Not live: nothing shows the words of a retry as they are heard.
    let session = DictationSession(
      server: settings.serverURL, profile: settings.profile,
      translateTo: settings.translateTo, vocabulary: settings.vocabulary)
    session.onEnd = { [weak self, weak session] end in
      self?.running.remove(id)
      guard let self else { return }
      if case .done(let text) = end, !text.isEmpty {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let usage = session?.usage {
          statistics.record(text: text, seconds: seconds, usage: usage)
        }
        history.resolve(id, text: text)
        log.info("finished", ["chars": text.count])
      } else {
        log.error("failed", ["reason": end.reason])
      }
    }
    // The session holds itself until it is over.
    session.start()
    session.send(recording: pcm)
  }
}
