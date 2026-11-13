import AppKit
import SwiftUI
import VoiceCore

/// What clicking Voice in the menu bar shows: whether it is listening, today's words, the
/// last transcriptions to copy, and the ways into the window.
struct MenuBarPanel: View {
  let controller: DictationController
  let settings: Settings
  let permissions: Permissions
  let statistics: StatisticsStore
  let history: HistoryStore
  let open: (Page) -> Void
  let openSetup: () -> Void

  private var needsSetup: Bool {
    !settings.hasOnboarded || !permissions.isComplete
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      status
      today
      recent
      Rectangle()
        .fill(Design.line)
        .frame(height: 1)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
      if needsSetup {
        Item(title: "Finish Setup…", shortcut: nil, action: openSetup)
      }
      Item(title: "Open \(AppInfo.name)", shortcut: "⌘O") { open(.transcriptions) }
        .keyboardShortcut("o")
      Item(title: "Settings…", shortcut: "⌘,") { open(.settings) }
        .keyboardShortcut(",")
      Item(title: "Quit \(AppInfo.name)", shortcut: "⌘Q") { NSApp.terminate(nil) }
        .keyboardShortcut("q")
    }
    .padding(6)
    .frame(width: 340)
    // Up into the popover's arrow, which takes the same ground.
    .background(Design.ground)
  }

  /// Ready, or what the dictation is doing, and the shortcut to dictate.
  private var status: some View {
    HStack {
      HStack(spacing: 9) {
        Lamp(isLit: controller.pill == .listening)
          .opacity(controller.pill == .hidden ? 0.5 : 1)
        Text(statusTitle)
          .font(.voiceTitle)
          .foregroundStyle(Design.ink)
          .contentTransition(.interpolate)
        if controller.pill.isRecording, let start = controller.recordingStarted {
          TimelineView(.periodic(from: start, by: 1)) { context in
            Text(
              Duration.seconds(context.date.timeIntervalSince(start)).formatted(
                .time(pattern: .minuteSecond))
            )
            .font(.voiceMono(12))
            .foregroundStyle(Design.ink3)
          }
        }
      }
      Spacer(minLength: Design.small)
      HStack(spacing: 6) {
        Text(controller.pill.isRecording && controller.mode == .push ? "Release" : "Hold")
        KeyCaps(labels: settings.pushToTalk.keyCaps)
          .foregroundStyle(Design.ink)
      }
      .font(.voiceCaption)
      .foregroundStyle(Design.ink2)
    }
    .padding(EdgeInsets(top: 10, leading: 10, bottom: 12, trailing: 10))
    .animation(Motion.snappy, value: controller.pill)
  }

  private var statusTitle: String {
    switch controller.pill {
    case .hidden: "Ready"
    case .starting: "Starting"
    case .listening: "Listening"
    case .finishing: "Finishing"
    case .failed(let error): error.message
    }
  }

  /// Today's words, and the week's bars. Clicking them opens the statistics.
  private var today: some View {
    let tally = statistics.statistics.total(.today, now: .now, in: .current)
    let week = statistics.statistics.bars(.week, now: .now, in: .current)
    let most = max(week.map(\.tally.words).max() ?? 0, 1)
    return Button {
      open(.statistics)
    } label: {
      HStack(alignment: .bottom) {
        VStack(alignment: .leading, spacing: 6) {
          Text(Figure.count(tally.words))
            .font(.voiceMono(30, weight: .medium))
            .tracking(-1.3)
            .foregroundStyle(Design.ink)
            .contentTransition(.numericText(value: Double(tally.words)))
          Text("words today")
            .font(.voiceCaption)
            .foregroundStyle(Design.ink2)
        }
        Spacer(minLength: Design.small)
        HStack(alignment: .bottom, spacing: 5) {
          ForEach(Array(week.enumerated()), id: \.element.id) { index, bar in
            RoundedRectangle(cornerRadius: 2, style: .continuous)
              .fill(index == week.count - 1 ? Design.signal : Design.bar)
              .frame(width: 7, height: max(3, 36 * Double(bar.tally.words) / Double(most)))
          }
        }
        .frame(height: 36, alignment: .bottom)
      }
      .padding(EdgeInsets(top: 12, leading: 12, bottom: 14, trailing: 12))
      .background(
        Design.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous)
      )
      .contentShape(Rectangle())
      .animation(Motion.snappy, value: tally.words)
    }
    .buttonStyle(.plain)
    .pointer()
    .accessibilityLabel("\(Figure.count(tally.words)) words today. Open statistics")
  }

  /// The last three transcriptions, each with a button that copies it.
  @ViewBuilder private var recent: some View {
    let recent = history.history.transcriptions.filter { !$0.text.isEmpty }.prefix(3)
    if !recent.isEmpty {
      Text("Recent")
        .font(.voiceLabel)
        .foregroundStyle(Design.ink2)
        .padding(EdgeInsets(top: 14, leading: 10, bottom: 6, trailing: 10))
      ForEach(recent) { transcription in
        RecentRow(transcription: transcription) { open(.transcription(transcription.id)) }
      }
    }
  }
}

/// A transcription in the panel: its time, its first line, and a button that copies it.
private struct RecentRow: View {
  let transcription: Transcription
  let open: () -> Void

  @State private var isHovered = false
  @State private var didCopy = false

  var body: some View {
    HStack(spacing: Design.small) {
      Button(action: open) {
        HStack(spacing: Design.small) {
          Text(transcription.date.time)
            .font(.voiceMono(11.5))
            .foregroundStyle(Design.ink3)
            .frame(width: Date.usesTwelveHours ? 58 : 40, alignment: .leading)
          Text(transcription.text)
            .font(.voiceBody)
            .foregroundStyle(Design.ink)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .contentShape(Rectangle())
      }
      .buttonStyle(.plain)
      .accessibilityLabel(transcription.text)
      IconButton(symbol: didCopy ? "checkmark" : "doc.on.doc", help: "Copy") {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(transcription.text, forType: .string)
        didCopy = true
        Task {
          try? await Task.sleep(for: .seconds(1.2))
          didCopy = false
        }
      }
    }
    .padding(.leading, 10)
    .padding(.trailing, 2)
    .frame(height: 36)
    .background(
      isHovered ? Design.hover : .clear,
      in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
    )
    .animation(Motion.hover, value: isHovered)
    .onHover { isHovered = $0 }
  }
}

/// An item of the panel, with its shortcut, like an item of a menu.
private struct Item: View {
  let title: String
  let shortcut: String?
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      HStack {
        Text(title)
          .font(.voiceBody)
          .foregroundStyle(Design.ink)
        Spacer(minLength: Design.small)
        if let shortcut {
          Text(shortcut)
            .font(.voiceMono(11.5))
            .foregroundStyle(Design.ink3)
        }
      }
      .padding(.horizontal, 10)
      .frame(height: 30)
      .background(
        isHovered ? Design.hover : .clear,
        in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
      )
      .contentShape(Rectangle())
      .animation(Motion.hover, value: isHovered)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
  }
}
