import Foundation

/// The shape of a recording: how loud it is along its length, to draw it small beside its
/// transcription and as the track of its player.
public enum Voiceprint {
  /// The loudness of `count` equal stretches of 16-bit mono PCM, from 0 to 1, in order.
  ///
  /// Each stretch is measured like a level of the microphone, then all of them are scaled
  /// so the loudest is 1: a quiet recording still shows its shape. Silence is all zeros.
  public static func levels(pcm: Data, count: Int) -> [Double] {
    guard count > 0 else { return [] }
    let sampleSize = MemoryLayout<Int16>.size
    let samples = pcm.count / sampleSize
    let levels = (0..<count).map { index -> Double in
      let start = samples * index / count
      let end = samples * (index + 1) / count
      guard end > start else { return 0 }
      let range = (pcm.startIndex + start * sampleSize)..<(pcm.startIndex + end * sampleSize)
      return Double(Level.normalized(pcm.subdata(in: range)))
    }
    guard let loudest = levels.max(), loudest > 0 else { return levels }
    return levels.map { $0 / loudest }
  }
}
