import AppKit
import Observation
import SwiftUI
import VoiceCore

/// A page of the app's window.
enum Page: Hashable {
  /// The past transcriptions, with today's figures over them.
  case transcriptions
  /// One transcription, to read and to listen to.
  case transcription(Transcription.ID)
  case statistics
  case settings
}

/// Where the window is.
///
/// The transcriptions are always there, under the page opened over them. Opening a page
/// takes two steps, so that what the list and the page share can travel between them: the
/// page is first laid out with those elements where the list has them, then comes forward.
/// Going back reverses the two steps, and takes the page away once everything has landed.
@MainActor @Observable
final class Navigation {
  /// The page over the list, while it shows or is on its way in or out.
  private(set) var top: Page?
  /// Whether that page is in front. What it shares with the list belongs to it then.
  private(set) var isOpen = false
  /// Whether the recording of the transcription being opened plays once it is open.
  var playsWhenOpen = false
  /// How docked today's figures are over the list, from 0 to 1, for the statistics to take
  /// them from the size they are seen at.
  var dockProgress = 0.0

  /// Counts the ways back, so that a page opened while another goes is not taken away.
  @ObservationIgnored private var closing = 0

  /// The page the window is on.
  var page: Page {
    isOpen ? top ?? .transcriptions : .transcriptions
  }

  /// Goes to a page. Without animation, as when the window is not on screen, it is there at
  /// once.
  func show(_ page: Page, animated: Bool = true) {
    guard page != .transcriptions else {
      animated ? back() : close()
      return
    }
    closing += 1
    if !animated {
      top = page
      isOpen = true
    } else if top != nil, isOpen {
      // From one page to another: the new one fades in over the old one.
      withAnimation(Motion.leave) { top = page }
    } else {
      top = page
      isOpen = false
    }
  }

  /// The second step of opening a page: it comes forward. The page calls it once it is laid
  /// out.
  func present() {
    guard top != nil, !isOpen else { return }
    withAnimation(Motion.morph) { isOpen = true }
  }

  /// Goes back to the list, then does `then` once the page is gone.
  func back(then: (() -> Void)? = nil) {
    guard top != nil else {
      then?()
      return
    }
    closing += 1
    let way = closing
    withAnimation(Motion.morph, completionCriteria: .logicallyComplete) {
      isOpen = false
    } completion: { [weak self] in
      guard let self, closing == way else { return }
      top = nil
      then?()
    }
  }

  private func close() {
    closing += 1
    top = nil
    isOpen = false
  }
}

/// The app's window: the transcriptions, and the page opened over them.
struct MainView: View {
  let navigation: Navigation
  let history: HistoryStore
  let statistics: StatisticsStore
  let retry: Retry
  let loginItem: LoginItem
  @Bindable var settings: Settings

  @Namespace private var shared

  var body: some View {
    GeometryReader { window in
      ZStack(alignment: .topLeading) {
        TranscriptionsPage(
          navigation: navigation, history: history, statistics: statistics.statistics,
          settings: settings, retry: retry, shared: shared)
        if let top = navigation.top {
          page(top)
            .id(top)
            .transition(.opacity)
        }
        UndoToast(history: history)
      }
      .environment(\.titleBarHeight, window.safeAreaInsets.top)
      .ignoresSafeArea(edges: .top)
    }
    .background(Design.ground)
    // A transcription deleted while its page is open, as when it gets too old to keep,
    // takes the window back to the list.
    .onChange(of: history.history.transcriptions.map(\.id)) { _, ids in
      if case .transcription(let id) = navigation.top, !ids.contains(id) { navigation.back() }
    }
  }

  @ViewBuilder private func page(_ page: Page) -> some View {
    switch page {
    case .transcription(let id):
      if let transcription = history.history.transcriptions.first(where: { $0.id == id }) {
        TranscriptionPage(
          transcription: transcription, navigation: navigation, history: history, retry: retry,
          shared: shared)
      }
    case .statistics:
      StatisticsPage(statistics: statistics.statistics, navigation: navigation, shared: shared)
    case .settings:
      SettingsPage(settings: settings, loginItem: loginItem, navigation: navigation)
    case .transcriptions:
      EmptyView()
    }
  }
}

extension View {
  /// Shows a part of the page over the list as the page comes forward, a beat after what it
  /// shares with the list, and takes it away at once when the page goes.
  func pagePart(isOpen: Bool) -> some View {
    animation(isOpen ? Motion.arrive : Motion.leave) {
      $0
        .opacity(isOpen ? 1 : 0)
        .offset(y: isOpen ? 0 : 8)
    }
  }

  /// Shows what a page shares with the list: its copy takes over at once as the page comes
  /// forward, and hands back to the list's copy as it goes.
  func sharedPart(isOpen: Bool) -> some View {
    animation(isOpen ? Motion.takeOver : Motion.handOff) {
      $0.opacity(isOpen ? 1 : 0)
    }
  }
}

/// Says a transcription was deleted, with the way to bring it back, until it is gone for good.
private struct UndoToast: View {
  let history: HistoryStore

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    ZStack {
      if history.deleted != nil {
        HStack(spacing: Design.medium) {
          Text("Transcription deleted")
            .font(.voiceBody)
          Button("Undo") { withAnimation(Motion.settle) { history.restore() } }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 10)
            .frame(height: 28)
            .contentShape(Rectangle())
            .pointer()
        }
        .foregroundStyle(Design.ground)
        .padding(.leading, Design.large)
        .padding(.trailing, 5)
        .frame(height: 38)
        .background(Design.ink, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 14, y: 6)
        .transition(
          reduceMotion
            ? .opacity
            : .asymmetric(
              insertion: .opacity.combined(with: .offset(y: 10)).combined(
                with: .scale(scale: 0.98)),
              removal: .opacity.combined(with: .offset(y: 6))))
      }
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
    .padding(.bottom, Design.wide)
    .animation(Motion.snappy, value: history.deleted?.id)
  }
}

extension Date {
  /// The day as the window names it: today, yesterday, or the date.
  ///
  /// In English, like the rest of the app, whatever language the Mac is in.
  var dayTitle: String {
    let calendar = Calendar.current
    if calendar.isDateInToday(self) { return "Today" }
    if calendar.isDateInYesterday(self) { return "Yesterday" }
    let isThisYear = calendar.isDate(self, equalTo: .now, toGranularity: .year)
    let format = Date.FormatStyle(locale: Locale(identifier: "en_US"))
      .weekday(.wide).day().month(.wide)
    return formatted(isThisYear ? format : format.year())
  }

  /// The time of day, as the Mac writes it, such as `10:42`.
  var time: String {
    formatted(date: .omitted, time: .shortened)
  }

  /// Whether the Mac writes times with AM and PM, which takes more room.
  static let usesTwelveHours =
    DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: .current)?.contains("a")
    ?? false
}
