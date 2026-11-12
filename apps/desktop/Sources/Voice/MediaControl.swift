import AudioToolbox
import CoreAudio
import Foundation
import VoiceCore
import os

/// Asks about and commands the media playing on the Mac, whichever app plays it, and gets
/// its sound back to normal after a recording.
///
/// macOS has no public interface for another app's playback. Asking and commanding use the
/// system's media remote, which is private: when it is not there, or not allowed, the
/// answer is that nothing is playing and the commands do nothing.
enum MediaControl {
  /// Whether an app is playing media now.
  ///
  /// macOS only tells its own programs what is playing, so the question goes through one
  /// of them: the system's script runner.
  static func isPlaying() async -> Bool {
    await withCheckedContinuation { continuation in
      nonisolated(unsafe) let process = Process()
      process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
      process.arguments = ["-l", "JavaScript", "-e", question]
      process.standardOutput = Pipe()
      process.standardError = FileHandle.nullDevice
      // Out of the way of the pill, which shows at the same moment.
      process.qualityOfService = .utility
      process.terminationHandler = { process in
        let output = (process.standardOutput as? Pipe)?.fileHandleForReading.readDataToEndOfFile()
        let answer = String(decoding: output ?? Data(), as: UTF8.self)
        continuation.resume(returning: answer.hasPrefix("true"))
      }
      do {
        try process.run()
      } catch {
        continuation.resume(returning: false)
        return
      }
      // An answer that does not come is a no.
      DispatchQueue.global().asyncAfter(deadline: .now() + 2) {
        if process.isRunning { process.terminate() }
      }
    }
  }

  /// Sends a command to the app playing media. Pausing what is paused, or playing what
  /// plays, changes nothing.
  static func send(_ command: MediaPause.Command) {
    guard let sendCommand else { return }
    _ = sendCommand(command == .play ? 0 : 1, nil)
    Log("media").debug("sent", ["command": command])
  }

  /// Gets sound back to normal after a recording, and returns once it is, or after five
  /// seconds. `microphone` is the identifier of the device that recorded.
  ///
  /// A Bluetooth headset plays in call quality while its microphone is open, and macOS
  /// leaves it there for two seconds after. Asked for its best quality, it leaves at once,
  /// but plays nothing for about a second more, while its link comes back. Media resumed
  /// before then is cut or flat, so this returns once the headset plays again.
  static func soundIsBack(microphone: String?) async {
    let input = microphone.flatMap(AudioDevice.withID) ?? defaultInput()
    let startedAt = ContinuousClock.now
    var exit = CallQualityExit()
    var asked = false
    waiting: while ContinuousClock.now - startedAt < .seconds(5) {
      switch exit.step(headset(input), after: ContinuousClock.now - startedAt) {
      case .done:
        break waiting
      case .ask:
        asked = true
        if !askForBestQuality() { exit.askFailed() }
      case .wait:
        break
      }
      guard (try? await Task.sleep(for: .milliseconds(25))) != nil else { return }
    }
    if asked, !Task.isCancelled {
      await Silence.play(within: .seconds(5) - (ContinuousClock.now - startedAt))
    }
    let waited = Int((ContinuousClock.now - startedAt) / .milliseconds(1))
    Log("media").debug("sound back", ["wait_ms": waited, "asked": asked])
  }

  /// What the device that plays sound is doing, with `input` the one that recorded.
  private static func headset(_ input: AudioObjectID?) -> CallQualityExit.Headset {
    let isRunning: UInt32? = input.flatMap {
      AudioDevice.read($0, kAudioDevicePropertyDeviceIsRunningSomewhere)
    }
    let rates = output().flatMap(rates)
    return CallQualityExit.Headset(
      // Below its best sample rate, which is what a headset does while its microphone
      // is open.
      isInCallQuality: rates.map { $0.now < $0.best } ?? false,
      isMicrophone: rates != nil && input.map(isBluetooth) == true,
      microphoneIsOpen: isRunning.map { $0 != 0 } ?? false)
  }

  /// Asks the headset for its best sample rate. Returns whether it took the request.
  private static func askForBestQuality() -> Bool {
    guard let device = output(), var best = rates(device)?.best else { return false }
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyNominalSampleRate,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let size = UInt32(MemoryLayout<Float64>.size)
    return AudioObjectSetPropertyData(device, &address, 0, nil, size, &best) == noErr
  }

  private static func defaultInput() -> AudioObjectID? {
    AudioDevice.read(
      AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice)
  }

