import AppKit
import SwiftUI

/// A titled window around a SwiftUI view.
@MainActor
final class AppWindow {
  private let window: NSWindow

  init(title: String, content: some View) {
    window = NSWindow(contentViewController: NSHostingController(rootView: content))
    window.title = title
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.center()
  }

  func show() {
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  func close() {
    window.close()
  }
}
