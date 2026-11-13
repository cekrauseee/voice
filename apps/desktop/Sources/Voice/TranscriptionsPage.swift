import AppKit
import SwiftUI
import VoiceCore

/// The past transcriptions, day by day, newest first, under today's figures.
///
/// Scrolling the list docks today's figures into the title bar: the same figures travel
/// there, following the scroll. The search finds transcriptions by their words.
struct TranscriptionsPage: View {
  let navigation: Navigation
  let history: HistoryStore
  let statistics: Statistics
  let settings: Settings
  let retry: Retry
  let shared: Namespace.ID

  @Environment(\.titleBarHeight) private var titleBar
  @State private var query = ""
  @State private var isSearching = false
  /// How far the list is scrolled, in points.
  @State private var offset = 0.0
  /// How tall today's figures are: the list scrolls that far while they dock.
  @State private var headerHeight = 150.0
  /// Transcriptions that just arrived, on a highlight for a moment.
  @State private var fresh: Set<Transcription.ID> = []
  /// The transcriptions the list has shown, to tell a new one.
  @State private var seen: Set<Transcription.ID> = []

  private var isFront: Bool { !navigation.isOpen }
  private var dock: HeaderDock { HeaderDock(range: headerHeight) }
  private var visible: History { history.history.matching(query) }

  var body: some View {
    GeometryReader { page in
      let progress = dock.progress(at: offset)
      ZStack(alignment: .topLeading) {
        feed
        TodayHeader(
          statistics: statistics, progress: progress, width: page.size.width, isFront: isFront,
          isSearching: isSearching,
          statisticsOpen: navigation.top == .statistics && navigation.isOpen,
          statisticsInvolved: navigation.top == .statistics, shared: shared,
          height: $headerHeight
        ) {
          navigation.show(.statistics)
        }
        titleBarContent(progress: progress)
      }
      .coordinateSpace(.named(TodayHeader.space))
    }
    .allowsHitTesting(isFront)
    .accessibilityHidden(!isFront)
    .onAppear { seen = Set(history.history.transcriptions.map(\.id)) }
    .onChange(of: history.history.transcriptions.map(\.id)) { _, ids in highlightNew(ids) }
  }

  private func titleBarContent(progress: Double) -> some View {
    TitleBar {
      EmptyView()
    } trailing: {
      HStack(spacing: 2) {
        SearchField(query: $query, isOpen: $isSearching)
        IconButton(symbol: "slider.horizontal.3", help: "Settings") {
          navigation.show(.settings)
        }
      }
    }
    .overlay(alignment: .bottom) {
      // Once the figures are docked, a line sets the title bar apart from the list.
      Rectangle()
        .fill(Design.line)
        .frame(height: 1)
        .opacity(min(max((progress - 0.6) / 0.4, 0), 1))
    }
    .listPart(isShown: isFront)
  }

  private var feed: some View {
    ScrollView {
      VStack(spacing: 0) {
        // The room of today's figures, which tells how far the list is scrolled.
        Color.clear
          .frame(height: headerHeight)
          .onGeometryChange(for: Double.self) { proxy in
            -proxy.frame(in: .named(Self.feedSpace)).minY
          } action: {
            offset = $0
            navigation.dockProgress = dock.progress(at: $0)
          }
        LazyVStack(alignment: .leading, spacing: 0) {
          content
        }
        .padding(.horizontal, Design.loose)
        .padding(.bottom, 48)
        .animation(Motion.settle, value: visible.transcriptions.map(\.id))
      }
    }
    .coordinateSpace(.named(Self.feedSpace))
    .scrollTargetBehavior(DockSnap(dock: dock))
    // The list ends at the title bar: it never scrolls under the docked figures.
    .clipped()
    .padding(.top, titleBar)
  }

