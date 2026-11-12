/// Gets a Bluetooth headset out of call quality after a recording, step by step.
///
/// While its microphone is open, a Bluetooth headset plays everything in call quality.
/// macOS leaves it there for two seconds after the microphone closes. Asking the headset
/// for its best sample rate takes it out at once.
public struct CallQualityExit {
  /// What the headset that plays sound is doing.
  public struct Headset: Equatable, Sendable {
    /// It plays in call quality.
    public var isInCallQuality: Bool
    /// Its microphone is the one that records, so a recording puts it in call quality.
    public var isMicrophone: Bool
    /// A microphone is open, in this app or another.
    public var microphoneIsOpen: Bool

    public init(isInCallQuality: Bool, isMicrophone: Bool, microphoneIsOpen: Bool) {
      self.isInCallQuality = isInCallQuality
      self.isMicrophone = isMicrophone
      self.microphoneIsOpen = microphoneIsOpen
    }
  }

  public enum Step: Equatable, Sendable {
    /// Look again in a moment.
    case wait
    /// Ask the headset for its best sample rate.
    case ask
    /// Sound plays normally, or will not get better by waiting.
    case done
  }

  /// How long after a recording the headset can still be on its way into call quality,
  /// and how long this recording's microphone can take to close.
  static let settling: Duration = .milliseconds(500)

  private var hasAsked = false

  public init() {}

  /// What to do now.
  ///
  /// - Parameters:
  ///   - headset: What the headset is doing now.
  ///   - elapsed: The time since the recording ended.
  public mutating func step(_ headset: Headset, after elapsed: Duration) -> Step {
    if headset.isInCallQuality {
      if headset.microphoneIsOpen {
        // Past the settling time it is another app that records: the headset stays in
        // call quality for as long as it does.
        return elapsed < Self.settling ? .wait : .done
      }
      // Asking twice makes the headset start over.
      guard !hasAsked else { return .wait }
      hasAsked = true
      return .ask
    }
    // A recording can end before the headset is in call quality. It still goes there.
    if !hasAsked, headset.isMicrophone, elapsed < Self.settling { return .wait }
    return .done
  }

  /// The headset did not take the request: ask again.
  public mutating func askFailed() {
    hasAsked = false
  }
}
