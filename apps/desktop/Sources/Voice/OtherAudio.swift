import CoreAudio
import Foundation

/// Mutes what the other apps play, while a dictation records. Only the app macOS shows as
/// playing can be paused: another one, such as a music player while a browser holds that
/// place, keeps playing, unheard.
///
/// It taps the other apps' sound with Core Audio, muted, and reads nothing from the tap.
/// macOS allows that with the System Audio Recording permission, which it asks for the
/// first time, and shows as recording meanwhile. So it does that only while another app
/// plays sound. When the app quits, the tap goes, and the sound comes back by itself.
final class OtherAudio: @unchecked Sendable {
  private let log = Log("media")
  /// Creating and removing the tap wait for Core Audio, so they run here. What follows is
  /// only touched on it.
  private let queue = DispatchQueue(label: "eu.cekrause.voice.other-audio")
  private var tap = AudioObjectID(kAudioObjectUnknown)
  private var device = AudioObjectID(kAudioObjectUnknown)
  private var reading: AudioDeviceIOProcID?

  func mute() {
    guard #available(macOS 14.2, *) else { return }
    queue.async { [self] in
      guard tap == kAudioObjectUnknown, Self.othersPlay() else { return }
      if open() {
        log.debug("others muted")
      } else {
        close()
      }
    }
  }

  func unmute() {
    queue.async { [self] in close() }
  }

  @available(macOS 14.2, *)
  private func open() -> Bool {
    let own = Self.process(getpid()).map { [$0] } ?? []
    let description = CATapDescription(stereoGlobalTapButExcludeProcesses: own)
    description.muteBehavior = .muted
    description.isPrivate = true
    var status = AudioHardwareCreateProcessTap(description, &tap)
    guard status == noErr else {
      log.error("others not muted", ["status": status])
      return false
    }
    // The tap runs in a device of its own, which macOS asks the permission for.
    let aggregate: [String: Any] = [
      kAudioAggregateDeviceNameKey: AppInfo.name,
      kAudioAggregateDeviceUIDKey: UUID().uuidString,
      kAudioAggregateDeviceIsPrivateKey: true,
      kAudioAggregateDeviceTapAutoStartKey: true,
      kAudioAggregateDeviceTapListKey: [[kAudioSubTapUIDKey: description.uuid.uuidString]],
    ]
    status = AudioHardwareCreateAggregateDevice(aggregate as CFDictionary, &device)
    guard status == noErr else {
      log.error("others not muted", ["status": status])
      return false
    }
    // Read on the device's own thread: stopping it from the queue waits for the reading.
    status = AudioDeviceCreateIOProcIDWithBlock(&reading, device, nil) { _, _, _, _, _ in }
    guard status == noErr, let reading else {
      log.error("others not muted", ["status": status])
      return false
    }
    status = AudioDeviceStart(device, reading)
    guard status == noErr else {
      log.error("others not muted", ["status": status])
      return false
    }
    return true
  }

  private func close() {
    if let reading {
      AudioDeviceStop(device, reading)
      AudioDeviceDestroyIOProcID(device, reading)
      self.reading = nil
    }
    if device != kAudioObjectUnknown {
      AudioHardwareDestroyAggregateDevice(device)
      device = AudioObjectID(kAudioObjectUnknown)
    }
    if tap != kAudioObjectUnknown {
      if #available(macOS 14.2, *) { AudioHardwareDestroyProcessTap(tap) }
      tap = AudioObjectID(kAudioObjectUnknown)
      log.debug("others heard")
    }
  }

  /// Whether an app other than this one plays sound now.
  @available(macOS 14.2, *)
  private static func othersPlay() -> Bool {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let system = AudioObjectID(kAudioObjectSystemObject)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
      return false
    }
    var processes = [AudioObjectID](
      repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &processes) == noErr
    else { return false }
    let own = process(getpid())
    return processes.contains { process in
      let isPlaying: UInt32? = AudioDevice.read(process, kAudioProcessPropertyIsRunningOutput)
      return process != own && isPlaying == 1
    }
  }

  /// The audio object of a process, once it uses Core Audio.
  @available(macOS 14.2, *)
  private static func process(_ pid: pid_t) -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var pid = pid
    var process = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
      AudioObjectID(kAudioObjectSystemObject), &address, UInt32(MemoryLayout<pid_t>.size),
      &pid, &size, &process)
    return status == noErr && process != kAudioObjectUnknown ? process : nil
  }
}
