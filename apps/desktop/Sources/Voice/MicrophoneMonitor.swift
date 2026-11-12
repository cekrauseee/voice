import AppKit
import CoreAudio
import VoiceCore

/// Asks Core Audio which apps hold the microphone: what the orange dot in the menu bar knows.
enum MicrophoneMonitor {
  /// The apps recording from an input device now, apart from this one.
  @MainActor
  static func users() -> Set<MicrophoneUser> {
    var users: Set<MicrophoneUser> = []
    for process in processes() {
      let running: UInt32? = read(process, kAudioProcessPropertyIsRunningInput)
      guard running == 1, let pid: pid_t = read(process, kAudioProcessPropertyPID),
        pid != getpid()
      else { continue }
      let bundleId = (read(process, kAudioProcessPropertyBundleID) as CFString?).map {
        $0 as String
      }
      guard let bundleId, !bundleId.isEmpty else { continue }
      let name =
        MeetingApps.name(of: bundleId)
        ?? NSRunningApplication(processIdentifier: pid)?.localizedName ?? bundleId
      users.insert(MicrophoneUser(bundleId: bundleId, name: name))
    }
    return users
  }

  /// The audio objects of every process Core Audio knows.
  private static func processes() -> [AudioObjectID] {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyProcessObjectList,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    let system = AudioObjectID(kAudioObjectSystemObject)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else {
      return []
    }
    var objects = [AudioObjectID](
      repeating: AudioObjectID(kAudioObjectUnknown),
      count: Int(size) / MemoryLayout<AudioObjectID>.size)
    guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else {
      return []
    }
    return objects
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
}
