import AVFoundation
import SwiftUI
import VoiceCore

struct SettingsView: View {
  @Bindable var settings: Settings
  let loginItem: LoginItem
  @State private var microphones = AudioCapture.microphones

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Design.wide) {
        group("General") {
          SettingRow(title: "Open at login", detail: "Starts in the menu bar when you log in") {
            Switch(
              title: "Open at login",
              isOn: Binding {
                loginItem.isEnabled
              } set: {
                loginItem.set($0)
              })
          }
          SettingRow(title: "Microphone", detail: "Records what you dictate") {
            Select(
              options: Microphone.options(chosen: settings.microphone, connected: microphones),
              selection: $settings.microphone)
          }
        }

        group("Appearance") {
          SettingRow(title: "Theme") {
            Segmented(options: Theme.allCases.map { ($0, $0.title) }, selection: $settings.theme)
          }
          SettingRow(title: "Pill") {
            Segmented(
              options: PillStyle.allCases.map { ($0, $0.title) }, selection: $settings.pillStyle)
          }
          SettingRow(title: "Pill position") {
            Segmented(
              options: PillPosition.allCases.map { ($0, $0.title) },
              selection: $settings.pillPosition)
          }
        }

        group("Shortcuts") {
          SettingRow(title: "Push to talk", detail: "Hold to record, release when done") {
            ShortcutField(
              shortcut: $settings.pushToTalk, fallback: .defaultPushToTalk, taken: settings.toggle,
              isRecording: $settings.isRecordingShortcut)
          }
          SettingRow(title: "Toggle recording", detail: "Press to start, press again to stop") {
            ShortcutField(
              shortcut: $settings.toggle, fallback: .defaultToggle, taken: settings.pushToTalk,
              isRecording: $settings.isRecordingShortcut)
          }
        }

        group("Transcription") {
          SettingRow(
            title: "Translate",
            detail: settings.translates && settings.translateTo.isEmpty
              ? "Type the language to write in" : "Writes what you say in another language"
          ) {
            TranslationControl(isOn: $settings.translates, language: $settings.translationLanguage)
          }
          SettingRow(
            title: "Keep on clipboard", detail: "Replaces the previous clipboard contents"
          ) {
            Switch(title: "Keep on clipboard", isOn: $settings.keepOnClipboard)
          }
          SettingRow(
            title: "Press Enter",
            detail: settings.enterBehavior == .withShift
              ? "Hold Shift when you stop recording" : "After pasting the transcription"
          ) {
            Select(
              options: EnterBehavior.allCases.map { ($0, $0.title) },
              selection: $settings.enterBehavior)
          }
        }

        group("Instructions") {
          TextEditor(text: $settings.instructions)
            .font(.voiceBody)
            .scrollContentBackground(.hidden)
            .frame(height: 64)
            .overlay(alignment: .topLeading) {
              if settings.instructions.isEmpty {
                Text("Write in a formal tone.")
                  .font(.voiceBody)
                  .foregroundStyle(.tertiary)
                  .padding(.leading, 5)
                  .allowsHitTesting(false)
              }
            }
            .padding(.horizontal, Design.small - 5)
            .padding(.vertical, Design.small)
            .background(
              Design.surface,
              in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
            )
            .padding(.vertical, Design.tight)
          Text("How to write what you say. Added to the built-in instructions.")
            .font(.voiceCaption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, Design.small)
        }

        group("History") {
          SettingRow(
            title: "Delete after", detail: "Transcriptions and recordings stay on this Mac"
          ) {
            Select(
              options: Retention.allCases.map { ($0, $0.title) }, selection: $settings.retention)
          }
        }
      }
      .padding(Design.medium)
    }
    .endsEditingOnClickOutside()
    // It can be changed in System Settings while the window is behind.
    .onAppear { loginItem.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    {
      _ in loginItem.refresh()
    }
    .onReceive(
      NotificationCenter.default.publisher(for: AVCaptureDevice.wasConnectedNotification)
        .merge(
          with: NotificationCenter.default.publisher(
            for: AVCaptureDevice.wasDisconnectedNotification)
        )
        .receive(on: RunLoop.main)
    ) { _ in microphones = AudioCapture.microphones }
  }

  private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      GroupTitle(title: title)
        .padding(.bottom, Design.tight)
      rows()
    }
  }
}

/// Translation, on or off. Turning it on brings in the field for the language, ready to type in.
/// The field is as wide as the language in it, as a `Select` is as wide as its choice.
private struct TranslationControl: View {
  @Binding var isOn: Bool
  @Binding var language: String
  @FocusState private var isFocused: Bool

  /// Wide enough for the language typed, or for the placeholder. A language too long for
  /// the row is cut short with an ellipsis.
  private var fieldWidth: Double {
    let text = language.isEmpty ? "Language" : language
    let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    let width = (text as NSString).size(withAttributes: [.font: font]).width
    // The padding on either side, and the room the field keeps around its text.
    return min(max(width.rounded(.up) + 26, 96), 240)
  }

  var body: some View {
    HStack(spacing: Design.small) {
      if isOn {
        TextField("Language", text: $language)
          .textFieldStyle(.plain)
          .font(.voiceLabel)
          .lineLimit(1)
          .truncationMode(.tail)
          .focused($isFocused)
          .onSubmit { isFocused = false }
          .onExitCommand { isFocused = false }
          .padding(.horizontal, 10)
          .frame(width: fieldWidth, height: 26)
          .background(
            Design.surface,
            in: RoundedRectangle(cornerRadius: Design.controlRadius + 1, style: .continuous)
          )
          .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
      }
      Switch(title: "Translate", isOn: $isOn)
    }
    .animation(Design.move, value: isOn)
    .onChange(of: isOn) { _, isOn in
      // Only an empty field asks to be typed in. A language set before stays as it is.
      if isOn && language.isEmpty { isFocused = true }
    }
  }
}

/// A setting: its name, what it does, and the control that changes it.
private struct SettingRow<Control: View>: View {
  let title: String
  var detail: String?
  @ViewBuilder let control: Control

  var body: some View {
    HStack(spacing: Design.medium) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.voiceBody)
        if let detail {
          Text(detail)
            .font(.voiceCaption)
            .foregroundStyle(.secondary)
        }
      }
      Spacer(minLength: Design.medium)
      control
    }
    .padding(.horizontal, Design.small)
    .frame(minHeight: detail == nil ? 34 : 44)
  }
}

/// A click anywhere but in a text field ends the typing in one, as pressing Return does.
/// By itself a field keeps the focus until the view goes away.
private struct EndsEditingOnClickOutside: ViewModifier {
  @State private var monitor: Any?

  func body(content: Content) -> some View {
    content
      .onAppear {
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
          if let window = event.window, window.firstResponder is NSText,
            let hit = window.contentView?.hitTest(event.locationInWindow),
            !(hit is NSText || hit is NSTextField)
          {
            window.makeFirstResponder(nil)
          }
          return event
        }
      }
      .onDisappear {
        monitor.map(NSEvent.removeMonitor)
        monitor = nil
      }
  }
}

extension View {
  fileprivate func endsEditingOnClickOutside() -> some View {
    modifier(EndsEditingOnClickOutside())
  }
}