  @ViewBuilder private var content: some View {
    let visible = visible
    if history.history.isEmpty {
      EmptyHistory(pushToTalk: settings.pushToTalk)
        .listPart(isShown: isFront)
    } else if visible.isEmpty {
      Text("No transcriptions match “\(query.trimmingCharacters(in: .whitespaces))”")
        .font(.voiceBody)
        .foregroundStyle(Design.ink2)
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
        .listPart(isShown: isFront)
    } else {
      let days = visible.days(in: .current)
      ForEach(days) { day in
        DayHeader(day: day, isFirst: day.id == days.first?.id)
          .listPart(isShown: isFront)
          .transition(.opacity)
        ForEach(day.transcriptions) { transcription in
          row(transcription)
        }
      }
    }
  }

  private func row(_ transcription: Transcription) -> some View {
    let id = transcription.id
    let opens = navigation.top == .transcription(id)
    return TranscriptionRow(
      transcription: transcription, history: history, shared: shared,
      isSource: !(opens && navigation.isOpen), isOpened: opens && navigation.isOpen,
      isFresh: fresh.contains(id), isRetrying: retry.running.contains(id),
      open: { navigation.show(.transcription(id)) },
      play: {
        navigation.playsWhenOpen = true
        navigation.show(.transcription(id))
      },
      retry: { retry.start(id) },
      remove: { withAnimation(Motion.settle) { history.remove(id) } }
    )
    .listPart(isShown: isFront, travels: opens)
    .transition(
      .asymmetric(
        insertion: .opacity.combined(with: .offset(y: -8)),
        removal: .opacity.combined(with: .scale(scale: 0.97))))
  }

  /// A transcription that was not there before is on a highlight for a moment, to show
  /// where it went.
  private func highlightNew(_ ids: [Transcription.ID]) {
    let new = Set(ids).subtracting(seen)
    seen.formUnion(new)
    guard !new.isEmpty else { return }
    fresh.formUnion(new)
    Task {
      try? await Task.sleep(for: .seconds(0.6))
      fresh.subtract(new)
    }
  }

  nonisolated private static let feedSpace = "feed"
}

extension View {
  /// Shows a part of the list, or hides it while a page is over it. It goes at once, and
  /// comes back once what travels from the page has landed. A part that travels takes over
  /// from the page's copy at once.
  fileprivate func listPart(isShown: Bool, travels: Bool = false) -> some View {
    animation(
      isShown
        ? (travels ? Motion.takeOver : Motion.arriveLate)
        : (travels ? Motion.handOff : Motion.leave)
    ) {
      $0.opacity(isShown ? 1 : 0)
    }
  }
}

/// Ends a scroll that leaves today's figures halfway docked at the nearer end.
private struct DockSnap: ScrollTargetBehavior {
  let dock: HeaderDock

  func updateTarget(_ target: inout ScrollTarget, context: TargetContext) {
    let maximum = context.contentSize.height - context.containerSize.height
    if let settled = dock.settle(target.rect.minY, maximum: maximum) {
      target.rect.origin.y = settled
    }
  }
}

/// Today's words, how long and how fast they were spoken and what they cost, and the words
/// of each day of the week. Clicking the week opens the statistics.
///
/// As the list scrolls, the words and the week travel into the title bar, smaller, the words
/// on the left and the week on the right. The rest scrolls away with the list, fading
/// before it reaches the top.
private struct TodayHeader: View {
  let statistics: Statistics
  /// How docked the figures are, from 0 to 1.
  let progress: Double
  let width: Double
  let isFront: Bool
  let isSearching: Bool
  /// Whether the statistics are open over the list: the words and the week are theirs then.
  let statisticsOpen: Bool
  /// Whether the statistics are on their way in or out, so the words and the week travel.
  let statisticsInvolved: Bool
  let shared: Namespace.ID
  @Binding var height: Double
  let openStatistics: () -> Void

  @Environment(\.titleBarHeight) private var titleBar
  @Environment(\.windowButtonsWidth) private var windowButtonsWidth
  /// Where the parts that dock are laid out, before they move.
  @State private var frames: [Part: CGRect] = [:]
  @State private var isWeekHovered = false

