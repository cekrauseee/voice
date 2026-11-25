import Testing

@testable import VoiceCore

@Suite struct RecoveryTests {
  @Test func aDictationThatFinishesTypesItsText() {
    var recovery = DictationRecovery(live: false)
    #expect(recovery.recordingEnded() == nil)
    #expect(recovery.sessionEnded(.done(" Hello."), draft: " Hello.") == .type(" Hello."))
  }

  @Test func aServerThatCannotBeReachedGetsTheRecordingOnceItEnds() {
    var recovery = DictationRecovery(live: false)
    #expect(!recovery.isOffline)
    // Nothing happens while the speaker talks, but the pill says so.
    #expect(recovery.sessionEnded(.disconnected, draft: "") == nil)
    #expect(recovery.isOffline)
    #expect(recovery.recordingEnded() == .resend)
    #expect(!recovery.isOffline)
    #expect(recovery.resent(.done("Hello.")) == .type("Hello."))
  }

  @Test func aRecordingSentAgainThatFailsIsSaved() {
    var recovery = DictationRecovery(live: false)
    _ = recovery.sessionEnded(.disconnected, draft: "")
    _ = recovery.recordingEnded()
    #expect(recovery.resent(.disconnected) == .save(draft: "", offline: true))
    #expect(
      recovery.resent(.failed(code: "unreachable", afterStop: true))
        == .save(draft: "", offline: true))
    #expect(
      recovery.resent(.failed(code: "transcription_failed", afterStop: true))
        == .save(draft: "", offline: false))
  }

  @Test(arguments: [
    ("transcription_failed", false), ("unreachable", true), ("timeout", false),
  ])
  func aWholeRecordingTheServerFailedToTranscribeIsNotSentAgain(code: String, offline: Bool) {
    var recovery = DictationRecovery(live: false)
    #expect(recovery.recordingEnded() == nil)
    #expect(
      recovery.sessionEnded(.failed(code: code, afterStop: true), draft: "")
        == .save(draft: "", offline: offline))
  }

  @Test func aRecordingTheServerMayNotHaveHadWholeIsSentAgain() {
    // An error before the stop: the server did not have the rest.
    var early = DictationRecovery(live: false)
    _ = early.sessionEnded(.failed(code: "transcription_failed", afterStop: false), draft: "")
    #expect(early.recordingEnded() == .resend)

    // A connection that drops after the stop says nothing of what the server did.
    var dropped = DictationRecovery(live: false)
    _ = dropped.recordingEnded()
    #expect(dropped.sessionEnded(.disconnected, draft: "") == .resend)

    // An error that is not about transcribing.
    var rejected = DictationRecovery(live: false)
    _ = rejected.recordingEnded()
    #expect(
      rejected.sessionEnded(.failed(code: "bad_request", afterStop: true), draft: "") == .resend)
  }

  @Test func aLiveDictationThatFailsIsSentAgainAndKeepsItsDraft() {
    var recovery = DictationRecovery(live: true)
    _ = recovery.recordingEnded()
    #expect(
      recovery.sessionEnded(.failed(code: "transcription_failed", afterStop: true), draft: "so the")
        == .resend)
    #expect(recovery.resent(.done("So the plan.")) == .type("So the plan."))
    #expect(recovery.resent(.disconnected) == .save(draft: "so the", offline: true))
  }

  @Test func onlyAMissingConnectionShowsAsOffline() {
    var unreachable = DictationRecovery(live: true)
    _ = unreachable.sessionEnded(.failed(code: "unreachable", afterStop: false), draft: "")
    #expect(unreachable.isOffline)

    var failed = DictationRecovery(live: true)
    _ = failed.sessionEnded(.failed(code: "transcription_failed", afterStop: false), draft: "so")
    #expect(!failed.isOffline)
    #expect(failed.recordingEnded() == .resend)
  }

  @Test func eachEndCountsOnce() {
    var recovery = DictationRecovery(live: false)
    _ = recovery.sessionEnded(.disconnected, draft: "")
    #expect(recovery.sessionEnded(.done("Late."), draft: "Late.") == nil)
    #expect(recovery.recordingEnded() == .resend)
    #expect(recovery.recordingEnded() == nil)
  }

  @Test func failuresSayWhetherTheDictationWasSaved() {
    #expect(DictationError.offline(saved: true).message == "No connection. Saved to History")
    #expect(DictationError.offline(saved: false).message == "No connection")
    #expect(
      DictationError.transcriptionFailed(saved: true).message
        == "Transcription failed. Saved to History")
    #expect(DictationError.transcriptionFailed(saved: false).message == "Transcription failed")
  }

  @Test func theServerSaysWhenItCannotReachOpenAI() {
    let message = ServerMessage(
      json: #"{"type":"error","code":"unreachable","message":"OpenAI could not be reached"}"#)
    #expect(message == .error(code: ServerErrorCode.unreachable))
    #expect(SessionEnd.failed(code: "unreachable", afterStop: true).isOffline)
    #expect(!SessionEnd.failed(code: "timeout", afterStop: true).isOffline)
  }
}
