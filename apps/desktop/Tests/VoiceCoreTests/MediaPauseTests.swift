import Testing

@testable import VoiceCore

/// The media on the Mac, as the tests set it.
@MainActor
private final class FakeMedia {
  var isPlaying: Bool
  /// When set, the question of what is playing is not answered until `release`.
  var holdsAnswer = false
  /// When set, sound is not back after a recording until `release`.
  var holdsSound = false
  private(set) var commands: [MediaPause.Command] = []
  /// Whether the other apps are muted, how many times that changed, and how many times
  /// they were asked to be.
  private(set) var othersMuted = false
  private(set) var muteChanges = 0
  private(set) var muteRequests = 0
  /// How many times sound was asked to get back to normal.
  private(set) var soundReturns = 0
  private var waiting: [CheckedContinuation<Void, Never>] = []

  init(isPlaying: Bool) {
    self.isPlaying = isPlaying
  }

  func makePause() -> MediaPause {
    MediaPause(
      isPlaying: { @MainActor in
        if self.holdsAnswer { await self.hold() }
        return self.isPlaying
      },
      send: { self.commands.append($0) },
      soundIsBack: { @MainActor in
        self.soundReturns += 1
        if self.holdsSound { await self.hold() }
      },
      muteOthers: {
        if $0 { self.muteRequests += 1 }
        if $0 != self.othersMuted { self.muteChanges += 1 }
        self.othersMuted = $0
      })
  }

  /// Lets what is being held go on.
  func release() {
    for continuation in waiting { continuation.resume() }
    waiting = []
  }

  private func hold() async {
    await withCheckedContinuation { waiting.append($0) }
  }
}

/// Lets the tasks that are waiting run.
private func settle() async {
  for _ in 0..<20 { await Task.yield() }
}

@Suite struct MediaBehaviorTests {
  @Test func mutingMutesTheOutputWithoutThePermission() {
    #expect(MediaBehavior.mute.muting(appsAllowed: true) == .apps)
    #expect(MediaBehavior.mute.muting(appsAllowed: false) == .output)
  }

  @Test func pausingMutesTheOtherAppsOnlyWithThePermission() {
    #expect(MediaBehavior.pause.muting(appsAllowed: true) == .apps)
    #expect(MediaBehavior.pause.muting(appsAllowed: false) == nil)
  }

  @Test func loweringTurnsTheOutputDownWithOrWithoutThePermission() {
    #expect(MediaBehavior.lower.muting(appsAllowed: true) == .lowerOutput)
    #expect(MediaBehavior.lower.muting(appsAllowed: false) == .lowerOutput)
  }

  @Test func keepingMutesNothing() {
    #expect(MediaBehavior.keep.muting(appsAllowed: true) == nil)
    #expect(MediaBehavior.keep.muting(appsAllowed: false) == nil)
  }
}

@MainActor @Suite struct MediaPauseTests {
  @Test func pausesWhatIsPlayingAndResumesIt() async {
    let media = FakeMedia(isPlaying: true)
    let pause = media.makePause()
    pause.pause()
    await settle()
    #expect(media.commands == [.pause])
    pause.resume()
    pause.resume()
    await settle()
    #expect(media.commands == [.pause, .play])
    pause.resume()
    await settle()
    #expect(media.commands == [.pause, .play])
  }

  @Test func mutingMutesEveryAppAndPausesNone() async {
    let media = FakeMedia(isPlaying: true)
    let pause = media.makePause()
    pause.pause(.mute)
    await settle()
    #expect(media.othersMuted)
    pause.resume()
    await settle()
    #expect(!media.othersMuted)
    #expect(media.commands == [])
    #expect(media.soundReturns == 1)
  }

  @Test func keepingLeavesTheMediaAsItIs() async {
    let media = FakeMedia(isPlaying: true)
    let pause = media.makePause()
    pause.pause(.keep)
    await settle()
    pause.resume()
    await settle()
    #expect(media.commands == [])
    #expect(media.muteChanges == 0)
    #expect(media.soundReturns == 1)
  }

  @Test func leavesAloneWhatWasNotPlaying() async {
    let media = FakeMedia(isPlaying: false)
    let pause = media.makePause()
    pause.pause()
    await settle()
    pause.resume()
    await settle()
    #expect(media.commands == [])
  }

  @Test func getsSoundBackAlsoWhenNothingWasPlaying() async {
    let media = FakeMedia(isPlaying: false)
    let pause = media.makePause()
    pause.pause()
    await settle()
    pause.resume()
    await settle()
    #expect(media.soundReturns == 1)
    #expect(media.commands == [])
  }

  @Test func aDictationThatEndsBeforeTheAnswerPausesNothing() async {
    let media = FakeMedia(isPlaying: true)
    media.holdsAnswer = true
    let pause = media.makePause()
    pause.pause()
    await settle()
    pause.resume()
    media.release()
    await settle()
    #expect(media.commands == [])
  }

  @Test func resumesOnceSoundIsBack() async {
    let media = FakeMedia(isPlaying: true)
    media.holdsSound = true
    let pause = media.makePause()
    pause.pause()
    await settle()
    pause.resume()
    await settle()
    #expect(media.commands == [.pause])
    media.release()
    await settle()
    #expect(media.commands == [.pause, .play])
  }

  @Test func aDictationThatStartsBeforeTheMediaResumedKeepsItPaused() async {
    let media = FakeMedia(isPlaying: true)
    media.holdsSound = true
    let pause = media.makePause()
    pause.pause()
    await settle()
    pause.resume()
    await settle()
    pause.pause()
    media.release()
    await settle()
    #expect(media.commands == [.pause])
    pause.resume()
    await settle()
    media.release()
    await settle()
    #expect(media.commands == [.pause, .play])
  }

  @Test func mutesTheOtherAppsUntilSoundIsBack() async {
    let media = FakeMedia(isPlaying: false)
    media.holdsAnswer = true
    media.holdsSound = true
    let pause = media.makePause()
    pause.pause()
    // At once, without waiting to know whether media plays.
    #expect(media.othersMuted)
    pause.resume()
    media.release()
    await settle()
    #expect(media.othersMuted)
    media.release()
    await settle()
    #expect(!media.othersMuted)
  }

  @Test func theOtherAppsAreHeardAgainWithTheMedia() async {
    let media = FakeMedia(isPlaying: true)
    let pause = media.makePause()
    pause.pause()
    await settle()
    pause.resume()
    await settle()
    #expect(media.commands == [.pause, .play])
    #expect(!media.othersMuted)
  }

  @Test func aDictationThatStartsBeforeTheMediaResumedKeepsTheOthersMuted() async {
    let media = FakeMedia(isPlaying: true)
    media.holdsSound = true
    let pause = media.makePause()
    pause.pause()
    await settle()
    pause.resume()
    await settle()
    pause.pause()
    media.release()
    await settle()
    #expect(media.othersMuted)
    #expect(media.muteChanges == 1)
    // Asked again, so that what was given back for the last one is quiet for this one.
    #expect(media.muteRequests == 2)
  }

  @Test func theNextDictationPausesAgain() async {
    let media = FakeMedia(isPlaying: true)
    let pause = media.makePause()
    pause.pause()
    await settle()
    pause.resume()
    await settle()
    pause.pause()
    pause.pause()
    await settle()
    pause.resume()
    await settle()
    #expect(media.commands == [.pause, .play, .pause, .play])
  }
}
