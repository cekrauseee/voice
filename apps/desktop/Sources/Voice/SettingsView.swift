import AVFoundation
import SwiftUI
import VoiceCore

struct SettingsView: View {
  @Bindable var settings: Settings
  let loginItem: LoginItem
  let permissions: Permissions
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
          SettingRow(title: "Media", detail: mediaDetail) {
            HStack(spacing: Design.small) {
              if needsSystemAudio {
                Button("Allow", action: permissions.requestSystemAudio)
                  .buttonStyle(.plain)
                  .font(.voiceLabel)
                  .padding(.horizontal, 10)
                  .frame(height: 26)
                  .background(
                    Design.surface,
                    in: RoundedRectangle(cornerRadius: Design.controlRadius + 1, style: .continuous)
                  )
                  .contentShape(Rectangle())
                  .pointer()
                  .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
              }
              if settings.mediaBehavior == .lower {
                Select(
                  options: LoweredVolume.allCases.map { ($0, $0.title) },
                  selection: $settings.loweredVolume
                )
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .trailing)))
              }
              Select(
                options: MediaBehavior.allCases.map { ($0, $0.title) },
                selection: $settings.mediaBehavior)
            }
            .animation(Design.move, value: needsSystemAudio)
            .animation(Design.move, value: settings.mediaBehavior)
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

  /// Muting works without a permission on an output that can be muted. On one that cannot,
  /// it takes the permission to mute the other apps, so the row asks for it, and only then.
  private var needsSystemAudio: Bool {
    settings.mediaBehavior == .mute && permissions.systemAudio != .allowed
      && !OtherAudio.canMuteOutput
  }

  /// Whether the microphone that records is the one of the Bluetooth headset that plays. It
  /// plays in call quality while its microphone is open, so media that plays on is heard
  /// that way.
  private var recordsWithHeadset: Bool {
    guard let output = AudioDevice.output, AudioDevice.isBluetooth(output) else { return false }
    let microphone = settings.microphone.flatMap { AudioDevice.withID($0.id) } ?? AudioDevice.input
    return microphone.map(AudioDevice.isBluetooth) ?? false
  }

  private var mediaDetail: String {
    if needsSystemAudio { return "Allow System Audio Recording to mute this output" }
    return switch settings.mediaBehavior {
    case .pause: "Pauses while you record, and resumes after"
    case .mute: "Plays on while you record, muted"
    case .lower:
      recordsWithHeadset
        ? "Quieter, and like a phone call with this microphone"
        : "Plays on while you record, quieter"
    case .keep:
      recordsWithHeadset
        ? "Like a phone call with this microphone" : "Plays on while you record"
    }
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
/// The field has one width: a language too long for it ends in an ellipsis.
private struct TranslationControl: View {
  @Binding var isOn: Bool
  @Binding var language: String
  /// Set when the field comes in empty, for it to take the focus.
  @State private var takesFocus = false

  var body: some View {
    HStack(spacing: Design.small) {
      if isOn {
        LineField(placeholder: "Language", text: $language, takesFocus: $takesFocus)
          .padding(.horizontal, Design.small)
          .frame(width: 160, height: 26)
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
      takesFocus = isOn && language.isEmpty
    }
  }
}

/// One line of text to type in, of a fixed width. While it is typed in, the text scrolls to
/// keep the insertion point in view. At rest, text too long for it ends in an ellipsis.
/// Return and Escape end the typing.
///
/// SwiftUI's `TextField` does one or the other: it scrolls and cuts the text off at rest, or
/// it shows the ellipsis and does not scroll.
private struct LineField: NSViewRepresentable {
  let placeholder: String
  @Binding var text: String
  @Binding var takesFocus: Bool

  func makeNSView(context: Context) -> Field {
    let field = Field()
    let font = NSFont.systemFont(ofSize: 12, weight: .medium)
    field.font = font
    field.placeholderAttributedString = NSAttributedString(
      string: placeholder, attributes: [.font: font, .foregroundColor: NSColor.tertiaryLabelColor])
    field.isBordered = false
    field.drawsBackground = false
    field.focusRingType = .none
    field.cell?.usesSingleLineMode = true
    field.cell?.lineBreakMode = .byTruncatingTail
    field.setContentHuggingPriority(.defaultLow, for: .horizontal)
    field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
    field.delegate = context.coordinator
    return field
  }

  func updateNSView(_ field: Field, context: Context) {
    context.coordinator.text = $text
    if field.stringValue != text { field.stringValue = text }
    guard takesFocus else { return }
    // Once it is in the window.
    DispatchQueue.main.async {
      takesFocus = false
      field.window?.makeFirstResponder(field)
    }
  }

  func makeCoordinator() -> Coordinator {
    Coordinator(text: $text)
  }

  @MainActor
  final class Coordinator: NSObject, NSTextFieldDelegate {
    var text: Binding<String>

    init(text: Binding<String>) {
      self.text = text
    }

    func controlTextDidChange(_ notification: Notification) {
      guard let field = notification.object as? NSTextField else { return }
      text.wrappedValue = field.stringValue
    }

    func control(
      _ control: NSControl, textView: NSTextView, doCommandBy selector: Selector
    ) -> Bool {
      guard
        selector == #selector(NSResponder.insertNewline(_:))
          || selector == #selector(NSResponder.cancelOperation(_:))
      else { return false }
      control.window?.makeFirstResponder(nil)
      return true
    }
  }

  /// A cell either scrolls or ends its text in an ellipsis, so the field scrolls while it is
  /// typed in, and goes back to the ellipsis after.
  final class Field: NSTextField {
    override func becomeFirstResponder() -> Bool {
      cell?.isScrollable = true
      return super.becomeFirstResponder()
    }

    override func textDidEndEditing(_ notification: Notification) {
      super.textDidEndEditing(notification)
      cell?.lineBreakMode = .byTruncatingTail
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
