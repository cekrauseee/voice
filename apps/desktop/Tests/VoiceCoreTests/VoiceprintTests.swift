import Foundation
import Testing

@testable import VoiceCore

@Suite struct VoiceprintTests {
  /// 16-bit mono PCM, one sample after the other.
  private func pcm(_ samples: [Int16]) -> Data {
    samples.withUnsafeBufferPointer { Data(buffer: $0) }
  }

  @Test func hasOneLevelForEachStretch() {
    let levels = Voiceprint.levels(pcm: pcm(Array(repeating: 3000, count: 2400)), count: 18)
    #expect(levels.count == 18)
  }

  @Test func silenceIsFlat() {
    let levels = Voiceprint.levels(pcm: pcm(Array(repeating: 0, count: 2400)), count: 6)
    #expect(levels == Array(repeating: 0, count: 6))
  }

  @Test func theLoudestStretchIsOne() {
    let quiet = Array(repeating: Int16(300), count: 1200)
    let loud = Array(repeating: Int16(6000), count: 1200)
    let levels = Voiceprint.levels(pcm: pcm(quiet + loud), count: 2)
    #expect(levels[1] == 1)
    #expect(levels[0] < levels[1])
    #expect(levels[0] > 0)
  }

  @Test func followsTheRecordingInOrder() {
    let loud = Array(repeating: Int16(8000), count: 800)
    let silent = Array(repeating: Int16(0), count: 800)
    let levels = Voiceprint.levels(pcm: pcm(loud + silent + loud), count: 3)
    #expect(levels == [1, 0, 1])
  }

  @Test func aRecordingShorterThanTheStretchesLeavesTheRestFlat() {
    let levels = Voiceprint.levels(pcm: pcm([8000, 8000]), count: 4)
    #expect(levels.count == 4)
    #expect(levels.filter { $0 > 0 }.count == 2)
  }

  @Test func noStretchesIsNothing() {
    #expect(Voiceprint.levels(pcm: pcm([8000]), count: 0).isEmpty)
  }
}