  nonisolated static let space = "page"

  private enum Part {
    case figure, unit, week
  }

  /// The sizes the parts dock at.
  private static let figureSize = 52.0
  private static let dockedFigure = 18.0
  private static let unitSize = 15.0
  private static let dockedUnit = 12.5
  private static let tallestBar = 52.0
  private static let dockedBar = 18.0
  /// The room the buttons take at the end of the title bar.
  private static let trailing = 14.0 + Design.control * 2 + 2

  private var today: Tally { statistics.total(.today, now: .now, in: .current) }
  private var week: [Statistics.Bar] { statistics.bars(.week, now: .now, in: .current) }

  var body: some View {
    ZStack(alignment: .topLeading) {
      // The ground under the figures hides the list as it scrolls under them, and goes with
      // them as they dock.
      Rectangle()
        .fill(Design.ground)
        .frame(height: max(height * (1 - progress), 0))
        .offset(y: titleBar)
        .allowsHitTesting(false)
      layout
        .padding(.top, titleBar)
    }
    .frame(maxWidth: .infinity, alignment: .topLeading)
  }

  private var layout: some View {
    HStack(alignment: .bottom, spacing: Design.loose) {
      VStack(alignment: .leading, spacing: 0) {
        Text("Today")
          .font(.voiceLabel)
          .foregroundStyle(Design.ink2)
          .modifier(Tuck(progress: progress, distance: height))
          .padding(.bottom, Design.small)
          .listPart(isShown: isFront)
        HStack(alignment: .firstTextBaseline, spacing: 10) {
          figure
          unit
        }
        readouts
          .modifier(Tuck(progress: progress, distance: height))
          .padding(.top, Design.medium)
          .listPart(isShown: isFront)
      }
      Spacer(minLength: 0)
      weekButton
    }
    .padding(.top, Design.tight)
    .padding(.horizontal, 40)
    .padding(.bottom, 26)
    .onGeometryChange(for: Double.self) {
      $0.size.height
    } action: {
      height = $0
    }
    .allowsHitTesting(true)
  }

