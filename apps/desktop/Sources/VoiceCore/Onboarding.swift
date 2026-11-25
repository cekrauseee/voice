/// Where the user is in the first-launch setup.
public struct Onboarding: Equatable, Sendable {
  public enum Step: CaseIterable, Sendable {
    case accessibility
    case microphone
    case tryIt
    /// Telling the app about yourself.
    case profile

    /// Whether the app can be used without it.
    public var isOptional: Bool {
      self == .tryIt || self == .profile
    }
  }

  public enum StepState: Equatable, Sendable {
    case done
    /// A step to act on now.
    case current
    /// A step that waits for an earlier one.
    case upcoming
  }

  public var accessibility: Bool
  public var microphone: Bool
  /// Whether a dictation produced text during the setup.
  public var hasDictated: Bool
  /// Whether the user has a profile written for them.
  public var hasProfile: Bool

  public init(
    accessibility: Bool, microphone: Bool, hasDictated: Bool = false, hasProfile: Bool = false
  ) {
    self.accessibility = accessibility
    self.microphone = microphone
    self.hasDictated = hasDictated
    self.hasProfile = hasProfile
  }

  /// The first step that is not done, in order.
  public var current: Step? {
    Step.allCases.first { !isDone($0) }
  }

  /// Whether the app can be used. Trying it and the profile are optional.
  public var canFinish: Bool {
    accessibility && microphone
  }

  /// A step waits for the steps before it, but not for one that is optional: once the app can
  /// be used, trying it and the profile can be taken in either order.
  public func state(of step: Step) -> StepState {
    if isDone(step) { return .done }
    let before = Step.allCases.prefix { $0 != step }
    return before.allSatisfy { isDone($0) || $0.isOptional } ? .current : .upcoming
  }

  private func isDone(_ step: Step) -> Bool {
    switch step {
    case .accessibility: accessibility
    case .microphone: microphone
    case .tryIt: hasDictated
    case .profile: hasProfile
    }
  }
}
