import AppKit
import ApplicationServices

@MainActor
enum Permissions {
  /// Accessibility access lets the app see the shortcuts and type the dictated text.
  static var isAccessibilityGranted: Bool {
    AXIsProcessTrusted()
  }

  /// Shows the system prompt that leads to the Accessibility settings.
  static func promptForAccessibility() {
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
  }

  static func openPrivacySettings(_ pane: String) {
    let url = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
    NSWorkspace.shared.open(URL(string: url)!)
  }
}
