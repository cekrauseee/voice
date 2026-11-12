import Testing

@testable import VoiceCore

@Suite struct NotchTests {
  @Test func itIsBetweenTheTwoSidesOfTheMenuBar() {
    let notch = Notch(screenWidth: 1512, leftWidth: 662, rightWidth: 662, height: 38)
    #expect(notch?.width == 188)
    #expect(notch?.height == 38)
    #expect(notch?.midX == 756)
  }

  @Test func itIsWhereTheLeftSideEnds() {
    let notch = Notch(screenWidth: 1512, leftWidth: 660, rightWidth: 664, height: 38)
    #expect(notch?.minX == 660)
    #expect(notch?.midX == 754)
  }

  @Test func aScreenWhoseMenuBarIsWholeHasNone() {
    #expect(Notch(screenWidth: 1512, leftWidth: 756, rightWidth: 756, height: 38) == nil)
  }

  @Test func aScreenThatLosesNothingAtTheTopHasNone() {
    #expect(Notch(screenWidth: 1512, leftWidth: 662, rightWidth: 662, height: 0) == nil)
  }
}
