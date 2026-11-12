@preconcurrency import AVFoundation
import CoreAudio
import VoiceCore

/// Records what the Mac plays, but for the app's own sound, as a stream of PCM chunks.
///
/// Core Audio taps the output of every other process, mixed down to one channel, and an
/// aggregate device of the system's output and that tap delivers it. The first tap asks the
/// user for System Audio Recording, once. A tap the user did not allow hears silence.
@MainActor
final class SystemAudioCapture {
  private var recording: TapRecording?

  /// Starts recording and returns at once. The stream ends after `stop`.
  func start() throws -> AsyncStream<AudioChunk> {
    stop()
    let (stream, continuation) = AsyncStream.makeStream(of: AudioChunk.self)
    let recording = TapRecording(continuation: continuation)
    do {
      try recording.start()
    } catch {
      recording.stop()
      throw error
    }
    self.recording = recording
    return stream
  }

  func stop() {
    recording?.stop()
    recording = nil
  }
}

/// What went wrong with the tap, as Core Audio reported it.
struct TapError: Error, CustomStringConvertible {
  let step: String
  let status: OSStatus

  var description: String {
    "\(step) failed with status \(status)"
  }
}

/// One recording: a tap, the aggregate device that runs it, and the chunks made of what it
/// delivers.
private final class TapRecording: @unchecked Sendable {
  /// The audio arrives here, in order. The converter and the chunker are only touched here.
  private let queue = DispatchQueue(label: "eu.cekrause.voice.tap")
  private let continuation: AsyncStream<AudioChunk>.Continuation
  private var converter: AVAudioConverter?
  private var chunker = PCMChunker()
  private var tap = AudioObjectID(kAudioObjectUnknown)
  private var aggregate = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?

  init(continuation: AsyncStream<AudioChunk>.Continuation) {
    self.continuation = continuation
  }

  func start() throws {
    let system = AudioObjectID(kAudioObjectSystemObject)
    let description = CATapDescription(monoGlobalTapButExcludeProcesses: [try ownProcess()])
    description.name = "Voice"
    description.isPrivate = true
    description.muteBehavior = .unmuted
    try check(AudioHardwareCreateProcessTap(description, &tap), "creating the tap")

    var format: AudioStreamBasicDescription = try read(tap, kAudioTapPropertyFormat)
    let output: AudioObjectID = try read(system, kAudioHardwarePropertyDefaultSystemOutputDevice)
    let outputUID: CFString = try read(output, kAudioDevicePropertyDeviceUID)
    let aggregateDescription: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Voice",
      kAudioAggregateDeviceUIDKey: UUID().uuidString,
      kAudioAggregateDeviceMainSubDeviceKey: outputUID,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceIsStackedKey: false,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceSubDeviceListKey: [[kAudioSubDeviceUIDKey: outputUID]],
      kAudioAggregateDeviceTapListKey: [
        [
          kAudioSubTapDriftCompensationKey: true,
          kAudioSubTapUIDKey: description.uuid.uuidString,
        ]
      ],
    ]
    try check(
      AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate),
      "creating the aggregate device")

    guard let input = AVAudioFormat(streamDescription: &format),
      let target = AVAudioFormat(
        commonFormat: .pcmFormatInt16, sampleRate: AudioFormat.sampleRate, channels: 1,
        interleaved: true),
      let converter = AVAudioConverter(from: input, to: target)
    else { throw TapError(step: "converting the tap's format", status: -1) }
    self.converter = converter

    try check(
      AudioDeviceCreateIOProcIDWithBlock(&procID, aggregate, queue) {
        [weak self] _, input, _, _, _ in
        self?.deliver(input)
      }, "creating the io proc")
    try check(AudioDeviceStart(aggregate, procID), "starting the device")
  }

  /// Releases the tap and the device, then ends the stream behind the audio still on its way.
  func stop() {
    if aggregate != kAudioObjectUnknown {
      if let procID {
        AudioDeviceStop(aggregate, procID)
        AudioDeviceDestroyIOProcID(aggregate, procID)
      }
      AudioHardwareDestroyAggregateDevice(aggregate)
      aggregate = AudioObjectID(kAudioObjectUnknown)
    }
    if tap != kAudioObjectUnknown {
      AudioHardwareDestroyProcessTap(tap)
      tap = AudioObjectID(kAudioObjectUnknown)
    }
    queue.async {
      if let rest = self.chunker.flush() { self.yield(rest) }
      self.continuation.finish()
    }
  }

  /// Converts what the tap delivers to the format the server expects, and cuts it in chunks.
  private func deliver(_ list: UnsafePointer<AudioBufferList>) {
    guard let converter,
      let buffer = AVAudioPCMBuffer(
        pcmFormat: converter.inputFormat, bufferListNoCopy: list, deallocator: nil),
      buffer.frameLength > 0
    else { return }
    let ratio = converter.outputFormat.sampleRate / converter.inputFormat.sampleRate
    let capacity = AVAudioFrameCount((Double(buffer.frameLength) * ratio).rounded(.up)) + 64
    guard
      let converted = AVAudioPCMBuffer(pcmFormat: converter.outputFormat, frameCapacity: capacity)
    else { return }
    var consumed = false
    var error: NSError?
    converter.convert(to: converted, error: &error) { _, status in
      if consumed {
        status.pointee = .noDataNow
        return nil
      }
      consumed = true
      status.pointee = .haveData
      return buffer
    }
    guard error == nil, converted.frameLength > 0, let samples = converted.int16ChannelData
    else { return }
    let pcm = Data(
      bytes: samples[0], count: Int(converted.frameLength) * MemoryLayout<Int16>.size)
    for chunk in chunker.append(pcm) { yield(chunk) }
  }

  private func yield(_ pcm: Data) {
    continuation.yield(AudioChunk(pcm: pcm, level: Level.normalized(pcm)))
  }

  /// The audio object of this process, which the tap leaves out.
  private func ownProcess() throws -> AudioObjectID {
    var pid = getpid()
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var process = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafePointer(to: &pid) { pid in
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size),
        pid, &size, &process)
    }
    try check(status, "finding the app's process")
    return process
  }

  /// Reads a property of an audio object that holds a single value.
  private func read<Value>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
  ) throws -> Value {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<Value>.size)
    let value = UnsafeMutablePointer<Value>.allocate(capacity: 1)
    defer { value.deallocate() }
    try check(
      AudioObjectGetPropertyData(object, &address, 0, nil, &size, value),
      "reading \(String(describing: Value.self))")
    return value.pointee
  }

  private func check(_ status: OSStatus, _ step: String) throws {
    if status != noErr { throw TapError(step: step, status: status) }
  }
}
