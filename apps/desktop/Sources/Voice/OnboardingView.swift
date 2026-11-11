import AVFoundation
import SwiftUI
import VoiceCore

/// The setup window: the two permissions the app needs, then a place to try it.
struct OnboardingView: View {
  let onboarding: Onboarding
  let pushToTalk: Shortcut
  /// Whether macOS can still ask for the microphone. If not, the way is System Settings.
  let canAskForMicrophone: Bool
  /// Whether System Settings was opened for Accessibility, to say what to do there.
  let isWaitingForAccessibility: Bool
  @Binding var sample: String
  let allowAccessibility: () -> Void
  let allowMicrophone: () -> Void
  let done: () -> Void

  @FocusState private var isSampleFocused: Bool

  var body: some View {
    VStack(spacing: 20) {
      VStack(spacing: 6) {
        Image(systemName: "waveform")
          .font(.system(size: 28, weight: .medium))
        Text("Welcome to Voice")
          .font(.title2.bold())
        Text("Three steps, then dictate into any app.")
          .foregroundStyle(.secondary)
      }

      VStack(spacing: 0) {
        StepRow(
          number: 1, title: "Accessibility", state: onboarding.state(of: .accessibility),
          actionTitle: "Open Settings", action: allowAccessibility
        ) {
          Text("To use the shortcuts and type the text")
        }
        Divider()
        StepRow(
          number: 2, title: "Microphone", state: onboarding.state(of: .microphone),
          actionTitle: canAskForMicrophone ? "Allow" : "Open Settings", action: allowMicrophone
        ) {
          Text("To hear you")
        }
        Divider()
        StepRow(number: 3, title: "Try it", state: onboarding.state(of: .tryIt)) {
          HStack(spacing: 5) {
            Text("Hold")
            KeyCaps(labels: pushToTalk.keyCaps)
            Text("and speak")
          }
          TextEditor(text: $sample)
            .font(.body)
            .foregroundStyle(.primary)
            .scrollContentBackground(.hidden)
            .focused($isSampleFocused)
            .padding(6)
            .frame(height: 64)
            .background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay(alignment: .topLeading) {
              if sample.isEmpty {
                Text("Your words appear here")
                  .foregroundStyle(.tertiary)
                  .padding(.horizontal, 11)
                  .padding(.vertical, 6)
                  .allowsHitTesting(false)
              }
            }
            .padding(.top, 4)
            .disabled(!onboarding.canFinish)
        }
      }
      .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
      .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.08)))

      // Always laid out, so the window keeps its size when the note appears.
      Text(
        "Turn on \(AppInfo.name) in the list. "
          + "If it is already on, remove it with − and turn it on again."
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .opacity(isWaitingForAccessibility && !onboarding.accessibility ? 1 : 0)

      Button("Done", action: done)
        .keyboardShortcut(.defaultAction)
        .controlSize(.large)
        .disabled(!onboarding.canFinish)
    }
    .padding(24)
    .frame(width: 460)
    .fixedSize()
    .animation(.smooth(duration: 0.35), value: onboarding)
    .animation(.smooth(duration: 0.35), value: isWaitingForAccessibility)
    // The dictated text goes to the focused field, so the sample takes the focus.
    .onChange(of: onboarding.canFinish, initial: true) { isSampleFocused = onboarding.canFinish }
  }
}

/// One step of the setup: its number or a checkmark, what it is for, and its action.
private struct StepRow<Detail: View>: View {
  let number: Int
  let title: String
  let state: Onboarding.StepState
  var actionTitle: String?
  var action: () -> Void = {}
  @ViewBuilder let detail: Detail

  var body: some View {
    HStack(alignment: .top, spacing: 12) {
      ZStack {
        Circle().fill(.primary.opacity(state == .done ? 1 : 0.1))
        if state == .done {
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.background)
            .transition(.scale(scale: 0.3).combined(with: .opacity))
        } else {
          Text("\(number)")
            .font(.system(size: 11, weight: .semibold))
            .transition(.opacity)
        }
      }
      .frame(width: 22, height: 22)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.body.weight(.medium))
        detail
          .font(.callout)
          .foregroundStyle(.secondary)
          .fixedSize(horizontal: false, vertical: true)
      }
      .frame(maxWidth: .infinity, alignment: .leading)

      if state == .current, let actionTitle {
        Button(actionTitle, action: action)
          .transition(.blurReplace)
      }
    }
    .padding(14)
    .opacity(state == .upcoming ? 0.45 : 1)
  }
}

/// The setup window with the live state of the permissions.
struct OnboardingContainer: View {
  let permissions: Permissions
  let settings: Settings
  let done: () -> Void

  @State private var sample = ""
  @State private var isWaitingForAccessibility = false

  private let log = Log("setup")

  var body: some View {
    let onboarding = Onboarding(
      accessibility: permissions.accessibility,
      microphone: permissions.microphone == .authorized,
      hasDictated: !sample.isEmpty)

    OnboardingView(
      onboarding: onboarding, pushToTalk: settings.pushToTalk,
      canAskForMicrophone: permissions.microphone == .notDetermined,
      isWaitingForAccessibility: isWaitingForAccessibility, sample: $sample,
      allowAccessibility: {
        isWaitingForAccessibility = true
        permissions.requestAccessibility()
      },
      allowMicrophone: permissions.requestMicrophone, done: done
    )
    .onChange(of: onboarding.current, initial: true) {
      log.info("step", ["current": onboarding.current.map { "\($0)" } ?? "none"])
    }
  }
}
