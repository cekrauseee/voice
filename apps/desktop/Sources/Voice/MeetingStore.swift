import Foundation
import Observation
import VoiceCore

/// The meetings, kept in `meetings/` in the app's Application Support folder: each one in
/// a JSON file of its own, with a WAV file for each of its channels.
///
/// A meeting is written as it goes, so that what was transcribed survives the app. The
/// files hold what was said: they stay on this Mac and are never logged.
@MainActor @Observable
final class MeetingStore {
  /// Newest first.
  private(set) var meetings: [Meeting] = []

  @ObservationIgnored private let directory: URL
  @ObservationIgnored private let log = Log("meetings")
  /// The recordings of the meeting being recorded.
  @ObservationIgnored private var writers: [Channel: WAVWriter] = [:]
  @ObservationIgnored private var pendingWrite: Task<Void, Never>?

  init(directory: URL = HistoryStore.defaultDirectory) {
    self.directory = directory.appending(path: "meetings")
    load()
  }

  private func load() {
    guard
      let files = try? FileManager.default.contentsOfDirectory(
        at: directory, includingPropertiesForKeys: nil)
    else { return }
    var loaded: [Meeting] = []
    for file in files where file.pathExtension == "json" {
      guard let data = try? Data(contentsOf: file) else { continue }
      do {
        var meeting = try Meeting(data: data)
        if meeting.isLive {
          // The app did not get to end it. Its recordings are closed where they stopped.
          meeting.isLive = false
          for channel in Channel.allCases { WAVWriter.complete(url(of: meeting.id, channel)) }
          write(meeting)
        }
        loaded.append(meeting)
      } catch {
        log.error("unreadable", ["file": file.lastPathComponent])
      }
    }
    meetings = loaded.sorted { $0.date > $1.date }
    log.info("loaded", ["meetings": meetings.count])
  }

  /// A meeting starts: it is kept from now on, and its recordings open.
  func begin(_ meeting: Meeting) {
    meetings.insert(meeting, at: 0)
    write(meeting)
    for channel in Channel.allCases {
      do {
        writers[channel] = try WAVWriter(url: url(of: meeting.id, channel))
      } catch {
        log.error(
          "recording not opened", ["channel": channel, "error": error.localizedDescription])
      }
    }
  }

  /// Audio of the meeting being recorded.
  func append(_ channel: Channel, _ pcm: Data) {
    writers[channel]?.append(pcm)
  }

  /// The meeting being recorded changed. It is written a moment later, once for a burst.
  func update(_ meeting: Meeting) {
    replace(meeting)
    pendingWrite?.cancel()
    pendingWrite = Task { [weak self] in
      try? await Task.sleep(for: .seconds(1))
      guard !Task.isCancelled else { return }
      self?.write(meeting)
    }
  }

  /// The meeting is over: it is written as it ended, and its recordings are completed.
  func end(_ meeting: Meeting) {
    replace(meeting)
    pendingWrite?.cancel()
    write(meeting)
    for writer in writers.values { writer.close() }
    writers = [:]
  }

  /// The meeting being recorded is dropped: its recordings close, and nothing of it is kept.
  func discard(_ id: Meeting.ID) {
    pendingWrite?.cancel()
    for writer in writers.values { writer.close() }
    writers = [:]
    remove(id)
  }

  /// The recording of a channel of a meeting, if it was kept.
  func recording(of id: Meeting.ID, _ channel: Channel) -> URL? {
    let url = url(of: id, channel)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
  }

  func remove(_ id: Meeting.ID) {
    meetings.removeAll { $0.id == id }
    try? FileManager.default.removeItem(at: file(of: id))
    for channel in Channel.allCases {
      try? FileManager.default.removeItem(at: url(of: id, channel))
    }
  }

  /// Deletes the meetings that are older than they are kept for, and their recordings.
  func prune(_ retention: Retention) {
    guard let cutoff = retention.cutoff(from: .now) else { return }
    let old = meetings.filter { $0.date < cutoff && !$0.isLive }.map(\.id)
    guard !old.isEmpty else { return }
    for id in old { remove(id) }
    log.info("pruned", ["meetings": old.count, "retention": retention.rawValue])
  }

  private func replace(_ meeting: Meeting) {
    if let index = meetings.firstIndex(where: { $0.id == meeting.id }) {
      meetings[index] = meeting
    } else {
      meetings.insert(meeting, at: 0)
    }
  }

  private func file(of id: Meeting.ID) -> URL {
    directory.appending(path: "\(id.uuidString).json")
  }

  private func url(of id: Meeting.ID, _ channel: Channel) -> URL {
    directory.appending(path: "\(id.uuidString)-\(channel.rawValue).wav")
  }

  private func write(_ meeting: Meeting) {
    do {
      try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
      try meeting.data.write(to: file(of: meeting.id), options: .atomic)
    } catch {
      log.error("not saved", ["error": error.localizedDescription])
    }
  }
}

/// Writes a WAV file as its samples come, and completes its header at the end.
final class WAVWriter {
  private let handle: FileHandle
  private var bytes = 0
  private var pending = Data()

  /// Samples are written to disk in runs of about this many bytes: two seconds of audio.
  private static let run = 96_000

  init(url: URL) throws {
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try WAV.header(pcmBytes: 0).write(to: url)
    handle = try FileHandle(forWritingTo: url)
    try handle.seekToEnd()
  }

  func append(_ pcm: Data) {
    pending.append(pcm)
    bytes += pcm.count
    if pending.count >= Self.run { flush() }
  }

  /// Writes the rest and the header with the final count.
  func close() {
    flush()
    try? handle.seek(toOffset: 0)
    try? handle.write(contentsOf: WAV.header(pcmBytes: bytes))
    try? handle.close()
  }

  /// Completes the header of a file that was left open, from its length.
  static func complete(_ url: URL) {
    guard let handle = try? FileHandle(forUpdating: url), let end = try? handle.seekToEnd()
    else { return }
    let header = WAV.header(pcmBytes: 0)
    guard end >= UInt64(header.count) else { return }
    try? handle.seek(toOffset: 0)
    try? handle.write(contentsOf: WAV.header(pcmBytes: Int(end) - header.count))
    try? handle.close()
  }

  private func flush() {
    guard !pending.isEmpty else { return }
    try? handle.write(contentsOf: pending)
    pending = Data()
  }
}
