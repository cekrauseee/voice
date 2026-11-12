import CoreAudio
import Foundation
import VoiceCore

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
  /// leaves it there for two seconds after. Media resumed before it is out sounds flat.
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
    let waited = Int((ContinuousClock.now - startedAt) / .milliseconds(1))
    Log("media").debug("sound back", ["wait_ms": waited, "asked": asked])
  }

  /// What the device that plays sound is doing, with `input` the one that recorded.
  private static func headset(_ input: AudioObjectID?) -> CallQualityExit.Headset {
    let isRunning: UInt32? = input.flatMap {
      read($0, kAudioDevicePropertyDeviceIsRunningSomewhere)
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
    read(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultInputDevice)
  }

  /// The device that plays sound, when it is a Bluetooth headset.
  private static func output() -> AudioObjectID? {
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard let device: AudioObjectID = read(system, kAudioHardwarePropertyDefaultOutputDevice),
      isBluetooth(device)
    else { return nil }
    return device
  }

  private static func isBluetooth(_ device: AudioObjectID) -> Bool {
    let transport: UInt32? = read(device, kAudioDevicePropertyTransportType)
    return transport == kAudioDeviceTransportTypeBluetooth
      || transport == kAudioDeviceTransportTypeBluetoothLE
  }

  /// The sample rate a device runs at, and the best one it has.
  private static func rates(_ device: AudioObjectID) -> (now: Float64, best: Float64)? {
    guard let now: Float64 = read(device, kAudioDevicePropertyNominalSampleRate) else {
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

  /// Reads a property of an audio object that holds a single value.
  private static func read<Value>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector
  ) -> Value? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal,
      mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<Value>.size)
    let value = UnsafeMutablePointer<Value>.allocate(capacity: 1)
    defer { value.deallocate() }
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else {
      return nil
    }
    return value.pointee
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
