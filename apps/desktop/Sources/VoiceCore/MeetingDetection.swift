import Foundation

/// An app that holds the microphone, as Core Audio sees it.
public struct MicrophoneUser: Hashable, Sendable {
  public let bundleId: String
  /// The app's name, to say which app is in a call.
  public let name: String

  public init(bundleId: String, name: String) {
    self.bundleId = bundleId
    self.name = name
  }
}

/// The apps that hold the microphone for a call: meeting apps, and the browsers calls run in.
public enum MeetingApps {
  /// By the start of their bundle identifier, which their helper processes share.
  static let known: [(prefix: String, name: String)] = [
    ("us.zoom.xos", "Zoom"),
    ("com.microsoft.teams", "Microsoft Teams"),
    ("com.google.Chrome", "Chrome"),
    ("com.apple.Safari", "Safari"),
    ("company.thebrowser.Browser", "Arc"),
    ("org.mozilla.firefox", "Firefox"),
    ("com.brave.Browser", "Brave"),
    ("com.microsoft.edgemac", "Edge"),
    ("com.vivaldi.Vivaldi", "Vivaldi"),
    ("com.operasoftware.Opera", "Opera"),
    ("com.tinyspeck.slackmacgap", "Slack"),
    ("com.hnc.Discord", "Discord"),
    ("com.apple.FaceTime", "FaceTime"),
    ("com.cisco.webexmeetingsapp", "Webex"),
    ("Cisco-Systems.Spark", "Webex"),
    ("com.skype.skype", "Skype"),
    ("net.whatsapp.WhatsApp", "WhatsApp"),
    ("ru.keepcoder.Telegram", "Telegram"),
    ("org.telegram.desktop", "Telegram"),
  ]

  /// The name of the app a bundle identifier belongs to, when it is one that holds calls.
  public static func name(of bundleId: String) -> String? {
    known.first { bundleId.hasPrefix($0.prefix) }?.name
  }
}

/// Notices a meeting in progress: an app that holds calls has held the microphone for a
/// moment, and no meeting is being recorded.
///
/// The prompt stands until the user acts on it or the app lets the microphone go. An app
/// whose prompt was dismissed, or whose call was recorded, is not asked about again until
/// it lets the microphone go and takes it again.
public struct MeetingDetection: Equatable, Sendable {
  /// How long an app must hold the microphone before it counts as a call.
  public static let holding: TimeInterval = 3

  /// The app the prompt is about, if a prompt is due.
  public private(set) var prompt: MicrophoneUser?
  /// When each app that holds the microphone took it.
  private var since: [MicrophoneUser: Date] = [:]
  /// The apps not to ask about while they hold the microphone.
  private var settled: Set<MicrophoneUser> = []

  public init() {}

  /// The apps holding the microphone now, apart from this one, at a time. Returns whether
  /// the prompt changed.
  @discardableResult
  public mutating func observe(_ users: Set<MicrophoneUser>, isRecording: Bool, at now: Date)
    -> Bool
  {
    let callers = users.filter { MeetingApps.name(of: $0.bundleId) != nil }
    for user in callers where since[user] == nil { since[user] = now }
    since = since.filter { callers.contains($0.key) }
    settled = settled.intersection(callers)

    let before = prompt
    if isRecording {
      prompt = nil
    } else {
      // The app that has held it the longest, among those that held it long enough.
      prompt =
        since
        .filter { now.timeIntervalSince($0.value) >= Self.holding && !settled.contains($0.key) }
        .min { ($0.value, $0.key.bundleId) < ($1.value, $1.key.bundleId) }?.key
    }
    return prompt != before
  }

  /// The user does not want this call recorded.
  public mutating func dismiss() {
    if let prompt { settled.insert(prompt) }
    prompt = nil
  }

  /// A meeting is being recorded: the apps in a call now are taken as that meeting.
  public mutating func recording() {
    settled.formUnion(since.keys)
    prompt = nil
  }
}
