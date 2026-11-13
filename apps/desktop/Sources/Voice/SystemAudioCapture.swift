@preconcurrency import AVFoundation
import CoreAudio
import VoiceCore

/// Records what the Mac plays, but for the app's own sound, as a stream of PCM chunks.
///
/// Core Audio taps the output of every other process, mixed down to one channel, and an
/// aggregate device made of that tap alone delivers it. The output device itself stays out
/// of the device: with a headset, its microphone would come first in what the device
/// delivers, and its sound would switch to call quality. The first tap asks the user for
/// System Audio Recording, once. A tap the user did not allow hears silence.
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
  private let log = Log("meeting")
  private let continuation: AsyncStream<AudioChunk>.Continuation
  private var converter: AVAudioConverter?
  private var chunker = PCMChunker()
  private let startedAt = ContinuousClock.now
  /// Whether the tap delivered anything but silence yet. Silence that goes on is a tap the
  /// user did not allow, or a quiet Mac.
  private var hasDelivered = false
  private var hasHeard = false
  private var hasWarned = false
  private var silentBytes = 0
  private var tap = AudioObjectID(kAudioObjectUnknown)
  private var aggregate = AudioObjectID(kAudioObjectUnknown)
  private var procID: AudioDeviceIOProcID?

  init(continuation: AsyncStream<AudioChunk>.Continuation) {
    self.continuation = continuation
  }

  func start() throws {
    let description = CATapDescription(monoGlobalTapButExcludeProcesses: [try ownProcess()])
    description.name = "Voice"
    description.isPrivate = true
    description.muteBehavior = .unmuted
    try check(AudioHardwareCreateProcessTap(description, &tap), "creating the tap")

    var format: AudioStreamBasicDescription = try read(tap, kAudioTapPropertyFormat)
    // The tap is the device's only part: what it delivers is the tap's sound and nothing else.
    let aggregateDescription: [String: Any] = [
      kAudioAggregateDeviceNameKey: "Voice",
      kAudioAggregateDeviceUIDKey: UUID().uuidString,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
    ]
    try check(
      AudioHardwareCreateAggregateDevice(aggregateDescription as CFDictionary, &aggregate),
      "creating the aggregate device")
    log.info(
      "tapped",
      [
        "sample_rate": Int(format.mSampleRate), "channels": format.mChannelsPerFrame,
        "format_id": format.mFormatID, "flags": format.mFormatFlags,
      ])

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
    if !hasDelivered {
      hasDelivered = true
      let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
      log.debug(
        "delivering",
        ["buffers": buffers.count, "bytes": buffers.map { Int($0.mDataByteSize) }])
    }
    guard let converter, let buffer = tapped(list, as: converter.inputFormat),
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
    listen(pcm)
    for chunk in chunker.append(pcm) { yield(chunk) }
  }

  /// The tap's sound, out of what the device delivers. The tap's buffers come last, after
  /// those of any other part of the device.
  private func tapped(
    _ list: UnsafePointer<AudioBufferList>, as format: AVAudioFormat
  ) -> AVAudioPCMBuffer? {
    let buffers = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: list))
    let needed = format.isInterleaved ? 1 : Int(format.channelCount)
    guard buffers.count >= needed else { return nil }
    if buffers.count == needed {
      return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: list, deallocator: nil)
    }
    let own = AudioBufferList.allocate(maximumBuffers: needed)
    for (index, buffer) in buffers.suffix(needed).enumerated() { own[index] = buffer }
    return AVAudioPCMBuffer(pcmFormat: format, bufferListNoCopy: own.unsafePointer) { _ in
      free(own.unsafeMutablePointer)
    }
  }

  /// Says once when the sound comes, and once when it has not come for a while.
  private func listen(_ pcm: Data) {
    guard !hasHeard else { return }
    let elapsed = Int((ContinuousClock.now - startedAt) / .milliseconds(1))
    if Level.isZero(pcm) {
      silentBytes += pcm.count
      if silentBytes >= Self.silenceWorthNoting, !hasWarned {
        hasWarned = true
        log.warn("silent", ["after_ms": elapsed, "hint": "System Audio Recording not allowed?"])
      }
      return
    }
    hasHeard = true
    log.debug("heard", ["after_ms": elapsed])
  }

  /// Ten seconds of nothing but silence, in bytes.
  private static let silenceWorthNoting = Int(AudioFormat.sampleRate) * 2 * 10

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
