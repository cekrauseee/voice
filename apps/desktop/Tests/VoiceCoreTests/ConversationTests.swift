import Foundation
import Testing

@testable import VoiceCore

@Suite struct ConversationTests {
  private let profile = ProfileUpdate(
    instructions: "Mantenha os termos de Git em inglês.", transcriptionPrompt: "Desenvolvedor.",
    languages: ["pt", "en"], terms: ["merge"])

  private func done(_ reply: String, profile: ProfileUpdate? = nil, addTerms: [String] = [])
    -> ProfileTurnMessage
  {
    .done(reply: reply, profile: profile, addTerms: addTerms, usage: Usage())
  }

  @Test func theAgentOpensAtOnce() {
    let conversation = Conversation(opening: "O que você faz?")
    #expect(conversation.messages.map(\.text) == ["O que você faz?"])
    #expect(conversation.state == .idle)
    #expect(conversation.canTalk)
    #expect(!conversation.hasStarted)
    #expect(
      conversation.history == [
        Conversation.Entry(role: "assistant", text: "O que você faz?", profile: nil)
      ])
  }

  @Test func aTurnFillsInWhatIsHeardThenTheReply() {
    var conversation = Conversation(opening: "O que você faz?")
    conversation.listen()
    #expect(conversation.state == .listening)
    #expect(!conversation.canTalk)
    #expect(conversation.apply(.ready) == nil)
    _ = conversation.apply(.delta(text: "sou"))
    _ = conversation.apply(.delta(text: " dev"))
    #expect(conversation.messages.last?.text == "sou dev")
    #expect(conversation.messages.last?.role == .user)

    conversation.think()
    #expect(conversation.state == .thinking)
    _ = conversation.apply(.heard(text: "Sou dev."))
    _ = conversation.apply(.reply(text: "Do que"))
    #expect(conversation.state == .replying)
    _ = conversation.apply(.reply(text: " você fala?"))
    #expect(
      conversation.messages.map(\.text) == ["O que você faz?", "Sou dev.", "Do que você fala?"])

    let outcome = conversation.apply(done("Do que você fala?", profile: profile, addTerms: ["Git"]))
    #expect(outcome == Conversation.Outcome(profile: profile, addTerms: ["Git"]))
    #expect(conversation.state == .idle)
    #expect(conversation.hasStarted)
    #expect(
      conversation.history == [
        Conversation.Entry(role: "assistant", text: "O que você faz?", profile: nil),
        Conversation.Entry(role: "user", text: "Sou dev.", profile: nil),
        Conversation.Entry(role: "assistant", text: "Do que você fala?", profile: profile),
      ])
  }

  @Test func theWholeReplyStandsForWhatWasStreamed() {
    var conversation = Conversation(opening: "Oi")
    conversation.listen()
    _ = conversation.apply(.heard(text: "Oi."))
    _ = conversation.apply(.reply(text: "Ol"))
    _ = conversation.apply(done("Olá!"))
    #expect(conversation.messages.last?.text == "Olá!")
    #expect(conversation.messages.count == 3)
  }

  @Test func aTurnWhereNothingWasHeardLeavesOnlyTheFailure() {
    var conversation = Conversation(opening: "Oi")
    conversation.listen()
    _ = conversation.apply(.heard(text: ""))
    #expect(conversation.apply(done("")) == nil)
    #expect(conversation.messages.map(\.text) == ["Oi"])
    #expect(conversation.state == .failed(.notHeard))
    #expect(conversation.canTalk)
  }

  @Test func anAgentThatFailsLeavesOnlyTheFailure() {
    var conversation = Conversation(opening: "Oi")
    conversation.listen()
    _ = conversation.apply(.heard(text: "Sou dev."))
    _ = conversation.apply(.reply(text: "Ent"))
    #expect(conversation.apply(.error(code: "agent_failed")) == nil)
    #expect(conversation.messages.map(\.text) == ["Oi"])
    #expect(conversation.state == .failed(.notAnswered))

    conversation.listen()
    _ = conversation.apply(.error(code: "transcription_failed"))
    #expect(conversation.state == .failed(.notTranscribed))

    // Without a connection to OpenAI, it says so.
    conversation.listen()
    _ = conversation.apply(.error(code: "unreachable"))
    #expect(conversation.state == .failed(.unreachable))
  }

  @Test func aCancelledTurnLeavesNothing() {
    var conversation = Conversation(opening: "Oi")
    conversation.listen()
    _ = conversation.apply(.delta(text: "sou"))
    conversation.cancel()
    #expect(conversation.messages.map(\.text) == ["Oi"])
    #expect(conversation.state == .idle)
  }

  @Test func theUserCannotSpeakWhileTheAgentAnswers() {
    var conversation = Conversation(opening: "Oi")
    conversation.listen()
    conversation.think()
    conversation.listen()
    #expect(conversation.messages.count == 2)
    #expect(conversation.state == .thinking)
  }

  @Test func aFailureBeforeTheTurnSaysWhy() {
    var conversation = Conversation(opening: "Oi")
    conversation.fail(Conversation.Failure(.microphoneDenied))
    #expect(conversation.state == .failed(.microphoneDenied))
    #expect(Conversation.Failure.microphoneDenied.message == "Microphone access needed")
    #expect(Conversation.Failure(.offline(saved: false)) == .unreachable)
    #expect(Conversation.Failure(.transcriptionFailed(saved: false)) == .notTranscribed)
  }

  @Test func notesAreNotSentToTheAgent() {
    var conversation = Conversation(opening: "Oi")
    conversation.note("Added 2 words to your dictionary")
    #expect(conversation.messages.last?.role == .note)
    #expect(conversation.history.count == 1)
  }

  @Test func whatTheUserSaysIsNeverKept() throws {
    var conversation = Conversation(opening: "Oi")
    conversation.listen()
    _ = conversation.apply(.heard(text: "Meu segredo é merge."))
    let outcome = conversation.apply(done("Anotado.", profile: profile))

    // The conversation cannot be written anywhere.
    #expect(!((conversation as Any) is any Encodable))
    // What is kept is the profile the agent wrote, and it holds none of what was said.
    let kept = try #require(outcome?.profile).self
    let data = try JSONEncoder().encode(Profile().applying(kept, vocabulary: []))
    let json = String(decoding: data, as: UTF8.self)
    #expect(!json.contains("segredo"))
    #expect(!json.contains("Anotado"))
  }

  @Test func theOpeningIsInTheLanguageOfTheMacOrEnglish() {
    #expect(
      Conversation.opening(language: "pt-BR", hasProfile: false)
        == "Oi! Me conta sobre você: o que você faz e o que costuma ditar?")
    #expect(
      Conversation.opening(language: "pt-BR", hasProfile: true)
        == "Esse é o seu perfil. O que você quer mudar?")
    #expect(
      Conversation.opening(language: "en-US", hasProfile: false)
        == "Hi! Tell me about yourself: what do you do, and what do you usually dictate?")
    #expect(
      Conversation.opening(language: "ja-JP", hasProfile: true)
        == "This is your profile. What would you like to change?")
    #expect(Conversation.opening(language: nil, hasProfile: false).hasPrefix("Hi!"))
  }
}

@Suite struct ShortcutTargetTests {
  @Test func theProfilePageInFrontTalksToTheAgent() {
    #expect(
      ShortcutTarget.forRecording(
        isAppActive: true, isWindowKey: true, showsProfile: true, canTalk: true) == .conversation)
  }

  @Test func whileTheAgentAnswersTheShortcutDoesNothingThere() {
    #expect(
      ShortcutTarget.forRecording(
        isAppActive: true, isWindowKey: true, showsProfile: true, canTalk: false) == .none)
  }

  @Test func anywhereElseItDictates() {
    for (isAppActive, isWindowKey, showsProfile) in [
      (false, true, true), (true, false, true), (true, true, false), (false, false, false),
    ] {
      #expect(
        ShortcutTarget.forRecording(
          isAppActive: isAppActive, isWindowKey: isWindowKey, showsProfile: showsProfile,
          canTalk: true) == .dictation)
    }
  }

  @Test func onlyADictationIsTypedKeptAndCounted() {
    #expect(ShortcutTarget.dictation.keepsRecording)
    #expect(!ShortcutTarget.conversation.keepsRecording)
  }
}
