import Foundation
import Testing

@testable import VoiceCore

private typealias Mode = OutputHold.Mode
private typealias Level = OutputHold.Level

private let speakers = Mode(output: "speakers")
private let media = Mode(output: "headset")
private let call = Mode(output: "headset", isCall: true)

private func level(_ volume: Float?, muted: Bool? = false) -> Level {
  Level(volume: volume, isMuted: muted)
}

/// What turning a volume down writes.
private func lowered(_ volume: Float) -> OutputHold.Write {
  .volume(volume * OutputHold.share)
}

@Suite struct OutputHoldTests {
  @Test func mutesTheOutputAndUnmutesItAfter() {
    var hold = OutputHold()
    hold.begin(.mute)
    #expect(hold.look(at: speakers, level(0.5), now: .zero) == .mute(true))
    #expect(hold.look(at: speakers, level(0.5, muted: true), now: .milliseconds(50)) == nil)
    hold.end()
    #expect(hold.look(at: speakers, level(0.5, muted: true), now: .seconds(5)) == .mute(false))
    #expect(!hold.isWatching)
  }

  @Test func anOutputMutedAlreadyIsNotUnmuted() {
    var hold = OutputHold()
    hold.begin(.mute)
    #expect(hold.look(at: speakers, level(0.5, muted: true), now: .zero) == nil)
    hold.end()
    #expect(hold.look(at: speakers, level(0.5, muted: true), now: .seconds(5)) == nil)
  }

  @Test func turnsTheOutputDownAndBackUp() {
    var hold = OutputHold()
    hold.begin(.lower)
    #expect(hold.look(at: speakers, level(0.5), now: .zero) == lowered(0.5))
    #expect(hold.look(at: speakers, level(0.15), now: .milliseconds(50)) == nil)
    hold.end()
    #expect(hold.look(at: speakers, level(0.15), now: .seconds(5)) == .volume(0.5))
    #expect(hold.changes.isEmpty)
  }

  @Test func aVolumeChangedWhileRecordingIsLeftWhereItIs() {
    var hold = OutputHold()
    hold.begin(.lower)
    #expect(hold.look(at: speakers, level(0.5), now: .zero) == lowered(0.5))
    #expect(hold.look(at: speakers, level(0.4), now: .seconds(4)) == nil)
    hold.end()
    #expect(hold.look(at: speakers, level(0.4), now: .seconds(5)) == nil)
    #expect(hold.changes.isEmpty)
  }

  @Test func aSilentOrMutedOutputIsNotTurnedDown() {
    var hold = OutputHold()
    hold.begin(.lower)
    #expect(hold.look(at: speakers, level(0), now: .zero) == nil)
    #expect(hold.look(at: speakers, level(0.5, muted: true), now: .zero) == nil)
    #expect(hold.look(at: speakers, level(nil), now: .zero) == nil)
    #expect(hold.changes.isEmpty)
  }

  @Test func aVolumeTheOutputRoundedIsTurnedBackUp() {
    var hold = OutputHold()
    hold.begin(.lower)
    #expect(hold.look(at: speakers, level(0.75), now: .zero) == lowered(0.75))
    // It has steps of a quarter.
    #expect(hold.look(at: speakers, level(0.25), now: .milliseconds(50)) == nil)
    hold.end()
    #expect(hold.look(at: speakers, level(0.25), now: .seconds(5)) == .volume(0.75))
  }

  @Test func aHeadsetIsMadeQuietAgainInCallQuality() {
    var hold = OutputHold()
    hold.begin(.mute)
    #expect(hold.look(at: media, level(0.5), now: .zero) == .mute(true))
    // Its microphone opened: for calls it has a mute of its own.
    #expect(hold.look(at: call, level(0.6), now: .milliseconds(350)) == .mute(true))
    #expect(hold.changes == [media: .muted, call: .muted])
  }

  @Test func whatAHeadsetBringsBackLateIsMadeQuietAgain() {
    var hold = OutputHold()
    hold.begin(.mute)
    #expect(hold.look(at: call, level(0.6), now: .zero) == .mute(true))
    #expect(hold.look(at: call, level(0.6, muted: false), now: .milliseconds(300)) == .mute(true))
    // Past that moment, unmuting is the user's doing.
    #expect(hold.look(at: call, level(0.6, muted: false), now: .seconds(3)) == nil)
  }

  @Test func turnsTheVolumeDownToTheShareTheRecordingAsksFor() {
    var hold = OutputHold()
    hold.begin(.lower, share: 0.1)
    #expect(hold.look(at: media, level(0.5), now: .zero) == .volume(0.5 * 0.1))
    // The headset arrives in call quality, and is turned down to the same share.
    #expect(hold.look(at: call, level(0.8), now: .milliseconds(350)) == .volume(0.8 * 0.1))
    hold.end()
    #expect(hold.look(at: media, level(0.05), now: .seconds(5)) == .volume(0.5))
  }

