import Testing

@testable import VoiceCore

private typealias Headset = CallQualityExit.Headset

private let inCallQuality = Headset(
  isInCallQuality: true, isMicrophone: true, microphoneIsOpen: false)
private let normal = Headset(isInCallQuality: false, isMicrophone: true, microphoneIsOpen: false)

@Suite struct CallQualityExitTests {
  @Test func asksOnceAndIsDoneWhenTheHeadsetIsOut() {
    var exit = CallQualityExit()
    #expect(exit.step(inCallQuality, after: .zero) == .ask)
    #expect(exit.step(inCallQuality, after: .milliseconds(25)) == .wait)
    #expect(exit.step(inCallQuality, after: .milliseconds(200)) == .wait)
    #expect(exit.step(normal, after: .milliseconds(225)) == .done)
  }

  @Test func asksAgainWhenTheHeadsetDidNotTakeTheRequest() {
    var exit = CallQualityExit()
    #expect(exit.step(inCallQuality, after: .zero) == .ask)
    exit.askFailed()
    #expect(exit.step(inCallQuality, after: .milliseconds(25)) == .ask)
    #expect(exit.step(inCallQuality, after: .milliseconds(50)) == .wait)
  }

  @Test func waitsForThisRecordingsMicrophoneToClose() {
    var exit = CallQualityExit()
    var closing = inCallQuality
    closing.microphoneIsOpen = true
    #expect(exit.step(closing, after: .zero) == .wait)
    #expect(exit.step(inCallQuality, after: .milliseconds(25)) == .ask)
  }

  @Test func leavesTheHeadsetAloneWhileAnotherAppRecords() {
    var exit = CallQualityExit()
    var recording = inCallQuality
    recording.microphoneIsOpen = true
    #expect(exit.step(recording, after: .zero) == .wait)
    #expect(exit.step(recording, after: .milliseconds(500)) == .done)
  }

  @Test func aShortRecordingWaitsForTheHeadsetToArriveInCallQuality() {
    var exit = CallQualityExit()
    #expect(exit.step(normal, after: .zero) == .wait)
    #expect(exit.step(normal, after: .milliseconds(200)) == .wait)
    #expect(exit.step(inCallQuality, after: .milliseconds(300)) == .ask)
    #expect(exit.step(normal, after: .milliseconds(450)) == .done)
  }

  @Test func aHeadsetThatNeverArrivesIsDoneAfterTheSettlingTime() {
    var exit = CallQualityExit()
    #expect(exit.step(normal, after: .milliseconds(475)) == .wait)
    #expect(exit.step(normal, after: .milliseconds(500)) == .done)
  }

  @Test func soundThatDoesNotPlayOnTheMicrophonesHeadsetIsDoneAtOnce() {
    var exit = CallQualityExit()
    let speakers = Headset(isInCallQuality: false, isMicrophone: false, microphoneIsOpen: true)
    #expect(exit.step(speakers, after: .zero) == .done)
  }
}
