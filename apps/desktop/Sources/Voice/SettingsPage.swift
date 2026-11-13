import AVFoundation
import SwiftUI
import VoiceCore

/// The settings, on a page of the window: the shortcuts first, then the pill, how to write
/// what is said, and the rest.
struct SettingsPage: View {
  @Bindable var settings: Settings
  let loginItem: LoginItem
  let navigation: Navigation

  @State private var microphones = AudioCapture.microphones

  private var isOpen: Bool { navigation.isOpen }

  var body: some View {
    VStack(spacing: 0) {
      TitleBar {
        BackButton(title: "Settings") { navigation.back() }
      } trailing: {
        EmptyView()
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 28) {
          shortcuts
          pill
          style
          general
          transcriptions
        }
        .padding(.horizontal, 40)
        .padding(.top, Design.tight)
        .padding(.bottom, 36)
        .frame(maxWidth: 560)
        .frame(maxWidth: .infinity)
      }
    }
    .pagePart(isOpen: isOpen)
    .task { navigation.present() }
    // It can be changed in System Settings while the window is behind.
    .onAppear { loginItem.refresh() }
    .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification))
    { _ in
      loginItem.refresh()
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

  private var shortcuts: some View {
    VStack(alignment: .leading, spacing: 0) {
      GroupTitle(title: "Shortcuts")
      Card {
        ShortcutRow(title: "Push to talk", detail: "Hold to record, release when done") {
          ShortcutField(
            shortcut: $settings.pushToTalk, fallback: .defaultPushToTalk, taken: settings.toggle,
            isRecording: $settings.isRecordingShortcut)
        }
        CardLine()
        ShortcutRow(title: "Toggle recording", detail: "Press to start, press again to stop") {
          ShortcutField(
            shortcut: $settings.toggle, fallback: .defaultToggle, taken: settings.pushToTalk,
            isRecording: $settings.isRecordingShortcut)
        }
        CardLine()
        ShortcutRow(title: "Cancel", detail: "Stops without typing anything") {
          KeyCaps(labels: ["esc"], size: .large)
            .foregroundStyle(Design.ink2)
        }
      }
      Hint("Click a shortcut to record a new one.")
    }
  }

  private var pill: some View {
    VStack(alignment: .leading, spacing: 0) {
      GroupTitle(title: "Pill")
      PillChoice(style: $settings.pillStyle, position: settings.pillPosition)
      HStack {
        Text("Position")
          .font(.voiceSetting)
          .foregroundStyle(Design.ink)
        Spacer()
        Segmented(
          options: PillPosition.allCases.map { ($0, $0.title) }, selection: $settings.pillPosition)
      }
      .padding(.horizontal, Design.tight)
      .padding(.top, 14)
    }
  }

  private var style: some View {
    VStack(alignment: .leading, spacing: 0) {
      GroupTitle(title: "Your style")
      TextEditor(text: $settings.instructions)
        .font(.system(size: 14))
        .foregroundStyle(Design.ink)
        .lineSpacing(3)
        .scrollContentBackground(.hidden)
        .frame(height: 72)
        .overlay(alignment: .topLeading) {
          if settings.instructions.isEmpty {
            Text("Write in a formal tone.")
              .font(.system(size: 14))
              .foregroundStyle(Design.ink3)
              .padding(.leading, 5)
              .allowsHitTesting(false)
          }
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 12)
        .background(
          Design.raised,
          in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
        )
        .accessibilityLabel("Your style")
      Hint("How to write what you say. Added to the built-in instructions.")
    }
  }

  private var general: some View {
    VStack(alignment: .leading, spacing: 0) {
      GroupTitle(title: "General")
      Card {
        SettingRow(title: "Microphone") {
          Select(
            options: Microphone.options(chosen: settings.microphone, connected: microphones),
            selection: $settings.microphone)
        }
        CardLine()
        SettingRow(title: "Open at login") {
          Switch(
            title: "Open at login",
            isOn: Binding {
              loginItem.isEnabled
            } set: {
              loginItem.set($0)
            })
        }
        CardLine()
        SettingRow(title: "Theme") {
          Segmented(
            options: Theme.allCases.map { ($0, $0.title) }, selection: $settings.theme,
            track: Design.fill)
        }
      }
    }
  }

  private var transcriptions: some View {
    VStack(alignment: .leading, spacing: 0) {
      GroupTitle(title: "Transcriptions")
      Card {
        SettingRow(title: "Keep on clipboard", detail: "Replaces what you copied before") {
          Switch(title: "Keep on clipboard", isOn: $settings.keepOnClipboard)
        }
        CardLine()
        SettingRow(
          title: "Press Enter",
          detail: settings.enterBehavior == .withShift
            ? "Hold Shift when you stop recording" : "After the text is typed"
        ) {
          Select(
            options: EnterBehavior.allCases.map { ($0, $0.title) },
            selection: $settings.enterBehavior)
        }
        CardLine()
        SettingRow(
          title: "Delete after", detail: "Transcriptions and recordings stay on this Mac"
        ) {
          Select(options: Retention.allCases.map { ($0, $0.title) }, selection: $settings.retention)
        }
      }
    }
  }
}

