/// Why a dictation could not start or finish.
public enum DictationError: Error, Equatable {
  case microphoneDenied
  case microphoneUnavailable
  case serverUnreachable
  case transcriptionFailed

  public var message: String {
    switch self {
    case .microphoneDenied: "Microphone access needed"
    case .microphoneUnavailable: "No microphone found"
    case .serverUnreachable: "Can't reach the server"
    case .transcriptionFailed: "Transcription failed"
    }
  }
}

/// What the pill shows.
public enum PillState: Equatable, Sendable {
  case hidden
  /// Recording, while the microphone starts: it delivers no sound yet, and what is said
  /// meanwhile is not heard.
  case starting
  /// Recording. The server may still be getting ready: the audio waits for it.
  case listening
  /// Recording ended, while the text is on its way.
  case finishing
  case failed(DictationError)

  /// Whether the microphone records, whether it delivers sound yet or not.
  public var isRecording: Bool {
    self == .starting || self == .listening
  }
}

/// How a recording was started, which decides how it ends.
public enum RecordingMode: Equatable, Sendable {
  /// Held: ends when the key is released.
  case push
  /// Toggled: ends when the shortcut is pressed again.
  case toggle
}

public enum Theme: String, CaseIterable, Identifiable, Sendable {
  case auto, light, dark

  public var id: Self { self }

  public var title: String {
    switch self {
    case .auto: "Auto"
    case .light: "Light"
    case .dark: "Dark"
    }
  }
}

public enum PillStyle: String, CaseIterable, Identifiable, Sendable {
  /// A small pill with a waveform.
  case minimal
  /// A larger pill that also shows the text as it is recognized.
  case detailed

  public var id: Self { self }

  public var title: String {
    switch self {
    case .minimal: "Minimal"
    case .detailed: "Detailed"
    }
  }
}

/// Where the pill shows, at the center of the screen.
public enum PillPosition: String, CaseIterable, Identifiable, Sendable {
  /// Above the Dock, at the bottom of the screen.
  case bottom
  /// Under the menu bar, or out of the notch on a screen that has one.
  case top

  public var id: Self { self }

  public var title: String {
    switch self {
    case .bottom: "Bottom"
    case .top: "Top"
    }
  }
}
