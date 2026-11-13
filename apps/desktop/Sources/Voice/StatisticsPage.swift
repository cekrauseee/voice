import SwiftUI
import VoiceCore

/// How much was dictated in a period, how fast, and what it cost, with the words of each
/// day, of each hour of today, or of each month.
///
/// It opens out of today's figures over the list: the words and the week's bars travel
/// into the figures and the chart of the last 7 days, and back.
struct StatisticsPage: View {
  let statistics: Statistics
  let navigation: Navigation
  let shared: Namespace.ID

  /// The sizes of the words and of the label under them, which today's figures travel to.
  static let figureSize = 40.0
  static let labelSize = 12.0

  @State private var period = Statistics.Period.week
  /// Whether the period was changed since the page opened: new bars then grow in.
  @State private var isPeriodChanged = false
  @State private var hovered: Statistics.Bar.ID?

  private var isOpen: Bool { navigation.isOpen }

  var body: some View {
    let total = statistics.total(period, now: .now, in: .current)
    let bars = statistics.bars(period, now: .now, in: .current)
    VStack(spacing: 0) {
      TitleBar {
        BackButton(title: "Statistics") { navigation.back() }
          .pagePart(isOpen: isOpen)
      } trailing: {
        Segmented(
          options: Statistics.Period.allCases.map { ($0, $0.title) },
          selection: Binding {
            period
          } set: { new in
            isPeriodChanged = true
            hovered = nil
            withAnimation(Motion.snappy) { period = new }
          }
        )
        .pagePart(isOpen: isOpen)
      }
      VStack(alignment: .leading, spacing: 0) {
        figures(total)
        chart(bars)
          .padding(.top, 38)
        Spacer(minLength: Design.loose)
        secondary(total)
          .pagePart(isOpen: isOpen)
      }
      .padding(.horizontal, 48)
      .padding(.top, 10)
      .padding(.bottom, 36)
    }
    .task { navigation.present() }
  }

  private func figures(_ total: Tally) -> some View {
    let dock = navigation.dockProgress
    // On the way in and out, the words are set at the size today's figures are seen at.
    let figureFrom = 52 * HeaderDock.blend(1, 18.0 / 52, by: dock) / Self.figureSize
    let labelFrom = 15 * HeaderDock.blend(1, 12.5 / 15, by: dock) / Self.labelSize
    return HStack(alignment: .top, spacing: Design.loose) {
      VStack(alignment: .leading, spacing: Design.small) {
        figure(Figure.count(total.words))
          .scaleEffect(isOpen ? 1 : figureFrom, anchor: .topLeading)
          .shared(.figure, in: shared, isSource: isOpen, isText: true)
          .sharedPart(isOpen: isOpen)
        Text("Words")
          .font(.system(size: Self.labelSize))
          .foregroundStyle(Design.ink2)
          .scaleEffect(isOpen ? 1 : labelFrom, anchor: .topLeading)
          .shared(.unit, in: shared, isSource: isOpen, isText: true)
          .sharedPart(isOpen: isOpen)
      }
      .frame(maxWidth: .infinity, alignment: .leading)
      Figured(value: total.wordsPerMinute.map(Figure.count) ?? "–", title: "Words per minute")
        .pagePart(isOpen: isOpen)
      Figured(value: Figure.time(total.seconds), title: "Time speaking")
        .pagePart(isOpen: isOpen)
    }
  }

  /// The words of each bar, and under the pointer the bar's day and its words.
  private func chart(_ bars: [Statistics.Bar]) -> some View {
    let pointed = bars.first { $0.id == hovered }
    let sharesBars = period == .week && bars.count == 7
    return VStack(alignment: .leading, spacing: 10) {
      HStack {
        Text(heading(bars.first?.unit ?? .day))
          .font(.voiceLabel)
          .foregroundStyle(Design.ink2)
          .contentTransition(.interpolate)
        Spacer(minLength: Design.small)
        if let pointed {
          Text("\(title(of: pointed))  ·  \(words(pointed.tally.words))")
            .font(.voiceMono(12))
            .foregroundStyle(Design.ink)
        }
      }
      .frame(height: 16)
      .pagePart(isOpen: isOpen)
      ChartBars(
        bars: bars, hovered: $hovered, growsIn: isPeriodChanged, sharesBars: sharesBars,
        isOpen: isOpen, shared: shared
      )
      .id(period)
      .transition(.opacity.animation(Motion.leave))
      .frame(height: 180)
      .overlay(alignment: .bottom) {
        Rectangle()
          .fill(Design.line)
          .frame(height: 1)
          .pagePart(isOpen: isOpen)
      }
      HStack {
        Text(bars.first.map(title) ?? "")
        Spacer(minLength: Design.small)
        Text(bars.last.map(end) ?? "")
      }
      .font(.voiceMono(11))
      .foregroundStyle(Design.ink3)
      .pagePart(isOpen: isOpen)
    }
  }

