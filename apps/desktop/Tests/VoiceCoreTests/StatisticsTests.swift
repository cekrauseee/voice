import Foundation
import Testing

@testable import VoiceCore

@Suite struct StatisticsTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  /// Noon on a day of 2026, in UTC.
  private func noon(month: Int = 11, day: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: month, day: day, hour: 12))!
  }

  private let usage = Usage(audioSeconds: 30, inputTokens: 300, outputTokens: 60, cost: 0.01)

  @Test func countsTheDictationsOfADay() {
    var statistics = Statistics()
    statistics.record(
      text: "one two three", seconds: 2, usage: usage, at: noon(day: 12), in: calendar)
    statistics.record(
      text: "four  five\nsix seven", seconds: 4, usage: usage, at: noon(day: 12) + 3600,
      in: calendar)

    var expected = Tally()
    expected.dictations = 2
    expected.words = 7
    expected.seconds = 6
    expected.inputTokens = 600
    expected.outputTokens = 120
    expected.cost = 0.02
    #expect(statistics.days == ["2026-11-12": expected])
    #expect(expected.tokens == 720)
    #expect(expected.wordsPerMinute == 70)
  }

  @Test func countsTheCostOfADictationWithoutWords() {
    var statistics = Statistics()
    statistics.record(text: " ", seconds: 5, usage: usage, at: noon(day: 12), in: calendar)
    let day = statistics.days["2026-11-12"]
    #expect(day?.dictations == 0)
    #expect(day?.seconds == 0)
    #expect(day?.cost == 0.01)
    #expect(day?.wordsPerMinute == nil)
  }

  @Test func totalsAPeriodThatEndsToday() {
    var statistics = Statistics()
    for day in [1, 5, 6, 12] {
      statistics.record(text: "word", seconds: 1, usage: usage, at: noon(day: day), in: calendar)
    }
    statistics.record(
      text: "word", seconds: 1, usage: usage, at: noon(month: 10, day: 13), in: calendar)
    let now = noon(day: 12)
    // Seven days back from the 12th start on the 6th.
    #expect(statistics.total(.week, now: now, in: calendar).words == 2)
    // Thirty days back start on October 14th.
    #expect(statistics.total(.month, now: now, in: calendar).words == 4)
    #expect(statistics.total(.all, now: now, in: calendar).words == 5)
  }

  @Test func hasABarForEachDayOfThePeriod() {
    var statistics = Statistics()
    statistics.record(
      text: "one two", seconds: 1, usage: usage, at: noon(day: 10), in: calendar)
    let week = statistics.bars(.week, now: noon(day: 12), in: calendar)
    #expect(week.count == 7)
    #expect(week.first?.start == calendar.startOfDay(for: noon(day: 6)))
    #expect(week.last?.start == calendar.startOfDay(for: noon(day: 12)))
    #expect(week.map(\.tally.words) == [0, 0, 0, 0, 2, 0, 0])
    #expect(statistics.bars(.month, now: noon(day: 12), in: calendar).count == 30)
  }

  @Test func allTimeStartsAtTheFirstDayAndShowsAWeekAtLeast() {
    var statistics = Statistics()
    #expect(statistics.bars(.all, now: noon(day: 12), in: calendar).count == 7)

    statistics.record(text: "word", seconds: 1, usage: usage, at: noon(day: 11), in: calendar)
    #expect(statistics.bars(.all, now: noon(day: 12), in: calendar).count == 7)

    statistics.record(
      text: "word", seconds: 1, usage: usage, at: noon(month: 10, day: 24), in: calendar)
    let bars = statistics.bars(.all, now: noon(day: 12), in: calendar)
    #expect(bars.count == 20)
    #expect(bars.first?.tally.words == 1)
    #expect(bars.allSatisfy { !$0.isMonth })
  }

  @Test func allTimeGoesByMonthOnceTheDaysAreTooMany() {
    var statistics = Statistics()
    statistics.record(
      text: "one", seconds: 1, usage: usage, at: noon(month: 6, day: 20), in: calendar)
    statistics.record(
      text: "two three", seconds: 1, usage: usage, at: noon(month: 6, day: 28), in: calendar)
    statistics.record(text: "four", seconds: 1, usage: usage, at: noon(day: 3), in: calendar)
    let bars = statistics.bars(.all, now: noon(day: 12), in: calendar)
    #expect(bars.allSatisfy { $0.isMonth })
    // June to November.
    #expect(bars.map(\.tally.words) == [3, 0, 0, 0, 0, 1])
    #expect(
      bars.first?.start == calendar.date(from: DateComponents(year: 2026, month: 6, day: 1)))
  }

  @Test func isReadAsItWasWritten() throws {
    var statistics = Statistics()
    statistics.record(
      text: "one two", seconds: 1.5, usage: usage, at: noon(day: 12), in: calendar)
    let read = try Statistics(data: statistics.data)
    #expect(read == statistics)
    #expect(throws: (any Error).self) { try Statistics(data: Data("[]".utf8)) }
  }

  @Test func writesCounts() {
    #expect(Figure.count(0) == "0")
    #expect(Figure.count(999) == "999")
    #expect(Figure.count(1284) == "1,284")
    #expect(Figure.count(9999) == "9,999")
    #expect(Figure.count(10_000) == "10K")
    #expect(Figure.count(18_449) == "18.4K")
    #expect(Figure.count(999_949) == "999.9K")
    #expect(Figure.count(999_950) == "1M")
    #expect(Figure.count(2_140_000) == "2.1M")
  }

  @Test func writesCosts() {
    #expect(Figure.cost(0) == "$0.00")
    #expect(Figure.cost(0.0042) == "$0.0042")
    #expect(Figure.cost(0.00996) == "$0.0100")
    #expect(Figure.cost(0.0149) == "$0.01")
    #expect(Figure.cost(1.2) == "$1.20")
    #expect(Figure.cost(1234.567) == "$1,234.57")
  }

  @Test func writesTimes() {
    #expect(Figure.time(0) == "0 s")
    #expect(Figure.time(42.4) == "42 s")
    #expect(Figure.time(59.6) == "1 min")
    #expect(Figure.time(9 * 60 + 10) == "9 min")
    #expect(Figure.time(3600) == "1 h")
    #expect(Figure.time(72 * 60) == "1 h 12 min")
  }
}
