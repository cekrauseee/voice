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
  var pillPosition: PillPosition {
    didSet { defaults.set(pillPosition.rawValue, forKey: "pillPosition") }
  }
  var pushToTalk: Shortcut {
    didSet { save(pushToTalk, forKey: "pushToTalk") }
  }
  var toggle: Shortcut {
    didSet { save(toggle, forKey: "toggle") }
  }
  /// What the models are told about the user: how they want their words written, what their
  /// recordings are like, and the languages they speak.
  var profile: Profile {
    didSet { defaults.set(try? JSONEncoder().encode(profile), forKey: "profile") }
  }

  /// Whether what the user says is written in another language.
  var translates: Bool {
    didSet { defaults.set(translates, forKey: "translates") }
  }

  /// The language to translate to, as the user typed it. Kept while translation is off.
  var translationLanguage: String {
    didSet { defaults.set(translationLanguage, forKey: "translationLanguage") }
  }

  /// The language new dictations are written in. Empty for the one spoken.
  var translateTo: String {
    Translation.target(isOn: translates, language: translationLanguage)
  }

  /// The user's dictionary: names and terms they use, newest first.
  var vocabulary: [String] {
    didSet { defaults.set(vocabulary, forKey: "vocabulary") }
  }

  /// Whether the text before the cursor in the focused field is sent with each dictation, so
  /// the dictation fits it. On by default.
  var usesFieldText: Bool {
    didSet { defaults.set(usesFieldText, forKey: "usesFieldText") }
  }

  /// Whether dictations are transcribed while the user talks, for the pill to show the words.
  /// Off by default: the recording is transcribed once it ends, for less.
  var transcribesLive: Bool {
    didSet { defaults.set(transcribesLive, forKey: "transcribesLive") }
  }

  var enterBehavior: EnterBehavior {
    didSet { defaults.set(enterBehavior.rawValue, forKey: "enterBehavior") }
  }

  var keepOnClipboard: Bool {
    didSet { defaults.set(keepOnClipboard, forKey: "keepOnClipboard") }
  }

  /// What happens to the media playing on the Mac while a dictation records.
  var mediaBehavior: MediaBehavior {
    didSet { defaults.set(mediaBehavior.rawValue, forKey: "mediaBehavior") }
  }

  /// How much of its volume the media keeps while a dictation records, when it is lowered.
  var loweredVolume: LoweredVolume {
    didSet { defaults.set(loweredVolume.rawValue, forKey: "loweredVolume") }
  }

  /// The microphone to dictate with. Without one, the system's records.
  var microphone: Microphone? {
    didSet {
      defaults.set(microphone.flatMap { try? JSONEncoder().encode($0) }, forKey: "microphone")
    }
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
    pillPosition = defaults.string(forKey: "pillPosition").flatMap(PillPosition.init) ?? .bottom
    pushToTalk = Self.shortcut(defaults, forKey: "pushToTalk") ?? .defaultPushToTalk
    toggle = Self.shortcut(defaults, forKey: "toggle") ?? .defaultToggle
    // The instructions set before profiles are left where they were, and read into the
    // profile until it is changed.
    profile = Profile.stored(
      defaults.data(forKey: "profile"), instructions: defaults.string(forKey: "instructions"))
    translates = defaults.bool(forKey: "translates")
    translationLanguage = defaults.string(forKey: "translationLanguage") ?? ""
    vocabulary = defaults.stringArray(forKey: "vocabulary") ?? []
    usesFieldText = defaults.object(forKey: "usesFieldText") as? Bool ?? true
    transcribesLive = defaults.bool(forKey: "transcribesLive")
    keepOnClipboard = defaults.bool(forKey: "keepOnClipboard")
    enterBehavior = defaults.string(forKey: "enterBehavior").flatMap(EnterBehavior.init) ?? .never
    mediaBehavior = defaults.string(forKey: "mediaBehavior").flatMap(MediaBehavior.init) ?? .pause
    loweredVolume = LoweredVolume(rawValue: defaults.integer(forKey: "loweredVolume")) ?? .thirty
    microphone = defaults.data(forKey: "microphone").flatMap {
      try? JSONDecoder().decode(Microphone.self, from: $0)
    }
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