  /// The device that plays sound, when it is a Bluetooth headset.
  private static func output() -> AudioObjectID? {
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard
      let device: AudioObjectID = AudioDevice.read(
        system, kAudioHardwarePropertyDefaultOutputDevice),
      isBluetooth(device)
    else { return nil }
    return device
  }

  private static func isBluetooth(_ device: AudioObjectID) -> Bool {
    let transport: UInt32? = AudioDevice.read(device, kAudioDevicePropertyTransportType)
    return transport == kAudioDeviceTransportTypeBluetooth
      || transport == kAudioDeviceTransportTypeBluetoothLE
  }

  /// The sample rate a device runs at, and the best one it has.
  private static func rates(_ device: AudioObjectID) -> (now: Float64, best: Float64)? {
    guard let now: Float64 = AudioDevice.read(device, kAudioDevicePropertyNominalSampleRate) else {
      return nil
    }
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else {
      return nil
    }
    var ranges = [AudioValueRange](
      repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &ranges) == noErr else {
      return nil
    }
    return (now, ranges.map(\.mMaximum).max() ?? now)
  }

  private static let question = """
    ObjC.import("Foundation");
    $.NSBundle.bundleWithPath("\(framework)").load;
    $.NSClassFromString("MRNowPlayingRequest").localIsPlaying ? "true" : "false";
    """

  private static let framework = "/System/Library/PrivateFrameworks/MediaRemote.framework"

  private typealias SendCommand = @convention(c) (UInt32, CFDictionary?) -> Bool

  private static let sendCommand: SendCommand? = {
    guard let handle = dlopen("\(framework)/MediaRemote", RTLD_LAZY),
      let symbol = dlsym(handle, "MRMediaRemoteSendCommand")
    else { return nil }
    return unsafeBitCast(symbol, to: SendCommand.self)
  }()
}

/// A moment of silence played through the device that plays sound, to tell when it plays:
/// starting a sound waits for the device, about a second for a Bluetooth headset that just
/// left call quality.
private final class Silence: @unchecked Sendable {
  private static let format = AudioStreamBasicDescription(
    mSampleRate: 48_000, mFormatID: kAudioFormatLinearPCM,
    mFormatFlags: kLinearPCMFormatFlagIsFloat | kLinearPCMFormatFlagIsPacked,
    mBytesPerPacket: 8, mFramesPerPacket: 1, mBytesPerFrame: 8, mChannelsPerFrame: 2,
    mBitsPerChannel: 32, mReserved: 0)
  /// 10 ms.
  private static let bufferBytes = UInt32(480 * 8)

  private let waiting = OSAllocatedUnfairLock<CheckedContinuation<Void, Never>?>(
    initialState: nil)
  private let played = DispatchSemaphore(value: 0)

  /// Returns once the silence plays, after `limit`, or when the task is cancelled.
  static func play(within limit: Duration) async {
    let silence = Silence()
    let limit = DispatchTimeInterval.milliseconds(max(Int(limit / .milliseconds(1)), 0))
    await withTaskCancellationHandler {
      await withCheckedContinuation { continuation in
        silence.waiting.withLock { $0 = continuation }
        DispatchQueue.global().asyncAfter(deadline: .now() + limit) { silence.finish() }
        DispatchQueue.global(qos: .utility).async { silence.run(within: limit) }
      }
    } onCancel: {
      silence.finish()
    }
  }

  private func run(within limit: DispatchTimeInterval) {
    var format = Self.format
    var queue: AudioQueueRef?
    guard
      AudioQueueNewOutput(
        &format,
        { context, _, _ in
          Unmanaged<Silence>.fromOpaque(context!).takeUnretainedValue().finish()
        }, Unmanaged.passUnretained(self).toOpaque(), nil, nil, 0, &queue) == noErr,
      let queue
    else { return finish() }
    defer { AudioQueueDispose(queue, true) }
    for _ in 0..<2 {
      var buffer: AudioQueueBufferRef?
      guard AudioQueueAllocateBuffer(queue, Self.bufferBytes, &buffer) == noErr, let buffer
      else { return finish() }
      memset(buffer.pointee.mAudioData, 0, Int(Self.bufferBytes))
      buffer.pointee.mAudioDataByteSize = Self.bufferBytes
      AudioQueueEnqueueBuffer(queue, buffer, 0, nil)
    }
    // Starting waits for the device, and the first buffer played says it plays.
    guard AudioQueueStart(queue, nil) == noErr else { return finish() }
    _ = played.wait(timeout: .now() + limit)
    AudioQueueStop(queue, true)
  }

  private func finish() {
    let continuation = waiting.withLock { waiting in
      defer { waiting = nil }
      return waiting
    }
    guard let continuation else { return }
    continuation.resume()
    played.signal()
  }
}
