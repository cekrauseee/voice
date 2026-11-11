import Testing

@testable import VoiceCore

@Suite struct OnboardingTests {
  @Test func stepsAreTakenInOrder() {
    var onboarding = Onboarding(accessibility: false, microphone: false)
    #expect(onboarding.current == .accessibility)
    #expect(onboarding.state(of: .accessibility) == .current)
    #expect(onboarding.state(of: .microphone) == .upcoming)
    #expect(!onboarding.canFinish)

    onboarding.accessibility = true
    #expect(onboarding.state(of: .accessibility) == .done)
    #expect(onboarding.current == .microphone)

    onboarding.microphone = true
    #expect(onboarding.current == .tryIt)
    #expect(onboarding.canFinish)

    onboarding.hasDictated = true
    #expect(onboarding.current == nil)
  }

  @Test func aStepDoneOutOfOrderStaysDone() {
    let onboarding = Onboarding(accessibility: false, microphone: true)
    #expect(onboarding.state(of: .microphone) == .done)
    #expect(onboarding.current == .accessibility)
    #expect(onboarding.state(of: .tryIt) == .upcoming)
  }
}

@Suite struct LogLineTests {
  @Test func fieldsFollowTheMessage() {
    #expect(logLine("shortcuts ready") == "shortcuts ready")
    #expect(
      logLine("dictation finished", ["mode": RecordingMode.push, "segments": 2, "ok": true])
        == "dictation finished mode=push segments=2 ok=true")
  }

  @Test func valuesThatWouldNotReadBackAreQuoted() {
    #expect(
      logLine("failed", ["reason": "no \"mic\" found", "note": ""])
        == #"failed reason="no \"mic\" found" note="""#)
    #expect(logLine("failed", ["a": "x=y"]) == #"failed a="x=y""#)
  }
}
