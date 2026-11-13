import Foundation
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

/// A moment into a push at which a key makes a combination with its key.
private let soon: TimeInterval = 0.2
/// A moment into a push at which it has become a dictation.
private let later: TimeInterval = 2

extension HotkeyEngine {
  /// Handles an event at the start of time: what the time is does not matter to the test.
  fileprivate mutating func handle(_ event: KeyEvent) -> Result {
    handle(event, at: 0)
  }
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

  @Test func typingWithTheModifierAtOnceCancelsPushToTalk() {
    var engine = defaults()
    _ = engine.handle(press(.rightOption))
    #expect(engine.handle(down(letterA, .option), at: soon) == .init(actions: [.pushCancel]))
    #expect(engine.handle(.keyUp(keyCode: letterA), at: soon) == .init())
    #expect(engine.handle(release(.rightOption), at: later).actions.isEmpty)
  }

  @Test func anotherModifierAtOnceCancelsPushToTalk() {
    var engine = defaults()
    _ = engine.handle(press(.rightOption))
    #expect(engine.handle(press(.leftShift, with: .option), at: soon).actions == [.pushCancel])
  }

  @Test func aKeyDuringTheDictationIsSwallowed() {
    var engine = defaults()
    _ = engine.handle(press(.rightOption))
    #expect(engine.handle(down(letterA, .option), at: later) == .init(consume: true))
    #expect(
      engine.handle(down(letterA, .option, isRepeat: true), at: later) == .init(consume: true))
    #expect(engine.handle(.keyUp(keyCode: letterA), at: later) == .init(consume: true))
    #expect(engine.handle(release(.rightOption), at: later) == .init(actions: [.pushEnd]))
  }

  @Test(arguments: [soon, later]) func spaceLocksThePushWithoutRestartingIt(time: TimeInterval) {
    var engine = defaults()
    _ = engine.handle(press(.rightOption))
    #expect(
      engine.handle(down(space, .option), at: time) == .init(actions: [.pushLock], consume: true))
    #expect(engine.handle(down(space, .option, isRepeat: true), at: later) == .init(consume: true))
    #expect(engine.handle(release(.rightOption), at: later) == .init())
    #expect(engine.handle(.keyUp(keyCode: space), at: later) == .init(consume: true))
    #expect(
      engine.handle(down(space, .option), at: later) == .init(actions: [.toggle], consume: true))
  }

  @Test func anotherModifierDuringTheDictationIsIgnored() {
    var engine = defaults()
    _ = engine.handle(press(.rightOption))
    #expect(engine.handle(press(.leftShift, with: .option), at: later).actions.isEmpty)
    #expect(engine.handle(down(letterA, [.option, .shift]), at: later) == .init(consume: true))
    #expect(engine.handle(release(.rightOption, leaving: .shift), at: later).actions == [.pushEnd])
  }

  @Test func escapeDuringTheDictationCancelsIt() {
    var engine = defaults()
    _ = engine.handle(press(.rightOption))
    let escape = down(KeyCode.escape, .option)
    #expect(engine.handle(escape, at: later) == .init(actions: [.pushCancel], consume: true))
    #expect(engine.handle(.keyUp(keyCode: KeyCode.escape), at: later) == .init(consume: true))
    // The key is an ordinary modifier again until it is released.
    #expect(engine.handle(down(letterA, .option), at: later) == .init())
    #expect(engine.handle(release(.rightOption), at: later).actions.isEmpty)
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

  @Test func spaceLocksACustomPushShortcut() {
    var engine = HotkeyEngine(
      pushToTalk: Shortcut(keyCode: letterA, modifiers: [.control, .option]),
      toggle: Shortcut(keyCode: 1, modifiers: .command))
    _ = engine.handle(down(letterA, [.control, .option]))
    #expect(
      engine.handle(down(space, [.control, .option]), at: soon)
        == .init(actions: [.pushLock], consume: true))
    #expect(engine.handle(release(.leftControl, leaving: .option)).actions.isEmpty)
    #expect(engine.handle(.keyUp(keyCode: letterA)) == .init(consume: true))
    #expect(engine.handle(down(space, isRepeat: true)) == .init(consume: true))
    #expect(engine.handle(.keyUp(keyCode: space)) == .init(consume: true))
    engine.capturesEscape = true
    #expect(engine.handle(down(KeyCode.escape)) == .init(actions: [.cancel], consume: true))
    #expect(engine.handle(down(letterA, [.control, .option])).actions == [.pushStart])
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
