import Testing

@testable import VoiceCore

@Suite struct WaveformMotionTests {
  private let frame = 1.0 / 60

  /// Runs the motion for a while, feeding it a level at the pace the microphone would.
  private func bars(
    _ motion: inout WaveformMotion, seconds: Double, level: Float? = nil, isLoading: Bool = false
  ) -> [WaveformMotion.Bar] {
    var bars: [WaveformMotion.Bar] = []
    var sinceSample = 0.0
    for _ in 0..<Int(seconds / frame) {
      sinceSample += frame
      if let level, sinceSample >= WaveformMotion.sampleInterval {
        sinceSample -= WaveformMotion.sampleInterval
        motion.push(level)
      }
      bars = motion.advance(by: frame, isLoading: isLoading)
    }
    return bars
  }

  private func run(
    _ motion: inout WaveformMotion, seconds: Double, level: Float? = nil, isLoading: Bool = false
  ) -> [Double] {
    bars(&motion, seconds: seconds, level: level, isLoading: isLoading).map(\.height)
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

  @Test func loadingComesInAtTheCenterAndLeavesThroughTheEdges() {
    var motion = WaveformMotion(barCount: 49)
    let coming = bars(&motion, seconds: 0.25, isLoading: true)
    #expect(coming[24].loading > 0.5)
    #expect(coming[0].loading == 0)
    #expect(bars(&motion, seconds: 1, isLoading: true).allSatisfy { $0.loading == 1 })

    let going = bars(&motion, seconds: 0.25)
    #expect(going[24].loading < 0.5)
    #expect(going[0].loading == 1)
    #expect(bars(&motion, seconds: 1).allSatisfy { $0.loading == 0 })
  }

  @Test func theRippleSwellsAndSettlesInsteadOfJumping() {
    var motion = WaveformMotion(barCount: 9)
    var last = motion.advance(by: frame, isLoading: false)
    var largest = 0.0
    for isLoading in [true, false] {
      for _ in 0..<60 {
        let bars = motion.advance(by: frame, isLoading: isLoading)
        largest = max(largest, zip(bars, last).map { abs($0.height - $1.height) }.max() ?? 0)
        last = bars
      }
    }
    #expect(largest < 0.05)
  }

  @Test func withoutTheRippleLoadingOnlyDims() {
    var motion = WaveformMotion(barCount: 9)
    var bars: [WaveformMotion.Bar] = []
    for _ in 0..<60 { bars = motion.advance(by: frame, isLoading: true, ripples: false) }
    #expect(bars.allSatisfy { $0.height < 0.01 && $0.loading == 1 })
  }

  @Test func aBurstOfLevelsDoesNotLeaveTheWaveformBehind() {
    var motion = WaveformMotion(barCount: 9)
    for _ in 0..<200 { motion.push(0) }
    motion.push(1)
    var peak = 0.0
    for _ in 0..<24 { peak = max(peak, motion.advance(by: frame, isLoading: false)[4].height) }
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
    .map { abs($0.height - $1.height) }
    #expect(difference.allSatisfy { $0 < 0.05 })
  }
}