/// A setting on a card: its name, what it does, and the control that changes it.
private struct SettingRow<Control: View>: View {
  let title: String
  var detail: String?
  @ViewBuilder let control: Control

  var body: some View {
    HStack(spacing: Design.large) {
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.voiceSetting)
          .foregroundStyle(Design.ink)
        if let detail {
          Text(detail)
            .font(.voiceCaption)
            .foregroundStyle(Design.ink2)
            .contentTransition(.interpolate)
            .animation(Motion.snappy, value: detail)
        }
      }
      Spacer(minLength: Design.medium)
      control
    }
    .padding(.leading, 18)
    .padding(.trailing, Design.medium)
    .frame(minHeight: detail == nil ? 52 : 64)
  }
}

/// A shortcut on a card: its keys first, then what it does.
private struct ShortcutRow<Keys: View>: View {
  let title: String
  let detail: String
  @ViewBuilder let keys: Keys

  var body: some View {
    HStack(spacing: Design.small) {
      keys
        .frame(width: 150, alignment: .leading)
      VStack(alignment: .leading, spacing: 2) {
        Text(title)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Design.ink)
        Text(detail)
          .font(.voiceCaption)
          .foregroundStyle(Design.ink2)
      }
      Spacer(minLength: 0)
    }
    .padding(.horizontal, 18)
    .padding(.vertical, 15)
  }
}

/// What explains a group, under it.
private struct Hint: View {
  let text: String

  init(_ text: String) {
    self.text = text
  }

  var body: some View {
    Text(text)
      .font(.voiceCaption)
      .foregroundStyle(Design.ink3)
      .padding(.horizontal, Design.tight)
      .padding(.top, 10)
  }
}

/// The two styles of the pill, each drawn on a small screen where the pill shows. The mark
/// of the choice slides to the one chosen, and the pills move when the position changes.
private struct PillChoice: View {
  @Binding var style: PillStyle
  let position: PillPosition

  @Namespace private var namespace

  var body: some View {
    HStack(spacing: Design.medium) {
      option(.minimal, title: "Minimal", detail: "Just the waveform")
      option(.detailed, title: "Detailed", detail: "The waveform and your words")
    }
    .animation(Motion.snappy, value: style)
    .animation(Motion.knob, value: position)
  }

  private func option(_ value: PillStyle, title: String, detail: String) -> some View {
    Button {
      style = value
    } label: {
      VStack(alignment: .leading, spacing: 10) {
        screen(value)
        VStack(alignment: .leading, spacing: 2) {
          Text(title)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(Design.ink)
          Text(detail)
            .font(.voiceCaption)
            .foregroundStyle(Design.ink2)
        }
        .padding(.horizontal, Design.tight)
        .padding(.bottom, 2)
      }
      .padding(10)
      .background(
        Design.raised, in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
      )
      .overlay {
        RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
          .strokeBorder(Design.line)
      }
      .overlay {
        if style == value {
          RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous)
            .strokeBorder(Design.ink, lineWidth: 2)
            .matchedGeometryEffect(id: "choice", in: namespace)
        }
      }
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointer()
    .accessibilityLabel(title)
    .accessibilityAddTraits(style == value ? .isSelected : [])
  }

  private func screen(_ value: PillStyle) -> some View {
    RoundedRectangle(cornerRadius: 9, style: .continuous)
      .fill(Design.fill)
      .frame(height: 84)
      .overlay(alignment: position == .top ? .top : .bottom) {
        Group {
          switch value {
          case .minimal: minimal
          case .detailed: detailed
          }
        }
        .padding(.vertical, 10)
      }
      .accessibilityHidden(true)
  }

  private var minimal: some View {
    HStack(spacing: 5) {
      Circle().fill(Design.signal).frame(width: 5, height: 5)
      HStack(spacing: 2) {
        ForEach([4.0, 7, 10, 6, 3], id: \.self) { height in
          Capsule().fill(.white).frame(width: 2, height: height)
        }
      }
    }
    .padding(.horizontal, 8)
    .frame(height: 16)
    .background(Design.lamp, in: Capsule())
  }

  private var detailed: some View {
    VStack(alignment: .leading, spacing: 4) {
      HStack(spacing: 4) {
        Circle().fill(Design.signal).frame(width: 5, height: 5)
        HStack(spacing: 2) {
          ForEach(0..<24, id: \.self) { _ in
            Capsule().fill(.white.opacity(0.8)).frame(width: 2, height: 6)
          }
        }
      }
      Capsule().fill(.white.opacity(0.45)).frame(width: 92, height: 3)
      Capsule().fill(.white.opacity(0.45)).frame(width: 64, height: 3)
    }
    .padding(.horizontal, 8)
    .padding(.vertical, 7)
    .frame(width: 116, alignment: .leading)
    .background(Design.lamp, in: RoundedRectangle(cornerRadius: 9, style: .continuous))
  }
}