  private var figure: some View {
    let visualSize = Self.figureSize * dockScale(.figure)
    return Text(Figure.count(today.words))
      .font(.voiceMono(Self.figureSize, weight: .medium))
      .tracking(-2.3)
      .foregroundStyle(Design.ink)
      .contentTransition(.numericText(value: Double(today.words)))
      .animation(Motion.snappy, value: today.words)
      .fixedSize()
      // Open, the statistics set the words at 40 points: on the way back they shrink from it.
      .scaleEffect(statisticsOpen ? StatisticsPage.figureSize / visualSize : 1, anchor: .topLeading)
      .shared(.figure, in: shared, isSource: !statisticsOpen, isText: true)
      .modifier(Dock(offset: dockOffset(.figure), scale: dockScale(.figure)))
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .named(Self.space))
      } action: {
        frames[.figure] = $0
      }
      .listPart(isShown: isFront, travels: statisticsInvolved)
      .allowsHitTesting(false)
      .accessibilityLabel("\(Figure.count(today.words)) words today")
  }

  private var unit: some View {
    Text("words")
      .font(.system(size: Self.unitSize))
      .foregroundStyle(Design.ink2)
      .fixedSize()
      .scaleEffect(
        statisticsOpen ? StatisticsPage.labelSize / (Self.unitSize * dockScale(.unit)) : 1,
        anchor: .topLeading
      )
      .shared(.unit, in: shared, isSource: !statisticsOpen, isText: true)
      .modifier(Dock(offset: dockOffset(.unit), scale: dockScale(.unit)))
      .onGeometryChange(for: CGRect.self) {
        $0.frame(in: .named(Self.space))
      } action: {
        frames[.unit] = $0
      }
      .listPart(isShown: isFront, travels: statisticsInvolved)
      .allowsHitTesting(false)
      .accessibilityHidden(true)
  }

  private var readouts: some View {
    HStack(spacing: Design.large) {
      Text("\(Figure.time(today.seconds)) speaking")
      Text(today.wordsPerMinute.map { "\($0) wpm" } ?? "– wpm")
      Text(Figure.cost(today.cost))
    }
    .font(.voiceMono(12))
    .foregroundStyle(Design.ink3)
    .contentTransition(.numericText())
    .animation(Motion.snappy, value: today)
  }

  private var weekButton: some View {
    let most = max(week.map(\.tally.words).max() ?? 0, 1)
    let labels = max(0, 1 - progress * 3)
    return Button(action: openStatistics) {
      HStack(alignment: .bottom, spacing: 7) {
        ForEach(Array(week.enumerated()), id: \.element.id) { index, bar in
          VStack(spacing: 7) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
              .fill(index == week.count - 1 ? Design.signal : Design.bar)
              .frame(
                width: 10,
                height: max(3, Self.tallestBar * Double(bar.tally.words) / Double(most))
              )
              .shared(.bar(index), in: shared, isSource: !statisticsOpen)
              .listPart(isShown: isFront, travels: statisticsInvolved)
            Text(bar.start.formatted(Self.weekday))
              .font(.voiceMono(10))
              .foregroundStyle(Design.ink3)
              .opacity(labels)
              .listPart(isShown: isFront)
          }
        }
      }
      .animation(Motion.settle, value: week.map(\.tally.words))
      .padding(EdgeInsets(top: 10, leading: 12, bottom: 8, trailing: 12))
      .background(
        isWeekHovered ? Design.hover : .clear,
        in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .contentShape(Rectangle())
      .animation(Motion.hover, value: isWeekHovered)
    }
    .buttonStyle(.plain)
    .onHover { isWeekHovered = $0 }
    .pointer()
    .help("Statistics")
    .accessibilityLabel("Open statistics")
    // While searching, the field takes the place the week docks in.
    .opacity(isSearching ? 1 - progress : 1)
    .modifier(Dock(offset: dockOffset(.week), scale: dockScale(.week)))
    .onGeometryChange(for: CGRect.self) {
      $0.frame(in: .named(Self.space))
    } action: {
      frames[.week] = $0
    }
    .padding(.trailing, -12)
  }

  /// How much smaller a part is, as docked as the figures are.
  private func dockScale(_ part: Part) -> Double {
    let docked =
      switch part {
      case .figure: Self.dockedFigure / Self.figureSize
      case .unit: Self.dockedUnit / Self.unitSize
      case .week: Self.dockedBar / Self.tallestBar
      }
    return HeaderDock.blend(1, docked, by: progress)
  }

  /// How far a part has moved from where it is laid out toward where it docks.
  private func dockOffset(_ part: Part) -> CGSize {
    guard let frame = frames[part], progress > 0 else { return .zero }
    let middle = titleBar / 2
    let figureX = windowButtonsWidth + Design.large
    let target: CGPoint
    switch part {
    case .figure:
      let scale = Self.dockedFigure / Self.figureSize
      target = CGPoint(x: figureX, y: middle - frame.height * scale / 2)
    case .unit:
      let figureWidth = (frames[.figure]?.width ?? 0) * Self.dockedFigure / Self.figureSize
      let scale = Self.dockedUnit / Self.unitSize
      target = CGPoint(x: figureX + figureWidth + 6, y: middle - frame.height * scale / 2 + 1)
    case .week:
      // The bars end a little before the buttons, centered in the title bar. The padding of
      // the button is the same small amount in either state.
      let scale = Self.dockedBar / Self.tallestBar
      let right = width - Self.trailing - 10
      target = CGPoint(
        x: right - (frame.width - 12) * scale, y: middle - (10 + Self.tallestBar / 2) * scale)
    }
    return CGSize(
      width: HeaderDock.blend(0, target.x - frame.minX, by: progress),
      height: HeaderDock.blend(0, target.y - frame.minY, by: progress))
  }

  private static let weekday = Date.FormatStyle(locale: Locale(identifier: "en_US")).weekday(
    .narrow)
}

