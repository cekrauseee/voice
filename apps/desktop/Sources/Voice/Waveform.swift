import SwiftUI
import VoiceCore

/// The microphone levels on their way to the waveform. The dictation writes them as they
/// arrive, and each waveform reads the ones it has not seen yet on every frame.
@MainActor
final class LevelFeed {
  /// How many levels were ever written.
  private(set) var count = 0
  private var recent: [Float] = []

  func push(_ level: Float) {
    recent.append(level)
    if recent.count > 16 { recent.removeFirst() }
    count += 1
  }

  /// The levels written after the first `seen`, oldest first.
  func levels(after seen: Int) -> ArraySlice<Float> {
    recent.suffix(min(max(count - seen, 0), recent.count))
  }
}

/// Bars that move with the voice, and ripple dimmed while loading.
struct Waveform: View {
  let feed: LevelFeed
  let barCount: Int
  let isLoading: Bool

  @State private var animator = WaveformAnimator()
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // With reduced motion the bars still show the level, a few times a second.
    TimelineView(.animation(minimumInterval: reduceMotion ? 0.25 : nil)) { timeline in
      Canvas { context, size in
        let bars = animator.bars(
          at: timeline.date, feed: feed, barCount: barCount, isLoading: isLoading,
          ripples: !reduceMotion)
        let step = size.width / Double(barCount)
        let width = min(step * 0.55, 3)
        for (index, bar) in bars.enumerated() {
          let height = max(width, bar.height * size.height)
          let rect = CGRect(
            x: (Double(index) + 0.5) * step - width / 2, y: (size.height - height) / 2,
            width: width, height: height)
          context.opacity = 1 - 0.45 * bar.loading
          context.fill(Path(roundedRect: rect, cornerRadius: width / 2), with: .foreground)
        }
      }
    }
  }
}

/// Keeps the motion of the bars between frames.
@MainActor
private final class WaveformAnimator {
  private var motion = WaveformMotion(barCount: 0)
  private var barCount = 0
  private var seen = 0
  private var lastFrame: Date?

  func bars(
    at date: Date, feed: LevelFeed, barCount: Int, isLoading: Bool, ripples: Bool
  ) -> [WaveformMotion.Bar] {
    if barCount != self.barCount {
      self.barCount = barCount
      motion = WaveformMotion(barCount: barCount)
    }
    for level in feed.levels(after: seen) { motion.push(level) }
    seen = feed.count
    let elapsed = lastFrame.map { date.timeIntervalSince($0) } ?? 0
    lastFrame = date
    return motion.advance(by: elapsed, isLoading: isLoading, ripples: ripples)
  }
}
