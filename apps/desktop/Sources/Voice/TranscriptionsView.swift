import AppKit
import SwiftUI
import VoiceCore

/// The past transcriptions, day by day, newest first.
struct TranscriptionsView: View {
  let history: History
  let pushToTalk: Shortcut
  let remove: (Transcription.ID) -> Void

  var body: some View {
    if history.isEmpty {
      empty
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Design.loose) {
          ForEach(history.days(in: .current)) { day in
            VStack(alignment: .leading, spacing: Design.small) {
              GroupTitle(title: title(of: day.date))
              Card {
                ForEach(day.transcriptions) { transcription in
                  if transcription.id != day.transcriptions.first?.id { Hairline() }
                  TranscriptionRow(transcription: transcription) { remove(transcription.id) }
                }
              }
            }
          }
        }
        .padding(.horizontal, Design.wide)
        .padding(.vertical, Design.large)
      }
    }
  }

  private var empty: some View {
    VStack(spacing: Design.small) {
      Image(systemName: "text.quote")
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.tertiary)
      Text("No transcriptions yet")
        .font(.voiceTitle)
      HStack(spacing: 5) {
        Text("Hold")
        KeyCaps(labels: pushToTalk.keyCaps)
        Text("and speak")
      }
      .font(.voiceCaption)
      .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func title(of day: Date) -> String {
    let calendar = Calendar.current
    if calendar.isDateInToday(day) { return "Today" }
    if calendar.isDateInYesterday(day) { return "Yesterday" }
    // In English, like the rest of the app, whatever language the Mac is in.
    let isThisYear = calendar.isDate(day, equalTo: .now, toGranularity: .year)
    let format = Date.FormatStyle(locale: Locale(identifier: "en_US"))
      .weekday(.wide).day().month(.wide)
    return day.formatted(isThisYear ? format : format.year())
  }
}

/// One transcription: when it was typed, its text, and how long the recording was.
///
/// The text is cut at three lines. Clicking the row shows all of it, to read or select.
private struct TranscriptionRow: View {
  let transcription: Transcription
  let remove: () -> Void

  @State private var isHovered = false
  @State private var isExpanded = false
  @State private var didCopy = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: Design.medium) {
      Text(transcription.date.formatted(date: .omitted, time: .shortened))
        .font(.voiceCaption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 36, alignment: .leading)
      text
        .font(.voiceBody)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(transcription.clock)
        .font(.voiceCaption)
        .monospacedDigit()
        .foregroundStyle(.tertiary)
        .opacity(isHovered ? 0 : 1)
        .overlay(alignment: .trailing) {
          if isHovered {
            Button(action: copy) {
              Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .font(.system(size: 11))
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .pointer()
            .help("Copy")
            .transition(.opacity)
          }
        }
    }
    .padding(.horizontal, Design.medium)
    .padding(.vertical, 10)
    .background(isHovered ? Design.hover : .clear)
    .contentShape(Rectangle())
    .onTapGesture { isExpanded.toggle() }
    .pointer()
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .animation(Design.morph, value: isExpanded)
    .contextMenu {
      Button("Copy", action: copy)
      Button("Delete", role: .destructive, action: remove)
    }
  }

  @ViewBuilder private var text: some View {
    if isExpanded {
      Text(transcription.text).textSelection(.enabled).pointer(.text)
    } else {
      Text(transcription.text).lineLimit(3)
    }
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