/// Moves a part of today's figures toward the title bar, scaled from its corner.
private struct Dock: ViewModifier {
  let offset: CGSize
  let scale: Double

  func body(content: Content) -> some View {
    content
      .scaleEffect(scale, anchor: .topLeading)
      .offset(offset)
  }
}

/// Scrolls a part away with the list, fading before it reaches the top.
private struct Tuck: ViewModifier {
  let progress: Double
  let distance: Double

  func body(content: Content) -> some View {
    content
      .offset(y: -progress * distance)
      .opacity(max(0, 1 - progress * 3))
  }
}

/// A day of the list: its name, and how many of its transcriptions show.
private struct DayHeader: View {
  let day: History.Day
  let isFirst: Bool

  var body: some View {
    let count = day.transcriptions.count
    HStack(alignment: .firstTextBaseline) {
      Text(day.date.dayTitle)
        .font(.voiceTitle)
        .foregroundStyle(Design.ink)
      Spacer(minLength: Design.small)
      Text(count == 1 ? "1 dictation" : "\(count) dictations")
        .font(.voiceMono(11.5))
        .foregroundStyle(Design.ink3)
    }
    .padding(.horizontal, Design.large)
    .padding(.top, isFirst ? 2 : 22)
    .padding(.bottom, Design.tight)
  }
}

/// What the list says before anything was dictated.
private struct EmptyHistory: View {
  let pushToTalk: Shortcut

  var body: some View {
    VStack(spacing: 10) {
      Text("No transcriptions yet")
        .font(.voiceTitle)
        .foregroundStyle(Design.ink)
      HStack(spacing: 6) {
        Text("Hold")
        KeyCaps(labels: pushToTalk.keyCaps)
        Text("and speak")
      }
      .font(.voiceCaption)
      .foregroundStyle(Design.ink2)
    }
    .frame(maxWidth: .infinity)
    .padding(.top, 56)
  }
}

/// The search: a button that opens into a field. ⌘F opens it, and Escape closes it, as does
/// leaving it empty.
private struct SearchField: View {
  @Binding var query: String
  @Binding var isOpen: Bool

  @FocusState private var isFocused: Bool

  var body: some View {
    HStack(spacing: 0) {
      IconButton(symbol: "magnifyingglass", help: "Search") {
        if isOpen { isFocused = true } else { isOpen = true }
      }
      .keyboardShortcut("f", modifiers: .command)
      if isOpen {
        TextField("Search", text: $query)
          .textFieldStyle(.plain)
          .font(.voiceBody)
          .foregroundStyle(Design.ink)
          .focused($isFocused)
          .frame(width: 176)
          .padding(.trailing, 10)
          .onExitCommand(perform: close)
          .onAppear { isFocused = true }
          .transition(.opacity)
          .accessibilityLabel("Search transcriptions")
      }
    }
    .background(
      isOpen ? Design.raised : .clear,
      in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
    )
    .clipShape(RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous))
    .animation(Motion.snappy, value: isOpen)
    .onChange(of: isFocused) { _, focused in
      if !focused, query.trimmingCharacters(in: .whitespaces).isEmpty { close() }
    }
  }

  private func close() {
    query = ""
    isFocused = false
    isOpen = false
  }
}

/// One transcription in the list: when it was dictated, the start of its text, its
/// voiceprint, and how long it is. Under the pointer, the voiceprint gives way to buttons
/// that copy the text and play the recording. One that failed can be tried again.
private struct TranscriptionRow: View {
  let transcription: Transcription
  let history: HistoryStore
  let shared: Namespace.ID
  /// Whether the row owns what it shares with its page: unless the page is open.
  let isSource: Bool
  /// Whether its page is open: the text is then set at the size the page reads it at, to
  /// shrink back from it.
  let isOpened: Bool
  let isFresh: Bool
  let isRetrying: Bool
  let open: () -> Void
  let play: () -> Void
  let retry: () -> Void
  let remove: () -> Void

