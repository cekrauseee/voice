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
  /// Whether the other apps are muted, and how many times that changed.
  private(set) var othersMuted = false
  private(set) var muteChanges = 0
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
        self.othersMuted = $0
        self.muteChanges += 1
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
