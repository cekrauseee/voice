import AVFoundation
import AudioToolbox
import VoiceCore
import os

struct AudioChunk: Sendable {
  /// 16-bit mono PCM at 24 kHz.
  let pcm: Data
  /// Loudness from 0 to 1.
  let level: Float
}

/// Records the microphone as a stream of PCM chunks.
///
/// The microphone is open only while a recording runs. Each recording has its own audio
/// queue, which is disposed of when it stops, so the app holds no audio device in between.
/// With a Bluetooth headset that matters: while anything holds its microphone, it plays
/// everything else in call quality.
///
/// It records with Core Audio, which gets sound from a microphone that was idle sooner than
/// a capture session does, and ends sooner too. Opening and closing the microphone wait
/// for the device, so they happen away from the main thread, and the pill does not wait
/// for them.
@MainActor
final class AudioCapture {
  private var recording: Recording?

  /// The identifier of the microphone the last recording asked for, which it keeps after
  /// it stops. Nil when it asked for the system's.
  private(set) var device: String?

  /// The microphones connected now.
  static var microphones: [Microphone] {
    AVCaptureDevice.DiscoverySession(
      deviceTypes: [.microphone], mediaType: .audio, position: .unspecified
    ).devices.map { Microphone(id: $0.uniqueID, name: $0.localizedName) }
  }

  /// Starts recording and returns at once. The chunks follow as soon as the microphone
  /// delivers audio. The stream ends after `stop`, once all of the audio is delivered, or
  /// by itself when the microphone does not start.
  ///
  /// It records with the microphone chosen while it is connected, and with the system's
  /// otherwise.
  func start(with microphone: Microphone?) -> AsyncStream<AudioChunk> {
    stop()
    let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
    let recording = Recording(continuation: continuation)
    self.recording = recording
    device = microphone?.id
    recording.start(device: microphone?.id)
    return stream
  }

  func stop() {
    recording?.stop()
    recording = nil
  }
}

/// One recording: an audio queue on the microphone, and the chunks made of what it
/// records.
private final class Recording: @unchecked Sendable {
  /// What the server expects, so the queue converts to it.
  private static let format = AudioStreamBasicDescription(
    mSampleRate: AudioFormat.sampleRate, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kLinearPCMFormatFlagIsSignedInteger | kLinearPCMFormatFlagIsPacked,
    mBytesPerPacket: 2, mFramesPerPacket: 1, mBytesPerFrame: 2, mChannelsPerFrame: 1,
    mBitsPerChannel: 16, mReserved: 0)
  /// Buffers of a chunk each, so a chunk goes out as soon as it is recorded.
  private static let buffers = 3

  private let log = Log("audio")
  /// Opening and closing the microphone wait for the device, so they run here. The audio
  /// queue is only touched on it.
  private let control = DispatchQueue(label: "eu.cekrause.voice.capture.control")
  /// The audio arrives here, in order. The chunker is only touched on this queue.
  private let audio = DispatchQueue(label: "eu.cekrause.voice.capture.audio")
  private let continuation: AsyncStream<AudioChunk>.Continuation
  private var chunker = PCMChunker()
  private var queue: AudioQueueRef?
  /// Whether the buffers go back to the queue once their audio is out.
  private let isRecording = OSAllocatedUnfairLock(initialState: true)

  init(continuation: AsyncStream<AudioChunk>.Continuation) {
    self.continuation = continuation
  }

  deinit {
    if let queue { AudioQueueDispose(queue, true) }
  }

  func start(device: String?) {
    control.async { [self] in
      if !open(device) { close() }
    }
  }

  /// Releases the microphone, then ends the stream.
  func stop() {
    control.async { [self] in close() }
  }

  private func open(_ device: String?) -> Bool {
    var format = Self.format
    let status = AudioQueueNewInput(
      &format,
      { context, queue, buffer, _, _, _ in
        Unmanaged<Recording>.fromOpaque(context!).takeUnretainedValue()
          .receive(buffer, from: queue)
      }, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &queue)
    guard status == noErr, let queue else {
      log.error("microphone not opened", ["status": status])
      return false
    }
    if let device {
      // The queue takes a device that is not connected, and then does not start.
      var uid = device as CFString
      let isChosen =
        AudioDevice.withID(device) != nil
        && AudioQueueSetProperty(
          queue, kAudioQueueProperty_CurrentDevice, &uid, UInt32(MemoryLayout<CFString>.size))
          == noErr
      if !isChosen { log.warn("microphone not connected", ["hint": "recording with the system's"]) }
    }
    let size = UInt32(AudioFormat.chunkSamples * MemoryLayout<Int16>.size)
    for _ in 0..<Self.buffers {
      var buffer: AudioQueueBufferRef?
      guard AudioQueueAllocateBuffer(queue, size, &buffer) == noErr, let buffer else {
        return false
      }
      AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
    }
    let started = AudioQueueStart(queue, nil)
    if started != noErr { log.error("microphone not started", ["status": started]) }
    return started == noErr
  }

  /// Closes the microphone, and ends the stream behind the audio still on its way.
  private func close() {
    isRecording.withLock { $0 = false }
    if let queue {
      // Stopping hands over what the buffers hold, before the microphone is released.
      AudioQueueStop(queue, true)
      AudioQueueDispose(queue, true)
      self.queue = nil
    }
    audio.async {
      if let rest = self.chunker.flush() { self.yield(rest) }
      self.continuation.finish()
    }
  }

  /// A buffer is recorded: its audio goes out, and the buffer goes back to be filled.
  private func receive(_ buffer: AudioQueueBufferRef, from queue: AudioQueueRef) {
    let pcm = Data(
      bytes: buffer.pointee.mAudioData, count: Int(buffer.pointee.mAudioDataByteSize))
    audio.async {
      for chunk in self.chunker.append(pcm) { self.yield(chunk) }
    }
    if isRecording.withLock({ $0 }) { AudioQueueEnqueueBuffer(queue, buffer, 0, nil) }
  }

  private func yield(_ pcm: Data) {
    continuation.yield(AudioChunk(pcm: pcm, level: Level.normalized(pcm)))
  }
}
