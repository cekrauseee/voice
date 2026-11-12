import AppKit
import SwiftUI

/// A window around a SwiftUI view.
///
/// The app lives in the menu bar, without a Dock icon. While one of its windows is open it
/// is a regular app instead, in the Dock and the app switcher, so the window can be found
/// and comes to the front like any other.
@MainActor
final class AppWindow: NSObject, NSWindowDelegate {
  enum Style {
    /// A small window of a fixed size, as large as its content.
    case panel
    /// A resizable window whose content reaches under the title bar.
    case main(size: NSSize, minimum: NSSize)
  }

  /// The windows that are open.
  private static var open: Set<ObjectIdentifier> = []

  private let window: NSWindow
  /// Called when the window closes, however it was closed.
  var onClose: () -> Void = {}

  init(title: String, style: Style = .panel, content: some View) {
    window = NSWindow(contentViewController: NSHostingController(rootView: content))
    super.init()
    window.title = title
    window.isReleasedWhenClosed = false
    window.delegate = self
    switch style {
    case .panel:
      window.styleMask = [.titled, .closable]
    case .main(let size, let minimum):
      window.styleMask = [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView]
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      window.setContentSize(size)
      window.contentMinSize = minimum
    }
    window.center()
    // The window comes back where and as large as it was left.
    if case .main = style { window.setFrameAutosaveName("Main") }
  }

  var isVisible: Bool {
    window.isVisible
  }

  /// Opens the window, or brings it back, in front of every other app.
  func show() {
    Self.open.insert(ObjectIdentifier(self))
    NSApp.setActivationPolicy(.regular)
    window.makeKeyAndOrderFront(nil)
    // An app in the background is not given the front for asking. The window goes there
    // by itself, and the app takes the keyboard with the one request macOS still honors.
    window.orderFrontRegardless()
    NSApp.activate(ignoringOtherApps: true)
  }

  /// Brings the window in front of other apps without taking the keyboard from them.
  func surface() {
    window.orderFrontRegardless()
  }

  func close() {
    window.close()
  }

  func windowWillClose(_ notification: Notification) {
    Self.open.remove(ObjectIdentifier(self))
    if Self.open.isEmpty { NSApp.setActivationPolicy(.accessory) }
    onClose()
  }
}
