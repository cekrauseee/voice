import AVFoundation
import CoreAudio
import VoiceCore

struct AudioChunk: Sendable {
  /// 16-bit mono PCM at 24 kHz.
  let pcm: Data
  /// Loudness from 0 to 1.
  let level: Float
}

/// Records the microphone as a stream of PCM chunks.
///
/// The microphone is open only while a recording runs. Each recording reads the device
/// itself, and stops reading when it ends, so the app holds no audio device in between.
/// With a Bluetooth headset that matters: while anything holds its microphone, it plays
/// everything else in call quality.
///
/// It reads the device with Core Audio, and neither through a capture session nor through
/// an audio queue. A capture session gets sound from a microphone that was idle later, and
/// ends later too. An audio queue keeps the microphone open for two seconds after it is
/// disposed of, and a headset stays in call quality as long. Opening and closing the
/// microphone wait for the device, so they happen away from the main thread, and the pill
/// does not wait for them.
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

/// One recording: what the microphone's device delivers, and the chunks made of it.
private final class Recording: @unchecked Sendable {
  private let log = Log("audio")
  /// Opening and closing the microphone wait for the device, so they run here. The device
  /// is only touched on it.
  private let control = DispatchQueue(label: "eu.cekrause.voice.capture.control")
  /// The audio arrives here, in order. The converter and the chunker are only touched on
  /// this queue.
  private let audio = DispatchQueue(label: "eu.cekrause.voice.capture.audio")
  private let continuation: AsyncStream<AudioChunk>.Continuation
  private var chunker = PCMChunker()
  /// Made for the format the microphone delivers, and again when that changes.
  private var converter: Converter?
  private var device = AudioObjectID(kAudioObjectUnknown)
  private var stream = AudioObjectID(kAudioObjectUnknown)
  private var reading: AudioDeviceIOProcID?
  private var formatChanged: AudioObjectPropertyListenerBlock?

  private static var formatAddress: AudioObjectPropertyAddress {
    AudioObjectPropertyAddress(
      mSelector: kAudioStreamPropertyVirtualFormat, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
  }

  init(continuation: AsyncStream<AudioChunk>.Continuation) {
    self.continuation = continuation
  }

  deinit {
    release()
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

  private func open(_ chosen: String?) -> Bool {
    let connected = chosen.flatMap(AudioDevice.withID)
    if chosen != nil, connected == nil {
      log.warn("microphone not connected", ["hint": "recording with the system's"])
    }
    guard let device = connected ?? AudioDevice.input, let stream = Self.stream(of: device)
    else {
      log.error("microphone not found")
      return false
    }
    self.device = device
    self.stream = stream

    // The format can change under a recording: a headset's does as it changes quality.
    let formatChanged: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
      self?.converter = nil
    }
    var address = Self.formatAddress
    if AudioObjectAddPropertyListenerBlock(stream, &address, audio, formatChanged) == noErr {
      self.formatChanged = formatChanged
    }

    // The device hands over what it records on the audio queue, and waits for it.
    var status = AudioDeviceCreateIOProcIDWithBlock(&reading, device, audio) {
      [weak self] _, input, _, _, _ in
      self?.receive(input)
    }
    guard status == noErr, let reading else {
      log.error("microphone not opened", ["status": status])
      return false
    }
    status = AudioDeviceStart(device, reading)
    if status != noErr { log.error("microphone not started", ["status": status]) }
    return status == noErr
  }

  /// Closes the microphone, and ends the stream behind the audio still on its way.
  private func close() {
    release()
    audio.async {
      if let rest = self.chunker.flush() { self.yield(rest) }
      self.continuation.finish()
    }
  }

  /// Stops reading the device. The microphone is released when this returns.
  private func release() {
    if let reading {
      AudioDeviceStop(device, reading)
      AudioDeviceDestroyIOProcID(device, reading)
      self.reading = nil
    }
    if let formatChanged {
      var address = Self.formatAddress
      AudioObjectRemovePropertyListenerBlock(stream, &address, audio, formatChanged)
      self.formatChanged = nil
    }
  }

  /// The device recorded a moment of audio: it goes out in chunks of the PCM the server
  /// expects.
  private func receive(_ input: UnsafePointer<AudioBufferList>) {
    // A device with several streams delivers a buffer for each. The first is recorded.
    let buffer = input.pointee.mBuffers
    guard input.pointee.mNumberBuffers > 0, buffer.mData != nil, buffer.mDataByteSize > 0
    else { return }
    if converter == nil {
      converter = Self.format(of: stream).flatMap(Converter.init)
      if converter == nil { log.error("microphone format not read") }
    }
    guard let pcm = converter?.convert(buffer) else { return }
    for chunk in chunker.append(pcm) { yield(chunk) }
  }

  private func yield(_ pcm: Data) {
    continuation.yield(AudioChunk(pcm: pcm, level: Level.normalized(pcm)))
  }

  /// The first stream a device records to.
  private static func stream(of device: AudioObjectID) -> AudioObjectID? {
    AudioDevice.list(device, kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
      .first
  }

  /// The format a stream delivers its audio in.
  private static func format(of stream: AudioObjectID) -> AudioStreamBasicDescription? {
    AudioDevice.read(stream, kAudioStreamPropertyVirtualFormat)
  }
}

/// Turns what a microphone delivers into the PCM the server expects: one channel of 16-bit
/// samples, at the server's rate.
private final class Converter {
  private let source: AVAudioFormat
  private let target: AVAudioFormat
  private let converter: AVAudioConverter
  private var converted: AVAudioPCMBuffer?

  init?(_ format: AudioStreamBasicDescription) {
    var format = format
    guard let source = AVAudioFormat(streamDescription: &format),
      let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: AudioFormat.sampleRate, channels: 1,
        interleaved: true),
      let converter = AVAudioConverter(from: source, to: target)
    else { return nil }
    self.source = source
    self.target = target
    self.converter = converter
  }

  /// Converts a moment of audio. The converter keeps what it needs between two of them, so
  /// the moments come out as one stream.
  func convert(_ buffer: AudioBuffer) -> Data? {
    let frameBytes = source.streamDescription.pointee.mBytesPerFrame
    guard frameBytes > 0, buffer.mNumberChannels == source.channelCount else { return nil }
    let frames = buffer.mDataByteSize / frameBytes
    let capacity = AVAudioFrameCount(Double(frames) * target.sampleRate / source.sampleRate) + 64
    if converted == nil || converted!.frameCapacity < capacity {
      converted = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity)
    }
    guard let converted else { return nil }

    var list = AudioBufferList(mNumberBuffers: 1, mBuffers: buffer)
    return withUnsafeMutablePointer(to: &list) { list -> Data? in
      guard
        let recorded = AVAudioPCMBuffer(
          pcmFormat: source, bufferListNoCopy: list, deallocator: nil)
      else { return nil }
      recorded.frameLength = frames
      // The moment is handed over once: after it, there is no more for now.
      var isGiven = false
      var error: NSError?
      let status = converter.convert(to: converted, error: &error) { _, status in
        if isGiven {
          status.pointee = .noDataNow
          return nil
        }
        isGiven = true
        status.pointee = .haveData
        return recorded
      }
      guard status != .error, converted.frameLength > 0, let samples = converted.int16ChannelData
      else { return nil }
      return Data(
        bytes: samples[0], count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
    }
  }
}
