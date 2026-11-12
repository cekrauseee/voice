import Foundation
import Observation
import VoiceCore

/// The past transcriptions, kept in a file in the app's Application Support folder.
///
/// The development and production builds have their own folder, so their histories do not
/// mix. The file holds what was dictated: it stays on this Mac and is never logged.
@MainActor @Observable
final class HistoryStore {
  private(set) var history = History()

  @ObservationIgnored private let file: URL
  @ObservationIgnored private let log = Log("history")

  init(directory: URL = HistoryStore.defaultDirectory) {
    file = directory.appending(path: "history.json")
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

  /// Keeps a dictation that was just typed, with what was heard when the text is not it.
  func add(text: String, heard: String? = nil, duration: TimeInterval) {
    let heard = heard?.trimmingCharacters(in: .whitespacesAndNewlines)
    history.add(
      Transcription(
        date: .now, text: text, heard: heard == text || heard == "" ? nil : heard,
        duration: duration))
    save()
  }

  func remove(_ id: Transcription.ID) {
    history.remove(id)
    save()
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
