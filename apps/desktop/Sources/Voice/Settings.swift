import Foundation
import Observation
import VoiceCore

/// The user's preferences, kept in the user defaults.
@MainActor @Observable
final class Settings {
  var theme: Theme {
    didSet { defaults.set(theme.rawValue, forKey: "theme") }
  }
  var pillStyle: PillStyle {
    didSet { defaults.set(pillStyle.rawValue, forKey: "pillStyle") }
  }
  var pushToTalk: Shortcut {
    didSet { save(pushToTalk, forKey: "pushToTalk") }
  }
  var toggle: Shortcut {
    didSet { save(toggle, forKey: "toggle") }
  }
  /// How the user wants their words written, on top of the server's own instructions.
  var instructions: String {
    didSet { defaults.set(instructions, forKey: "instructions") }
  }

  /// How long a transcription and its recording are kept.
  var retention: Retention {
    didSet { defaults.set(retention.rawValue, forKey: "retention") }
  }

  /// Whether the window's sidebar only shows icons.
  var isSidebarCollapsed: Bool {
    didSet { defaults.set(isSidebarCollapsed, forKey: "isSidebarCollapsed") }
  }

  /// Whether the welcome window was completed.
  var hasOnboarded: Bool {
    didSet { defaults.set(hasOnboarded, forKey: "hasOnboarded") }
  }

  /// Set while the settings window captures a new shortcut, so the current ones stay quiet.
  var isRecordingShortcut = false

  /// Where the dictation server is. Change it with `defaults write eu.cekrause.voice serverURL`.
  /// Unless it is set, the production app runs its own server, and the development app uses the
  /// one `pnpm dev` runs.
  let serverURL: URL

  /// Whether the app runs the server itself, on this Mac.
  let runsServer: Bool

  /// The `.env` the app's server runs with. `pnpm install-app` sets it to the repository's.
  let serverEnvFile: String?

  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    theme = defaults.string(forKey: "theme").flatMap(Theme.init) ?? .auto
    pillStyle = defaults.string(forKey: "pillStyle").flatMap(PillStyle.init) ?? .minimal
    pushToTalk = Self.shortcut(defaults, forKey: "pushToTalk") ?? .defaultPushToTalk
    toggle = Self.shortcut(defaults, forKey: "toggle") ?? .defaultToggle
    instructions = defaults.string(forKey: "instructions") ?? ""
    retention = defaults.string(forKey: "retention").flatMap(Retention.init) ?? .never
    isSidebarCollapsed = defaults.bool(forKey: "isSidebarCollapsed")
    hasOnboarded = defaults.bool(forKey: "hasOnboarded")
    let otherServer = defaults.string(forKey: "serverURL").flatMap(URL.init)
    runsServer = otherServer == nil && !AppInfo.isDevelopment
    serverURL =
      otherServer ?? (AppInfo.isDevelopment ? URL(string: "ws://127.0.0.1:8787")! : LocalServer.url)
    serverEnvFile = defaults.string(forKey: "serverEnvFile")
  }

  private static func shortcut(_ defaults: UserDefaults, forKey key: String) -> Shortcut? {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
  }

  private func save(_ shortcut: Shortcut, forKey key: String) {
    defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
  }
}
