import CoreAudio

/// The audio devices of the Mac, as Core Audio knows them.
enum AudioDevice {
  private static let system = AudioObjectID(kAudioObjectSystemObject)

  /// The device the Mac plays sound through.
  static var output: AudioObjectID? {
    known(read(system, kAudioHardwarePropertyDefaultOutputDevice))
  }

  /// The device the Mac records with, unless another is chosen.
  static var input: AudioObjectID? {
    known(read(system, kAudioHardwarePropertyDefaultInputDevice))
  }

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
        system, &address, UInt32(MemoryLayout<CFString>.size), $0, &size, &device)
    }
    return status == noErr ? known(device) : nil
  }

  static func isBluetooth(_ device: AudioObjectID) -> Bool {
    let transport: UInt32? = read(device, kAudioDevicePropertyTransportType)
    return transport == kAudioDeviceTransportTypeBluetooth
      || transport == kAudioDeviceTransportTypeBluetoothLE
  }

  /// The sample rate a device runs at, and the best one it has. A Bluetooth headset runs
  /// below its best while it is in call quality.
  static func rates(of device: AudioObjectID) -> (now: Float64, best: Float64)? {
    guard let now: Float64 = read(device, kAudioDevicePropertyNominalSampleRate) else {
      return nil
    }
    let ranges: [AudioValueRange] = list(device, kAudioDevicePropertyAvailableNominalSampleRates)
    return (now, ranges.map(\.mMaximum).max() ?? now)
  }

  /// The apps that use audio, other than this one, as Core Audio knows them.
  @available(macOS 14.2, *)
  static var otherProcesses: [AudioObjectID] {
    let own = process(getpid())
    return list(system, kAudioHardwarePropertyProcessObjectList).filter { $0 != own }
  }

  /// The audio object of a process, once it uses Core Audio.
  @available(macOS 14.2, *)
  static func process(_ pid: pid_t) -> AudioObjectID? {
    var address = AudioObjectPropertyAddress(
      mSelector: kAudioHardwarePropertyTranslatePIDToProcessObject,
      mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    var pid = pid
    var process = AudioObjectID(kAudioObjectUnknown)
    var size = UInt32(MemoryLayout<AudioObjectID>.size)
    let status = AudioObjectGetPropertyData(
      system, &address, UInt32(MemoryLayout<pid_t>.size), &pid, &size, &process)
    return status == noErr ? known(process) : nil
  }

  /// Reads a property of an audio object that holds a single value.
  static func read<Value>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> Value? {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size = UInt32(MemoryLayout<Value>.size)
    let value = UnsafeMutablePointer<Value>.allocate(capacity: 1)
    defer { value.deallocate() }
    guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, value) == noErr else {
      return nil
    }
    return value.pointee
  }

  /// Reads a property of an audio object that holds several values. Empty when it cannot
  /// be read.
  static func list<Value>(
    _ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
    scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
  ) -> [Value] {
    var address = AudioObjectPropertyAddress(
      mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    var size: UInt32 = 0
    guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0
    else { return [] }
    let count = Int(size) / MemoryLayout<Value>.stride
    return [Value](unsafeUninitializedCapacity: count) { buffer, initialized in
      let status = AudioObjectGetPropertyData(object, &address, 0, nil, &size, buffer.baseAddress!)
      initialized = status == noErr ? Int(size) / MemoryLayout<Value>.stride : 0
    }
  }

  private static func known(_ object: AudioObjectID?) -> AudioObjectID? {
    object == kAudioObjectUnknown ? nil : object
  }
}
