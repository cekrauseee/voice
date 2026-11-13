import AVFoundation
import SwiftUI
import VoiceCore

/// The setup window: the two permissions the app needs, then a place to try it. Under
/// them is the choice of opening the app at login, which is not a step: it can be left.
struct OnboardingView: View {
  let onboarding: Onboarding
  let pushToTalk: Shortcut
  /// Whether macOS can still ask for the microphone. If not, the way is System Settings.
  let canAskForMicrophone: Bool
  /// Whether System Settings was opened for Accessibility, to say what to do there.
  let isWaitingForAccessibility: Bool
  @Binding var sample: String
  @Binding var opensAtLogin: Bool
  let allowAccessibility: () -> Void
  let allowMicrophone: () -> Void
  let done: () -> Void

  @FocusState private var isSampleFocused: Bool

  var body: some View {
    VStack(spacing: 0) {
      VStack(spacing: 0) {
        Image(nsImage: NSApp.applicationIconImage)
          .resizable()
          .frame(width: 80, height: 80)
          .accessibilityHidden(true)
        Text("Welcome to Voice")
          .font(.system(size: 26, weight: .semibold))
          .tracking(-0.5)
          .foregroundStyle(Design.ink)
          .padding(.top, 14)
        Text("Hold a key, speak, and your words are typed where you are.")
          .font(.system(size: 14))
          .foregroundStyle(Design.ink2)
          .multilineTextAlignment(.center)
          .padding(.top, 8)
      }
      .padding(.horizontal, 40)

      VStack(spacing: 0) {
        StepRow(
          number: 1, title: "Accessibility", state: onboarding.state(of: .accessibility),
          actionTitle: "Open Settings", action: allowAccessibility
        ) {
          Text("To use the shortcuts and type the text")
        }
        StepLine()
        StepRow(
          number: 2, title: "Microphone", state: onboarding.state(of: .microphone),
          actionTitle: canAskForMicrophone ? "Allow" : "Open Settings", action: allowMicrophone
        ) {
          Text("To hear you")
        }
        StepLine()
        StepRow(number: 3, title: "Try it", state: onboarding.state(of: .tryIt)) {
          HStack(spacing: 6) {
            Text("Hold")
            KeyCaps(labels: pushToTalk.keyCaps)
              .foregroundStyle(Design.ink)
            Text("and speak")
          }
          TextEditor(text: $sample)
            .font(.system(size: 14))
            .foregroundStyle(Design.ink)
            .scrollContentBackground(.hidden)
            .focused($isSampleFocused)
            .padding(.horizontal, 9)
            .padding(.vertical, 10)
            .frame(height: 72)
            .background(Design.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            .overlay(alignment: .topLeading) {
              if sample.isEmpty {
                Text("Your words appear here")
                  .font(.system(size: 14))
                  .foregroundStyle(Design.ink3)
                  .padding(.horizontal, 14)
                  .padding(.vertical, 10)
                  .allowsHitTesting(false)
              }
            }
            .padding(.top, 4)
            .disabled(!onboarding.canFinish)
            .accessibilityLabel("Try a dictation")
        }
      }
      .padding(.horizontal, 36)
      .padding(.top, 28)

      // Always laid out, so the window keeps its size when the note appears.
      Text(
        "Turn on \(AppInfo.name) in the list. "
          + "If it is already on, remove it with − and turn it on again."
      )
      .font(.voiceCaption)
      .foregroundStyle(Design.ink2)
      .multilineTextAlignment(.center)
      .fixedSize(horizontal: false, vertical: true)
      .padding(.horizontal, 40)
      .padding(.top, 10)
      .opacity(isWaitingForAccessibility && !onboarding.accessibility ? 1 : 0)

      HStack {
        HStack(spacing: 10) {
          Switch(title: "Open at login", isOn: $opensAtLogin)
          Text("Open at login")
            .font(.voiceBody)
            .foregroundStyle(Design.ink)
        }
        Spacer()
        Button("Done", action: done)
          .buttonStyle(PrimaryButtonStyle())
          .pointer()
          .keyboardShortcut(.defaultAction)
          .disabled(!onboarding.canFinish)
      }
      .padding(.horizontal, 36)
      .padding(.top, 16)
      .padding(.bottom, 26)
      .overlay(alignment: .top) {
        Rectangle().fill(Design.line).frame(height: 1).padding(.top, 2)
      }
      .padding(.top, 10)
    }
    .padding(.top, 8)
    .frame(width: 520)
    .fixedSize()
    .background(Design.ground)
    .animation(.smooth(duration: 0.35), value: onboarding)
    .animation(.smooth(duration: 0.35), value: isWaitingForAccessibility)
    // The dictated text goes to the focused field, so the sample takes the focus.
    .onChange(of: onboarding.canFinish, initial: true) { isSampleFocused = onboarding.canFinish }
  }
}

/// The line between two steps.
private struct StepLine: View {
  var body: some View {
    Rectangle().fill(Design.line).frame(height: 1)
  }
}

/// One step of the setup: a check once it is done, else its number, what it is for, and its
/// action.
private struct StepRow<Detail: View>: View {
  let number: Int
  let title: String
  let state: Onboarding.StepState
  var actionTitle: String?
  var action: () -> Void = {}
  @ViewBuilder let detail: Detail

  var body: some View {
    HStack(alignment: .top, spacing: 14) {
      ZStack {
        if state == .done {
          Circle().fill(Design.ink)
          Image(systemName: "checkmark")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(Design.ground)
            .transition(.scale(scale: 0.3).combined(with: .opacity))
        } else {
          Circle().strokeBorder(state == .current ? Design.ink : Design.ink3, lineWidth: 1.5)
          Text("\(number)")
            .font(.voiceMono(11, weight: .semibold))
            .foregroundStyle(state == .current ? Design.ink : Design.ink2)
            .transition(.opacity)
        }
      }
      .frame(width: 24, height: 24)

      VStack(alignment: .leading, spacing: 4) {
        Text(title)
          .font(.system(size: 14, weight: .medium))
          .foregroundStyle(Design.ink)
        detail
          .font(.system(size: 12.5))
          .foregroundStyle(Design.ink2)
          .fixedSize(horizontal: false, vertical: true)
      }
      .padding(.top, 3)
      .frame(maxWidth: .infinity, alignment: .leading)

      if state == .current, let actionTitle {
        Button(actionTitle, action: action)
          .buttonStyle(PrimaryButtonStyle())
          .pointer()
          .transition(.blurReplace)
      } else if state == .done {
        Text(title == "Try it" ? "Done" : "Allowed")
          .font(.voiceMono(11.5))
          .foregroundStyle(Design.ink3)
          .padding(.top, 5)
          .transition(.opacity)
      }
    }
    .padding(.vertical, 16)
    .opacity(state == .upcoming ? 0.45 : 1)
  }
}

/// The setup window with the live state of the permissions.
struct OnboardingContainer: View {
  let permissions: Permissions
  let settings: Settings
  let loginItem: LoginItem
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
      opensAtLogin: Binding {
        loginItem.isEnabled
      } set: {
        loginItem.set($0)
      },
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
