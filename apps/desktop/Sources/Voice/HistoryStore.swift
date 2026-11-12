import Foundation
import Observation
import VoiceCore

/// The past transcriptions and their recordings, kept in the app's Application Support
/// folder: the transcriptions in one file, and each recording in a file of its own.
///
/// The development and production builds have their own folder, so their histories do not
/// mix. The files hold what was dictated: they stay on this Mac and are never logged.
@MainActor @Observable
final class HistoryStore {
  private(set) var history = History()

  @ObservationIgnored private let file: URL
  @ObservationIgnored private let recordings: URL
  @ObservationIgnored private let log = Log("history")

  /// A failed dictation shorter than this, in seconds, holds nothing to try again.
  private static let shortestKept = 0.5

  init(directory: URL = HistoryStore.defaultDirectory) {
    file = directory.appending(path: "history.json")
    recordings = directory.appending(path: "recordings")
    guard let data = try? Data(contentsOf: file) else { return }
    do {
      history = try History(data: data)
      log.info("loaded", ["transcriptions": history.transcriptions.count])
    } catch {
      // Keep what cannot be read, instead of writing over it.
      let unreadable = directory.appending(path: "history.unreadable.json")
      try? FileManager.default.removeItem(at: unreadable)
      try? FileManager.default.moveItem(at: file, to: unreadable)
      log.error("unreadable", ["kept": unreadable.lastPathComponent])
    }
  }

  /// Keeps a dictation that just ended, with its recording. One that failed is kept even
  /// without words, to be tried again.
  func add(text: String, duration: TimeInterval, recording: Data, failed: Bool) {
    let transcription = Transcription(
      date: .now, text: text, duration: duration, failed: failed)
    guard !failed || !text.isEmpty || duration >= Self.shortestKept,
      history.add(transcription)
    else { return }
    do {
      try FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
      try WAV.file(pcm: recording).write(to: url(of: transcription.id), options: .atomic)
    } catch {
      log.error("recording not saved", ["error": error.localizedDescription])
    }
    save()
  }

  /// The recording of a transcription, if it was kept.
  func recording(of id: Transcription.ID) -> URL? {
    let url = url(of: id)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  /// Gives a transcription that failed the text it got on another try.
  func resolve(_ id: Transcription.ID, text: String) {
    history.resolve(id, text: text)
    save()
  }

  func remove(_ id: Transcription.ID) {
    history.remove(id)
    try? FileManager.default.removeItem(at: url(of: id))
    save()
  }

  /// Deletes the transcriptions that are older than they are kept for, and their recordings.
  func prune(_ retention: Retention) {
    guard let cutoff = retention.cutoff(from: .now) else { return }
    let old = history.prune(before: cutoff)
    guard !old.isEmpty else { return }
    for id in old { try? FileManager.default.removeItem(at: url(of: id)) }
    save()
    log.info("pruned", ["transcriptions": old.count, "retention": retention.rawValue])
  }

  private func url(of id: Transcription.ID) -> URL {
    recordings.appending(path: "\(id.uuidString).wav")
  }

  private func save() {
    do {
      try FileManager.default.createDirectory(
        at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
      try history.data.write(to: file, options: .atomic)
    } catch {
      log.error("not saved", ["error": error.localizedDescription])
    }
  }

  nonisolated static var defaultDirectory: URL {
    URL.applicationSupportDirectory.appending(path: AppInfo.identifier)
  }
}