  @Test func theVolumeAHeadsetBringsBackIsTurnedDownOnce() {
    var hold = OutputHold()
    hold.begin(.lower)
    #expect(hold.look(at: call, level(0.5), now: .zero) == lowered(0.5))
    #expect(hold.look(at: call, level(0.8), now: .milliseconds(100)) == lowered(0.8))
    // Whatever it says after, it is not turned down again.
    #expect(hold.look(at: call, level(0.6), now: .milliseconds(150)) == nil)
    hold.end()
    #expect(hold.look(at: call, level(0.6), now: .seconds(5)) == .volume(0.8))
  }

  @Test func callQualityIsPutBackAsTheHeadsetLeavesIt() {
    var hold = OutputHold()
    hold.begin(.lower)
    #expect(hold.look(at: media, level(0.5), now: .zero) == lowered(0.5))
    #expect(hold.look(at: call, level(0.6), now: .milliseconds(350)) == lowered(0.6))
    // The recording ended, and the headset was asked for its best quality.
    #expect(hold.leave(call, level(0.18)) == .volume(0.6))
    // It is still in call quality for a moment: that is not made quiet again.
    #expect(hold.look(at: call, level(0.6), now: .seconds(9)) == nil)
    // Back in full quality, it stays quiet until sound is back.
    #expect(hold.look(at: media, level(0.15), now: .seconds(10)) == nil)
    hold.end()
    #expect(hold.look(at: media, level(0.15), now: .seconds(11)) == .volume(0.5))
    #expect(!hold.isWatching)
  }

  @Test func aModeTheOutputIsNotInIsPutBackWhenItIsSeenAgain() {
    var hold = OutputHold()
    hold.begin(.mute)
    #expect(hold.look(at: media, level(0.5), now: .zero) == .mute(true))
    #expect(hold.look(at: call, level(0.6), now: .milliseconds(350)) == .mute(true))
    // Another app keeps the headset in call quality past the recording.
    hold.end()
    #expect(hold.look(at: call, level(0.6, muted: true), now: .seconds(5)) == .mute(false))
    #expect(hold.isWatching)
    #expect(hold.look(at: media, level(0.5, muted: true), now: .seconds(60)) == .mute(false))
    #expect(!hold.isWatching)
  }

  @Test func whatAnEarlierRunLeftIsPutBack() {
    var hold = OutputHold(changes: [speakers: .lowered(from: 0.5, to: 0.15), call: .muted])
    #expect(hold.isWatching)
    #expect(hold.look(at: speakers, level(0.15), now: .zero) == .volume(0.5))
    #expect(hold.look(at: call, level(0.6, muted: true), now: .seconds(90)) == .mute(false))
    #expect(!hold.isWatching)
  }

  @Test func quietLeftFromAnEarlierRecordingIsKept() {
    var hold = OutputHold(changes: [call: .lowered(from: 0.6, to: 0.18)])
    hold.begin(.lower)
    #expect(hold.look(at: call, level(0.18), now: .zero) == nil)
    hold.end()
    #expect(hold.look(at: call, level(0.18), now: .seconds(5)) == .volume(0.6))
  }

  @Test func quietOfTheOtherKindIsPutBackFirst() {
    var hold = OutputHold(changes: [speakers: .muted])
    hold.begin(.lower)
    #expect(hold.look(at: speakers, level(0.5, muted: true), now: .zero) == .mute(false))
    #expect(hold.look(at: speakers, level(0.5), now: .milliseconds(50)) == lowered(0.5))
  }

  @Test func aRecordingThatStartsBeforeTheLastWasOverHoldsCallQualityAgain() {
    var hold = OutputHold()
    hold.begin(.mute)
    #expect(hold.look(at: call, level(0.6), now: .zero) == .mute(true))
    #expect(hold.leave(call, level(0.6, muted: true)) == .mute(false))
    hold.begin(.mute)
    #expect(hold.look(at: call, level(0.6), now: .seconds(3)) == .mute(true))
  }

  @Test func anOutputThatCannotSayWhatItIsAtStaysToPutBack() {
    var hold = OutputHold()
    hold.begin(.lower)
    #expect(hold.look(at: call, level(0.6), now: .zero) == lowered(0.6))
    hold.end()
    // In between two modes, a headset says nothing.
    #expect(hold.look(at: call, level(nil, muted: nil), now: .seconds(5)) == nil)
    #expect(hold.isWatching)
    #expect(hold.look(at: call, level(0.18), now: .seconds(6)) == .volume(0.6))
  }

  @Test func whatIsLeftSurvivesBeingSaved() throws {
    var hold = OutputHold()
    hold.begin(.lower)
    _ = hold.look(at: media, level(0.5), now: .zero)
    hold.begin(.mute)
    _ = hold.look(at: call, level(0.6), now: .zero)
    let saved = try JSONEncoder().encode(hold.changes)
    let read = try JSONDecoder().decode([Mode: OutputHold.Change].self, from: saved)
    #expect(read == hold.changes)
  }
}
