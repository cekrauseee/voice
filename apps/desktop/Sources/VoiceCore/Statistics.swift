import Foundation

/// What was dictated in a stretch of time, and what it took.
public struct Tally: Codable, Equatable, Sendable {
  /// The dictations that typed words.
  public var dictations = 0
  public var words = 0
  /// How long the speaker talked for those words, in seconds.
  public var seconds = 0.0
  /// Tokens the refinements read.
  public var inputTokens = 0
  /// Tokens the refinements wrote.
  public var outputTokens = 0
  /// What it cost, in US dollars, as the server estimated it.
  public var cost = 0.0

  public init() {}

  public var tokens: Int {
    inputTokens + outputTokens
  }

  /// How fast the speaker dictates, if anything was dictated.
  public var wordsPerMinute: Int? {
    seconds > 0 ? Int((Double(words) / seconds * 60).rounded()) : nil
  }

  public static func += (tally: inout Tally, other: Tally) {
    tally.dictations += other.dictations
    tally.words += other.words
    tally.seconds += other.seconds
    tally.inputTokens += other.inputTokens
    tally.outputTokens += other.outputTokens
    tally.cost += other.cost
  }
}

/// How much was dictated, day by day, and what it cost. Today is also kept hour by hour.
///
/// It is counted as dictations happen and kept apart from the history, so deleting a
/// transcription does not change it.
public struct Statistics: Codable, Equatable, Sendable {
  /// The stretch of time the figures are shown for.
  public enum Period: String, CaseIterable, Identifiable, Sendable {
    case today
    case week
    case month
    case all

    public var id: Self { self }

    public var title: String {
      switch self {
      case .today: "Today"
      case .week: "7 days"
      case .month: "30 days"
      case .all: "All time"
      }
    }

    /// How many days it goes back, today included. All time has no end.
    var days: Int? {
      switch self {
      case .today: 1
      case .week: 7
      case .month: 30
      case .all: nil
      }
    }
  }

  /// A bar of the chart: an hour of today, a day, or a month when there are too many days
  /// to show.
  public struct Bar: Equatable, Identifiable, Sendable {
    public enum Unit: Sendable {
      case hour
      case day
      case month
    }

    /// When the hour, the day, or the month starts.
    public let start: Date
    public let unit: Unit
    public let tally: Tally

    public var id: Date { start }
  }

  /// More days than this are shown as months.
  static let mostDays = 90

  /// The figures of each day that has any, by its date, such as `2026-11-12`.
  public private(set) var days: [String: Tally]
  /// The figures of each hour of the last day dictated on, by the day and the hour, such
  /// as `2026-11-12T09`.
  public private(set) var hours: [String: Tally]

  public init(days: [String: Tally] = [:], hours: [String: Tally] = [:]) {
    self.days = days
    self.hours = hours
  }

  public init(from decoder: any Decoder) throws {
    let values = try decoder.container(keyedBy: CodingKeys.self)
    days = try values.decode([String: Tally].self, forKey: .days)
    // Statistics written before the hours were kept have none.
    hours = try values.decodeIfPresent([String: Tally].self, forKey: .hours) ?? [:]
  }

  /// Reads the statistics as `data` wrote them.
  public init(data: Data) throws {
    self = try JSONDecoder().decode(Statistics.self, from: data)
  }

  /// The statistics as JSON, to be kept in a file.
  public var data: Data {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return (try? encoder.encode(self)) ?? Data()
  }

  /// Counts a dictation that ended with its text. What it cost counts even when no word
  /// came out of it: it was paid for.
  public mutating func record(
    text: String, seconds: TimeInterval, usage: Usage, at date: Date, in calendar: Calendar
  ) {
    var dictation = Tally()
    dictation.words = text.wordCount
    if dictation.words > 0 {
      dictation.dictations = 1
      dictation.seconds = seconds
    }
    dictation.inputTokens = usage.inputTokens
    dictation.outputTokens = usage.outputTokens
    dictation.cost = usage.cost

    let day = Self.key(date, in: calendar)
    days[day, default: Tally()] += dictation
    // Only the hours of this day are kept.
    hours = hours.filter { $0.key.hasPrefix(day) }
    hours[Self.key(date, hourIn: calendar), default: Tally()] += dictation
  }

  /// The figures of a period that ends today.
  public func total(_ period: Period, now: Date, in calendar: Calendar) -> Tally {
    var total = Tally()
    guard let count = period.days else {
      for tally in days.values { total += tally }
      return total
    }
    for day in Self.days(count, endingAt: now, in: calendar) {
      if let tally = days[Self.key(day, in: calendar)] { total += tally }
    }
    return total
  }

