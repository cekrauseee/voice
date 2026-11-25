import AppKit
import ApplicationServices
import VoiceCore

/// Reads the text before the cursor in the focused field, with the Accessibility permission
/// the app already has to type.
@MainActor
enum FocusedField {
  /// How long the focused app has to answer each question. A busy app is not waited for:
  /// the dictation goes on without its text.
  private static let timeout: Float = 0.05

  /// The roles of the elements that hold text the user types.
  private static let textRoles: Set<String> = [
    kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole,
  ]

  /// The text before the cursor, up to `FieldContext.limit`. Empty when the focused element
  /// is not a text field, is a password field, or does not say, as many apps do not.
  static func textBeforeCursor() -> String {
    // The app's own fields would be asked from the thread that answers them.
    guard !NSApp.isActive else { return "" }
    let system = AXUIElementCreateSystemWide()
    AXUIElementSetMessagingTimeout(system, timeout)
    guard let field = element(system, kAXFocusedUIElementAttribute) else { return "" }
    AXUIElementSetMessagingTimeout(field, timeout)
    guard let role = string(field, kAXRoleAttribute), textRoles.contains(role),
      string(field, kAXSubroleAttribute) != kAXSecureTextFieldSubrole,
      let cursor = selectionStart(field)
    else { return "" }

    // Only the end of a long text is needed, so only that is asked for when the app can.
    let window = FieldContext.window(cursor: cursor)
    if window.isEmpty { return "" }
    if let read = string(field, in: window) {
      return FieldContext.text(read, isCut: window.lowerBound > 0)
    }
    guard let value = string(field, kAXValueAttribute) else { return "" }
    return FieldContext.before(value, cursor: cursor)
  }

  private static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
    var value: CFTypeRef?
    guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success
    else { return nil }
    return value
  }

  private static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
    guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID()
    else { return nil }
    return unsafeDowncast(value, to: AXUIElement.self)
  }

  private static func string(_ element: AXUIElement, _ attribute: String) -> String? {
    copy(element, attribute) as? String
  }

  /// Where the selection starts, which is the cursor when nothing is selected.
  private static func selectionStart(_ field: AXUIElement) -> Int? {
    guard let value = copy(field, kAXSelectedTextRangeAttribute),
      CFGetTypeID(value) == AXValueGetTypeID()
    else { return nil }
    var range = CFRange()
    guard AXValueGetValue(unsafeDowncast(value, to: AXValue.self), .cfRange, &range) else {
      return nil
    }
    return range.location
  }

  private static func string(_ field: AXUIElement, in window: Range<Int>) -> String? {
    var range = CFRange(location: window.lowerBound, length: window.count)
    guard let parameter = AXValueCreate(.cfRange, &range) else { return nil }
    var value: CFTypeRef?
    guard
      AXUIElementCopyParameterizedAttributeValue(
        field, kAXStringForRangeParameterizedAttribute as CFString, parameter, &value) == .success
    else { return nil }
    return value as? String
  }
}
