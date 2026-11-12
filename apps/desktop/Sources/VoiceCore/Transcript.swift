import Foundation

/// The text of one dictation: what is heard while the speaker talks, then the refined text.
public struct Transcript: Equatable, Sendable {
  /// The text as it arrived, so that what is new in it can be shown appearing.
  public private(set) var stream = TextStream()
  /// Until the text is refined it is a draft: shown, but not typed.
  public private(set) var isRefined = false
  /// The draft the refined text was made from.
  public private(set) var heard: String?

  public init() {}

  public var text: String {
    stream.text
  }

  public var isEmpty: Bool {
    text.isEmpty
  }

  public mutating func apply(_ message: ServerMessage, at time: Date = .now) {
    switch message {
    case .delta(let text):
      if !isRefined { stream.append(text, at: time) }
    case .done(let text):
      heard = self.text
      stream = TextStream(text)
      isRefined = true
    case .ready, .error:
      break
    }
  }
}
