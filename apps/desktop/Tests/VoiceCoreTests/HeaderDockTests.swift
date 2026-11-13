import Testing

@testable import VoiceCore

@Suite struct HeaderDockTests {
  private let dock = HeaderDock(range: 120)

  @Test func followsTheScroll() {
    #expect(dock.progress(at: 0) == 0)
    #expect(dock.progress(at: 30) == 0.25)
    #expect(dock.progress(at: 120) == 1)
  }

  @Test func staysDockedOrShowingPastEitherEnd() {
    #expect(dock.progress(at: -40) == 0)
    #expect(dock.progress(at: 900) == 1)
  }

  @Test func aHeaderLeftHalfwayGoesToTheNearerEnd() {
    #expect(dock.settle(40, maximum: 2000) == 0)
    #expect(dock.settle(80, maximum: 2000) == 120)
  }

  @Test func aHeaderAtEitherEndStaysThere() {
    #expect(dock.settle(0, maximum: 2000) == nil)
    #expect(dock.settle(120, maximum: 2000) == nil)
    #expect(dock.settle(700, maximum: 2000) == nil)
  }

  @Test func aListTooShortToDockIsLeftWhereItIs() {
    #expect(dock.settle(80, maximum: 100) == nil)
  }

  @Test func blendsBetweenTheTwoPlaces() {
    #expect(HeaderDock.blend(40, 140, by: 0) == 40)
    #expect(HeaderDock.blend(40, 140, by: 0.5) == 90)
    #expect(HeaderDock.blend(40, 140, by: 1) == 140)
  }
}
