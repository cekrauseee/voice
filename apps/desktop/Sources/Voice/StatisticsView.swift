import SwiftUI
import VoiceCore

/// How much was dictated in a period, what it cost, and the words of each day, or of each
/// hour of today.
struct StatisticsView: View {
  let statistics: Statistics
  let period: Statistics.Period

  /// The bar under the pointer.
  @State private var hovered: Statistics.Bar.ID?

  var body: some View {
    let total = statistics.total(period, now: .now, in: .current)
    let bars = statistics.bars(period, now: .now, in: .current)
    VStack(alignment: .leading, spacing: Design.loose) {
      Grid(alignment: .leading, horizontalSpacing: Design.large, verticalSpacing: Design.wide) {
        GridRow {
          Figured(value: Figure.count(total.words), title: "Words")
          Figured(
            value: total.wordsPerMinute.map(Figure.count) ?? "–", title: "Words per minute")
          Figured(value: Figure.count(total.dictations), title: "Dictations")
        }
        GridRow {
          Figured(value: Figure.time(total.seconds), title: "Time speaking")
          Figured(value: Figure.count(total.tokens), title: "Tokens")
            .help(
              "\(Figure.count(total.inputTokens)) read, \(Figure.count(total.outputTokens)) written"
            )
          Figured(value: Figure.cost(total.cost), title: "Estimated cost")
            .help("At the prices set on the server")
        }
      }
      chart(bars)
    }
    .padding(.horizontal, Design.wide)
    .padding(.top, Design.medium)
    .padding(.bottom, Design.wide)
    .frame(maxHeight: .infinity, alignment: .top)
    // A bar of another period is another bar.
    .onChange(of: period) { hovered = nil }
  }

  /// The words of each day, and under the pointer the day and its words.
  private func chart(_ bars: [Statistics.Bar]) -> some View {
    let most = max(bars.map(\.tally.words).max() ?? 0, 1)
    let pointed = bars.first { $0.id == hovered }
    return VStack(alignment: .leading, spacing: Design.small) {
      HStack {
        Text(heading(bars.first?.unit ?? .day))
          .foregroundStyle(.secondary)
        Spacer(minLength: Design.small)
        if let pointed {
          Text("\(title(of: pointed))  ·  \(words(pointed.tally.words))")
            .foregroundStyle(.secondary)
        }
      }
      .font(.voiceLabel)
      // The chart takes the height the page has left.
      GeometryReader { area in
        HStack(alignment: .bottom, spacing: bars.count > 14 ? 2 : Design.tight) {
          ForEach(bars) { bar in
            let height = area.size.height * Double(bar.tally.words) / Double(most)
            // A day without words still has its place: a mark on the floor.
            RoundedRectangle(cornerRadius: bars.count > 14 ? 2 : 3, style: .continuous)
              .fill(
                bar.tally.words == 0
                  ? Design.selected : bar.id == hovered ? Design.barHover : Design.bar
              )
              .frame(height: max(height, 2))
              .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
              .contentShape(Rectangle())
              .onHover { inside in
                if inside { hovered = bar.id } else if hovered == bar.id { hovered = nil }
              }
              .accessibilityElement()
              .accessibilityLabel("\(title(of: bar)), \(words(bar.tally.words))")
          }
        }
      }
      .frame(minHeight: 60, maxHeight: Chart.tallest)
      HStack {
        Text(bars.first.map(title) ?? "")
        Spacer(minLength: Design.small)
        Text(bars.last.map(end) ?? "")
      }
      .font(.voiceCaption)
      .foregroundStyle(.tertiary)
    }
  }

  private func heading(_ unit: Statistics.Bar.Unit) -> String {
    switch unit {
    case .hour: "Words per hour"
    case .day: "Words per day"
    case .month: "Words per month"
    }
  }

  /// The hour, the day, or the month of a bar, such as `09:00`, `Nov 12`, or
  /// `November 2026`.
  private func title(of bar: Statistics.Bar) -> String {
    let format = Date.FormatStyle(locale: Locale(identifier: "en_US"))
    switch bar.unit {
    case .hour:
      let hour = Calendar.current.component(.hour, from: bar.start)
      return "\(hour < 10 ? "0" : "")\(hour):00"
    case .day: return bar.start.formatted(format.month(.abbreviated).day())
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

private enum Chart {
  /// How tall the tallest bar gets.
  static let tallest = 220.0
}

/// A figure, with what it counts under it.
private struct Figured: View {
  let value: String
  let title: String

  var body: some View {
    VStack(alignment: .leading, spacing: 2) {
      Text(value)
        .font(.voiceFigure)
      Text(title)
        .font(.voiceCaption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
    .accessibilityElement(children: .combine)
  }
}
