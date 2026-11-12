import CoreAudio
import Foundation
import VoiceCore

/// Asks about and commands the media playing on the Mac, whichever app plays it.
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
  }

  /// Returns once sound plays normally again after a recording, or after five seconds.
  ///
  /// A Bluetooth headset plays in call quality while its microphone is open, and takes a
  /// moment to leave it after the microphone closes. Media resumed before that sounds flat.
  static func soundIsBack() async {
    let deadline = ContinuousClock.now + .seconds(5)
    while isInCallQuality(), ContinuousClock.now < deadline {
      guard (try? await Task.sleep(for: .milliseconds(100))) != nil else { return }
    }
  }

  /// Whether the device that plays sound is a Bluetooth headset running below its best
  /// sample rate, which is what it does while a microphone is open on it.
  private static func isInCallQuality() -> Bool {
    let system = AudioObjectID(kAudioObjectSystemObject)
    guard let device: AudioObjectID = read(system, kAudioHardwarePropertyDefaultOutputDevice),
      let transport: UInt32 = read(device, kAudioDevicePropertyTransportType),
      transport == kAudioDeviceTransportTypeBluetooth
        || transport == kAudioDeviceTransportTypeBluetoothLE,
      let rate: Float64 = read(device, kAudioDevicePropertyNominalSampleRate)
    else { return false }

    var address = AudioObjectPropertyAddress(
      mSelector: kAudioDevicePropertyAvailableNominalSampleRates,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr else {
      return false
    }
    var rates = [AudioValueRange](
      repeating: AudioValueRange(), count: Int(size) / MemoryLayout<AudioValueRange>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rates) == noErr else {
      return false
    }
    return rate < (rates.map(\.mMaximum).max() ?? rate)
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
