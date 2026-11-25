import Foundation

/// The text of one dictation: what is heard while the speaker talks, then the refined text.
public struct Transcript: Equatable, Sendable {
  /// The text as it arrived, so that what is new in it can be shown appearing.
  public private(set) var stream = TextStream()
  /// Until the text is refined it is a draft: shown, but not typed.
  public private(set) var isRefined = false
  /// The whitespace the refined text begins with, which separates it from the text before
  /// the cursor. It is typed, but not shown.
  private var separator = ""

  public init() {}

  public var text: String {
    stream.text
  }

  public var isEmpty: Bool {
    text.isEmpty
  }

  /// What to type: the refined text as the server sent it, with the space that joins it to
  /// the text before the cursor. When the dictation failed, the draft, trimmed.
  public var typed: String {
    isRefined ? separator + text : text.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  public mutating func apply(_ message: ServerMessage, at time: Date = .now) {
    switch message {
    case .delta(let text):
      if !isRefined { stream.append(text, at: time) }
    case .done(let text, _):
      let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
      separator = trimmed.isEmpty ? "" : String(text.prefix(while: \.isWhitespace))
      stream = TextStream(trimmed)
      isRefined = true
    case .ready, .error:
      break
    }
  }
}
