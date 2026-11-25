/// The user's dictionary: names and terms they use, spelled the way they write them. Each
/// dictation is told about them, so they are heard and written right.
public enum Vocabulary {
  /// The longest term the server passes on. A longer one is not a word or a name.
  public static let maxLength = 100

  /// A term as the dictionary keeps it: on one line, without spaces around it, and without
  /// `<` or `>`, which the transcription rejects. Empty when nothing is left.
  public static func term(_ text: String) -> String {
    text.filter { $0 != "<" && $0 != ">" }
      .split(whereSeparator: \.isWhitespace)
      .joined(separator: " ")
  }

  /// The terms with one more, first. The same term in another case gives way to it, so
  /// adding a term again is how its spelling changes. Nothing changes for a blank term, or
  /// one too long.
  public static func adding(_ text: String, to terms: [String]) -> [String] {
    let term = term(text)
    guard !term.isEmpty, term.count <= maxLength else { return terms }
    return [term] + terms.filter { $0.caseInsensitiveCompare(term) != .orderedSame }
  }
}
