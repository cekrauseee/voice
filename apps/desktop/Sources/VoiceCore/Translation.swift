/// Writing a dictation in another language than the one spoken.
public enum Translation {
  /// The language to ask the server for: the one typed, while translation is on. Empty
  /// when the dictation keeps the speaker's language.
  public static func target(isOn: Bool, language: String) -> String {
    isOn ? language.trimmingCharacters(in: .whitespacesAndNewlines) : ""
  }
}
