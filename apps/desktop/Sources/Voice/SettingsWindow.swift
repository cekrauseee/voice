import AppKit
import SwiftUI

@MainActor
final class SettingsWindow {
  private let window: NSWindow

  init(settings: Settings) {
    window = NSWindow(
      contentViewController: NSHostingController(rootView: SettingsView(settings: settings)))
    window.title = "Settings"
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
  }

  func show() {
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }
}
