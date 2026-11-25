import Foundation

/// What the models are told about the user, as the agent wrote it in a conversation with
/// them. Each dictation is sent the instructions, the transcription prompt, and the
/// languages. It is all the app keeps of the conversation.
public struct Profile: Codable, Equatable, Sendable {
  /// How dictations are written: what the refinement is told.
  public var instructions: String
  /// What the user's recordings are like, for the transcription.
  public var transcriptionPrompt: String
  /// The languages the user speaks, as ISO 639-1 codes.
  public var languages: [String]
  /// Names and terms suggested for the dictionary, until the user adds them.
  public var suggestions: [String]

  public init(
    instructions: String = "", transcriptionPrompt: String = "", languages: [String] = [],
    suggestions: [String] = []
  ) {
    self.instructions = instructions
    self.transcriptionPrompt = transcriptionPrompt
    self.languages = languages
    self.suggestions = suggestions
  }

  /// The most terms suggested at once.
  public static let maxSuggestions = 20

  /// Whether there is nothing in it.
  public var isEmpty: Bool {
    self == Profile()
  }

  /// Whether it tells the models anything: suggestions alone do not.
  public var isWritten: Bool {
    !instructions.isEmpty || !transcriptionPrompt.isEmpty || !languages.isEmpty
  }

  /// The profile kept in the user defaults. Before profiles, the user set instructions on
  /// their own: those become the profile's instructions, so nothing set is lost.
  public static func stored(_ data: Data?, instructions: String?) -> Profile {
    if let data, let profile = try? JSONDecoder().decode(Profile.self, from: data) {
      return profile
    }
    return Profile(instructions: instructions ?? "")
  }

  /// The profile the agent wrote, in place of this one. The terms suggested are its terms,
  /// without those in the dictionary.
  public func applying(_ update: ProfileUpdate, vocabulary: [String]) -> Profile {
    Profile(
      instructions: update.instructions, transcriptionPrompt: update.transcriptionPrompt,
      languages: update.languages,
      suggestions: Self.suggestions(update.terms, excluding: vocabulary))
  }

  /// The profile as the agent is given it: the suggestions are the ones still to answer.
  public func update(vocabulary: [String]) -> ProfileUpdate {
    ProfileUpdate(
      instructions: instructions, transcriptionPrompt: transcriptionPrompt,
      languages: languages, terms: pendingSuggestions(vocabulary: vocabulary))
  }

  /// The terms to suggest: as the dictionary keeps them, each once, without the ones it has.
  public static func suggestions(_ terms: [String], excluding vocabulary: [String]) -> [String] {
    var suggestions: [String] = []
    for term in terms.map(Vocabulary.term) {
      guard !term.isEmpty, term.count <= Vocabulary.maxLength,
        !(vocabulary + suggestions).contains(where: {
          $0.caseInsensitiveCompare(term) == .orderedSame
        })
      else { continue }
      suggestions.append(term)
      if suggestions.count == maxSuggestions { break }
    }
    return suggestions
  }

  /// The suggestions still to answer: a term added to the dictionary otherwise is not one.
  public func pendingSuggestions(vocabulary: [String]) -> [String] {
    Self.suggestions(suggestions, excluding: vocabulary)
  }

  /// The names of the languages, in English, like the rest of the app.
  public var languageNames: [String] {
    let english = Locale(identifier: "en_US")
    return languages.map { english.localizedString(forLanguageCode: $0) ?? $0 }
  }

  enum CodingKeys: String, CodingKey {
    case instructions, transcriptionPrompt, languages, suggestions
  }

  /// A part missing from what was kept is empty, so a profile kept by an earlier version
  /// still reads.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    instructions = try container.decodeIfPresent(String.self, forKey: .instructions) ?? ""
    transcriptionPrompt =
      try container.decodeIfPresent(String.self, forKey: .transcriptionPrompt) ?? ""
    languages = try container.decodeIfPresent([String].self, forKey: .languages) ?? []
    suggestions = try container.decodeIfPresent([String].self, forKey: .suggestions) ?? []
  }
}

extension Vocabulary {
  /// The terms with others added, first and in their order.
  public static func adding(contentsOf texts: [String], to terms: [String]) -> [String] {
    texts.reversed().reduce(terms) { terms, text in adding(text, to: terms) }
  }
}
