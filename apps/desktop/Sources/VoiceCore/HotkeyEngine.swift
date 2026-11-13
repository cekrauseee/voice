import Foundation

/// Turns keyboard events into dictation actions.
///
/// A shortcut made of a key with modifiers is consumed, so it never reaches the focused app.
/// A shortcut made of one modifier key still works as a modifier: a key pressed with it right
/// away makes a key combination, which cancels the push and reaches the focused app as usual.
/// Once the push has lasted longer than that, it is a dictation, and the keyboard belongs to
/// it: a key pressed by accident types nothing and ends nothing, and Escape cancels the push.
/// Space keeps the same dictation running after the push shortcut is released.
public struct HotkeyEngine: Sendable {
  public enum Action: Equatable, Sendable {
    case pushStart
    case pushEnd
    /// Keeps the current recording running after the push shortcut is released.
    case pushLock
    /// The push is dropped: its key turned out to be part of a key combination, or Escape
    /// was pressed during it.
    case pushCancel
    case toggle
    case cancel
  }

  public struct Result: Equatable, Sendable {
    public var actions: [Action] = []
    /// Whether to keep the event from the focused app.
    public var consume = false
  }

  /// How long after a modifier key goes down another key still makes a combination with
  /// it, in seconds. A key pressed later lands in a dictation.
  public static let combination: TimeInterval = 0.5

  public var pushToTalk: Shortcut
  public var toggle: Shortcut
  /// While set, Escape is consumed and cancels.
  public var capturesEscape = false

  private var pushHeld = false
  private var pushedAt: TimeInterval = 0
  private var toggleArmed = false
  private var consumedKeys: Set<UInt16> = []

  public init(pushToTalk: Shortcut, toggle: Shortcut) {
    self.pushToTalk = pushToTalk
    self.toggle = toggle
  }

  /// Handles an event that happened at `time`, in seconds on any steady clock: it only
  /// measures how long a push has lasted.
  public mutating func handle(_ event: KeyEvent, at time: TimeInterval) -> Result {
    switch event {
    case .keyDown(let keyCode, let modifiers, let isRepeat):
      keyDown(keyCode, modifiers, isRepeat, time)
    case .keyUp(let keyCode):
      keyUp(keyCode)
    case .modifierChanged(let key, let isDown, let modifiers):
      modifierChanged(key, isDown, modifiers, time)
    }
  }

  /// Whether a key pressed at `time` makes a combination with the held push-to-talk key.
  private func isCombination(at time: TimeInterval) -> Bool {
    time - pushedAt < Self.combination
  }

  private mutating func keyDown(
    _ keyCode: UInt16, _ modifiers: Modifiers, _ isRepeat: Bool, _ time: TimeInterval
  ) -> Result {
    var result = Result()
    toggleArmed = false
    if isRepeat && consumedKeys.contains(keyCode) {
      return Result(consume: true)
    }
    if pushHeld && keyCode == KeyCode.space {
      if !isRepeat {
        pushHeld = false
        result.actions.append(.pushLock)
      }
      consumedKeys.insert(keyCode)
      result.consume = true
      return result
    }
    if pushHeld && pushToTalk.modifierKey != nil {
      if isCombination(at: time) {
        pushHeld = false
        result.actions.append(.pushCancel)
      } else {
        if keyCode == KeyCode.escape && !isRepeat {
          pushHeld = false
          result.actions.append(.pushCancel)
        }
        consumedKeys.insert(keyCode)
        result.consume = true
        return result
      }
    }

    let pressed = Shortcut(keyCode: keyCode, modifiers: modifiers)
    if capturesEscape && pressed == Shortcut(keyCode: KeyCode.escape) {
      if !isRepeat { result.actions.append(.cancel) }
    } else if pressed == toggle {
      if !isRepeat { result.actions.append(.toggle) }
    } else if pressed == pushToTalk {
      if !isRepeat && !pushHeld {
        pushHeld = true
        pushedAt = time
        result.actions.append(.pushStart)
      }
    } else {
      return result
    }
    consumedKeys.insert(keyCode)
    result.consume = true
    return result
  }

  private mutating func keyUp(_ keyCode: UInt16) -> Result {
    var result = Result()
    result.consume = consumedKeys.remove(keyCode) != nil
    if pushHeld && pushToTalk.modifierKey == nil && keyCode == pushToTalk.keyCode {
      pushHeld = false
      result.actions.append(.pushEnd)
    }
    return result
  }

  private mutating func modifierChanged(
    _ key: ModifierKey, _ isDown: Bool, _ modifiers: Modifiers, _ time: TimeInterval
  ) -> Result {
    var result = Result()
    let alone = modifiers == key.modifier

    if key == pushToTalk.modifierKey {
      if isDown && alone && !pushHeld {
        pushHeld = true
        pushedAt = time
        result.actions.append(.pushStart)
      } else if !isDown && pushHeld {
        pushHeld = false
        result.actions.append(.pushEnd)
      }
    } else if pushHeld {
      if pushToTalk.modifierKey != nil {
        if isDown && isCombination(at: time) {
          pushHeld = false
          result.actions.append(.pushCancel)
        }
      } else if !modifiers.isSuperset(of: pushToTalk.modifiers) {
        pushHeld = false
        result.actions.append(.pushEnd)
      }
    }

    if key == toggle.modifierKey {
      if isDown {
        toggleArmed = alone
      } else if toggleArmed {
        toggleArmed = false
        result.actions.append(.toggle)
      }
    } else if isDown {
      toggleArmed = false
    }
    return result
  }
}
