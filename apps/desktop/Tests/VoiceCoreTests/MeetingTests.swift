import Foundation
import Testing

@testable import VoiceCore

private func segment(
  _ id: Int, _ channel: Channel, _ start: TimeInterval, _ end: TimeInterval, _ text: String
) -> MeetingSegment {
  MeetingSegment(id: id, channel: channel, start: start, end: end, text: text)
}

@Suite struct MeetingTests {
  @Test func keepsTheSegmentsInTheOrderTheyWereSpoken() {
    var meeting = Meeting(date: .now)
    meeting.add(segment(2, .others, 3, 5, "Hello."))
    meeting.add(segment(1, .me, 0, 2, "Hi."))
    meeting.add(segment(3, .me, 5, 7, "How are you?"))
    #expect(meeting.segments.map(\.id) == [1, 2, 3])
    #expect(meeting.nextId == 4)
    #expect(meeting.covered(.me) == 7)
    #expect(meeting.covered(.others) == 5)
  }

  @Test func aSegmentSentAgainReplacesTheOneItCovers() {
    var meeting = Meeting(
      date: .now, segments: [segment(1, .me, 0, 2, "Hi."), segment(2, .others, 1, 3, "Yo.")])
    meeting.add(segment(5, .me, 0.5, 2.5, "Hi there."))
    #expect(meeting.segments.map(\.text) == ["Hi there.", "Yo."])
    #expect(meeting.segments.map(\.id) == [5, 2])
  }

  @Test func aRevisionReplacesTheSegmentsItCovers() {
    var meeting = Meeting(
      date: .now,
      segments: [
        segment(1, .me, 0, 2, "so um the plan"), segment(2, .others, 1, 3, "uh huh"),
        segment(3, .me, 2, 4, "is simple"), segment(4, .me, 5, 6, "right"),
      ])
    meeting.revise(
      from: 1, to: 3,
      with: [segment(5, .me, 0, 4, "So the plan is simple."), segment(6, .others, 1, 3, "Uh-huh.")])
    #expect(meeting.segments.map(\.id) == [5, 6, 4])
    #expect(meeting.segments.map(\.isRevised) == [true, true, false])
    #expect(meeting.nextId == 7)
  }

  @Test func joinsConsecutiveSegmentsOfASideIntoParagraphs() {
    let meeting = Meeting(
      date: .now,
      segments: [
        segment(1, .me, 0, 2, "Hi."), segment(2, .me, 2, 4, "How are you?"),
        segment(3, .others, 4, 6, "Fine."), segment(4, .me, 6, 8, "Good."),
      ])
    #expect(meeting.paragraphs.map(\.text) == ["Hi. How are you?", "Fine.", "Good."])
    #expect(meeting.paragraphs.map(\.id) == [1, 3, 4])
    #expect(meeting.paragraphs.map(\.start) == [0, 4, 6])
    #expect(meeting.text == "Me: Hi. How are you?\n\nOthers: Fine.\n\nMe: Good.")
    #expect(meeting.words == 6)
  }

