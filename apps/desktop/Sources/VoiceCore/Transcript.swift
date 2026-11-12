/// The text of one dictation: what is heard while the speaker talks, then the refined text.
public struct Transcript: Equatable, Sendable {
  public private(set) var text = ""
  /// Until the text is refined it is a draft: shown, but not typed.
  public private(set) var isRefined = false

  public init() {}

  public var isEmpty: Bool {
    text.isEmpty
  }

  public mutating func apply(_ message: ServerMessage) {
    switch message {
    case .delta(let text):
      if !isRefined { self.text += text }
    case .done(let text):
      self.text = text
      isRefined = true
    case .ready, .error:
      break
    }
  }
}
