import Foundation
import Testing

@testable import VoiceCore

@Suite struct ServerMessageTests {
  @Test func decodesEveryMessage() {
    #expect(ServerMessage(json: #"{"type":"ready"}"#) == .ready)
    #expect(ServerMessage(json: #"{"type":"delta","text":"hi"}"#) == .delta(text: "hi"))
    #expect(ServerMessage(json: #"{"type":"done","text":""}"#) == .done(text: ""))
    #expect(
      ServerMessage(json: #"{"type":"error","code":"timeout","message":"Transcription timed out"}"#)
        == .error(code: "timeout"))
  }

  @Test func rejectsWhatItDoesNotKnow() {
    #expect(ServerMessage(json: #"{"type":"other"}"#) == nil)
    #expect(ServerMessage(json: #"{"type":"delta"}"#) == nil)
    #expect(ServerMessage(json: #"{"type":"done"}"#) == nil)
    #expect(ServerMessage(json: "not json") == nil)
  }
}

@Suite struct ClientMessageTests {
  @Test func encodesEveryMessage() {
    #expect(ClientMessage.stop.json == #"{"type":"stop"}"#)
    #expect(
      ClientMessage.start(instructions: "").json == #"{"instructions":"","type":"start"}"#)
    #expect(
      ClientMessage.start(instructions: "Say \"hi\".\nUse a/b.").json
        == #"{"instructions":"Say \"hi\".\nUse a/b.","type":"start"}"#)
  }
}

@Suite struct TranscriptTests {
  @Test func deltasBuildTheDraft() {
    var transcript = Transcript()
    #expect(transcript.isEmpty)
    transcript.apply(.ready)
    transcript.apply(.delta(text: "hello"))
    transcript.apply(.delta(text: " wor"))
    #expect(transcript.text == "hello wor")
    #expect(!transcript.isRefined)
  }

  @Test func doneReplacesTheDraftWithTheRefinedText() {
    var transcript = Transcript()
    transcript.apply(.delta(text: "hello world"))
    transcript.apply(.done(text: "Hello, world."))
    #expect(transcript.text == "Hello, world.")
    #expect(transcript.isRefined)

    transcript.apply(.delta(text: " late"))
    #expect(transcript.text == "Hello, world.")
  }
}

@Suite struct AudioTests {
  @Test func chunkerEmitsFixedChunksAndKeepsTheRest() {
    var chunker = PCMChunker(chunkSamples: 4)
    let samples: [Int16] = [1, 2, 3, 4, 5, 6]
    let first = samples.withUnsafeBufferPointer { chunker.append($0) }
    #expect(first.map(\.count) == [8])
    let second = samples.withUnsafeBufferPointer { chunker.append($0) }
    #expect(second.map(\.count) == [8, 8])
    #expect(second[0] == Data([5, 0, 6, 0, 1, 0, 2, 0]))
  }

  @Test func levelRisesWithLoudness() {
    func pcm(_ amplitude: Int16) -> Data {
      [Int16](repeating: amplitude, count: 100).withUnsafeBufferPointer { Data(buffer: $0) }
    }
    #expect(Level.normalized(pcm(0)) == 0)
    #expect(Level.normalized(pcm(50)) == 0)
    #expect(Level.normalized(pcm(1000)) > 0.3)
    #expect(Level.normalized(pcm(1000)) < Level.normalized(pcm(5000)))
    #expect(Level.normalized(pcm(20_000)) == 1)
  }
}
