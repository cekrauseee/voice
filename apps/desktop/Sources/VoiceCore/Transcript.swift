/// The text of one dictation, segment by segment.
public struct Transcript: Equatable, Sendable {
  public struct Segment: Equatable, Identifiable, Sendable {
    public let id: Int
    public var text = ""
    /// Refined text is final and already typed. Until then the text can still change.
    public var isRefined = false
  }

  public private(set) var segments: [Segment] = []
  private var hasTyped = false

  public init() {}

  public var isEmpty: Bool {
    segments.allSatisfy { $0.text.isEmpty }
  }

  /// Applies a server message. Returns the text to type into the focused field, if any.
  public mutating func apply(_ message: ServerMessage) -> String? {
    switch message {
    case .delta(let segment, let text):
      update(segment) { $0.text += text }
    case .final(let segment, let text):
      update(segment) { $0.text = text }
    case .refined(let segment, let text):
      update(segment) {
        $0.text = text
        $0.isRefined = true
      }
      guard !text.isEmpty else { return nil }
      defer { hasTyped = true }
      return hasTyped ? " " + text : text
    case .ready, .done, .error:
      break
    }
    return nil
  }

  private mutating func update(_ id: Int, _ change: (inout Segment) -> Void) {
    let index = segments.firstIndex { $0.id >= id } ?? segments.endIndex
    if index == segments.endIndex || segments[index].id != id {
      segments.insert(Segment(id: id), at: index)
    }
    guard !segments[index].isRefined else { return }
    change(&segments[index])
  }
}
