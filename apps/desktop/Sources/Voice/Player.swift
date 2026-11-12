import AVFoundation
import Observation

/// Plays the recording of a transcription.
@MainActor @Observable
final class Player: NSObject, AVAudioPlayerDelegate {
  private(set) var isPlaying = false
  /// How far into the recording it is, in seconds.
  private(set) var time: TimeInterval = 0
  private(set) var duration: TimeInterval = 0

  @ObservationIgnored private var player: AVAudioPlayer?
  @ObservationIgnored private var clock: Task<Void, Never>?

  /// Gets a recording ready to play, from its start.
  func load(_ url: URL?) {
    stop()
    player = url.flatMap { try? AVAudioPlayer(contentsOf: $0) }
    player?.delegate = self
    duration = player?.duration ?? 0
    time = 0
  }

  func toggle() {
    guard let player else { return }
    if isPlaying {
      player.pause()
      isPlaying = false
      clock?.cancel()
    } else {
      player.play()
      isPlaying = true
      // The player does not say where it is: it is asked while it plays.
      clock = Task {
        while !Task.isCancelled {
          time = player.currentTime
          try? await Task.sleep(for: .milliseconds(50))
        }
      }
    }
  }

  /// Moves to a part of the recording, from 0 at its start to 1 at its end.
  func seek(to fraction: Double) {
    guard let player else { return }
    player.currentTime = min(max(fraction, 0), 1) * duration
    time = player.currentTime
  }

  func stop() {
    clock?.cancel()
    player?.stop()
    isPlaying = false
  }

  nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) {
    Task { @MainActor in
      clock?.cancel()
      isPlaying = false
      time = 0
    }
  }
}
