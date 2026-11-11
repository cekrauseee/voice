/// Captures the next shortcut the user presses.
public struct ShortcutRecorder: Sendable {
  public enum Outcome: Equatable, Sendable {
    case captured(Shortcut)
    case cancelled
  }

  /// The modifier key pressed alone so far. It becomes the shortcut when released.
  private var candidate: ModifierKey?

  public init() {}

  /// Returns the outcome once the event completes a shortcut, or Escape cancels.
  public mutating func handle(_ event: KeyEvent) -> Outcome? {
    switch event {
    case .keyDown(let keyCode, let modifiers, _):
      candidate = nil
      if keyCode == KeyCode.escape && modifiers.isEmpty { return .cancelled }
      guard !modifiers.isEmpty || Shortcut.isFunctionKey(keyCode) else { return nil }
      return .captured(Shortcut(keyCode: keyCode, modifiers: modifiers))
    case .keyUp:
      return nil
    case .modifierChanged(let key, let isDown, let modifiers):
      if isDown {
        candidate = modifiers == key.modifier ? key : nil
        return nil
      }
      guard key == candidate else { return nil }
      candidate = nil
      return .captured(Shortcut(keyCode: key.rawValue))
    }
  }
}
