import SwiftUI
import VoiceCore

struct SettingsView: View {
  @Bindable var settings: Settings

  var body: some View {
    Form {
      Section("Appearance") {
        Picker("Theme", selection: $settings.theme) {
          ForEach(Theme.allCases) { Text($0.title).tag($0) }
        }
        Picker("Pill", selection: $settings.pillStyle) {
          ForEach(PillStyle.allCases) { Text($0.title).tag($0) }
        }
      }
      .pickerStyle(.segmented)

      Section("Shortcuts") {
        LabeledContent {
          ShortcutField(
            shortcut: $settings.pushToTalk, fallback: .defaultPushToTalk, taken: settings.toggle,
            isRecording: $settings.isRecordingShortcut)
        } label: {
          Text("Push to talk")
          Text("Hold to record, release when done")
        }
        LabeledContent {
          ShortcutField(
            shortcut: $settings.toggle, fallback: .defaultToggle, taken: settings.pushToTalk,
            isRecording: $settings.isRecordingShortcut)
        } label: {
          Text("Toggle recording")
          Text("Press to start, press again to stop")
        }
      }

      Section {
        TextEditor(text: $settings.instructions)
          .font(.body)
          .scrollContentBackground(.hidden)
          .frame(height: 72)
          .overlay(alignment: .topLeading) {
            if settings.instructions.isEmpty {
              Text("Write in a formal tone.")
                .foregroundStyle(.tertiary)
                .padding(.leading, 5)
                .allowsHitTesting(false)
            }
          }
      } header: {
        Text("Instructions")
      } footer: {
        Text("How to write what you say. Added to the built-in instructions.")
      }
    }
    .formStyle(.grouped)
  }
}
