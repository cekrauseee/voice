/// The text before the cursor in the field a dictation goes into. The server reads it to
/// write the dictation so that it fits: the same names, the same register, and the rest of a
/// sentence left unfinished.
public enum FieldContext {
  /// The most of it that is read, in UTF-16 code units as the Accessibility API counts them:
  /// about a page.
  public static let limit = 2000

  /// How far into a cut text its first word may end, to start the text after it.
  private static let longestWord = 40

  /// The part of the field to read, in UTF-16 offsets: what is before the cursor, up to the
  /// limit.
  public static func window(cursor: Int) -> Range<Int> {
    let cursor = max(cursor, 0)
    return max(cursor - limit, 0)..<cursor
  }

  /// The text before `cursor`, a UTF-16 offset into all of the field's `value`, up to the
  /// limit. Empty when the cursor is not in the value.
  public static func before(_ value: String, cursor: Int) -> String {
    let utf16 = value.utf16
    let window = window(cursor: cursor)
    guard cursor >= 0, cursor <= utf16.count else { return "" }
    let start = utf16.index(utf16.startIndex, offsetBy: window.lowerBound)
    let end = utf16.index(utf16.startIndex, offsetBy: window.upperBound)
    return text(String(value[start..<end]), isCut: window.lowerBound > 0)
  }

  /// The text read from the field's window. When the window cut a word at its start, that
  /// word is dropped. Empty when there is nothing but whitespace.
  public static func text(_ read: String, isCut: Bool) -> String {
    guard !read.allSatisfy(\.isWhitespace) else { return "" }
    guard isCut,
      let space = read.prefix(longestWord).firstIndex(where: \.isWhitespace)
    else { return read }
    return String(read[read.index(after: space)...])
  }
}
