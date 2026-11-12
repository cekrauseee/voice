import SwiftUI
import VoiceCore

struct SettingsView: View {
  @Bindable var settings: Settings

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Design.loose) {
        group("Appearance") {
          SettingRow(title: "Theme") {
            Segmented(options: Theme.allCases.map { ($0, $0.title) }, selection: $settings.theme)
          }
          Hairline()
          SettingRow(title: "Pill") {
            Segmented(
              options: PillStyle.allCases.map { ($0, $0.title) }, selection: $settings.pillStyle)
          }
        }

        group("Shortcuts") {
          SettingRow(title: "Push to talk", detail: "Hold to record, release when done") {
            ShortcutField(
              shortcut: $settings.pushToTalk, fallback: .defaultPushToTalk, taken: settings.toggle,
              isRecording: $settings.isRecordingShortcut)
          }
          Hairline()
          SettingRow(title: "Toggle recording", detail: "Press to start, press again to stop") {
            ShortcutField(
              shortcut: $settings.toggle, fallback: .defaultToggle, taken: settings.pushToTalk,
              isRecording: $settings.isRecordingShortcut)
          }
        }

        VStack(alignment: .leading, spacing: Design.small) {
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
              .padding(.horizontal, Design.medium - 5)
              .padding(.vertical, 10)
          }
          Text("How to write what you say. Added to the built-in instructions.")
            .font(.voiceCaption)
            .foregroundStyle(.secondary)
            .padding(.leading, Design.medium)
        }
      }
      .padding(.horizontal, Design.wide)
      .padding(.vertical, Design.large)
    }
  }

  private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: Design.small) {
      GroupTitle(title: title)
      Card(content: rows)
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
    .padding(.horizontal, Design.medium)
    .frame(minHeight: detail == nil ? 40 : 52)
  }
}
