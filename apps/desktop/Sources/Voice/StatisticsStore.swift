import Foundation
import Observation
import VoiceCore

/// How much was dictated and what it cost, kept in the app's Application Support folder,
/// beside the history.
///
/// It holds figures only, never what was dictated, and it is counted as dictations
/// happen: deleting a transcription does not change it.
@MainActor @Observable
final class StatisticsStore {
  private(set) var statistics = Statistics()

  @ObservationIgnored private let file: URL
  @ObservationIgnored private let log = Log("statistics")
  /// The file is written here, in order, away from the main thread: a dictation that ends
  /// does not wait for the disk.
  @ObservationIgnored private let disk = DispatchQueue(label: "eu.cekrause.voice.statistics")

  init(directory: URL = HistoryStore.defaultDirectory) {
    file = directory.appending(path: "statistics.json")
    guard let data = try? Data(contentsOf: file) else { return }
    do {
      statistics = try Statistics(data: data)
      log.info("loaded", ["days": statistics.days.count])
    } catch {
      // Keep what cannot be read, instead of writing over it.
      let unreadable = directory.appending(path: "statistics.unreadable.json")
      try? FileManager.default.removeItem(at: unreadable)
      try? FileManager.default.moveItem(at: file, to: unreadable)
      log.error("unreadable", ["kept": unreadable.lastPathComponent])
    }
  }

  /// Counts a dictation that just ended with its text.
  func record(text: String, seconds: TimeInterval, usage: Usage) {
    statistics.record(text: text, seconds: seconds, usage: usage, at: .now, in: .current)
    let (statistics, file, log) = (statistics, file, log)
    disk.async {
      do {
        try FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try statistics.data.write(to: file, options: .atomic)
      } catch {
        log.error("not saved", ["error": error.localizedDescription])
      }
    }
  }

  /// Waits for the file still being written.
  func flush() {
    disk.sync {}
  }
}
