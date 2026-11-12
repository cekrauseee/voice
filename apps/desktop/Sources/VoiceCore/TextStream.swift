import Foundation

/// A text that arrives piece by piece, kept so that each new piece can appear on its own.
///
/// Only the pieces that are still appearing are kept apart. The text before them is one
/// run, so however long the text gets, only its last moments are in pieces.
public struct TextStream: Equatable, Sendable {
  public struct Piece: Equatable, Sendable {
    public let text: String
    public let arrivedAt: Date
  }

  /// How long a piece takes to appear, in seconds.
  public static let appearance = 0.45

  /// The text that has appeared.
  public private(set) var settled: String
  /// The pieces still appearing, oldest first.
  public private(set) var pieces: [Piece] = []

  public init(_ settled: String = "") {
    self.settled = settled
  }

  public var text: String {
    pieces.reduce(into: settled) { $0 += $1.text }
  }

  /// Adds a piece that arrived at a time. The pieces that have appeared by then settle.
  public mutating func append(_ text: String, at time: Date) {
    guard !text.isEmpty else { return }
    let appeared = pieces.prefix { Self.progress(since: $0.arrivedAt, at: time) >= 1 }
    for piece in appeared { settled += piece.text }
    pieces.removeFirst(appeared.count)
    pieces.append(Piece(text: text, arrivedAt: time))
  }

  /// How far into its appearance a piece is at a time, from 0 to 1.
  public static func progress(since arrival: Date, at time: Date) -> Double {
    min(max(time.timeIntervalSince(arrival) / appearance, 0), 1)
  }
}
