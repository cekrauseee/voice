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
    #expect(transcript.stream.pieces.isEmpty)

    transcript.apply(.delta(text: " late"))
    #expect(transcript.text == "Hello, world.")
  }
}

@Suite struct TextStreamTests {
  private let start = Date(timeIntervalSinceReferenceDate: 0)

  @Test func newPiecesStayApartWhileTheyAppear() {
    var stream = TextStream()
    stream.append("so", at: start)
    stream.append(" the", at: start + 0.1)
    stream.append("", at: start + 0.2)
    #expect(stream.settled == "")
    #expect(stream.pieces.map(\.text) == ["so", " the"])
    #expect(stream.text == "so the")
  }

  @Test func piecesThatHaveAppearedSettleWhenTheNextOneArrives() {
    var stream = TextStream()
    stream.append("so", at: start)
    stream.append(" the", at: start + 0.3)
    stream.append(" plan", at: start + TextStream.appearance)
    #expect(stream.settled == "so")
    #expect(stream.pieces.map(\.text) == [" the", " plan"])
    #expect(stream.text == "so the plan")
  }

  @Test func aPieceAppearsOverTheAppearance() {
    #expect(TextStream.progress(since: start, at: start - 1) == 0)
    #expect(TextStream.progress(since: start, at: start) == 0)
    #expect(TextStream.progress(since: start, at: start + TextStream.appearance / 2) == 0.5)
    #expect(TextStream.progress(since: start, at: start + 10) == 1)
  }
}

@Suite struct WAVTests {
  @Test func wrapsThePCMInAFileAndGivesItBack() {
    let pcm = Data([1, 0, 2, 0, 3, 0])
    let file = WAV.file(pcm: pcm)
    #expect(file.count == 44 + pcm.count)
    #expect(String(decoding: file.prefix(4), as: UTF8.self) == "RIFF")
    #expect(String(decoding: file[8..<16], as: UTF8.self) == "WAVEfmt ")
    // 24 kHz, in little-endian bytes.
    #expect(Array(file[24..<28]) == [0xC0, 0x5D, 0, 0])
    #expect(WAV.pcm(file: file) == pcm)
    #expect(WAV.pcm(file: Data("not a file".utf8)) == nil)

    // A file from another program can have other chunks before the samples.
    let filler = Data("FLLR".utf8) + Data([3, 0, 0, 0, 9, 9, 9, 0])
    let other = file.prefix(36) + filler + file.dropFirst(36)
    #expect(WAV.pcm(file: Data(other)) == pcm)
  }
}

@Suite struct AudioTests {
  @Test func chunkerEmitsFixedChunksAndKeepsTheRest() {
    var chunker = PCMChunker(chunkSamples: 4)
    let pcm = Data([1, 0, 2, 0, 3, 0, 4, 0, 5, 0, 6, 0])
    #expect(chunker.append(pcm).map(\.count) == [8])
    let second = chunker.append(pcm)
    #expect(second.map(\.count) == [8, 8])
    #expect(second[0] == Data([5, 0, 6, 0, 1, 0, 2, 0]))
  }

  @Test func chunkerGivesUpTheRestWhenTheStreamEnds() {
    var chunker = PCMChunker(chunkSamples: 4)
    #expect(chunker.flush() == nil)
    _ = chunker.append(Data([1, 0, 2, 0, 3, 0, 4, 0, 5, 0]))
    #expect(chunker.flush() == Data([5, 0]))
    #expect(chunker.flush() == nil)
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
