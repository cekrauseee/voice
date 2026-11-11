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
