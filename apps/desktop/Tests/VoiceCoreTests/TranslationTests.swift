import Testing

@testable import VoiceCore

@Suite struct TranslationTests {
  @Test func asksForTheLanguageTypedWhileOn() {
    #expect(Translation.target(isOn: true, language: " Spanish\n") == "Spanish")
  }

  @Test func keepsTheSpeakersLanguageWhenOffOrWithoutALanguage() {
    #expect(Translation.target(isOn: false, language: "Spanish") == "")
    #expect(Translation.target(isOn: true, language: "  ") == "")
  }
}