  @State private var isHovered = false
  @State private var didCopy = false
  @State private var levels: [Double] = []

  private var id: Transcription.ID { transcription.id }
  private var hasText: Bool { !transcription.text.isEmpty }

  var body: some View {
    HStack(alignment: .top, spacing: Design.loose) {
      Button(action: open) {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
          Text(transcription.date.time)
            .font(.voiceMono(12))
            .foregroundStyle(Design.ink3)
            .frame(width: Date.usesTwelveHours ? 62 : 44, alignment: .leading)
            .shared(.time(id), in: shared, isSource: isSource, isText: true)
          Text(hasText ? transcription.text : "Not transcribed")
            .font(.voiceRow)
            .lineSpacing(4)
            .lineLimit(2)
            .multilineTextAlignment(.leading)
            .foregroundStyle(hasText ? Design.ink : Design.ink2)
            .frame(maxWidth: .infinity, alignment: .leading)
            .scaleEffect(
              isOpened ? TranscriptionPage.readingSize / 15 : 1, anchor: .topLeading
            )
            .shared(.text(id), in: shared, isSource: isSource, isText: true)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .pointer()
      .accessibilityLabel(
        "\(transcription.date.time), \(hasText ? transcription.text : "Not transcribed")"
      )
      .accessibilityHint("Opens the transcription")
      side
    }
    .padding(.horizontal, Design.large)
    .padding(.vertical, 13)
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Design.raised)
        .opacity(isFresh ? 1 : 0)
        .animation(isFresh ? nil : .easeOut(duration: 1.4), value: isFresh)
    }
    .background {
      RoundedRectangle(cornerRadius: 12, style: .continuous)
        .fill(Design.raised)
        .opacity(isHovered ? 1 : 0)
        .animation(Motion.hover, value: isHovered)
    }
    .onHover { isHovered = $0 }
    .contextMenu {
      if hasText { Button("Copy", action: copy) }
      Button("Delete", role: .destructive, action: remove)
    }
    .task(id: id) {
      levels = await history.voiceprint(of: id, count: 18) ?? []
    }
  }

  private var side: some View {
    HStack(spacing: Design.medium) {
      if transcription.failed {
        Group {
          if isRetrying {
            ProgressView()
              .controlSize(.small)
              .frame(width: 26, height: 26)
          } else {
            Button(action: retry) {
              Label("Try again", systemImage: "arrow.clockwise")
                .labelStyle(.titleAndIcon)
            }
            .buttonStyle(QuietButtonStyle())
            .pointer()
          }
        }
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
      } else {
        ZStack(alignment: .trailing) {
          VoiceprintView(levels: levels)
            .frame(width: 70, height: 18)
            .shared(.voiceprint(id), in: shared, isSource: isSource)
            .opacity(isHovered ? 0 : 1)
          HStack(spacing: 2) {
            if hasText {
              IconButton(symbol: didCopy ? "checkmark" : "doc.on.doc", help: "Copy", action: copy)
            }
            IconButton(symbol: "play.fill", help: "Play", action: play)
          }
          .opacity(isHovered ? 1 : 0)
          .allowsHitTesting(isHovered)
        }
        .frame(width: 70, alignment: .trailing)
        .animation(Motion.hover, value: isHovered)
      }
      Text(transcription.clock)
        .font(.voiceMono(11.5))
        .foregroundStyle(Design.ink3)
        .frame(minWidth: 28, alignment: .trailing)
        .shared(.duration(id), in: shared, isSource: isSource, isText: true)
    }
    .frame(height: 24)
    .animation(Motion.snappy, value: isRetrying)
  }

  private func copy() {
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(transcription.text, forType: .string)
    didCopy = true
    Task {
      try? await Task.sleep(for: .seconds(1.2))
      didCopy = false
    }
  }
}
