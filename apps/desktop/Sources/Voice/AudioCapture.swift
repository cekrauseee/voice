@preconcurrency import AVFoundation
import VoiceCore

struct AudioChunk: Sendable {
  /// 16-bit mono PCM at 24 kHz.
  let pcm: Data
  /// Loudness from 0 to 1.
  let level: Float
}

/// Records the microphone as a stream of fixed-size PCM chunks.
@MainActor
final class AudioCapture {
  private let engine = AVAudioEngine()
  private var continuation: AsyncStream<AudioChunk>.Continuation?

  func start() throws -> AsyncStream<AudioChunk> {
    let input = engine.inputNode
    let format = input.outputFormat(forBus: 0)
    guard
      format.sampleRate > 0,
      let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: AudioFormat.sampleRate, channels: 1,
        interleaved: true),
      let converter = AVAudioConverter(from: format, to: target)
    else { throw DictationError.microphoneUnavailable }

    let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
    self.continuation = continuation
    AudioProcessor(converter: converter, continuation: continuation).install(on: input)
    do {
      try engine.start()
    } catch {
      stop()
      throw DictationError.microphoneUnavailable
    }
    return stream
  }

  func stop() {
    engine.inputNode.removeTap(onBus: 0)
    engine.stop()
    continuation?.finish()
    continuation = nil
  }
}

/// Converts what the microphone delivers into chunks. Runs on the audio thread only.
private final class AudioProcessor: @unchecked Sendable {
  private let converter: AVAudioConverter
  private let continuation: AsyncStream<AudioChunk>.Continuation
  private var chunker = PCMChunker()

  init(converter: AVAudioConverter, continuation: AsyncStream<AudioChunk>.Continuation) {
    self.converter = converter
    self.continuation = continuation
  }

  func install(on input: AVAudioInputNode) {
    input.installTap(onBus: 0, bufferSize: 1024, format: converter.inputFormat) { buffer, _ in
      self.process(buffer)
    }
  }

  private func process(_ buffer: AVAudioPCMBuffer) {
    let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
    let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 64
    guard let output = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)
    else { return }

    // The converter asks for input until it has enough: hand it this buffer once.
    nonisolated(unsafe) var input: AVAudioPCMBuffer? = buffer
    let status = converter.convert(to: output, error: nil) { _, inputStatus in
      inputStatus.pointee = input == nil ? .noDataNow : .haveData
      defer { input = nil }
      return input
    }
    guard status != .error, let samples = output.int16ChannelData else { return }

    let converted = UnsafeBufferPointer(start: samples[0], count: Int(output.frameLength))
    for pcm in chunker.append(converted) {
      continuation.yield(AudioChunk(pcm: pcm, level: Level.normalized(pcm)))
    }
  }
}
