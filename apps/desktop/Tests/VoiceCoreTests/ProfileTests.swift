import Foundation
import Testing
import VoiceCore

@Suite struct ProfileTests {
  private let update = ProfileUpdate(
    instructions: "Keep Git terms in English.",
    transcriptionPrompt: "A developer speaking Portuguese about Git.",
    languages: ["pt", "en"],
    terms: ["merge", "Claude", " pull\nrequest ", "Merge", "", "<rebase>"])

  @Test func theInstructionsSetBeforeProfilesBecomeTheProfiles() {
    #expect(
      Profile.stored(nil, instructions: "Write formally.")
        == Profile(instructions: "Write formally."))
    #expect(Profile.stored(nil, instructions: nil) == Profile())
  }

  @Test func aKeptProfileWinsOverTheInstructionsSetBefore() throws {
    let kept = Profile(instructions: "Be brief.", languages: ["pt"])
    let data = try JSONEncoder().encode(kept)
    #expect(Profile.stored(data, instructions: "Write formally.") == kept)
  }

  @Test func aProfileThatDoesNotReadKeepsTheInstructionsSetBefore() {
    #expect(
      Profile.stored(Data("nonsense".utf8), instructions: "Write formally.")
        == Profile(instructions: "Write formally."))
  }

  @Test func aProfileMissingPartsStillReads() {
    let data = Data(#"{"instructions":"Be brief.","about":"Old field"}"#.utf8)
    #expect(Profile.stored(data, instructions: nil) == Profile(instructions: "Be brief."))
  }

  @Test func whatTheAgentWroteReplacesTheProfile() {
    let profile = Profile(instructions: "Old.", suggestions: ["Swift"])
    let applied = profile.applying(update, vocabulary: ["Claude"])
    #expect(applied.instructions == "Keep Git terms in English.")
    #expect(applied.transcriptionPrompt == "A developer speaking Portuguese about Git.")
    #expect(applied.languages == ["pt", "en"])
    // Cleaned up, each once, without the dictionary's.
    #expect(applied.suggestions == ["merge", "pull request", "rebase"])
    #expect(applied.isWritten)
  }

  @Test func theAgentIsGivenTheSuggestionsStillToAnswer() {
    let profile = Profile(
      instructions: "Be brief.", transcriptionPrompt: "A developer.", languages: ["pt"],
      suggestions: ["merge", "rebase"])
    #expect(
      profile.update(vocabulary: ["Rebase"])
        == ProfileUpdate(
          instructions: "Be brief.", transcriptionPrompt: "A developer.", languages: ["pt"],
          terms: ["merge"]))
  }

  @Test func suggestionsAreFewEnoughToRead() {
    let terms = (1...30).map { "term\($0)" }
    #expect(Profile.suggestions(terms, excluding: []).count == Profile.maxSuggestions)
  }

  @Test func acceptedTermsGoFirstInTheirOrder() {
    #expect(
      Vocabulary.adding(contentsOf: ["merge", "rebase"], to: ["Claude", "MERGE"])
        == ["merge", "rebase", "Claude"])
  }

  @Test func suggestionsAloneAreNotAProfile() {
    #expect(Profile().isEmpty)
    #expect(!Profile(suggestions: ["merge"]).isWritten)
    #expect(!Profile(suggestions: ["merge"]).isEmpty)
    #expect(Profile(languages: ["pt"]).isWritten)
  }

  @Test func languagesHaveTheirEnglishNames() {
    #expect(Profile(languages: ["pt", "en"]).languageNames == ["Portuguese", "English"])
  }
}

@Suite struct ProfileTurnMessageTests {
  @Test func readsEveryMessage() {
    #expect(ProfileTurnMessage(json: #"{"type":"ready"}"#) == .ready)
    #expect(ProfileTurnMessage(json: #"{"type":"delta","text":"sou"}"#) == .delta(text: "sou"))
    #expect(
      ProfileTurnMessage(json: #"{"type":"heard","text":"Sou dev."}"#) == .heard(text: "Sou dev."))
    #expect(ProfileTurnMessage(json: #"{"type":"reply","text":"Certo"}"#) == .reply(text: "Certo"))
    #expect(
      ProfileTurnMessage(
        json:
          #"{"type":"done","reply":"Certo.","profile":{"instructions":"Be brief.","transcription_prompt":"A developer.","languages":["pt"],"terms":["merge"]},"add_terms":["Git"],"usage":{"audio_seconds":2,"input_tokens":10,"output_tokens":5,"cost":0.01}}"#
      )
        == .done(
          reply: "Certo.",
          profile: ProfileUpdate(
            instructions: "Be brief.", transcriptionPrompt: "A developer.", languages: ["pt"],
            terms: ["merge"]),
          addTerms: ["Git"],
          usage: Usage(audioSeconds: 2, inputTokens: 10, outputTokens: 5, cost: 0.01)))
    #expect(
      ProfileTurnMessage(json: #"{"type":"done","reply":"Certo.","profile":null,"add_terms":[]}"#)
        == .done(reply: "Certo.", profile: nil, addTerms: [], usage: Usage()))
    #expect(
      ProfileTurnMessage(json: #"{"type":"error","code":"agent_failed","message":"No"}"#)
        == .error(code: "agent_failed"))
    #expect(ProfileTurnMessage(json: #"{"type":"reply"}"#) == nil)
    #expect(ProfileTurnMessage(json: "nonsense") == nil)
  }

  @Test func startCarriesTheConversationAndTheProfile() {
    var conversation = Conversation(opening: "O que você faz?")
    conversation.listen()
    _ = conversation.apply(.heard(text: "Sou dev."))
    _ = conversation.apply(
      .done(
        reply: "Certo.", profile: ProfileUpdate(instructions: "Be brief."), addTerms: [],
        usage: Usage()))
    conversation.note("Added 1 word to your dictionary")
    #expect(
      ProfileTurnMessage.start(
        history: conversation.history,
        profile: ProfileUpdate(instructions: "Be brief.", languages: ["pt"]),
        vocabulary: ["Claude"])
        == #"{"history":[{"role":"assistant","text":"O que você faz?"},{"role":"user","text":"Sou dev."},{"profile":{"instructions":"Be brief.","languages":[],"terms":[],"transcription_prompt":""},"role":"assistant","text":"Certo."}],"profile":{"instructions":"Be brief.","languages":["pt"],"terms":[],"transcription_prompt":""},"type":"start","vocabulary":["Claude"]}"#
    )
  }
}
