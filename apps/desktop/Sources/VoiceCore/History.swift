import Foundation

/// A dictation, kept to be read again, and to be transcribed again when it failed.
public struct Transcription: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  /// When it was dictated.
  public let date: Date
  /// What was typed. Empty when the dictation failed before any word came back.
  public var text: String
  /// How long the recording was, in seconds.
  public let duration: TimeInterval
  /// Whether the dictation failed. Its recording can then be transcribed again.
  public var failed: Bool

  public init(
    id: UUID = UUID(), date: Date, text: String, duration: TimeInterval, failed: Bool = false
  ) {
    self.id = id
    self.date = date
    self.text = text
    self.duration = duration
    self.failed = failed
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    id = try values.decode(UUID.self, forKey: .id)
    date = try values.decode(Date.self, forKey: .date)
    text = try values.decode(String.self, forKey: .text)
    duration = try values.decode(TimeInterval.self, forKey: .duration)
    // A history written before failures were kept has none.
    failed = try values.decodeIfPresent(Bool.self, forKey: .failed) ?? false
  }
}

/// How long a transcription is kept before it is deleted by itself.
public enum Retention: String, CaseIterable, Identifiable, Sendable {
  case day
  case week
  case month
  case never

  public var id: Self { self }

  public var title: String {
    switch self {
    case .day: "1 day"
    case .week: "7 days"
    case .month: "30 days"
    case .never: "Never"
    }
  }

  /// The moment before which a transcription is too old to keep, if any is.
  public func cutoff(from now: Date) -> Date? {
    let day = 24.0 * 60 * 60
    switch self {
    case .day: return now - day
    case .week: return now - 7 * day
    case .month: return now - 30 * day
    case .never: return nil
    }
  }
}

/// The past transcriptions, newest first.
public struct History: Codable, Equatable, Sendable {
  /// The transcriptions of one day.
  public struct Day: Equatable, Identifiable, Sendable {
    /// The start of the day.
    public let date: Date
    public let transcriptions: [Transcription]

    public var id: Date { date }
  }

  public private(set) var transcriptions: [Transcription]

  public init(_ transcriptions: [Transcription] = []) {
    self.transcriptions = transcriptions.sorted { $0.date > $1.date }
  }

  /// Reads the history as `data` wrote it.
  public init(data: Data) throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self.init(try decoder.decode(History.self, from: data).transcriptions)
  }

  /// The history as JSON, to be kept in a file.
  public var data: Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? encoder.encode(self)) ?? Data()
  }

  public var isEmpty: Bool {
    transcriptions.isEmpty
  }

  /// Adds a transcription. One without words is only kept when it failed, to be tried
  /// again. Returns whether it was kept.
  @discardableResult
  public mutating func add(_ transcription: Transcription) -> Bool {
    guard transcription.failed || !transcription.text.allSatisfy(\.isWhitespace) else {
      return false
    }
    let index = transcriptions.firstIndex { $0.date <= transcription.date } ?? transcriptions.count
    transcriptions.insert(transcription, at: index)
    return true
  }

  public mutating func remove(_ id: Transcription.ID) {
    transcriptions.removeAll { $0.id == id }
  }

  /// Gives a transcription that failed the text it got on another try.
  public mutating func resolve(_ id: Transcription.ID, text: String) {
    guard let index = transcriptions.firstIndex(where: { $0.id == id }) else { return }
    transcriptions[index].text = text
    transcriptions[index].failed = false
  }

  /// Removes the transcriptions dictated before a moment. Returns the ones removed.
  @discardableResult
  public mutating func prune(before cutoff: Date) -> [Transcription.ID] {
    let old = transcriptions.filter { $0.date < cutoff }.map(\.id)
    transcriptions.removeAll { $0.date < cutoff }
    return old
  }

  /// The transcriptions day by day, newest first.
  public func days(in calendar: Calendar) -> [Day] {
    var days: [(date: Date, transcriptions: [Transcription])] = []
    for transcription in transcriptions {
      let date = calendar.startOfDay(for: transcription.date)
      if days.last?.date == date {
        days[days.count - 1].transcriptions.append(transcription)
      } else {
        days.append((date, [transcription]))
      }
    }
    return days.map { Day(date: $0.date, transcriptions: $0.transcriptions) }
  }
}

extension Transcription {
  /// How many words the text has.
  public var words: Int {
    text.split(whereSeparator: \.isWhitespace).count
  }

  /// The duration as minutes and seconds, such as `1:05`.
  public var clock: String {
    let seconds = Int(duration.rounded())
    return "\(seconds / 60):" + (seconds % 60 < 10 ? "0" : "") + "\(seconds % 60)"
  }
}
