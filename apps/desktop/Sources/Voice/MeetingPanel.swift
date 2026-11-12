import AppKit
import SwiftUI
import VoiceCore

/// The floating window that shows the meeting being recorded: how long it has run, the
/// last of what was said, and the way to stop it. It takes clicks, but never the focus.
@MainActor
final class MeetingPanel {
  private let controller: MeetingController
  private let panel: NSPanel

  init(controller: MeetingController, open: @escaping () -> Void) {
    self.controller = controller
    panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 380, height: 160),
      styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    panel.level = .floating
    panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
    panel.isOpaque = false
    panel.backgroundColor = .clear
    panel.hasShadow = false
    panel.isMovableByWindowBackground = true
    panel.hidesOnDeactivate = false
    panel.contentView = NSHostingView(
      rootView: MeetingPanelView(controller: controller, open: open))
  }

  func start() {
    track { [controller] in
      controller.live != nil || controller.failure != nil
    } onChange: { [weak self] isVisible in
      self?.update(isVisible)
    }
  }

  private func update(_ isVisible: Bool) {
    if isVisible {
      // The top right corner of the main screen, under the menu bar.
      if let area = NSScreen.main?.visibleFrame {
        panel.setFrameOrigin(
          NSPoint(
            x: area.maxX - panel.frame.width - Design.small,
            y: area.maxY - panel.frame.height - Design.small))
      }
      panel.orderFrontRegardless()
    } else {
      Task {
        try? await Task.sleep(for: .milliseconds(400))
        if controller.live == nil && controller.failure == nil { panel.orderOut(nil) }
      }
    }
  }
}

private struct MeetingPanelView: View {
  let controller: MeetingController
  let open: () -> Void

  @Environment(\.colorScheme) private var colorScheme

  private static let morph = Animation.spring(duration: 0.42, bounce: 0.24)

  var body: some View {
    ZStack(alignment: .topTrailing) {
      if controller.live != nil || controller.failure != nil {
        content
          .padding(14)
          .frame(width: 340, alignment: .leading)
          .background(colorScheme == .dark ? Color(white: 0.12) : .white)
          .clipShape(shape)
          .overlay(shape.strokeBorder(.primary.opacity(0.12)))
          .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
          .transition(.blurReplace)
      }
    }
    .padding(.top, 20)
    .padding(.trailing, 20)
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
    .animation(Self.morph, value: controller.live == nil)
    .animation(Self.morph, value: controller.failure)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: 14, style: .continuous)
  }

  @ViewBuilder private var content: some View {
    if let failure = controller.failure {
      Label(failure.message, systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 12, weight: .medium))
    } else if let live = controller.live {
      VStack(alignment: .leading, spacing: 10) {
        HStack(spacing: Design.small) {
          Circle()
            .fill(controller.isStopping ? Color.secondary : .red)
            .frame(width: 8, height: 8)
          TimelineView(.periodic(from: .now, by: 1)) { _ in
            Text(controller.elapsed.clock)
              .monospacedDigit()
          }
          Text(controller.isStopping ? "Finishing" : "Recording")
            .foregroundStyle(.secondary)
          Spacer(minLength: 0)
          IconButton(symbol: "arrow.up.forward.square", help: "Open", action: open)
          Button("Stop", action: controller.stop)
            .buttonStyle(.plain)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 10)
            .frame(height: 24)
            .background(
              Design.selected,
              in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
            )
            .pointer()
            .disabled(controller.isStopping)
        }
        .font(.system(size: 12, weight: .medium))
        if !recent(live).characters.isEmpty {
          // The end of the conversation: what does not fit is cut at the start.
          Text(recent(live))
            .font(.system(size: 13))
            .lineLimit(3)
            .truncationMode(.head)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        if controller.isMissingSystemAudio {
          Label("Only the microphone is recorded", systemImage: "speaker.slash")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
        }
      }
    }
  }

  /// The last paragraphs, and after them what is being heard, dimmed.
  private func recent(_ live: LiveMeeting) -> AttributedString {
    var text = AttributedString(
      live.meeting.paragraphs.suffix(2).map { "\($0.channel.title): \($0.text)" }
        .joined(separator: "\n"))
    for channel in Channel.allCases {
      guard let draft = live.drafts[channel] else { continue }
      var piece = AttributedString(
        (text.characters.isEmpty ? "" : "\n") + "\(channel.title): \(draft)")
      piece.foregroundColor = .secondary
      text += piece
    }
    return text
  }
}
