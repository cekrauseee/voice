import AppKit
import SwiftUI
import VoiceCore

/// The floating window that holds the pill. It never takes the focus, and takes clicks
/// only while the pill has buttons, for a meeting.
@MainActor
final class PillPanel {
  private let controller: DictationController
  private let meeting: MeetingController
  private let settings: Settings
  private let panel: NSPanel
  private let placement = PillPlacement()
  /// Takes the window down once the pill has animated out.
  private var putAway: Task<Void, Never>?

  init(
    controller: DictationController, meeting: MeetingController, settings: Settings,
    open: @escaping () -> Void
  ) {
    self.controller = controller
    self.meeting = meeting
    self.settings = settings
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 440, height: 240),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    // Above the menu bar, so the pill can grow out of the notch.
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
      rootView: PillContainer(
        controller: controller, meeting: meeting, settings: settings, placement: placement,
        open: open))
  }

  func start() {
    track { [controller, meeting] in
      PillContent(dictation: controller.pill, meeting: meeting.status)
    } onChange: { [weak self] content in
      self?.update(content)
    }
  }

  private func update(_ content: PillContent) {
    let wasHidden = placement.content == .hidden
    panel.ignoresMouseEvents = !content.takesClicks
    if content != .hidden, wasHidden {
      putAway?.cancel()
      // At the center of the screen the pointer is on, at the bottom or at the top.
      let pointer = NSEvent.mouseLocation
      if let screen = NSScreen.screens.first(where: { $0.frame.contains(pointer) }) ?? .main {
        place(on: screen)
      }
      panel.orderFrontRegardless()
    }
    // The pill shows the state once the window is where it shows it, on the screen it
    // shows it on, so it grows out of the right place.
    placement.content = content
    if content == .hidden, !wasHidden {
      putAway = Task {
        // Leave the window up until the pill has animated out.
        try? await Task.sleep(for: .milliseconds(500))
        guard !Task.isCancelled else { return }
        // Empty the window before it goes, so it does not bring back the pill closed in
        // the notch, wherever it shows next.
        placement.notch = nil
        try? await Task.sleep(for: .milliseconds(50))
        guard !Task.isCancelled else { return }
        panel.orderOut(nil)
      }
    }
  }

  private func place(on screen: NSScreen) {
    let area = screen.visibleFrame
    placement.notch = settings.pillPosition == .top ? screen.notch : nil
    let y =
      if placement.notch != nil {
        // At the very top, around the notch.
        screen.frame.maxY - panel.frame.height
      } else {
        switch settings.pillPosition {
        case .bottom: area.minY
        // Under the menu bar, also when it is hidden.
        case .top: area.maxY - panel.frame.height
        }
      }
    let x = placement.notch.map { screen.frame.minX + $0.midX } ?? area.midX
    panel.setFrameOrigin(NSPoint(x: x - panel.frame.width / 2, y: y))
  }
}

/// What the pill shows, and where.
@MainActor @Observable
private final class PillPlacement {
  var content: PillContent = .hidden
  /// The notch the pill opens out of, while the window is up at the top of a screen that
  /// has one.
  var notch: Notch?
}

extension NSScreen {
  fileprivate var notch: Notch? {
    guard let left = auxiliaryTopLeftArea, let right = auxiliaryTopRightArea else { return nil }
    return Notch(
      screenWidth: frame.width, leftWidth: left.width, rightWidth: right.width,
      height: safeAreaInsets.top)
  }
}

private struct PillContainer: View {
  let controller: DictationController
  let meeting: MeetingController
  let settings: Settings
  let placement: PillPlacement
  let open: () -> Void

  var body: some View {
    PillView(
      content: placement.content, style: settings.pillStyle, feed: controller.levels,
      transcript: controller.transcript, mode: controller.mode, toggle: settings.toggle,
      meeting: meeting, open: open, edge: edge, notch: placement.notch
    )
    .padding(edge == .bottom ? .bottom : .top, padding)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: edge == .bottom ? .bottom : .top)
    // Up to the top of the screen, around the notch.
    .ignoresSafeArea()
  }

  private var edge: VerticalEdge {
    settings.pillPosition == .bottom ? .bottom : .top
  }

  private var padding: Double {
    if placement.notch != nil { return 0 }
    return edge == .bottom ? 24 : 8
  }
}
