import Testing
import VoiceCore

@Suite struct VocabularyTests {
  @Test func aTermIsOneLineWithoutSpacesAround() {
    #expect(Vocabulary.term("  Claude ") == "Claude")
    #expect(Vocabulary.term("Visual\nStudio  Code") == "Visual Studio Code")
    #expect(Vocabulary.term(" \t\n") == "")
  }

  @Test func aTermHasNoAngleBrackets() {
    #expect(Vocabulary.term("<Claude>") == "Claude")
    #expect(Vocabulary.term("<>") == "")
  }

  @Test func addingPutsTheTermFirst() {
    #expect(Vocabulary.adding(" Supabase ", to: ["Claude"]) == ["Supabase", "Claude"])
  }

  @Test func addingATermAgainChangesItsSpelling() {
    #expect(
      Vocabulary.adding("iOS", to: ["Claude", "IOS", "Voice"]) == ["iOS", "Claude", "Voice"])
  }

  @Test func addingABlankOrLongTermChangesNothing() {
    #expect(Vocabulary.adding("  ", to: ["Claude"]) == ["Claude"])
    let long = String(repeating: "x", count: Vocabulary.maxLength + 1)
    #expect(Vocabulary.adding(long, to: ["Claude"]) == ["Claude"])
    let longest = String(repeating: "x", count: Vocabulary.maxLength)
    #expect(Vocabulary.adding(longest, to: []) == [longest])
  }
}
