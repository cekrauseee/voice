/// How the header of the transcriptions docks into the title bar as the list scrolls.
///
/// The header follows the scroll exactly, so it never moves on its own while the list is
/// scrolled. Only a scroll that ends with the header halfway settles it, at whichever end
/// is nearer.
public struct HeaderDock: Equatable, Sendable {
  /// How far the list scrolls while the header docks, in points: the height of the header.
  public let range: Double

  public init(range: Double) {
    self.range = max(range, 1)
  }

  /// How docked the header is when the list is scrolled this far: from 0, all of the
  /// header showing, to 1, docked in the title bar.
  public func progress(at offset: Double) -> Double {
    min(max(offset / range, 0), 1)
  }

  /// Where a scroll that would end at `offset` ends instead, or nil when it ends there.
  ///
  /// A header left halfway goes to the nearer end. A list too short to dock the header
  /// all the way, scrolling at most `maximum`, is left where it is.
  public func settle(_ offset: Double, maximum: Double) -> Double? {
    guard offset > 0, offset < range, maximum >= range else { return nil }
    return offset < range / 2 ? 0 : range
  }

  /// A value between where it is with the header showing and where it is docked.
  public static func blend(_ start: Double, _ end: Double, by progress: Double) -> Double {
    start + (end - start) * progress
  }
}
