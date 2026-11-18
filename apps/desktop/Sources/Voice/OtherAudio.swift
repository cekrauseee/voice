import CoreAudio
import Foundation
import VoiceCore

/// Mutes what the other apps play, while a dictation records. Only the app macOS shows as
/// playing can be paused: another one, such as a music player while a browser holds that
/// place, keeps playing, unheard.
///
/// There are two ways. With the System Audio Recording permission it mutes the other apps
/// alone. Without it, it mutes the Mac's output, which needs no permission: see
/// `MediaMuting`. It never asks for the permission by itself.
///
/// It taps the other apps' sound with Core Audio, muted, and reads nothing from the tap.
/// macOS allows that with the System Audio Recording permission, which it asks for the
/// first time, and shows as recording meanwhile. So it does that only while another app
/// plays sound. When the app quits, the tap goes, and the sound comes back by itself.
///
/// A muted output stays muted when the app quits, so the app keeps note of the output it
/// muted, and unmutes it the next time it opens.
final class OtherAudio: @unchecked Sendable {
  private let log = Log("media")
  /// Creating and removing the tap wait for Core Audio, so they run here. What follows is
  /// only touched on it.
  private let queue = DispatchQueue(label: "eu.cekrause.voice.other-audio")
  private var tap = AudioObjectID(kAudioObjectUnknown)
  private var device = AudioObjectID(kAudioObjectUnknown)
  private var reading: AudioDeviceIOProcID?
  /// The output this muted, until it unmutes it.
  private var mutedOutput: AudioObjectID?

  /// The output muted by a dictation that the app did not live to unmute.
  private static let leftMuted = "mutedOutput"

  init() {
    queue.async {
      guard let uid = UserDefaults.standard.string(forKey: Self.leftMuted) else { return }
      UserDefaults.standard.removeObject(forKey: Self.leftMuted)
      if let device = AudioDevice.withID(uid) { Self.setMuted(device, false) }
    }
  }

  /// Whether the output the Mac plays through can be muted. Some cannot, such as most
  /// displays: their sound can only be taken away app by app.
  static var canMuteOutput: Bool {
    guard let device = output() else { return false }
    var address = muteAddress
    var isSettable: DarwinBoolean = false
    return AudioObjectHasProperty(device, &address)
      && AudioObjectIsPropertySettable(device, &address, &isSettable) == noErr
      && isSettable.boolValue
  }

  func mute(_ muting: MediaMuting) {
    queue.async { [self] in
      guard tap == kAudioObjectUnknown, mutedOutput == nil else { return }
      switch muting {
      case .apps:
        guard #available(macOS 14.2, *), Self.othersPlay() else { return }
        if open() {
          log.debug("others muted")
        } else {
          close()
        }
      case .output:
        muteOutput()
      }
    }
  }

  /// Mutes the output, unless it is muted already: then it is not this app's to unmute.
  private func muteOutput() {
    guard let device = Self.output(), Self.canMuteOutput, Self.isMuted(device) == false,
      Self.setMuted(device, true)
    else { return }
    mutedOutput = device
    let uid: CFString? = AudioDevice.read(device, kAudioDevicePropertyDeviceUID)
    UserDefaults.standard.set(uid as String?, forKey: Self.leftMuted)
    log.debug("output muted")
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
    if let mutedOutput {
      Self.setMuted(mutedOutput, false)
      self.mutedOutput = nil
      UserDefaults.standard.removeObject(forKey: Self.leftMuted)
      log.debug("output heard")
    }
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

  private static let muteAddress = AudioObjectPropertyAddress(
    mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput,
    mElement: kAudioObjectPropertyElementMain)

  /// The device the Mac plays sound through.
  private static func output() -> AudioObjectID? {
    AudioDevice.read(
      AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice)
  }

  private static func isMuted(_ device: AudioObjectID) -> Bool? {
    var address = muteAddress
    var muted: UInt32 = 0
    var size = UInt32(MemoryLayout<UInt32>.size)
    guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr else {
      return nil
    }
    return muted != 0
  }

  @discardableResult
  private static func setMuted(_ device: AudioObjectID, _ muted: Bool) -> Bool {
    var address = muteAddress
    var value: UInt32 = muted ? 1 : 0
    let size = UInt32(MemoryLayout<UInt32>.size)
    return AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr
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
