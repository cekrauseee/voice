import AVFoundation
import SwiftUI
import VoiceCore

/// The first-launch window: the two permissions the app needs, and how to dictate.
struct OnboardingView: View {
  let settings: Settings
  let onDone: () -> Void

  @State private var askedForAccessibility = false

  var body: some View {
    // The permissions are granted outside the app, so their state is read again every second.
    TimelineView(.periodic(from: .now, by: 1)) { _ in
      let accessibility = Permissions.isAccessibilityGranted
      let microphone = AVCaptureDevice.authorizationStatus(for: .audio)

      VStack(spacing: 0) {
        VStack(spacing: 6) {
          Image(systemName: "waveform")
            .font(.system(size: 28, weight: .medium))
          Text("Welcome to Voice")
            .font(.title2.bold())
          Text("Allow two permissions, then dictate into any app.")
            .foregroundStyle(.secondary)
        }
        .padding(.top, 28)

        Form {
          Section("Permissions") {
            PermissionRow(
              title: "Accessibility", detail: "To use the shortcuts and type the text",
              isAllowed: accessibility, allow: allowAccessibility)
            PermissionRow(
              title: "Microphone", detail: "To hear you",
              isAllowed: microphone == .authorized
            ) {
              if microphone == .notDetermined {
                AVCaptureDevice.requestAccess(for: .audio) { _ in }
              } else {
                Permissions.openPrivacySettings("Privacy_Microphone")
              }
            }
          }
          Section("Shortcuts") {
            LabeledContent("Hold to dictate") {
              KeyCaps(labels: settings.pushToTalk.keyCaps)
            }
            LabeledContent("Press to start and stop") {
              KeyCaps(labels: settings.toggle.keyCaps)
            }
          }
        }
        .formStyle(.grouped)

        Button("Done", action: onDone)
          .keyboardShortcut(.defaultAction)
          .controlSize(.large)
          .disabled(!accessibility || microphone != .authorized)
          .padding(.bottom, 20)
      }
      .frame(width: 440)
      .fixedSize()
    }
  }

  /// The system prompt shows once. After that, the settings page is the way in.
  private func allowAccessibility() {
    if askedForAccessibility {
      Permissions.openPrivacySettings("Privacy_Accessibility")
    } else {
      askedForAccessibility = true
      Permissions.promptForAccessibility()
    }
  }
}

private struct PermissionRow: View {
  let title: String
  let detail: String
  let isAllowed: Bool
  let allow: () -> Void

  var body: some View {
    LabeledContent {
      if isAllowed {
        Label("Allowed", systemImage: "checkmark")
          .foregroundStyle(.secondary)
      } else {
        Button("Allow", action: allow)
      }
    } label: {
      Text(title)
      Text(detail)
    }
  }
}
