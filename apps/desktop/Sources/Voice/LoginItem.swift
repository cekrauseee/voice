import Observation
import ServiceManagement

/// Whether macOS opens the app when the user logs in.
///
/// macOS keeps the answer, and the user can change it in System Settings, under Login
/// Items. So it is read from there, and not kept with the settings.
@MainActor @Observable
final class LoginItem {
  private(set) var isEnabled = SMAppService.mainApp.status == .enabled

  @ObservationIgnored private let log = Log("login")

  /// Reads the answer again: it may have changed in System Settings.
  func refresh() {
    isEnabled = SMAppService.mainApp.status == .enabled
  }

  func set(_ enabled: Bool) {
    do {
      if enabled {
        try SMAppService.mainApp.register()
      } else {
        try SMAppService.mainApp.unregister()
      }
    } catch {
      log.error("not changed", ["enabled": enabled, "error": error.localizedDescription])
    }
    // The user turned the app off in System Settings, and only they can turn it on again.
    if enabled, SMAppService.mainApp.status == .requiresApproval {
      SMAppService.openSystemSettingsLoginItems()
    }
    refresh()
    log.info("changed", ["enabled": isEnabled])
  }
}
