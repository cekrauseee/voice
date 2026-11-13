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
  /// The transcription deleted last, while it can still be brought back. Its recording is
  /// kept until then.
  private(set) var deleted: Transcription?

  /// How long a deleted transcription can be brought back.
  static let undoTime = Duration.seconds(5)

  @ObservationIgnored private var forgetting: Task<Void, Never>?
  /// The voiceprints read from the recordings, by transcription and length.
  @ObservationIgnored private var voiceprints: [String: [Double]] = [:]
  @ObservationIgnored private let file: URL
  @ObservationIgnored private let recordings: URL
  @ObservationIgnored private let log = Log("history")
  /// The files are written here, in order, away from the main thread: a dictation that
  /// ends does not wait for the disk.
  @ObservationIgnored private let disk = DispatchQueue(label: "eu.cekrause.voice.history")

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
    let (recordings, file, log) = (recordings, url(of: transcription.id), log)
    disk.async {
      do {
        try FileManager.default.createDirectory(
          at: recordings, withIntermediateDirectories: true)
        try WAV.file(pcm: recording).write(to: file, options: .atomic)
      } catch {
        log.error("recording not saved", ["error": error.localizedDescription])
      }
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

  /// Deletes a transcription. It can be brought back for a moment, with `restore`, and its
  /// recording is deleted after that.
  func remove(_ id: Transcription.ID) {
    guard let transcription = history.transcriptions.first(where: { $0.id == id }) else { return }
    forget()
    history.remove(id)
    deleted = transcription
    forgetting = Task { [weak self] in
      try? await Task.sleep(for: Self.undoTime)
      guard !Task.isCancelled else { return }
      self?.forget()
    }
    save()
  }

  /// Brings back the transcription deleted last, while it can be.
  func restore() {
    guard let transcription = deleted else { return }
    forgetting?.cancel()
    deleted = nil
    history.add(transcription)
    save()
    log.info("restored")
  }

  /// The voiceprint of a transcription's recording, `count` levels long, or nil when its
  /// recording was not kept. It is read once, away from the main thread.
  func voiceprint(of id: Transcription.ID, count: Int) async -> [Double]? {
    let key = "\(id.uuidString)-\(count)"
    if let levels = voiceprints[key] { return levels }
    guard let url = recording(of: id) else { return nil }
    let levels = await Task.detached(priority: .utility) {
      (try? Data(contentsOf: url)).flatMap(WAV.pcm).map { Voiceprint.levels(pcm: $0, count: count) }
    }.value
    voiceprints[key] = levels
    return levels
  }

  /// Deletes for good the transcription deleted last, which can no longer be brought back.
  private func forget() {
    forgetting?.cancel()
    forgetting = nil
    guard let transcription = deleted else { return }
    deleted = nil
    delete([transcription.id])
  }

  /// Deletes the transcriptions that are older than they are kept for, and their recordings.
  func prune(_ retention: Retention) {
    guard let cutoff = retention.cutoff(from: .now) else { return }
    let old = history.prune(before: cutoff)
    guard !old.isEmpty else { return }
    delete(old)
    save()
    log.info("pruned", ["transcriptions": old.count, "retention": retention.rawValue])
  }

  private func url(of id: Transcription.ID) -> URL {
    recordings.appending(path: "\(id.uuidString).wav")
  }

  /// Deletes what can no longer be brought back once the app quits, and waits for the files
  /// still being written.
  func flush() {
    forget()
    disk.sync {}
  }

  private func delete(_ ids: [Transcription.ID]) {
    let files = ids.map(url(of:))
    disk.async {
      for file in files { try? FileManager.default.removeItem(at: file) }
    }
  }

  private func save() {
    let (history, file, log) = (history, file, log)
    disk.async {
      do {
        try FileManager.default.createDirectory(
          at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try history.data.write(to: file, options: .atomic)
      } catch {
        log.error("not saved", ["error": error.localizedDescription])
      }
    }
  }

  nonisolated static var defaultDirectory: URL {
    URL.applicationSupportDirectory.appending(path: AppInfo.identifier)
  }
}
