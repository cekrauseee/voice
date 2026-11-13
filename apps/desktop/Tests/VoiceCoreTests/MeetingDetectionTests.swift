import Foundation
import Testing

@testable import VoiceCore

@Suite struct MeetingDetectionTests {
  private let zoom = MicrophoneUser(bundleId: "us.zoom.xos", name: "Zoom")
  private let chrome = MicrophoneUser(bundleId: "com.google.Chrome.helper", name: "Chrome")
  private let memos = MicrophoneUser(bundleId: "com.apple.VoiceMemos", name: "Voice Memos")
  private let start = Date(timeIntervalSince1970: 1_700_000_000)

  @Test func promptsOnceACallAppHasHeldTheMicrophoneForAMoment() {
    var detection = MeetingDetection()
    let changed1 = detection.observe([zoom], isRecording: false, at: start)
    #expect(!changed1)
    #expect(detection.prompt == nil)
    let changed2 = detection.observe([zoom], isRecording: false, at: start + 2)
    #expect(!changed2)
    let changed3 = detection.observe([zoom], isRecording: false, at: start + 3)
    #expect(changed3)
    #expect(detection.prompt == zoom)

    // Letting the microphone go takes the prompt away. Taking it again starts over.
    let changed4 = detection.observe([], isRecording: false, at: start + 4)
    #expect(changed4)
    #expect(detection.prompt == nil)
    detection.observe([zoom], isRecording: false, at: start + 5)
    #expect(detection.prompt == nil)
    detection.observe([zoom], isRecording: false, at: start + 8)
    #expect(detection.prompt == zoom)
  }

  @Test func ignoresAppsThatDoNotHoldCalls() {
    var detection = MeetingDetection()
    detection.observe([memos], isRecording: false, at: start)
    detection.observe([memos], isRecording: false, at: start + 10)
    #expect(detection.prompt == nil)
  }

  @Test func aDismissedAppIsNotAskedAboutUntilItTakesTheMicrophoneAgain() {
    var detection = MeetingDetection()
    detection.observe([zoom], isRecording: false, at: start)
    detection.observe([zoom], isRecording: false, at: start + 3)
    detection.dismiss()
    #expect(detection.prompt == nil)
    detection.observe([zoom], isRecording: false, at: start + 60)
    #expect(detection.prompt == nil)

    detection.observe([], isRecording: false, at: start + 61)
    detection.observe([zoom], isRecording: false, at: start + 62)
    detection.observe([zoom], isRecording: false, at: start + 65)
    #expect(detection.prompt == zoom)
  }

  @Test func aRecordedCallIsNotAskedAboutAgainWhenTheRecordingStops() {
    var detection = MeetingDetection()
    detection.observe([zoom], isRecording: false, at: start)
    detection.observe([zoom, chrome], isRecording: false, at: start + 1)
    detection.observe([zoom, chrome], isRecording: false, at: start + 3)
    #expect(detection.prompt == zoom)
    detection.recording()
    detection.observe([zoom, chrome], isRecording: true, at: start + 10)
    #expect(detection.prompt == nil)
    detection.observe([zoom, chrome], isRecording: false, at: start + 600)
    #expect(detection.prompt == nil)
  }

  @Test func theAppThatHasHeldTheMicrophoneLongestIsTheOneAsked() {
    var detection = MeetingDetection()
    detection.observe([chrome], isRecording: false, at: start)
    detection.observe([chrome, zoom], isRecording: false, at: start + 1)
    detection.observe([chrome, zoom], isRecording: false, at: start + 5)
    #expect(detection.prompt == chrome)
    detection.dismiss()
    detection.observe([chrome, zoom], isRecording: false, at: start + 5)
    #expect(detection.prompt == zoom)
  }

  @Test func namesTheAppsThatHoldCalls() {
    #expect(MeetingApps.name(of: "us.zoom.xos") == "Zoom")
    #expect(MeetingApps.name(of: "com.google.Chrome.helper.renderer") == "Chrome")
    #expect(MeetingApps.name(of: "com.apple.VoiceMemos") == nil)
  }
}
