import Foundation
import Testing

@testable import VoiceCore

@Suite struct HistoryTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  /// Noon on a day of November 2026, in UTC.
  private func noon(day: Int) -> Date {
    calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: 12))!
  }

  private func transcription(_ text: String, day: Int, hours: Double = 0) -> Transcription {
    Transcription(date: noon(day: day) + hours * 3600, text: text, duration: 3)
  }

  @Test func keepsTheNewestFirst() {
    var history = History()
    history.add(transcription("second", day: 11))
    history.add(transcription("third", day: 12))
    history.add(transcription("first", day: 10))
    #expect(history.transcriptions.map(\.text) == ["third", "second", "first"])
  }

  @Test func doesNotKeepATranscriptionWithoutWords() {
    var history = History()
    history.add(transcription(" \n", day: 10))
    #expect(history.isEmpty)
  }

  @Test func removesATranscription() {
    let kept = transcription("kept", day: 10)
    let removed = transcription("removed", day: 11)
    var history = History([kept, removed])
    history.remove(removed.id)
    #expect(history.transcriptions == [kept])
  }

  @Test func groupsTheTranscriptionsByDay() {
    let history = History([
      transcription("morning", day: 11, hours: -3),
      transcription("evening", day: 11, hours: 8),
      transcription("before", day: 9),
    ])
    let days = history.days(in: calendar)
    #expect(days.map(\.date) == [noon(day: 11) - 12 * 3600, noon(day: 9) - 12 * 3600])
    #expect(days.map { $0.transcriptions.map(\.text) } == [["evening", "morning"], ["before"]])
  }

  @Test func survivesBeingWrittenAndRead() throws {
    let history = History([transcription("one", day: 10), transcription("two", day: 11)])
    #expect(try History(data: history.data) == history)
    #expect(throws: (any Error).self) { try History(data: Data("not json".utf8)) }
  }

  @Test func showsTheDurationAsMinutesAndSeconds() {
    func clock(_ duration: TimeInterval) -> String {
      Transcription(date: noon(day: 10), text: "x", duration: duration).clock
    }
    #expect(clock(0.4) == "0:00")
    #expect(clock(9.5) == "0:10")
    #expect(clock(65) == "1:05")
    #expect(clock(600) == "10:00")
  }
}
