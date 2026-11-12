import Testing

@testable import VoiceCore

@Suite struct MicrophoneTests {
  let builtIn = Microphone(id: "BuiltInMicrophoneDevice", name: "MacBook Pro Microphone")
  let headset = Microphone(id: "18-3F-70-C2-C1-AB:input", name: "AirPods")

  @Test func theSystemsComesFirst() {
    let options = Microphone.options(chosen: nil, connected: [builtIn, headset])
    #expect(options.map(\.value) == [nil, builtIn, headset])
    #expect(options.map(\.title) == ["System default", "MacBook Pro Microphone", "AirPods"])
  }

  @Test func aChosenOneThatIsNotConnectedStays() {
    let options = Microphone.options(chosen: headset, connected: [builtIn])
    #expect(options.map(\.value) == [nil, builtIn, headset])
    #expect(options.last?.title == "AirPods (not connected)")
  }

  @Test func aConnectedOneIsListedOnce() {
    let renamed = Microphone(id: headset.id, name: "Old name")
    let options = Microphone.options(chosen: renamed, connected: [builtIn, headset])
    #expect(options.map(\.title) == ["System default", "MacBook Pro Microphone", "AirPods"])
  }
}
