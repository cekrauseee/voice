/// Keeps an output quiet while a dictation records, and puts back what it changed.
///
/// It mutes the output, or turns it down, which macOS lets any app do. An output is not
/// always one thing, though. A Bluetooth headset has a volume and a mute for calls, apart
/// from the ones it plays media with, and it goes into call quality when its microphone
/// opens. What was made quiet before is not quiet there, and what is changed there can
/// only be put back there. So the output is looked at again and again: while a recording
/// lasts, to make each mode it goes through quiet, and after it, for as long as a mode is
/// left to put back.
public struct OutputHold: Equatable, Sendable {
  /// How the output is kept quiet.
  public enum Kind: String, Codable, Sendable {
    case mute, lower
  }

  /// An output in one of its modes. Only a Bluetooth headset has two.
  public struct Mode: Hashable, Codable, Sendable {
    /// The identifier of the output device.
    public var output: String
    /// Whether it plays in call quality.
    public var isCall: Bool

    public init(output: String, isCall: Bool = false) {
      self.output = output
      self.isCall = isCall
    }
  }

  /// What an output is at. Nil for what it has no control of, or cannot say now.
  public struct Level: Equatable, Sendable {
    public var volume: Float?
    public var isMuted: Bool?

    public init(volume: Float?, isMuted: Bool?) {
      self.volume = volume
      self.isMuted = isMuted
    }
  }

  /// A change to make to the output.
  public enum Write: Equatable, Sendable {
    case mute(Bool)
    case volume(Float)
  }

  /// What was changed in a mode, to put back.
  public enum Change: Equatable, Codable, Sendable {
    case muted
    /// Turned down from a volume to another.
    case lowered(from: Float, to: Float)

    var kind: Kind {
      switch self {
      case .muted: .mute
      case .lowered: .lower
      }
    }
  }

  /// A volume write can take a moment to show up on the output.
  private enum VolumeWrite: Equatable, Sendable {
    case waiting(at: Float, for: Float)
    case read
  }

  /// How much of the volume is left while recording, unless a recording says.
  public static let share: Float = 0.3
  /// How long a mode is watched after it is made quiet. A headset that arrives in call
  /// quality says so before it brings back the mute it had there.
  static let settling: Duration = .milliseconds(1500)
  /// How close a volume has to be to the one that was set to be the same one.
  static let same: Float = 0.02
  /// How far from the volume it was given an output can round it.
  static let rounding: Float = 0.08

  /// What was changed and is not put back yet. It is kept between two runs of the app, so
  /// what a run did not live to put back is put back by the next.
  public private(set) var changes: [Mode: Change]
  /// How the recording that lasts keeps the output quiet.
  private var kind: Kind?
  /// How much of the volume the recording that lasts leaves, when it turns it down.
  private var share = OutputHold.share
  /// Until when each mode is watched.
  private var watched: [Mode: Duration] = [:]
  /// Which of our volume writes have been read back.
  private var volumeWrites: [Mode: VolumeWrite] = [:]
  /// The modes whose own volume came back once. A second time it is left alone, so a
  /// volume is never turned down again and again.
  private var cameBack: Set<Mode> = []
  /// The modes given back before the recording is over.
  private var given: Set<Mode> = []

  public init(changes: [Mode: Change] = [:]) {
    self.changes = changes
  }

  /// Whether a recording lasts.
  public var isHolding: Bool {
    kind != nil
  }

  /// Whether the output is to be looked at: a recording lasts, or something is left to put
  /// back.
  public var isWatching: Bool {
    kind != nil || !changes.isEmpty
  }

  /// A recording starts, or another one does before the last was over. `share` is how
  /// much of the volume it leaves, when it turns it down.
  public mutating func begin(_ kind: Kind, share: Float = OutputHold.share) {
    self.kind = kind
    self.share = share
    watched = [:]
    cameBack = []
    given = []
  }

  /// The recording is over, and sound is back to normal: what was changed is put back as
  /// each mode is looked at.
  public mutating func end() {
    kind = nil
    watched = [:]
    cameBack = []
    given = []
  }

  /// The output is in a mode, at a level. Returns what to change, if anything.
  ///
  /// - Parameter now: The time on any clock that only goes forward.
  public mutating func look(at mode: Mode, _ level: Level, now: Duration) -> Write? {
    guard let kind, !given.contains(mode) else { return putBack(mode, level) }
    guard let change = changes[mode] else { return quiet(kind, mode, level, now) }
    // Quiet of the other kind is left from an earlier recording.
    guard change.kind == kind else { return putBack(mode, level) }
    let firstLook = watched[mode] == nil
    let until = watched[mode] ?? now + Self.settling
    guard now < until else {
      if case .waiting = volumeWrites[mode] { volumeWrites[mode] = nil }
      return nil
    }
    if change.kind == .lower, level.volume == nil { return nil }
    watched[mode] = until
    return keep(mode, level, firstLook: firstLook)
  }

