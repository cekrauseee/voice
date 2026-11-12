@preconcurrency import AVFoundation
import VoiceCore

struct AudioChunk: Sendable {
  /// 16-bit mono PCM at 24 kHz.
  let pcm: Data
  /// Loudness from 0 to 1.
  let level: Float
}

/// Records the microphone as a stream of PCM chunks.
///
/// The microphone is open only while a recording runs. Each recording has its own capture
/// session, which is torn down when it stops, so the app holds no audio device in between.
/// With a Bluetooth headset that matters: while anything holds its microphone, it plays
/// everything else in call quality.
@MainActor
final class AudioCapture {
  private var recording: Recording?

  /// The identifier of the device the last recording used, which it keeps after it stops.
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
  func start(with microphone: Microphone?) throws -> AsyncStream<AudioChunk> {
    stop()
    let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
    let chosen = microphone.flatMap { AVCaptureDevice(uniqueID: $0.id) }
    if microphone != nil && chosen == nil {
      Log("audio").warn("microphone not connected", ["hint": "recording with the system's"])
    }
    guard let device = chosen ?? AVCaptureDevice.default(for: .audio),
      let recording = Recording(device: device, continuation: continuation)
    else { throw DictationError.microphoneUnavailable }
    self.recording = recording
    self.device = device.uniqueID
    recording.start()
    return stream
  }

  func stop() {
    recording?.stop()
    recording = nil
  }
}

/// One recording: a capture session, and the chunks made of what it delivers.
private final class Recording: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate,
  @unchecked Sendable
{
  private let session = AVCaptureSession()
  /// Starting and stopping the session block until the device answers, so they run here.
  private let control = DispatchQueue(label: "eu.cekrause.voice.capture.control")
  /// The audio arrives here, in order. The chunker is only touched on this queue.
  private let audio = DispatchQueue(label: "eu.cekrause.voice.capture.audio")
  private let continuation: AsyncStream<AudioChunk>.Continuation
  private var chunker = PCMChunker()

  init?(device: AVCaptureDevice, continuation: AsyncStream<AudioChunk>.Continuation) {
    self.continuation = continuation
    super.init()

    // The session converts what the device delivers into the format the server expects.
    let output = AVCaptureAudioDataOutput()
    output.audioSettings = [
      AVFormatIDKey: kAudioFormatLinearPCM,
      AVSampleRateKey: AudioFormat.sampleRate,
      AVNumberOfChannelsKey: 1,
      AVLinearPCMBitDepthKey: 16,
      AVLinearPCMIsFloatKey: false,
      AVLinearPCMIsBigEndianKey: false,
      AVLinearPCMIsNonInterleaved: false,
    ]
    output.setSampleBufferDelegate(self, queue: audio)
    guard let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input),
      session.canAddOutput(output)
    else { return nil }
    session.addInput(input)
    session.addOutput(output)
  }

  func start() {
    control.async {
      self.session.startRunning()
      if !self.session.isRunning { self.finish() }
    }
  }

  /// Releases the microphone, then ends the stream.
  func stop() {
    control.async {
      self.session.stopRunning()
      self.finish()
    }
  }

  /// Ends the stream behind the audio still on its way.
  private func finish() {
    audio.async {
      if let rest = self.chunker.flush() { self.yield(rest) }
      self.continuation.finish()
    }
  }

  func captureOutput(
    _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
    from connection: AVCaptureConnection
  ) {
    guard let block = sampleBuffer.dataBuffer, block.dataLength > 0,
      let samples = try? block.dataBytes()
    else { return }
    for pcm in chunker.append(samples) { yield(pcm) }
  }

  private func yield(_ pcm: Data) {
    continuation.yield(AudioChunk(pcm: pcm, level: Level.normalized(pcm)))
  }
}
