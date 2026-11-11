import AVFoundation
import AppKit
import ApplicationServices
import Observation

/// The two permissions the app needs. They are granted in System Settings, outside the
/// app, so their state is read again every second.
@MainActor @Observable
final class Permissions {
  /// Lets the app see the shortcuts and type the dictated text.
  private(set) var accessibility = AXIsProcessTrusted()
  private(set) var microphone = AVCaptureDevice.authorizationStatus(for: .audio)

  @ObservationIgnored private let log = Log("permissions")

  init() {
    log.info("state", ["accessibility": accessibility, "microphone": microphone.name])
    Task {
      while true {
        try? await Task.sleep(for: .seconds(1))
        refresh()
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

  private func refresh() {
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
