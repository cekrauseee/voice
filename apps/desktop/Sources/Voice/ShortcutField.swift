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
    HStack(spacing: 8) {
      if shortcut != fallback && fallback != taken {
        Button("Reset", systemImage: "arrow.counterclockwise") { shortcut = fallback }
          .labelStyle(.iconOnly)
          .buttonStyle(.borderless)
      }
      Button {
        if monitor == nil { begin() } else { end() }
      } label: {
        if monitor == nil {
          HStack(spacing: 3) {
            ForEach(shortcut.keyCaps, id: \.self) { KeyCap(label: $0) }
          }
        } else {
          Text("Press shortcut").foregroundStyle(.secondary)
        }
      }
      .buttonStyle(.plain)
    }
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
