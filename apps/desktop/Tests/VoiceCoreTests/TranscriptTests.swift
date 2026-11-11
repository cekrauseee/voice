import Foundation
import Testing

@testable import VoiceCore

@Suite struct ServerMessageTests {
  @Test func decodesEveryMessage() {
    #expect(ServerMessage(json: #"{"type":"ready"}"#) == .ready)
    #expect(
      ServerMessage(json: #"{"type":"delta","segment":1,"text":"hi"}"#)
        == .delta(segment: 1, text: "hi"))
    #expect(
      ServerMessage(json: #"{"type":"final","segment":0,"text":"hi"}"#)
        == .final(segment: 0, text: "hi"))
    #expect(
      ServerMessage(json: #"{"type":"refined","segment":0,"text":""}"#)
        == .refined(segment: 0, text: ""))
    #expect(ServerMessage(json: #"{"type":"done"}"#) == .done)
    #expect(
      ServerMessage(json: #"{"type":"error","code":"timeout","message":"Transcription timed out"}"#)
        == .error(code: "timeout"))
  }

  @Test func rejectsWhatItDoesNotKnow() {
    #expect(ServerMessage(json: #"{"type":"other"}"#) == nil)
    #expect(ServerMessage(json: #"{"type":"delta","segment":1}"#) == nil)
    #expect(ServerMessage(json: "not json") == nil)
  }
}

@Suite struct TranscriptTests {
  @Test func deltasBuildTheLiveTextAndFinalReplacesIt() {
    var transcript = Transcript()
    #expect(transcript.isEmpty)
    #expect(transcript.apply(.delta(segment: 0, text: "hello")) == nil)
    #expect(transcript.apply(.delta(segment: 0, text: " wor")) == nil)
    #expect(transcript.segments == [.init(id: 0, text: "hello wor")])
    #expect(transcript.apply(.final(segment: 0, text: "hello world")) == nil)
    #expect(transcript.segments == [.init(id: 0, text: "hello world")])
  }

  @Test func refinedTextIsTypedWithASpaceBetweenSegments() {
    var transcript = Transcript()
    #expect(transcript.apply(.refined(segment: 0, text: "Hello.")) == "Hello.")
    #expect(transcript.apply(.refined(segment: 1, text: "")) == nil)
    #expect(transcript.apply(.refined(segment: 2, text: "Again.")) == " Again.")
    #expect(transcript.segments.map(\.isRefined) == [true, true, true])
  }

  @Test func segmentsStayInOrderAndRefinedTextIsNotOverwritten() {
    var transcript = Transcript()
    _ = transcript.apply(.delta(segment: 1, text: "second"))
    _ = transcript.apply(.refined(segment: 0, text: "First."))
    _ = transcript.apply(.delta(segment: 0, text: "late"))
    #expect(
      transcript.segments == [
        .init(id: 0, text: "First.", isRefined: true), .init(id: 1, text: "second"),
      ])
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

  @Test func levelHistoryKeepsTheLatestLevels() {
    var history = LevelHistory(count: 3)
    history.push(0.1)
    history.push(0.2)
    history.push(0.3)
    history.push(0.4)
    #expect(history.levels == [0.2, 0.3, 0.4])
  }
}
