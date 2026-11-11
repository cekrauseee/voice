import AppKit
import SwiftUI

/// A titled window around a SwiftUI view.
@MainActor
final class AppWindow: NSObject, NSWindowDelegate {
  private let window: NSWindow
  /// Called when the window closes, however it was closed.
  var onClose: () -> Void = {}

  init(title: String, content: some View) {
    window = NSWindow(contentViewController: NSHostingController(rootView: content))
    super.init()
    window.title = title
    window.styleMask = [.titled, .closable]
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
  }

  var isVisible: Bool {
    window.isVisible
  }

  func show() {
    NSApp.activate()
    window.makeKeyAndOrderFront(nil)
  }

  /// Brings the window in front of other apps without taking the keyboard from them.
  func surface() {
    window.orderFrontRegardless()
  }

  func close() {
    window.close()
  }

  func windowWillClose(_ notification: Notification) {
    onClose()
  }
}
