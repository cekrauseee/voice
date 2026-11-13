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

  @Test func keepsAFailedTranscriptionWithoutWordsAndResolvesIt() {
    let failed = Transcription(date: noon(day: 10), text: "", duration: 4, failed: true)
    var history = History()
    let keptFailed = history.add(failed)
    let keptEmpty = history.add(Transcription(date: noon(day: 10), text: "", duration: 4))
    #expect(keptFailed)
    #expect(!keptEmpty)
    history.resolve(failed.id, text: "At last.")
    #expect(history.transcriptions.map(\.text) == ["At last."])
    #expect(!history.transcriptions[0].failed)
  }

  @Test func prunesWhatIsOlderThanItIsKeptFor() {
    let old = transcription("old", day: 2)
    var history = History([old, transcription("recent", day: 11)])
    let now = noon(day: 12)
    #expect(Retention.never.cutoff(from: now) == nil)
    let afterMonth = history.prune(before: Retention.month.cutoff(from: now)!)
    #expect(afterMonth == [])
    let afterWeek = history.prune(before: Retention.week.cutoff(from: now)!)
    #expect(afterWeek == [old.id])
    #expect(history.transcriptions.map(\.text) == ["recent"])
    // The recent one was dictated a day before `now`, to the second.
    let afterDay = history.prune(before: Retention.day.cutoff(from: now)!)
    #expect(afterDay == [])
    let anHourLater = history.prune(before: Retention.day.cutoff(from: now + 3600)!)
    #expect(anHourLater.count == 1)
  }

  @Test func survivesBeingWrittenAndRead() throws {
    let failed = Transcription(date: noon(day: 12), text: "", duration: 1, failed: true)
    let history = History([transcription("one", day: 10), transcription("two", day: 11), failed])
    #expect(try History(data: history.data) == history)
    #expect(throws: (any Error).self) { try History(data: Data("not json".utf8)) }
  }

  @Test func readsAHistoryWrittenBeforeFailuresWereKept() throws {
    let old = """
      {"transcriptions":[{"id":"5EED0000-0000-4000-8000-000000000000",\
      "date":"2026-11-10T12:00:00Z","text":"Hello.","heard":"hello","duration":2}]}
      """
    let history = try History(data: Data(old.utf8))
    #expect(history.transcriptions.map(\.text) == ["Hello."])
    #expect(!history.transcriptions[0].failed)
  }

  @Test func countsTheWords() {
    #expect(transcription("Hello, world.\nHow are  you?", day: 10).words == 5)
    #expect(transcription("x", day: 10).words == 1)
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

  @Test func findsTheTranscriptionsThatHoldEveryWordOfAQuery() {
    let history = History([
      transcription("Revisar o PR do pill", day: 10),
      transcription("Send the numbers before the call", day: 11),
      transcription("The pill opens at the notch", day: 12),
    ])
    #expect(
      history.matching("pill").transcriptions.map(\.text) == [
        "The pill opens at the notch", "Revisar o PR do pill",
      ])
    #expect(
      history.matching("pill notch").transcriptions.map(\.text) == [
        "The pill opens at the notch"
      ])
    #expect(history.matching("pill numbers").isEmpty)
  }

  @Test func searchesWhateverTheCaseAndAccents() {
    let history = History([transcription("Testar a animação no notch", day: 10)])
    #expect(history.matching("ANIMACAO").transcriptions.count == 1)
    #expect(history.matching("animação").transcriptions.count == 1)
  }

  @Test func aQueryWithoutWordsFindsEverything() {
    let history = History([transcription("one", day: 10), transcription("two", day: 11)])
    #expect(history.matching("").transcriptions.count == 2)
    #expect(history.matching("  ").transcriptions.count == 2)
  }

  @Test func aFailedTranscriptionWithoutWordsIsNotFound() {
    var failed = transcription("", day: 10)
    failed.failed = true
    #expect(History([failed]).matching("not").isEmpty)
  }
}
