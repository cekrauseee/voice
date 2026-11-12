import Foundation

/// A dictation that was typed, kept to be read again.
public struct Transcription: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  /// When it was typed.
  public let date: Date
  public let text: String
  /// What was heard, before it was refined into the text. Absent when it was not kept, or
  /// when the words were typed as heard.
  public let heard: String?
  /// How long the recording was, in seconds.
  public let duration: TimeInterval

  public init(
    id: UUID = UUID(), date: Date, text: String, heard: String? = nil, duration: TimeInterval
  ) {
    self.id = id
    self.date = date
    self.text = text
    self.heard = heard
    self.duration = duration
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

  /// Adds a transcription. One without words is not kept.
  public mutating func add(_ transcription: Transcription) {
    guard !transcription.text.allSatisfy(\.isWhitespace) else { return }
    let index = transcriptions.firstIndex { $0.date <= transcription.date } ?? transcriptions.count
    transcriptions.insert(transcription, at: index)
  }

  public mutating func remove(_ id: Transcription.ID) {
    transcriptions.removeAll { $0.id == id }
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
