import Testing

@testable import VoiceCore

@Suite struct WaveformMotionTests {
  private let frame = 1.0 / 60

  /// Runs the motion for a while, feeding it a level at the pace the microphone would.
  private func run(
    _ motion: inout WaveformMotion, seconds: Double, level: Float? = nil, isLoading: Bool = false
  ) -> [Double] {
    var heights: [Double] = []
    var sinceSample = 0.0
    for _ in 0..<Int(seconds / frame) {
      sinceSample += frame
      if let level, sinceSample >= WaveformMotion.sampleInterval {
        sinceSample -= WaveformMotion.sampleInterval
        motion.push(level)
      }
      heights = motion.advance(by: frame, isLoading: isLoading)
    }
    return heights
  }

  @Test func silenceIsFlat() {
    var motion = WaveformMotion(barCount: 9)
    #expect(run(&motion, seconds: 1).allSatisfy { $0 < 0.01 })
  }

  @Test func aVoiceReachesTheCenterFirstAndThenTheEdges() {
    var motion = WaveformMotion(barCount: 9)
    let early = run(&motion, seconds: 0.1, level: 1)
    #expect(early[4] > 0.3)
    #expect(early[0] < 0.05)

    let settled = run(&motion, seconds: 1, level: 1)
    #expect(settled[4] > 0.9)
    #expect(settled[0] > 0.4)
    #expect(settled[0] < settled[4])
    #expect(settled[0] == settled[8])
  }

  @Test func aWideWaveformFillsAsFastAsANarrowOne() {
    var motion = WaveformMotion(barCount: 49)
    let heights = run(&motion, seconds: 0.8, level: 1)
    #expect(heights[0] > 0.4)
    #expect(heights[0] == heights[48])
    #expect(heights[12] < heights[24])
  }

  @Test func theBarsFallWhenTheVoiceStops() {
    var motion = WaveformMotion(barCount: 9)
    _ = run(&motion, seconds: 1, level: 1)
    #expect(run(&motion, seconds: 1.5).allSatisfy { $0 < 0.02 })
  }

  @Test func loadingRipplesAndAVoiceStillShowsThroughIt() {
    var motion = WaveformMotion(barCount: 9)
    let first = run(&motion, seconds: 1, isLoading: true)
    let later = run(&motion, seconds: 0.3, isLoading: true)
    #expect(first.allSatisfy { $0 > 0.02 && $0 < 0.45 })
    #expect(first != later)

    #expect(run(&motion, seconds: 0.5, level: 1, isLoading: true)[4] > 0.9)
  }

  @Test func aBurstOfLevelsDoesNotLeaveTheWaveformBehind() {
    var motion = WaveformMotion(barCount: 9)
    for _ in 0..<200 { motion.push(0) }
    motion.push(1)
    var peak = 0.0
    for _ in 0..<24 { peak = max(peak, motion.advance(by: frame, isLoading: false)[4]) }
    #expect(peak > 0.3)
  }

  @Test func theMotionDoesNotDependOnTheFrameRate() {
    var smooth = WaveformMotion(barCount: 9)
    var coarse = WaveformMotion(barCount: 9)
    for _ in 0..<25 {
      smooth.push(0.8)
      coarse.push(0.8)
      for _ in 0..<4 { _ = smooth.advance(by: 0.01, isLoading: false) }
      _ = coarse.advance(by: 0.04, isLoading: false)
    }
    let difference = zip(
      smooth.advance(by: 0, isLoading: false), coarse.advance(by: 0, isLoading: false)
    )
    .map { abs($0 - $1) }
    #expect(difference.allSatisfy { $0 < 0.05 })
  }
}
