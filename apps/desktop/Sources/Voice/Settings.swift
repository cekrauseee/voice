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
  let serverURL: URL

  @ObservationIgnored private let defaults: UserDefaults

  init(defaults: UserDefaults = .standard) {
    self.defaults = defaults
    theme = defaults.string(forKey: "theme").flatMap(Theme.init) ?? .auto
    pillStyle = defaults.string(forKey: "pillStyle").flatMap(PillStyle.init) ?? .minimal
    pushToTalk = Self.shortcut(defaults, forKey: "pushToTalk") ?? .defaultPushToTalk
    toggle = Self.shortcut(defaults, forKey: "toggle") ?? .defaultToggle
    instructions = defaults.string(forKey: "instructions") ?? ""
    isSidebarCollapsed = defaults.bool(forKey: "isSidebarCollapsed")
    hasOnboarded = defaults.bool(forKey: "hasOnboarded")
    serverURL =
      defaults.string(forKey: "serverURL").flatMap(URL.init)
      ?? URL(string: "ws://127.0.0.1:8787")!
  }

  private static func shortcut(_ defaults: UserDefaults, forKey key: String) -> Shortcut? {
    defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Shortcut.self, from: $0) }
  }

  private func save(_ shortcut: Shortcut, forKey key: String) {
    defaults.set(try? JSONEncoder().encode(shortcut), forKey: key)
  }
}
