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
    /// A resizable window whose content reaches under the title bar and draws the header
    /// there, beside the window's buttons.
    case main(size: NSSize, minimum: NSSize)
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
    case .main(let size, let minimum):
      window = NSWindow(
        contentRect: NSRect(origin: .zero, size: size),
        styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
        backing: .buffered, defer: false)
      window.titlebarAppearsTransparent = true
      window.titleVisibility = .hidden
      // An empty toolbar makes the title bar tall enough for a header, with the window's
      // buttons in the middle of it.
      window.toolbar = NSToolbar()
      window.toolbarStyle = .unifiedCompact
      let buttons = window.standardWindowButton(.zoomButton).map { $0.convert($0.bounds, to: nil) }
      window.contentViewController = NSHostingController(
        rootView: content.environment(\.windowButtonsWidth, buttons?.maxX ?? 0))
      window.setContentSize(size)
      window.contentMinSize = minimum
    }
    super.init()
    window.title = title
    window.isReleasedWhenClosed = false
    window.delegate = self
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

extension EnvironmentValues {
  /// How far the window's buttons reach from the leading edge of the title bar, for a
  /// header that is drawn beside them. Zero where the content does not reach under it.
  var windowButtonsWidth: CGFloat {
    get { self[WindowButtonsWidthKey.self] }
    set { self[WindowButtonsWidthKey.self] = newValue }
  }
}

private struct WindowButtonsWidthKey: EnvironmentKey {
  static let defaultValue: CGFloat = 0
}
