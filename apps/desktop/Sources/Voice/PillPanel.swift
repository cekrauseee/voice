import AppKit
import SwiftUI
import VoiceCore

/// The floating window that holds the pill. It never takes focus or mouse events.
@MainActor
final class PillPanel {
  private let controller: DictationController
  private let settings: Settings
  private let panel: NSPanel

  init(controller: DictationController, settings: Settings) {
    self.controller = controller
    self.settings = settings
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
      // At the center of the screen the pointer is on, at the bottom or at the top.
      let pointer = NSEvent.mouseLocation
      if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? .main {
        let area = screen.visibleFrame
        let y =
          switch settings.pillPosition {
          case .bottom: area.minY
          // Under the menu bar, and under the notch also when the menu bar is hidden.
          case .top:
            min(area.maxY, screen.frame.maxY - screen.safeAreaInsets.top) - panel.frame.height
          }
        panel.setFrameOrigin(NSPoint(x: area.midX - panel.frame.width / 2, y: y))
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
      transcript: controller.transcript, mode: controller.mode, toggle: settings.toggle,
      edge: edge
    )
    .padding(edge == .bottom ? .bottom : .top, edge == .bottom ? 24 : 8)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .bottom ? .bottom : .top)
  }

  private var edge: VerticalEdge {
    settings.pillPosition == .bottom ? .bottom : .top
  }
}
