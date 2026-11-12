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
    /// A window of one size whose content reaches under the title bar and draws the header
    /// there, beside the button that closes it. It has no other button: it cannot be
    /// minimized, zoomed, or made full screen.
    case main(size: NSSize)
  }

  /// The windows that are open.
  private static var open: Set<ObjectIdentifier> = []

  let window: NSWindow
  /// Called when the window closes, however it was closed.
  var onClose: () -> Void = {}

  init(title: String, style: Style = .panel, content: some View) {
    switch style {
    case .panel:
      window = NSWindow(contentViewController: NSHostingController(rootView: content))
      window.styleMask = [.titled, .closable]
    case .main(let size):
      window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      // An empty toolbar makes the title bar tall enough for a header, with the window's
      // button in the middle of it.
      window.toolbar = NSToolbar()
      window.toolbarStyle = .unifiedCompact
      window.collectionBehavior.insert(.fullScreenNone)
      window.standardWindowButton(.miniaturizeButton)?.isHidden = true
      window.standardWindowButton(.zoomButton)?.isHidden = true
      let close = window.standardWindowButton(.closeButton).map { $0.convert($0.bounds, to: nil) }
      window.contentViewController = NSHostingController(
        rootView: content.environment(\.windowButtonsWidth, close?.maxX ?? 0))
      window.setContentSize(size)
    }
    super.init()
    window.title = title
    window.isReleasedWhenClosed = false
    window.delegate = self
    window.center()
    if case .main(let size) = style {
      // The window comes back where it was left. macOS does not move a window of a fixed
      // size back by itself, and what it kept may be of another size.
      window.setFrameAutosaveName("Main")
      if window.setFrameUsingName("Main", force: true) {
        let topLeft = NSPoint(x: window.frame.minX, y: window.frame.maxY)
        window.setContentSize(size)
        window.setFrameTopLeftPoint(topLeft)
      }
    }
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

extension EnvironmentValues {
  /// How far the window's button reaches from the leading edge of the title bar, for a
  /// header that is drawn beside it. Zero where the content does not reach under it.
  var windowButtonsWidth: CGFloat {
    get { self[WindowButtonsWidthKey.self] }
    set { self[WindowButtonsWidthKey.self] = newValue }
  }
}

private struct WindowButtonsWidthKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}
