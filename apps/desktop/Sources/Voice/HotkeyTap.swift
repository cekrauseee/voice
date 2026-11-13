import CoreGraphics
import Foundation
import VoiceCore

extension KeyEvent {
  /// Reads a keyboard event. Returns nil for events that shortcuts do not depend on.
  init?(type: CGEventType, keyCode: UInt16, flags: UInt64, isRepeat: Bool) {
    let modifiers = Modifiers(eventFlags: flags)
    switch type {
    case .keyDown:
      self = .keyDown(keyCode: keyCode, modifiers: modifiers, isRepeat: isRepeat)
    case .keyUp:
      self = .keyUp(keyCode: keyCode)
    case .flagsChanged:
      guard let key = ModifierKey(rawValue: keyCode) else { return nil }
      self = .modifierChanged(
        key: key, isDown: key.isDown(eventFlags: flags), modifiers: modifiers)
    default:
      return nil
    }
  }

  init?(_ event: CGEvent) {
    self.init(
      type: event.type,
      keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
      flags: event.flags.rawValue,
      isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
  }
}

/// Watches the keyboard system-wide and drives the dictation with the shortcuts.
@MainActor
final class HotkeyTap {
  private let settings: Settings
  private let controller: DictationController
  private var engine: HotkeyEngine
  private var tap: CFMachPort?

  init(settings: Settings, controller: DictationController) {
    self.settings = settings
    self.controller = controller
    engine = HotkeyEngine(pushToTalk: settings.pushToTalk, toggle: settings.toggle)
  }

  /// Starts watching. Returns false while the app has no Accessibility access.
  func start() -> Bool {
    guard tap == nil else { return true }
    let events: [CGEventType] = [.keyDown, .keyUp, .flagsChanged]
    let mask = events.reduce(CGEventMask(0)) { $0 | 1 << $1.rawValue }
    let callback: CGEventTapCallBack = { _, type, event, userInfo in
      let tap = Unmanaged<HotkeyTap>.fromOpaque(userInfo!).takeUnretainedValue()
      let isOwn = event.getIntegerValueField(.eventSourceUserData) == TextInserter.eventMarker
      let keyEvent = isOwn ? nil : KeyEvent(event)
      let shiftHeld = event.flags.contains(.maskShift)
      let time = TimeInterval(event.timestamp) / 1_000_000_000
      // The tap is on the main run loop, so the callback runs on the main thread.
      let consume = MainActor.assumeIsolated {
        tap.handle(type, keyEvent, at: time, shiftHeld: shiftHeld)
      }
      return consume ? nil : Unmanaged.passUnretained(event)
    }
    guard
      let tap = CGEvent.tapCreate(
        tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
        eventsOfInterest: mask, callback: callback,
        userInfo: Unmanaged.passUnretained(self).toOpaque())
    else { return false }
    self.tap = tap
    CFRunLoopAddSource(
      CFRunLoopGetMain(), CFMachPortCreateRunLoopSource(nil, tap, 0), .commonModes)
    return true
  }

  /// Returns whether to keep the event from the focused app.
  private func handle(
    _ type: CGEventType, _ event: KeyEvent?, at time: TimeInterval, shiftHeld: Bool
  ) -> Bool {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
      if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
      return false
    }
    guard let event, !settings.isRecordingShortcut else { return false }

    engine.pushToTalk = settings.pushToTalk
    engine.toggle = settings.toggle
    engine.capturesEscape = controller.isActive
    engine.allowsShiftToStop = controller.allowsShiftToStop
    let result = engine.handle(event, at: time)
    if !result.actions.isEmpty {
      // Leave the callback first: the system disables a tap that is slow to return.
      Task {
        for action in result.actions { controller.handle(action, shiftHeld: shiftHeld) }
      }
    }
    return result.consume
  }
}