  /// The bars of a period that ends today, oldest first. Today has a bar for each of its
  /// hours. All time starts at the first day
  /// with figures, shows a week at least, and goes by month once the days are too many.
  public func bars(_ period: Period, now: Date, in calendar: Calendar) -> [Bar] {
    let today = calendar.startOfDay(for: now)
    if period == .today {
      return (0..<24).compactMap { calendar.date(byAdding: .hour, value: $0, to: today) }.map {
        Bar(start: $0, unit: .hour, tally: hours[Self.key($0, hourIn: calendar)] ?? Tally())
      }
    }
    var count = period.days ?? 7
    if period == .all, let first = days.keys.min().flatMap({ Self.date($0, in: calendar) }) {
      let span = (calendar.dateComponents([.day], from: first, to: today).day ?? 0) + 1
      if span > Self.mostDays { return months(from: first, to: today, in: calendar) }
      count = max(count, span)
    }
    return Self.days(count, endingAt: now, in: calendar).map { day in
      Bar(start: day, unit: .day, tally: days[Self.key(day, in: calendar)] ?? Tally())
    }
  }

  private func months(from first: Date, to today: Date, in calendar: Calendar) -> [Bar] {
    var totals: [Date: Tally] = [:]
    for (key, tally) in days {
      guard let day = Self.date(key, in: calendar),
        let month = calendar.dateInterval(of: .month, for: day)?.start
      else { continue }
      totals[month, default: Tally()] += tally
    }
    var bars: [Bar] = []
    var month = calendar.dateInterval(of: .month, for: first)?.start ?? first
    while month <= today {
      bars.append(Bar(start: month, unit: .month, tally: totals[month] ?? Tally()))
      guard let next = calendar.date(byAdding: .month, value: 1, to: month) else { break }
      month = next
    }
    return bars
  }

  /// The starts of the last days, oldest first, the last one being today.
  private static func days(_ count: Int, endingAt now: Date, in calendar: Calendar) -> [Date] {
    let today = calendar.startOfDay(for: now)
    return (0..<count).reversed().compactMap {
      calendar.date(byAdding: .day, value: -$0, to: today)
    }
  }

  /// The date of a day as the statistics name it, such as `2026-11-12`.
  static func key(_ date: Date, in calendar: Calendar) -> String {
    let day = calendar.dateComponents([.year, .month, .day], from: date)
    let (month, number) = (day.month ?? 0, day.day ?? 0)
    return "\(day.year ?? 0)-\(month < 10 ? "0" : "")\(month)-\(number < 10 ? "0" : "")\(number)"
  }

  /// The hour of a day as the statistics name it, such as `2026-11-12T09`.
  static func key(_ date: Date, hourIn calendar: Calendar) -> String {
    let hour = calendar.component(.hour, from: date)
    return "\(key(date, in: calendar))T\(hour < 10 ? "0" : "")\(hour)"
  }

  /// The start of the day a name stands for.
  static func date(_ key: String, in calendar: Calendar) -> Date? {
    let parts = key.split(separator: "-").compactMap { Int($0) }
    guard parts.count == 3 else { return nil }
    return calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2]))
  }
}

/// How the figures are written, in English, like the rest of the app.
public enum Figure {
  /// A count, in full up to ten thousand and rounded after: `1,284`, `18.4K`, `2.1M`.
  public static func count(_ value: Int) -> String {
    switch value {
    case ..<10_000:
      let digits = String(value)
      var grouped = ""
      for (index, digit) in digits.enumerated() {
        if index > 0, (digits.count - index) % 3 == 0 { grouped.append(",") }
        grouped.append(digit)
      }
      return grouped
    case ..<999_950:
      return rounded(Double(value) / 1000) + "K"
    default:
      return rounded(Double(value) / 1_000_000) + "M"
    }
  }

  /// A cost in US dollars, in cents, or finer while it is under a cent: `$1.20`, `$0.0042`.
  public static func cost(_ dollars: Double) -> String {
    let places = dollars > 0 && dollars < 0.01 ? 4 : 2
    let scale = places == 4 ? 10_000.0 : 100.0
    let units = Int((dollars * scale).rounded())
    let fraction = String(units % Int(scale))
    let padding = String(repeating: "0", count: places - fraction.count)
    return "$\(count(units / Int(scale))).\(padding)\(fraction)"
  }

  /// A length of time, in its two largest units at most: `42 s`, `9 min`, `1 h 12 min`.
  public static func time(_ seconds: TimeInterval) -> String {
    let total = Int(seconds.rounded())
    if total < 60 { return "\(total) s" }
    let minutes = Int((seconds / 60).rounded())
    if minutes < 60 { return "\(minutes) min" }
    return minutes % 60 == 0 ? "\(minutes / 60) h" : "\(minutes / 60) h \(minutes % 60) min"
  }

  /// A number with one decimal, which is left out when it is zero.
  private static func rounded(_ value: Double) -> String {
    let tenths = Int((value * 10).rounded())
    return tenths % 10 == 0 ? "\(tenths / 10)" : "\(tenths / 10).\(tenths % 10)"
  }
}

extension String {
  /// How many words the text has.
  var wordCount: Int {
    split(whereSeparator: \.isWhitespace).count
  }
}
