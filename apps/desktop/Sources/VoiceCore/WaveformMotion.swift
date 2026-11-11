import Foundation

/// The motion of the waveform's bars.
///
/// Levels enter at the center and flow outward, so the middle answers the voice at once and
/// the sides show the moments before. A spring carries each bar to its
/// height, which keeps the motion smooth whatever rhythm the levels arrive in, and lets the
/// loading ripple and the live waveform turn into each other.
public struct WaveformMotion: Sendable {
  /// How often a level is taken from the microphone and moved one step outward.
  public static let sampleInterval = 0.04

  /// The edges show at most this many steps back, about half a second.
  private static let maximumSteps = 12.0

  /// The microphone delivers levels in bursts. More than this many waiting means the
  /// waveform has fallen behind the voice, and the oldest are dropped.
  private static let maximumPending = 4
  /// How quickly a bar reaches its height, and how much it overshoots on the way.
  private static let response = 0.2
  private static let damping = 0.68

  /// Levels from the center outward, newest first.
  private var trail: [Double]
  /// How many bars a level moves outward per step.
  private let spread: Double
  private var pending: [Double] = []
  private var heights: [Double]
  private var velocities: [Double]
  private var sampleClock = 0.0
  private var time = 0.0

  public init(barCount: Int) {
    let center = Double(max(barCount - 1, 0)) / 2
    spread = max(1, center / Self.maximumSteps)
    trail = Array(repeating: 0, count: Int(center / spread) + 2)
    heights = Array(repeating: 0, count: barCount)
    velocities = heights
  }

  /// Adds a microphone level from 0 to 1.
  public mutating func push(_ level: Float) {
    pending.append(Double(level))
    if pending.count > Self.maximumPending {
      pending.removeFirst(pending.count - Self.maximumPending)
    }
  }

  /// Moves the bars forward in time. Returns the height of each bar from 0 to 1.
  ///
  /// While loading, a ripple runs outward wherever the voice is quieter than it.
  public mutating func advance(by elapsed: Double, isLoading: Bool) -> [Double] {
    let elapsed = min(max(elapsed, 0), 0.1)
    time += elapsed
    sampleClock += elapsed
    while sampleClock >= Self.sampleInterval {
      sampleClock -= Self.sampleInterval
      // With nothing new from the microphone, the last level fades out.
      let level = pending.isEmpty ? (trail.first ?? 0) * 0.5 : pending.removeFirst()
      trail.removeLast()
      trail.insert(level, at: 0)
    }

    let center = Double(heights.count - 1) / 2
    let targets = heights.indices.map { index in
      let distance = abs(Double(index) - center)
      let position = distance / spread
      let near = Int(position)
      let blend = position - Double(near)
      let trailed = trail[near] * (1 - blend) + trail[near + 1] * blend
      // Quiet speech still shows, and the bars get shorter toward the edges.
      let level = pow(trailed, 0.7) * (1 - 0.45 * distance / max(center, 1))
      let ripple = isLoading ? 0.22 + 0.18 * sin(time * 5.5 - position * 0.9) : 0
      return max(level, ripple)
    }

    // Small steps keep the springs stable at any frame rate.
    let frequency = 2 * Double.pi / Self.response
    let steps = max(1, Int((elapsed / 0.004).rounded(.up)))
    let step = elapsed / Double(steps)
    for _ in 0..<steps {
      for index in heights.indices {
        let pull = frequency * frequency * (targets[index] - heights[index])
        velocities[index] += (pull - 2 * Self.damping * frequency * velocities[index]) * step
        heights[index] += velocities[index] * step
      }
    }
    return heights.map { min(max($0, 0), 1) }
  }
}
