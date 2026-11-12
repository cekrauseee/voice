import CoreAudio

/// The audio devices of the Mac, as Core Audio knows them.
enum AudioDevice {
  /// The device with an identifier, as a capture device reports it, while it is connected.
  static func withID(_ id: String) -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslateUIDToDevice,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var uid = id as CFString
    var device = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = withUnsafeMutablePointer(to: &uid) {
      AudioObjectGetPropertyData(
        AudioObjectID(kAudioObjectSystemObject), &address,
        UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
    }
    return status == noErr && device != kAudioObjectUnknown ? device : nil
  }

  /// Reads a property of an audio object that holds a single value.
  static func read<Value>(
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
