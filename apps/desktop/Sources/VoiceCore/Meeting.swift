import Foundation

/// A side of a meeting: whose audio a channel carries.
public enum Channel: String, Codable, CaseIterable, Sendable {
  /// The speaker, through the microphone.
  case me
  /// The other participants, through what the meeting app plays.
  case others

  public var title: String {
    switch self {
    case .me: "Me"
    case .others: "Others"
    }
  }

  /// The byte that names the channel at the start of an audio frame.
  public var frameByte: UInt8 {
    switch self {
    case .me: 0
    case .others: 1
    }
  }
}

/// A stretch of speech on one channel of a meeting, with its text.
public struct MeetingSegment: Codable, Equatable, Identifiable, Sendable {
  public let id: Int
  public let channel: Channel
  /// Seconds since the meeting started.
  public let start: TimeInterval
  public let end: TimeInterval
  public var text: String

  public init(id: Int, channel: Channel, start: TimeInterval, end: TimeInterval, text: String) {
    self.id = id
    self.channel = channel
    self.start = start
    self.end = end
    self.text = text
  }
}

/// What one side said before the other spoke: consecutive segments of the same channel.
public struct Paragraph: Equatable, Identifiable, Sendable {
  /// The id of its first segment.
  public let id: Int
  public let channel: Channel
  /// Seconds since the meeting started.
  public let start: TimeInterval
  public let text: String
}

/// A meeting: when it started, how long it ran, and what was said, in segments.
public struct Meeting: Codable, Equatable, Identifiable, Sendable {
  public let id: UUID
  /// When it started.
  public let date: Date
  /// How long it ran, in seconds. It grows while the meeting is recorded.
  public var duration: TimeInterval
  /// The segments in the order they were spoken.
  public private(set) var segments: [MeetingSegment]
  /// What it used on the server, and what that cost.
  public var usage: Usage
  /// Whether it is still being recorded.
  public var isLive: Bool

  public init(
    id: UUID = UUID(), date: Date, duration: TimeInterval = 0, segments: [MeetingSegment] = [],
    usage: Usage = Usage(), isLive: Bool = false
  ) {
    self.id = id
    self.date = date
    self.duration = duration
    self.segments = []
    self.usage = usage
    self.isLive = isLive
    for segment in segments { add(segment) }
  }

  /// Reads a meeting as `data` wrote it.
  public init(data: Data) throws {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .iso8601
    self = try decoder.decode(Meeting.self, from: data)
  }

  /// The meeting as JSON, to be kept in a file.
  public var data: Data {
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? encoder.encode(self)) ?? Data()
  }

  /// Adds a segment where its time puts it. One that covers the time of a segment already
  /// there, on the same channel, replaces it: the server transcribed that stretch again.
  public mutating func add(_ segment: MeetingSegment) {
    segments.removeAll {
      $0.channel == segment.channel && $0.start < segment.end && segment.start < $0.end
    }
    let index =
      segments.firstIndex { ($0.start, $0.id) > (segment.start, segment.id) } ?? segments.count
    segments.insert(segment, at: index)
  }

  /// The id for the next segment: after the highest so far.
  public var nextId: Int {
    (segments.map(\.id).max() ?? 0) + 1
  }

  /// Where a channel's segments reach, in seconds.
  public func covered(_ channel: Channel) -> TimeInterval {
    segments.filter { $0.channel == channel }.map(\.end).max() ?? 0
  }

  /// The conversation, a paragraph for each turn of it.
  public var paragraphs: [Paragraph] {
    var paragraphs: [Paragraph] = []
    for segment in segments {
      if let last = paragraphs.last, last.channel == segment.channel {
        paragraphs[paragraphs.count - 1] = Paragraph(
          id: last.id, channel: last.channel, start: last.start,
          text: last.text + " " + segment.text)
      } else {
        paragraphs.append(
          Paragraph(
            id: segment.id, channel: segment.channel, start: segment.start, text: segment.text))
      }
    }
    return paragraphs
  }

  /// The transcript as text to copy: each paragraph named by its side.
  public var text: String {
    paragraphs.map { "\($0.channel.title): \($0.text)" }.joined(separator: "\n\n")
  }

  public var isEmpty: Bool {
    segments.isEmpty
  }

  public var words: Int {
    segments.reduce(0) { $0 + $1.text.wordCount }
  }

  /// The duration as minutes and seconds, such as `42:05`, or with hours past an hour.
  public var clock: String {
    duration.clock
  }
}

