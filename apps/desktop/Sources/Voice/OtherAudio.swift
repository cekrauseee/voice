import CoreAudio
import Foundation
import VoiceCore

/// Keeps what the other apps play out of a dictation, while it records. Only the app macOS
/// shows as playing can be paused: another one, such as a music player while a browser
/// holds that place, keeps playing, unheard.
///
/// There are two ways. With the System Audio Recording permission it mutes the other apps
/// alone, with a tap. Without it, or to turn them down, it changes the Mac's output, which
/// needs no permission: see `MediaMuting`. It never asks for the permission by itself.
///
/// The tap is on the other apps' sound with Core Audio, muted, and nothing is read from
/// it. macOS allows that with the permission, and shows the app as recording meanwhile. So
/// it taps only while another app plays sound. When the app quits, the tap goes, and the
/// sound comes back by itself.
///
/// An output that was muted or turned down stays so when the app quits, and a Bluetooth
/// headset has to be made quiet again in call quality: see `OutputHold`, which says what to
/// change as the output is looked at. What is left to put back is kept between two runs of
/// the app.
final class OtherAudio: @unchecked Sendable {
  private let log = Log("media")
  /// Creating and removing the tap wait for Core Audio, so they run here. What follows is
  /// only touched on it.
  private let queue = DispatchQueue(label: "eu.cekrause.voice.other-audio")
  private var tap = AudioObjectID(kAudioObjectUnknown)
  private var device = AudioObjectID(kAudioObjectUnknown)
  private var reading: AudioDeviceIOProcID?
  /// What the output is kept at, and what is left to put back.
  private var hold: OutputHold
  /// Looks at the output while there is a reason to.
  private var watch: DispatchSourceTimer?
  /// Whether macOS lets this app mute the other apps, as of the last recording.
  private var canMuteApps = false
  private let startedAt = ContinuousClock.now

  /// What an earlier run of the app changed and did not put back.
  private static let saved = "outputChanges"
  /// How often the output is looked at: often while a recording lasts, so a headset is
  /// quiet again before it plays in call quality, and now and then while something is
  /// only left to put back.
  private static let often: DispatchTimeInterval = .milliseconds(50)
  private static let nowAndThen: DispatchTimeInterval = .milliseconds(500)

  init() {
    let saved = UserDefaults.standard.data(forKey: Self.saved)
    let changes = saved.flatMap {
      try? JSONDecoder().decode([OutputHold.Mode: OutputHold.Change].self, from: $0)
    }
    hold = OutputHold(changes: changes ?? [:])
    queue.async { [self] in
      look()
      watchOutput()
    }
  }

  /// Whether the output the Mac plays through can be muted. Some cannot, such as most
  /// displays: their sound can only be taken away app by app.
  static var canMuteOutput: Bool {
    AudioDevice.output.map(AudioDevice.canMute) ?? false
  }