  /// Remembers where our write left the volume. The old level may still be there for a
  /// moment, so it is checked again later.
  public mutating func didSetVolume(_ volume: Float, in mode: Mode) {
    guard case .waiting(let before, _) = volumeWrites[mode], volume != before,
      case .lowered(let from, _) = changes[mode]
    else { return }
    changes[mode] = .lowered(from: from, to: volume)
    volumeWrites[mode] = .read
  }

  /// A write the output refused has no new volume to look for.
  public mutating func volumeWriteFailed(in mode: Mode) {
    volumeWrites[mode] = nil
  }

  /// The output is about to leave a mode, before the recording is over for the others: a
  /// headset leaving call quality. The mode is put back, and left alone from then on.
  public mutating func leave(_ mode: Mode, _ level: Level) -> Write? {
    given.insert(mode)
    return putBack(mode, level)
  }

  /// Puts a mode back the way it was. A mode that cannot say what it is at stays to put
  /// back.
  public mutating func putBack(_ mode: Mode, _ level: Level) -> Write? {
    if let volume = level.volume { readRoundedVolume(volume, in: mode) }
    switch changes[mode] {
    case nil:
      return nil
    case .muted:
      guard let isMuted = level.isMuted else { return nil }
      changes[mode] = nil
      return isMuted ? .mute(false) : nil
    case .lowered(let from, let to):
      guard let volume = level.volume else { return nil }
      let restore = matches(volume, to, in: mode)
      changes[mode] = nil
      volumeWrites[mode] = nil
      // A volume that is not the one it was left at was changed meanwhile: it is where
      // it is wanted.
      return restore ? .volume(from) : nil
    }
  }

  private mutating func quiet(_ kind: Kind, _ mode: Mode, _ level: Level, _ now: Duration)
    -> Write?
  {
    switch kind {
    case .mute:
      // An output that is muted already is not this to unmute.
      guard level.isMuted == false else { return nil }
      changes[mode] = .muted
      watched[mode] = now + Self.settling
      return .mute(true)
    case .lower:
      guard let volume = level.volume, volume > 0, level.isMuted != true else { return nil }
      watched[mode] = now + Self.settling
      return lower(mode, from: volume, at: volume)
    }
  }

  private mutating func lower(_ mode: Mode, from: Float, at volume: Float, keeping to: Float? = nil)
    -> Write
  {
    let target = from * share
    // If a mode was quiet already, keep that level until the new write shows up.
    changes[mode] = .lowered(from: from, to: to ?? target)
    volumeWrites[mode] = .waiting(at: volume, for: target)
    return .volume(target)
  }

  private func matches(_ volume: Float, _ to: Float, in mode: Mode) -> Bool {
    if volumeWrites[mode] == .read { return volume == to }
    return abs(volume - to) < Self.same
  }

  /// A write can show up later, rounded to a level the device can play.
  private mutating func readRoundedVolume(_ volume: Float, in mode: Mode) {
    guard case .waiting(_, let target) = volumeWrites[mode],
      volume == 0 || abs(volume - target) <= Self.rounding || cameBack.contains(mode)
    else { return }
    didSetVolume(volume, in: mode)
  }

  /// Makes a mode quiet again when it is not anymore, a moment after it was made so.
  private mutating func keep(_ mode: Mode, _ level: Level, firstLook: Bool) -> Write? {
    if let volume = level.volume { readRoundedVolume(volume, in: mode) }
    switch changes[mode] {
    case nil:
      return nil
    case .muted:
      return level.isMuted == false ? .mute(true) : nil
    case .lowered(let from, let to):
      guard let volume = level.volume else { return nil }
      // Quiet left from an earlier recording is still based on its original volume.
      if firstLook, volume == to, from * share != to {
        return lower(mode, from: from, at: volume, keeping: to)
      }
      guard !cameBack.contains(mode), volume > 0, level.isMuted != true,
        abs(volume - to) > Self.rounding
      else { return nil }
      // The volume the mode had came back: it is turned down from there.
      cameBack.insert(mode)
      return lower(mode, from: volume, at: volume)
    }
  }
}
