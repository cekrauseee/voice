/// Turns keyboard events into dictation actions.
///
/// A shortcut made of a key with modifiers is consumed, so it never reaches the focused app.
/// A shortcut made of one modifier key acts only while that key is used alone: pressing
/// another key with it turns it back into an ordinary modifier.
public struct HotkeyEngine: Sendable {
  public enum Action: Equatable, Sendable {
    case pushStart
    case pushEnd
    /// The push-to-talk key turned out to be part of another key combination.
    case pushCancel
    case toggle
    case cancel
  }

  public struct Result: Equatable, Sendable {
    public var actions: [Action] = []
    /// Whether to keep the event from the focused app.
    public var consume = false
  }

  public var pushToTalk: Shortcut
  public var toggle: Shortcut
  /// While set, Escape is consumed and cancels.
  public var capturesEscape = false

  private var pushHeld = false
  private var toggleArmed = false
  private var consumedKeys: Set<UInt16> = []

  public init(pushToTalk: Shortcut, toggle: Shortcut) {
    self.pushToTalk = pushToTalk
    self.toggle = toggle
  }

  public mutating func handle(_ event: KeyEvent) -> Result {
    switch event {
    case .keyDown(let keyCode, let modifiers, let isRepeat):
      keyDown(keyCode, modifiers, isRepeat)
    case .keyUp(let keyCode):
      keyUp(keyCode)
    case .modifierChanged(let key, let isDown, let modifiers):
      modifierChanged(key, isDown, modifiers)
    }
  }

  private mutating func keyDown(_ keyCode: UInt16, _ modifiers: Modifiers, _ isRepeat: Bool)
    -> Result
  {
    var result = Result()
    if pushHeld && pushToTalk.modifierKey != nil {
      pushHeld = false
      result.actions.append(.pushCancel)
    }
    toggleArmed = false

    let pressed = Shortcut(keyCode: keyCode, modifiers: modifiers)
    if capturesEscape && pressed == Shortcut(keyCode: KeyCode.escape) {
      if !isRepeat { result.actions.append(.cancel) }
    } else if pressed == toggle {
      if !isRepeat { result.actions.append(.toggle) }
    } else if pressed == pushToTalk {
      if !isRepeat && !pushHeld {
        pushHeld = true
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

  private mutating func modifierChanged(_ key: ModifierKey, _ isDown: Bool, _ modifiers: Modifiers)
    -> Result
  {
    var result = Result()
    let alone = modifiers == key.modifier

    if key == pushToTalk.modifierKey {
      if isDown && alone && !pushHeld {
        pushHeld = true
        result.actions.append(.pushStart)
      } else if !isDown && pushHeld {
        pushHeld = false
        result.actions.append(.pushEnd)
      }
    } else if pushHeld {
      if pushToTalk.modifierKey != nil {
        if isDown {
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
