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

/// A recording as a WAV file: the PCM the server expects, with the header that lets any
/// player read it.
public enum WAV {
  /// Wraps 16-bit mono PCM in a WAV file.
  public static func file(pcm: Data, sampleRate: Double = AudioFormat.sampleRate) -> Data {
    func bytes<T: FixedWidthInteger>(_ value: T) -> Data {
      withUnsafeBytes(of: value.littleEndian) { Data($0) }
    }
    let rate = UInt32(sampleRate)
    var file = Data("RIFF".utf8) + bytes(UInt32(36 + pcm.count)) + Data("WAVEfmt ".utf8)
    // PCM, one channel, 16 bits a sample.
    file += bytes(UInt32(16)) + bytes(UInt16(1)) + bytes(UInt16(1))
    file += bytes(rate) + bytes(rate * 2) + bytes(UInt16(2)) + bytes(UInt16(16))
    file += Data("data".utf8) + bytes(UInt32(pcm.count))
    return file + pcm
  }

  /// The samples of a WAV file: what its `data` chunk holds, whatever comes before it.
  public static func pcm(file: Data) -> Data? {
    let file = Data(file)
    guard file.count >= 12, file.prefix(4) == Data("RIFF".utf8) else { return nil }
    var offset = 12
    while offset + 8 <= file.count {
      let size = file[offset + 4..<offset + 8].enumerated().reduce(0) {
        $0 | Int($1.element) << (8 * $1.offset)
      }
      let body = offset + 8
      if file[offset..<offset + 4] == Data("data".utf8) {
        return file.subdata(in: body..<min(body + size, file.count))
      }
      // Chunks are padded to an even length.
      offset = body + size + size % 2
    }
    return nil
  }
}
