import AppKit
import SwiftUI
import VoiceCore

/// Shows a shortcut. Click it, then press the new one.
struct ShortcutField: View {
  @Binding var shortcut: Shortcut
  /// The shortcut the reset button restores.
  let fallback: Shortcut
  /// The shortcut of the other action, which this one cannot also use.
  let taken: Shortcut
  @Binding var isRecording: Bool

  @State private var monitor: Any?
  @State private var recorder = ShortcutRecorder()

  var body: some View {
    HStack(spacing: Design.small) {
      Button {
        if monitor == nil { begin() } else { end() }
      } label: {
        Group {
          if monitor == nil {
            KeyCaps(labels: shortcut.keyCaps, size: .large)
              .foregroundStyle(Design.ink)
          } else {
            Text("Press keys")
              .font(.voiceLabel)
              .foregroundStyle(Design.ink2)
              .padding(.horizontal, 10)
              .frame(height: 30)
              .overlay {
                RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
                  .strokeBorder(Design.ink3, lineWidth: 1.5)
              }
          }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
      }
      .buttonStyle(.plain)
      .pointer()
      .help("Record a new shortcut")
      if shortcut != fallback && fallback != taken && monitor == nil {
        Button("Reset", systemImage: "arrow.counterclockwise") { shortcut = fallback }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
          .foregroundStyle(Design.ink2)
          .pointer()
          .help("Back to \(fallback.keyCaps.joined(separator: " "))")
      }
    }
    .animation(Motion.snappy, value: monitor == nil)
    .onDisappear(perform: end)
  }

  private func begin() {
    recorder = ShortcutRecorder()
    isRecording = true
    monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp, .flagsChanged]) {
      guard let event = $0.cgEvent.flatMap(KeyEvent.init) else { return $0 }
      switch recorder.handle(event) {
      case .captured(let captured) where captured == taken:
        NSSound.beep()
      case .captured(let captured):
        shortcut = captured
        end()
      case .cancelled:
        end()
      case nil:
        break
      }
      return nil
    }
  }

  private func end() {
    if let monitor { NSEvent.removeMonitor(monitor) }
    monitor = nil
    isRecording = false
  }
}
