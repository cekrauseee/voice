import Testing

@testable import VoiceCore

@MainActor @Suite struct DictationDeliveryTests {
  @Test func defaultsPreserveTheClipboardAndDoNotSubmit() {
    let delivery = DictationDelivery()
    delivery.stop(shiftHeld: true)
    #expect(!delivery.keepOnClipboard)
    #expect(!delivery.pressesEnter(text: "Hello", failed: false))
  }

  @Test(arguments: EnterBehavior.allCases, [false, true])
  func enterUsesTheStopGesture(behavior: EnterBehavior, shiftHeld: Bool) {
    let delivery = DictationDelivery(keepOnClipboard: true, enterBehavior: behavior)
    #expect(delivery.keepOnClipboard)
    #expect(!delivery.pressesEnter(text: "Hello", failed: false))
    delivery.stop(shiftHeld: shiftHeld)
    #expect(
      delivery.pressesEnter(text: "Hello", failed: false)
        == (behavior == .always || (behavior == .withShift && shiftHeld)))
    #expect(!delivery.pressesEnter(text: "Hello", failed: true))
    #expect(!delivery.pressesEnter(text: "", failed: false))
  }

  @Test func overlappingDictationsKeepTheirOwnStopGesture() {
    let first = DictationDelivery(enterBehavior: .withShift)
    first.stop(shiftHeld: true)
    let second = DictationDelivery(enterBehavior: .withShift)
    second.stop(shiftHeld: false)
    #expect(first.pressesEnter(text: "First", failed: false))
    #expect(!second.pressesEnter(text: "Second", failed: false))
  }
}
