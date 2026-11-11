import SwiftUI

/// Bars that follow the microphone level, or ripple while loading.
struct Waveform: View {
  /// Levels from 0 to 1, oldest first. One bar each.
  let levels: ArraySlice<Float>
  let isLoading: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    TimelineView(.animation(paused: !isLoading || reduceMotion)) { timeline in
      Canvas { context, size in
        let time = timeline.date.timeIntervalSinceReferenceDate
        let step = size.width / Double(levels.count)
        let width = min(step * 0.6, 3)
        for (index, level) in levels.enumerated() {
          let amount = isLoading ? ripple(index, time) : Double(level)
          let height = max(width, amount * size.height)
          let bar = CGRect(
            x: (Double(index) + 0.5) * step - width / 2, y: (size.height - height) / 2,
            width: width, height: height)
          context.fill(Path(roundedRect: bar, cornerRadius: width / 2), with: .foreground)
        }
      }
    }
    .opacity(isLoading ? 0.5 : 1)
  }

  /// A low wave that travels along the bars.
  private func ripple(_ index: Int, _ time: TimeInterval) -> Double {
    reduceMotion ? 0 : 0.25 * (1 + sin(time * 6 - Double(index) * 0.7)) / 2
  }
}
