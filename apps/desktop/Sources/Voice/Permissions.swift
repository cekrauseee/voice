import AVFoundation
import AppKit
import ApplicationServices
import Observation

/// The two permissions the app needs, and the one it can do without. They are granted in
/// System Settings, outside the app, so their state is read again every second.
@MainActor @Observable
final class Permissions {
  /// Lets the app see the shortcuts and type the dictated text.
  private(set) var accessibility = AXIsProcessTrusted()
  private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)
  /// Lets the app mute the other apps alone. Without it, muting mutes the Mac's output.
  /// Asking macOS about it takes a few milliseconds, so it is asked away from the main
  /// thread, and what a dictation reads is the last answer.
  private(set) var systemAudio = SystemAudio.state

  @ObservationIgnored private let log = Log("permissions")

  init() {
    log.info(
      "state",
      [
        "accessibility": accessibility, "microphone": microphone.name,
        "system_audio": systemAudio.rawValue,
      ])
    Task {
      while true {
        try? await Task.sleep(for: .seconds(1))
        refresh(systemAudio: await Task.detached { SystemAudio.state }.value)
      }
    }
  }

  var isComplete: Bool {
    accessibility && microphone == .authorized
  }

  /// Adds the app to the Accessibility list in System Settings and opens it there.
  func requestAccessibility() {
    log.info("requested", ["permission": "accessibility"])
    _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
    openSettings("Privacy_Accessibility")
  }

  /// Asks for the microphone. macOS asks only once: after that, the way is System Settings.
  func requestMicrophone() {
    log.info("requested", ["permission": "microphone"])
    if microphone == .notDetermined {
      Task {
        _ = await AVCaptureDevice.requestAccess(for: .audio)
        refresh()
      }
    } else {
      openSettings("Privacy_Microphone")
    }
  }

  /// Asks for System Audio Recording. macOS asks only once: after that, the way is System
  /// Settings.
  func requestSystemAudio() {
    log.info("requested", ["permission": "system_audio"])
    if systemAudio == .undetermined {
      SystemAudio.request()
    } else {
      openSettings("Privacy_AudioCapture")
    }
  }

  private func refresh(systemAudio: SystemAudio.State? = nil) {
    if let systemAudio, systemAudio != self.systemAudio {
      self.systemAudio = systemAudio
      log.info("changed", ["permission": "system_audio", "state": systemAudio.rawValue])
    }
    let accessibility = AXIsProcessTrusted()
    if accessibility != self.accessibility {
      self.accessibility = accessibility
      log.info("changed", ["permission": "accessibility", "granted": accessibility])
    }
    let microphone = AVCaptureDevice.authorizationStatus(for: .audio)
    if microphone != self.microphone {
      self.microphone = microphone
      log.info("changed", ["permission": "microphone", "state": microphone.name])
    }
  }

  private func openSettings(_ pane: String) {
    let url = "x-apple.systempreferences:com.apple.preference.security?\(pane)"
    NSWorkspace.shared.open(URL(string: url)!)
  }
}

extension AVAuthorizationStatus {
  fileprivate var name: String {
    switch self {
    case .authorized: "granted"
    case .denied: "denied"
    case .restricted: "restricted"
    case .notDetermined: "undetermined"
    @unknown default: "unknown"
    }
  }
}
