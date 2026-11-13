/// Whether pasting a completed dictation also presses Enter.
public enum EnterBehavior: String, CaseIterable, Sendable {
  case never, withShift, always

  public var title: String {
    switch self {
    case .never: "Never"
    case .withShift: "With Shift"
    case .always: "Always"
    }
  }
}

/// Output preferences and the stop gesture belong to one dictation, even if another starts.
@MainActor
public final class DictationDelivery {
  public let keepOnClipboard: Bool
  public let enterBehavior: EnterBehavior
  private var submits = false

  public init(keepOnClipboard: Bool = false, enterBehavior: EnterBehavior = .never) {
    self.keepOnClipboard = keepOnClipboard
    self.enterBehavior = enterBehavior
  }

  public func stop(shiftHeld: Bool) {
    submits = enterBehavior == .always || (enterBehavior == .withShift && shiftHeld)
  }

  /// A failed dictation may paste its draft, but must not submit it.
  public func pressesEnter(text: String, failed: Bool) -> Bool {
    submits && !text.isEmpty && !failed
  }
}
