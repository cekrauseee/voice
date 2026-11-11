import AppKit
import SwiftUI
import VoiceCore

/// The floating window that holds the pill. It never takes focus or mouse events.
@MainActor
final class PillPanel {
  private let controller: DictationController
  private let panel: NSPanel

  init(controller: DictationController, settings: Settings) {
    self.controller = controller
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .statusBar
    panel.collectionBehavior = [
      .canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle,
    ]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.ignoresMouseEvents = true
    panel.hidesOnDeactivate = false
    panel.contentView = NSHostingView(
      rootView: PillContainer(controller: controller, settings: settings))
  }

  func start() {
    track { [controller] in
      controller.pill != .hidden
    } onChange: { [weak self] isVisible in
      self?.update(isVisible)
    }
  }

  private func update(_ isVisible: Bool) {
    if isVisible {
      // Bottom center of the screen the pointer is on.
      let pointer = NSEvent.mouseLocation
      let screen = NSScreen.screens.first { $0.frame.contains(pointer) } ?? NSScreen.main
      if let area = screen?.visibleFrame {
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: area.minY))
      }
      panel.orderFrontRegardless()
    } else {
      // Leave the window up until the pill has animated out.
      Task {
        try? await Task.sleep(for: .milliseconds(500))
        if controller.pill == .hidden { panel.orderOut(nil) }
      }
    }
  }
}

private struct PillContainer: View {
  let controller: DictationController
  let settings: Settings

  var body: some View {
    PillView(
      state: controller.pill, style: settings.pillStyle, feed: controller.levels,
      transcript: controller.transcript, mode: controller.mode, toggle: settings.toggle
    )
    .padding(.bottom, 24)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
  }
}
