/// Where the user is in the first-launch setup.
public struct Onboarding: Equatable, Sendable {
  public enum Step: CaseIterable, Sendable {
    case accessibility
    case microphone
    case tryIt
  }

  public enum StepState: Equatable, Sendable {
    case done
    /// The step to act on now.
    case current
    /// A step that waits for an earlier one.
    case upcoming
  }

  public var accessibility: Bool
  public var microphone: Bool
  /// Whether a dictation produced text during the setup.
  public var hasDictated: Bool

  public init(accessibility: Bool, microphone: Bool, hasDictated: Bool = false) {
    self.accessibility = accessibility
    self.microphone = microphone
    self.hasDictated = hasDictated
  }

  /// The first step that is not done, in order.
  public var current: Step? {
    Step.allCases.first { !isDone($0) }
  }

  /// Whether the app can be used. Trying it is optional.
  public var canFinish: Bool {
    accessibility && microphone
  }

  public func state(of step: Step) -> StepState {
    if isDone(step) { return .done }
    return step == current ? .current : .upcoming
  }

  private func isDone(_ step: Step) -> Bool {
    switch step {
    case .accessibility: accessibility
    case .microphone: microphone
    case .tryIt: hasDictated
    }
  }
}
