import Foundation

/// The audio the server expects: 16-bit mono PCM.
public enum AudioFormat {
  public static let sampleRate = 24_000.0
  /// Samples per chunk sent to the server: 40 ms.
  public static let chunkSamples = 960
}

/// Cuts a stream of PCM into chunks of a fixed size.
public struct PCMChunker: Sendable {
  private let chunkBytes: Int
  private var pending = Data()

  public init(chunkSamples: Int = AudioFormat.chunkSamples) {
    chunkBytes = chunkSamples * MemoryLayout<Int16>.size
  }

  /// Adds PCM and returns the chunks it completes.
  public mutating func append(_ pcm: Data) -> [Data] {
    pending.append(pcm)
    var chunks: [Data] = []
    while pending.count >= chunkBytes {
      chunks.append(Data(pending.prefix(chunkBytes)))
      pending = Data(pending.dropFirst(chunkBytes))
    }
    return chunks
  }

  /// Returns what is left, shorter than a chunk, when the stream ends.
  public mutating func flush() -> Data? {
    defer { pending = Data() }
    return pending.isEmpty ? nil : pending
  }
}

public enum Level {
  /// The loudness of a PCM chunk from 0 to 1, where 0 is -50 dBFS or quieter and 1 is -10 dBFS.
  public static func normalized(_ pcm: Data) -> Float {
    let sum = pcm.withUnsafeBytes { bytes in
      bytes.bindMemory(to: Int16.self).reduce(0.0) { $0 + Double($1) * Double($1) }
    }
    let count = pcm.count / MemoryLayout<Int16>.size
    guard count > 0, sum > 0 else { return 0 }
    let decibels = 20 * log10((sum / Double(count)).squareRoot() / 32_768)
    return Float(min(max((decibels + 50) / 40, 0), 1))
  }
}