  private func secondary(_ total: Tally) -> some View {
    HStack(alignment: .top, spacing: Design.loose) {
      Figured(value: Figure.count(total.dictations), title: "Dictations", size: 18)
      Figured(value: Figure.count(total.tokens), title: "Tokens", size: 18)
        .help(
          "\(Figure.count(total.inputTokens)) read, \(Figure.count(total.outputTokens)) written")
      Figured(value: Figure.cost(total.cost), title: "Estimated cost", size: 18)
        .help("At the prices set on the server")
    }
    .padding(.top, Design.wide)
    .overlay(alignment: .top) {
      Rectangle().fill(Design.line).frame(height: 1)
    }
  }

  private func figure(_ value: String) -> some View {
    Text(value)
      .font(.voiceMono(Self.figureSize, weight: .medium))
      .tracking(-1.8)
      .foregroundStyle(Design.ink)
      .contentTransition(.numericText())
      .fixedSize()
  }

  private func heading(_ unit: Statistics.Bar.Unit) -> String {
    switch unit {
    case .hour: "Words per hour"
    case .day: "Words per day"
    case .month: "Words per month"
    }
  }

  /// The hour, the day, or the month of a bar, such as `09:00`, `Thu, Nov 12`, or
  /// `November 2026`.
  private func title(of bar: Statistics.Bar) -> String {
    let format = Date.FormatStyle(locale: Locale(identifier: "en_US"))
    switch bar.unit {
    case .hour:
      let hour = Calendar.current.component(.hour, from: bar.start)
      return "\(hour < 10 ? "0" : "")\(hour):00"
    case .day: return bar.start.formatted(format.weekday(.abbreviated).month(.abbreviated).day())
    case .month: return bar.start.formatted(format.month(.wide).year())
    }
  }

  /// What the last bar is called under the chart.
  private func end(_ bar: Statistics.Bar) -> String {
    switch bar.unit {
    case .hour: title(of: bar)
    case .day: "Today"
    case .month: "This month"
    }
  }

  private func words(_ count: Int) -> String {
    count == 1 ? "1 word" : "\(Figure.count(count)) words"
  }
}

/// The bars of a period. The last one, now, is in the signal, and the one under the pointer
/// in ink. When the period changes, the new bars grow in from the left.
private struct ChartBars: View {
  let bars: [Statistics.Bar]
  @Binding var hovered: Statistics.Bar.ID?
  let growsIn: Bool
  /// Whether these are the week's bars that travel from today's figures.
  let sharesBars: Bool
  let isOpen: Bool
  let shared: Namespace.ID

  @State private var isGrown = false
  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    let most = max(bars.map(\.tally.words).max() ?? 0, 1)
    let gap = bars.count > 14 ? 3.0 : bars.count > 8 ? 10 : 16
    let step = min(0.014, 0.22 / Double(max(bars.count, 1)))
    HStack(alignment: .bottom, spacing: gap) {
      ForEach(Array(bars.enumerated()), id: \.element.id) { index, bar in
        RoundedRectangle(cornerRadius: bars.count > 14 ? 2 : 4, style: .continuous)
          .fill(color(of: bar, isLast: index == bars.count - 1))
          .frame(
            height: bar.tally.words == 0 ? 3 : max(4, 176 * Double(bar.tally.words) / Double(most))
          )
          .scaleEffect(y: isGrown || !growsIn ? 1 : 0.001, anchor: .bottom)
          .animation(
            reduceMotion ? nil : Motion.settle.delay(0.1 + Double(index) * step), value: isGrown
          )
          .modifier(SharedBar(index: index, isShared: sharesBars, isOpen: isOpen, shared: shared))
          .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
          .contentShape(Rectangle())
          .onHover { inside in
            if inside { hovered = bar.id } else if hovered == bar.id { hovered = nil }
          }
          .accessibilityElement()
          .accessibilityLabel(
            "\(bar.start.formatted(date: .abbreviated, time: bar.unit == .hour ? .shortened : .omitted)), \(bar.tally.words) words"
          )
      }
    }
    .animation(Motion.hover, value: hovered)
    .onAppear { isGrown = true }
  }

  private func color(of bar: Statistics.Bar, isLast: Bool) -> Color {
    if bar.id == hovered { return Design.ink }
    if isLast { return Design.signal }
    return bar.tally.words == 0 ? Design.line : Design.bar
  }
}

/// A bar of the week, which travels from today's figures.
private struct SharedBar: ViewModifier {
  let index: Int
  let isShared: Bool
  let isOpen: Bool
  let shared: Namespace.ID

  func body(content: Content) -> some View {
    if isShared {
      content
        .shared(.bar(index), in: shared, isSource: isOpen)
        .sharedPart(isOpen: isOpen)
    } else {
      content.pagePart(isOpen: isOpen)
    }
  }
}

/// A figure, with what it counts under it.
private struct Figured: View {
  let value: String
  let title: String
  var size = StatisticsPage.figureSize

  var body: some View {
    VStack(alignment: .leading, spacing: size > 20 ? Design.small : 6) {
      Text(value)
        .font(.voiceMono(size, weight: .medium))
        .tracking(size > 20 ? -1.8 : -0.4)
        .foregroundStyle(Design.ink)
        .contentTransition(.numericText())
      Text(title)
        .font(.system(size: StatisticsPage.labelSize))
        .foregroundStyle(Design.ink2)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
