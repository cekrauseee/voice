import Testing

@testable import VoiceCore

private typealias Action = HotkeyEngine.Action

private let space = KeyCode.space
private let letterA: UInt16 = 0

private func defaults() -> HotkeyEngine {
  HotkeyEngine(pushToTalk: .defaultPushToTalk, toggle: .defaultToggle)
}

private func down(_ keyCode: UInt16, _ modifiers: Modifiers = [], isRepeat: Bool = false)
  -> KeyEvent
{
  .keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
}

private func press(_ key: ModifierKey, with others: Modifiers = []) -> KeyEvent {
  .modifierChanged(key: key, isDown: true, modifiers: key.modifier.union(others))
}

private func release(_ key: ModifierKey, leaving modifiers: Modifiers = []) -> KeyEvent {
  .modifierChanged(key: key, isDown: false, modifiers: modifiers)
}

@Suite struct HotkeyEngineTests {
  @Test func holdingTheModifierPushesToTalk() {
    var engine = defaults()
    #expect(engine.handle(press(.rightOption)) == .init(actions: [.pushStart]))
    #expect(engine.handle(release(.rightOption)) == .init(actions: [.pushEnd]))
  }

  @Test func theOtherOptionKeyDoesNotPushToTalk() {
    var engine = defaults()
    #expect(engine.handle(press(.leftOption)).actions.isEmpty)
    #expect(engine.handle(release(.leftOption)).actions.isEmpty)
  }

  @Test func aModifierPressedWithOthersDoesNotPushToTalk() {
    var engine = defaults()
    _ = engine.handle(press(.leftShift))
    #expect(engine.handle(press(.rightOption, with: .shift)).actions.isEmpty)
    #expect(engine.handle(release(.rightOption, leaving: .shift)).actions.isEmpty)
  }

  @Test func typingWithTheModifierCancelsPushToTalk() {
    var engine = defaults()
    _ = engine.handle(press(.rightOption))
    #expect(engine.handle(down(letterA, .option)) == .init(actions: [.pushCancel]))
    #expect(engine.handle(release(.rightOption)).actions.isEmpty)
  }

  @Test func anotherModifierCancelsPushToTalk() {
    var engine = defaults()
    _ = engine.handle(press(.rightOption))
    #expect(engine.handle(press(.leftShift, with: .option)).actions == [.pushCancel])
  }

  @Test func theToggleShortcutIsConsumedAndFiresOnce() {
    var engine = defaults()
    _ = engine.handle(press(.leftOption))
    #expect(engine.handle(down(space, .option)) == .init(actions: [.toggle], consume: true))
    #expect(engine.handle(down(space, .option, isRepeat: true)) == .init(consume: true))
    #expect(engine.handle(.keyUp(keyCode: space)) == .init(consume: true))
    #expect(engine.handle(.keyUp(keyCode: space)) == .init())
  }

  @Test func theToggleShortcutNeedsItsExactModifiers() {
    var engine = defaults()
    #expect(engine.handle(down(space)) == .init())
    #expect(engine.handle(down(space, [.option, .shift])) == .init())
  }

  @Test func toggleWithThePushToTalkModifierCancelsThePush() {
    var engine = defaults()
    _ = engine.handle(press(.rightOption))
    let result = engine.handle(down(space, .option))
    #expect(result == .init(actions: [.pushCancel, .toggle], consume: true))
  }

  @Test func aKeyShortcutPushesWhileHeld() {
    var engine = HotkeyEngine(
      pushToTalk: Shortcut(keyCode: letterA, modifiers: [.control, .option]),
      toggle: .defaultToggle)
    let modifiers: Modifiers = [.control, .option]
    #expect(engine.handle(down(letterA, modifiers)) == .init(actions: [.pushStart], consume: true))
    #expect(engine.handle(down(letterA, modifiers, isRepeat: true)) == .init(consume: true))
    #expect(engine.handle(.keyUp(keyCode: letterA)) == .init(actions: [.pushEnd], consume: true))
  }

  @Test func releasingAModifierOfAKeyShortcutEndsThePush() {
    var engine = HotkeyEngine(
      pushToTalk: Shortcut(keyCode: letterA, modifiers: [.control, .option]),
      toggle: .defaultToggle)
    _ = engine.handle(down(letterA, [.control, .option]))
    #expect(engine.handle(release(.leftControl, leaving: .option)).actions == [.pushEnd])
    #expect(engine.handle(.keyUp(keyCode: letterA)) == .init(consume: true))
  }

  @Test func aModifierToggleFiresWhenReleasedAlone() {
    var engine = HotkeyEngine(
      pushToTalk: .defaultPushToTalk, toggle: Shortcut(keyCode: ModifierKey.rightCommand.rawValue))
    #expect(engine.handle(press(.rightCommand)).actions.isEmpty)
    #expect(engine.handle(release(.rightCommand)).actions == [.toggle])

    _ = engine.handle(press(.rightCommand))
    _ = engine.handle(down(letterA, .command))
    #expect(engine.handle(release(.rightCommand)).actions.isEmpty)
  }

  @Test func escapeCancelsOnlyWhileCaptured() {
    var engine = defaults()
    #expect(engine.handle(down(KeyCode.escape)) == .init())

    engine.capturesEscape = true
    #expect(engine.handle(down(KeyCode.escape)) == .init(actions: [.cancel], consume: true))
    #expect(engine.handle(.keyUp(keyCode: KeyCode.escape)) == .init(consume: true))
  }
}
