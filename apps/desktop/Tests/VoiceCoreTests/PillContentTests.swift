import Testing

@testable import VoiceCore

@Suite struct PillContentTests {
  let zoom = MicrophoneUser(bundleId: "us.zoom.xos", name: "Zoom")

  @Test func nothingShowsNothing() {
    #expect(PillContent(dictation: .hidden, meeting: .idle) == .hidden)
  }

  @Test func aMeetingShowsAsItGoes() {
    #expect(PillContent(dictation: .hidden, meeting: .offered(zoom)) == .offer(zoom))
    #expect(PillContent(dictation: .hidden, meeting: .recording) == .meeting(isFinishing: false))
    #expect(PillContent(dictation: .hidden, meeting: .finishing) == .meeting(isFinishing: true))
    #expect(
      PillContent(dictation: .hidden, meeting: .failed(.microphoneUnavailable))
        == .meetingFailed(.microphoneUnavailable))
  }

  @Test func aDictationShowsOverTheMeeting() {
    #expect(PillContent(dictation: .listening, meeting: .recording) == .dictation(.listening))
    #expect(PillContent(dictation: .finishing, meeting: .offered(zoom)) == .dictation(.finishing))
    #expect(
      PillContent(dictation: .failed(.serverUnreachable), meeting: .recording)
        == .dictation(.failed(.serverUnreachable)))
  }

  @Test func onlyAMeetingTakesClicks() {
    #expect(PillContent.offer(zoom).takesClicks)
    #expect(PillContent.meeting(isFinishing: false).takesClicks)
    #expect(PillContent.meeting(isFinishing: true).takesClicks)
    #expect(!PillContent.hidden.takesClicks)
    #expect(!PillContent.dictation(.listening).takesClicks)
    #expect(!PillContent.meetingFailed(.microphoneDenied).takesClicks)
  }
}