  @Test func readsWhatItWrote() throws {
    let meeting = Meeting(
      date: Date(timeIntervalSince1970: 1_700_000_000), duration: 125,
      segments: [segment(1, .me, 0, 2, "Hi.")],
      usage: Usage(audioSeconds: 2, cost: 0.02))
    #expect(try Meeting(data: meeting.data) == meeting)
    // A meeting written before segments said whether they were revised.
    let old = #"""
      {"date":"2026-11-12T10:00:00Z","duration":1,"id":"\#(UUID().uuidString)","isLive":false,
      "segments":[{"channel":"me","end":1,"id":1,"start":0,"text":"Hi."}],
      "usage":{"audio_seconds":0,"cost":0,"input_tokens":0,"output_tokens":0}}
      """#
    #expect(try Meeting(data: Data(old.utf8)).segments.first?.isRevised == false)
    #expect(meeting.clock == "2:05")
    #expect(TimeInterval(3725).clock == "1:02:05")
  }

  @Test func groupsTheMeetingsByDay() {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    let noon = calendar.date(from: DateComponents(year: 2026, month: 11, day: 12, hour: 12))!
    let meetings = [
      Meeting(date: noon + 3600), Meeting(date: noon), Meeting(date: noon - 86400),
    ]
    let days = meetings.days(in: calendar)
    #expect(days.map { $0.meetings.count } == [2, 1])
    #expect(days.map(\.date) == [noon - 12 * 3600, noon - 36 * 3600])
  }
}

@Suite struct LiveMeetingTests {
  @Test func appliesWhatTheServerSends() {
    var live = LiveMeeting(Meeting(date: .now))
    #expect(live.meeting.isLive)
    live.apply(.draft(channel: .me, text: "so"))
    live.apply(.draft(channel: .others, text: "well"))
    #expect(live.drafts == [.me: "so", .others: "well"])

    live.apply(.segment(segment(1, .me, 0, 2, "So.")))
    live.apply(.draft(channel: .me, text: ""))
    live.apply(.usage(Usage(audioSeconds: 2, cost: 0.02)))
    #expect(live.drafts == [.others: "well"])
    #expect(live.meeting.segments.map(\.text) == ["So."])
    #expect(live.meeting.usage == Usage(audioSeconds: 2, cost: 0.02))

    live.end(duration: 10)
    #expect(!live.meeting.isLive)
    #expect(live.meeting.duration == 10)
    #expect(live.drafts.isEmpty)
  }

  @Test func addsUpTheUsageOfEveryConnection() {
    var live = LiveMeeting(Meeting(date: .now))
    live.apply(.usage(Usage(audioSeconds: 2, cost: 0.02)))
    live.apply(.usage(Usage(audioSeconds: 5, cost: 0.05)))
    live.apply(.draft(channel: .me, text: "lost"))
    live.reconnecting()
    #expect(live.drafts.isEmpty)
    #expect(live.meeting.usage == Usage(audioSeconds: 5, cost: 0.05))

    live.apply(.usage(Usage(audioSeconds: 1, cost: 0.01)))
    live.apply(.done(usage: Usage(audioSeconds: 3, cost: 0.03)))
    #expect(live.meeting.usage == Usage(audioSeconds: 8, cost: 0.08))
  }
}

@Suite struct MeetingMessageTests {
  @Test func decodesEveryMessage() {
    #expect(MeetingServerMessage(json: #"{"type":"ready"}"#) == .ready)
    #expect(
      MeetingServerMessage(json: #"{"type":"draft","channel":"others","text":"hi"}"#)
        == .draft(channel: .others, text: "hi"))
    #expect(
      MeetingServerMessage(
        json: #"{"type":"segment","id":4,"channel":"me","start":1.5,"end":3,"text":"Hi."}"#)
        == .segment(segment(4, .me, 1.5, 3, "Hi.")))
    #expect(
      MeetingServerMessage(
        json:
          #"{"type":"revised","from":4,"to":5,"segments":[{"id":6,"channel":"others","start":1.5,"end":3,"text":"Hi."}]}"#
      )
        == .revised(from: 4, to: 5, segments: [segment(6, .others, 1.5, 3, "Hi.")]))
    let usage = #"{"audio_seconds":2.5,"input_tokens":0,"output_tokens":0,"cost":0.0007}"#
    #expect(
      MeetingServerMessage(json: #"{"type":"usage","usage":\#(usage)}"#)
        == .usage(Usage(audioSeconds: 2.5, cost: 0.0007)))
    #expect(
      MeetingServerMessage(json: #"{"type":"done","usage":\#(usage)}"#)
        == .done(usage: Usage(audioSeconds: 2.5, cost: 0.0007)))
    #expect(
      MeetingServerMessage(json: #"{"type":"error","code":"timeout","message":"x"}"#)
        == .error(code: "timeout"))
  }

  @Test func rejectsWhatItDoesNotKnow() {
    #expect(MeetingServerMessage(json: #"{"type":"segment","id":1}"#) == nil)
    #expect(MeetingServerMessage(json: #"{"type":"revised","from":1}"#) == nil)
    #expect(MeetingServerMessage(json: #"{"type":"draft","channel":"you","text":""}"#) == nil)
    #expect(MeetingServerMessage(json: #"{"type":"other"}"#) == nil)
    #expect(MeetingServerMessage(json: "nope") == nil)
  }

  @Test func encodesEveryMessage() {
    #expect(MeetingClientMessage.stop.json == #"{"type":"stop"}"#)
    #expect(
      MeetingClientMessage.start(instructions: "", firstId: 7, offsets: [.me: 12.5, .others: 3])
        .json
        == #"{"first_id":7,"instructions":"","offsets":{"me":12.5,"others":3},"type":"start"}"#)
    #expect(AudioFrame.make(.others, Data([1, 2])) == Data([1, 1, 2]))
    #expect(AudioFrame.make(.me, Data()) == Data([0]))
  }
}

@Suite struct ReplayTailTests {
  /// A second of audio.
  private let second = Data(count: Int(AudioFormat.sampleRate) * 2)

  @Test func keepsWhatIsNotConfirmedAndReplaysItFromWhereItStarts() {
    var tail = ReplayTail()
    for time in 0..<3 { tail.append(second, at: Double(time), isConnected: true) }
    #expect(tail.replay.offset == 0)
    #expect(tail.replay.chunks.count == 3)
    #expect(tail.seconds == 3)

    tail.confirm(upTo: 1.5)
    #expect(tail.confirmed == 1.5)
    #expect(tail.replay.offset == 1)
    #expect(tail.replay.chunks.count == 2)

    tail.confirm(upTo: 1)
    #expect(tail.confirmed == 1.5)
  }

  @Test func confirmsOldAudioByTimeWhileConnected() {
    var tail = ReplayTail()
    for time in 0..<50 { tail.append(second, at: Double(time), isConnected: true) }
    #expect(tail.confirmed == 49 - ReplayTail.margin)
    #expect(tail.replay.chunks.count == 41)

    for time in 50..<60 { tail.append(second, at: Double(time), isConnected: false) }
    #expect(tail.confirmed == 49 - ReplayTail.margin)
    #expect(tail.replay.chunks.count == 51)
  }

  @Test func startsWhereItIsToldTo() {
    var tail = ReplayTail(confirmed: 100)
    #expect(tail.replay.offset == 100)
    tail.append(second, at: 100, isConnected: true)
    #expect(tail.replay.offset == 100)
    #expect(tail.replay.chunks.count == 1)
  }
}

@Suite struct BackoffTests {
  @Test func doublesUpToTheLimit() {
    #expect(Backoff.delay(afterFailures: 1) == .seconds(1))
    #expect(Backoff.delay(afterFailures: 2) == .seconds(2))
    #expect(Backoff.delay(afterFailures: 5) == .seconds(16))
    #expect(Backoff.delay(afterFailures: 6) == .seconds(30))
    #expect(Backoff.delay(afterFailures: 40) == .seconds(30))
  }
}

@Suite struct WAVHeaderTests {
  @Test func theHeaderIsWhatAFileStartsWith() {
    let pcm = Data([1, 2, 3, 4])
    #expect(WAV.file(pcm: pcm) == WAV.header(pcmBytes: 4) + pcm)
    #expect(WAV.header(pcmBytes: 4).count == 44)
    #expect(WAV.pcm(file: WAV.header(pcmBytes: 4) + pcm) == pcm)
  }
}
