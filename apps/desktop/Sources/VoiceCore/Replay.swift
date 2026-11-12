import Foundation

/// The audio of a channel that the server has not confirmed, kept to be sent again on
/// another connection.
///
/// A segment confirms the audio before its end. Audio that makes no segment is confirmed
/// by time: while connected, what is older than the longest turn has been heard and found
/// empty. While disconnected nothing is confirmed, so the tail grows with the outage.
public struct ReplayTail: Equatable, Sendable {
  private struct Chunk: Equatable, Sendable {
    let start: TimeInterval
    let pcm: Data

    var end: TimeInterval {
      start + Double(pcm.count / MemoryLayout<Int16>.size) / AudioFormat.sampleRate
    }
  }

  /// How far back audio can still be in a turn that is not a segment yet: the longest
  /// turn, its pause, and the time its transcript takes.
  public static let margin: TimeInterval = 40

  /// Up to where, in seconds, the server has the channel.
  public private(set) var confirmed: TimeInterval
  private var chunks: [Chunk] = []

  public init(confirmed: TimeInterval = 0) {
    self.confirmed = confirmed
  }

  /// Keeps a chunk that was sent, or that waits to be, with the time it starts at. While
  /// connected, the audio older than the margin before it is taken as confirmed.
  public mutating func append(_ pcm: Data, at start: TimeInterval, isConnected: Bool) {
    chunks.append(Chunk(start: start, pcm: pcm))
    if isConnected { confirm(upTo: start - Self.margin) }
  }

  /// The server reached a time on the channel: the audio before it is confirmed.
  public mutating func confirm(upTo time: TimeInterval) {
    guard time > confirmed else { return }
    confirmed = time
    chunks.removeAll { $0.end <= time }
  }

  /// The audio to send on another connection: the chunks not confirmed, and the time the
  /// first of them starts at, where the channel's clock resumes.
  public var replay: (offset: TimeInterval, chunks: [Data]) {
    (chunks.first?.start ?? confirmed, chunks.map(\.pcm))
  }

  /// How much audio waits, in seconds.
  public var seconds: TimeInterval {
    guard let first = chunks.first, let last = chunks.last else { return 0 }
    return last.end - first.start
  }
}

/// How long to wait before connecting again: longer after each failure, up to a limit.
public enum Backoff {
  public static let longest: Duration = .seconds(30)

  /// The wait after a number of failures in a row, from 1.
  public static func delay(afterFailures failures: Int) -> Duration {
    let seconds = 1 << min(max(failures, 1) - 1, 5)
    return min(.seconds(seconds), longest)
  }
}