extension TimeInterval {
  /// Seconds as `m:ss`, or `h:mm:ss` past an hour.
  public var clock: String {
    let seconds = Int(rounded())
    let two = { (value: Int) in (value < 10 ? "0" : "") + "\(value)" }
    if seconds >= 3600 {
      return "\(seconds / 3600):\(two(seconds / 60 % 60)):\(two(seconds % 60))"
    }
    return "\(seconds / 60):\(two(seconds % 60))"
  }
}

/// The meetings of one day.
public struct MeetingDay: Equatable, Identifiable, Sendable {
  /// The start of the day.
  public let date: Date
  public let meetings: [Meeting]

  public var id: Date { date }
}

extension [Meeting] {
  /// The meetings day by day, newest first. They are expected newest first already.
  public func days(in calendar: Calendar) -> [MeetingDay] {
    var days: [(date: Date, meetings: [Meeting])] = []
    for meeting in self {
      let date = calendar.startOfDay(for: meeting.date)
      if days.last?.date == date {
        days[days.count - 1].meetings.append(meeting)
      } else {
        days.append((date, [meeting]))
      }
    }
    return days.map { MeetingDay(date: $0.date, meetings: $0.meetings) }
  }
}

/// A meeting while it is recorded: what the server has sent, and the text heard on each
/// channel that is not in a segment yet.
public struct LiveMeeting: Equatable, Sendable {
  public private(set) var meeting: Meeting
  /// The text heard on each channel that is not in a segment yet.
  public private(set) var drafts: [Channel: String] = [:]
  /// What the connections before the current one used.
  private var earlier = Usage()
  /// What the current connection used.
  private var current = Usage()

  public init(_ meeting: Meeting) {
    self.meeting = meeting
    self.meeting.isLive = true
  }

  public mutating func apply(_ message: MeetingServerMessage) {
    switch message {
    case .ready, .error:
      break
    case .draft(let channel, let text):
      drafts[channel] = text.isEmpty ? nil : text
    case .segment(let segment):
      meeting.add(segment)
    case .usage(let usage), .done(let usage):
      current = usage
      meeting.usage = earlier + current
    }
  }

  /// The connection was lost and another begins. What it uses adds to what the ones
  /// before used, and the drafts are void: the server starts them over.
  public mutating func reconnecting() {
    earlier = earlier + current
    current = Usage()
    drafts = [:]
  }

  /// How long the meeting has run.
  public mutating func update(duration: TimeInterval) {
    meeting.duration = duration
  }

  /// The meeting is over.
  public mutating func end(duration: TimeInterval) {
    meeting.duration = duration
    meeting.isLive = false
    drafts = [:]
  }
}

extension Usage {
  public static func + (lhs: Usage, rhs: Usage) -> Usage {
    Usage(
      audioSeconds: lhs.audioSeconds + rhs.audioSeconds,
      inputTokens: lhs.inputTokens + rhs.inputTokens,
      outputTokens: lhs.outputTokens + rhs.outputTokens, cost: lhs.cost + rhs.cost)
  }
}

/// Why a meeting could not start as it should.
public enum MeetingError: Error, Equatable, Sendable {
  case microphoneDenied
  case microphoneUnavailable

  public var message: String {
    switch self {
    case .microphoneDenied: "Microphone access needed"
    case .microphoneUnavailable: "No microphone found"
    }
  }
}
