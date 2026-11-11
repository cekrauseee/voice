import Testing

@testable import VoiceCore

@Suite struct ShortcutTests {
  @Test func keyCapsNameTheKeysInOrder() {
    #expect(Shortcut.defaultToggle.keyCaps == ["⌥", "Space"])
    #expect(Shortcut.defaultPushToTalk.keyCaps == ["Right ⌥"])
    #expect(
      Shortcut(keyCode: 40, modifiers: [.command, .shift, .control]).keyCaps == [
        "⌃", "⇧", "⌘", "K",
      ])
    #expect(Shortcut(keyCode: 200, modifiers: .command).keyCaps == ["⌘", "Key 200"])
  }

  @Test func modifiersAreReadFromEventFlags() {
    #expect(Modifiers(eventFlags: 0x8_0000 | 0x40) == .option)
    #expect(Modifiers(eventFlags: 0x10_0000 | 0x2_0000) == [.command, .shift])
    #expect(ModifierKey.rightOption.isDown(eventFlags: 0x8_0000 | 0x40))
    #expect(!ModifierKey.rightOption.isDown(eventFlags: 0x8_0000 | 0x20))
  }
}

@Suite struct ShortcutRecorderTests {
  @Test func capturesAKeyWithModifiers() {
    var recorder = ShortcutRecorder()
    #expect(
      recorder.handle(.modifierChanged(key: .leftCommand, isDown: true, modifiers: .command)) == nil
    )
    let outcome = recorder.handle(.keyDown(keyCode: 40, modifiers: .command, isRepeat: false))
    #expect(outcome == .captured(Shortcut(keyCode: 40, modifiers: .command)))
  }

  @Test func capturesAModifierPressedAndReleasedAlone() {
    var recorder = ShortcutRecorder()
    #expect(
      recorder.handle(.modifierChanged(key: .rightOption, isDown: true, modifiers: .option)) == nil)
    let outcome = recorder.handle(.modifierChanged(key: .rightOption, isDown: false, modifiers: []))
    #expect(outcome == .captured(.defaultPushToTalk))
  }

  @Test func ignoresAPlainKeyButAcceptsAFunctionKey() {
    var recorder = ShortcutRecorder()
    #expect(recorder.handle(.keyDown(keyCode: 0, modifiers: [], isRepeat: false)) == nil)
    let outcome = recorder.handle(.keyDown(keyCode: 96, modifiers: [], isRepeat: false))
    #expect(outcome == .captured(Shortcut(keyCode: 96)))
  }

  @Test func twoModifiersTogetherAreNotAShortcut() {
    var recorder = ShortcutRecorder()
    _ = recorder.handle(.modifierChanged(key: .leftShift, isDown: true, modifiers: .shift))
    _ = recorder.handle(
      .modifierChanged(key: .leftOption, isDown: true, modifiers: [.shift, .option]))
    #expect(
      recorder.handle(.modifierChanged(key: .leftOption, isDown: false, modifiers: .shift)) == nil)
    #expect(recorder.handle(.modifierChanged(key: .leftShift, isDown: false, modifiers: [])) == nil)
  }

  @Test func escapeCancels() {
    var recorder = ShortcutRecorder()
    #expect(
      recorder.handle(.keyDown(keyCode: KeyCode.escape, modifiers: [], isRepeat: false))
        == .cancelled)
  }
}