  /// Makes the other apps quiet. A dictation that starts before the last one was over asks
  /// again. `appsAllowed` is whether macOS lets this app mute the other apps.
  func mute(_ muting: MediaMuting, appsAllowed: Bool) {
    queue.async { [self] in
      canMuteApps = appsAllowed
      if let kind = muting.hold {
        if case .lowerOutput(let share) = muting {
          hold.begin(kind, share: share)
        } else {
          hold.begin(kind)
        }
        look()
        watchOutput()
        return
      }
      guard tap == kAudioObjectUnknown, #available(macOS 14.2, *), Self.othersPlay() else {
        return
      }
      if open() {
        log.debug("others muted")
      } else {
        close()
      }
    }
  }

  /// Sound is back to normal after the recording: the other apps are heard again.
  func unmute() {
    queue.async { [self] in
      if hold.isHolding {
        hold.end()
        look()
        watchOutput()
      }
      close()
    }
  }

  /// The recording ended with a headset in call quality, where it was turned down. Putting
  /// that back is heard for a moment, loud and in call quality, before the headset leaves
  /// it. With the permission, the other apps are muted over that moment, until sound is
  /// back.
  func recordingEnded() {
    queue.async { [self] in
      guard hold.isHolding, canMuteApps, tap == kAudioObjectUnknown,
        let output = AudioDevice.output, Self.mode(of: output)?.isCall == true,
        #available(macOS 14.2, *), Self.othersPlay()
      else { return }
      if open() {
        log.debug("others muted")
      } else {
        close()
      }
    }
  }

  /// The headset was asked to leave call quality, and is still in it: what was changed
  /// there is put back now. Once the headset stops playing, a fifth of a second later, it
  /// cannot be anymore.
  func leavingCallQuality() {
    queue.sync {
      guard hold.isHolding, let output = AudioDevice.output, let mode = Self.mode(of: output),
        mode.isCall
      else { return }
      if let write = hold.leave(mode, Self.level(of: output)) { make(write, on: output) }
      save()
    }
  }

  /// Looks at the output, and changes what the hold says to.
  private func look() {
    let before = hold.changes
    let output = AudioDevice.output
    // What is left on an output that is not played through anymore is put back there.
    for mode in hold.changes.keys {
      guard let other = AudioDevice.withID(mode.output), other != output,
        Self.mode(of: other) == mode
      else { continue }
      if let write = hold.putBack(mode, Self.level(of: other)) { make(write, on: other) }
    }
    if let output, let mode = Self.mode(of: output) {
      let write = hold.look(
        at: mode, Self.level(of: output), now: ContinuousClock.now - startedAt)
      if let write { make(write, on: output, in: mode) }
    }
    if hold.changes != before { save() }
  }

  /// Keeps looking at the output for as long as there is a reason to.
  private func watchOutput() {
    guard hold.isWatching else {
      watch?.cancel()
      watch = nil
      return
    }
    let watch = watch ?? makeWatch()
    let interval = hold.isHolding ? Self.often : Self.nowAndThen
    watch.schedule(deadline: .now() + interval, repeating: interval)
    if self.watch == nil {
      self.watch = watch
      watch.resume()
    }
  }

  private func makeWatch() -> DispatchSourceTimer {
    let watch = DispatchSource.makeTimerSource(queue: queue)
    watch.setEventHandler { [weak self] in
      guard let self else { return }
      look()
      if !hold.isWatching { watchOutput() }
    }
    return watch
  }

  private func make(
    _ write: OutputHold.Write, on output: AudioObjectID, in mode: OutputHold.Mode? = nil
  ) {
    switch write {
    case .mute(let isMuted):
      AudioDevice.setMuted(isMuted, output)
      log.debug(isMuted ? "output muted" : "output unmuted")
    case .volume(let volume):
      let written = AudioDevice.setVolume(volume, of: output)
      if let mode {
        if !written {
          hold.volumeWriteFailed(in: mode)
        } else if Self.mode(of: output) == mode, let actual = AudioDevice.volume(of: output) {
          hold.didSetVolume(actual, in: mode)
        }
      }
      log.debug("output volume set", ["volume": String(format: "%.2f", volume)])
    }
  }

  private func save() {
    if hold.changes.isEmpty {
      UserDefaults.standard.removeObject(forKey: Self.saved)
    } else {
      UserDefaults.standard.set(try? JSONEncoder().encode(hold.changes), forKey: Self.saved)
    }
  }

  /// The mode an output is in. Nil while it cannot say: a headset between two of them.
  private static func mode(of output: AudioObjectID) -> OutputHold.Mode? {
    guard let id = AudioDevice.id(of: output) else { return nil }
    guard AudioDevice.isBluetooth(output) else { return OutputHold.Mode(output: id) }
    guard let rates = AudioDevice.rates(of: output) else { return nil }
    // Below its best sample rate, which is what a headset does while its microphone is
    // open.
    return OutputHold.Mode(output: id, isCall: rates.now < rates.best)
  }

  private static func level(of output: AudioObjectID) -> OutputHold.Level {
    OutputHold.Level(
      volume: AudioDevice.volume(of: output), isMuted: AudioDevice.isMuted(output))
  }

  @available(macOS 14.2, *)
  private func open() -> Bool {
    let own = AudioDevice.process(getpid()).map { [$0] } ?? []
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
    AudioDevice.otherProcesses.contains { process in
      let isPlaying: UInt32? = AudioDevice.read(process, kAudioProcessPropertyIsRunningOutput)
      return isPlaying == 1
    }
  }
}
