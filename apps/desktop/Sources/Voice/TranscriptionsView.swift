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
        LazyVStack(alignment: .leading, spacing: 22) {
          ForEach(history.days(in: .current)) { day in
            VStack(alignment: .leading, spacing: 8) {
              Text(title(of: day.date))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)
                .padding(.leading, 12)
              VStack(spacing: 0) {
                ForEach(day.transcriptions) { transcription in
                  if transcription.id != day.transcriptions.first?.id {
                    Divider().padding(.leading, 12)
                  }
                  TranscriptionRow(transcription: transcription) { remove(transcription.id) }
                }
              }
              .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            }
          }
        }
        .padding(20)
      }
    }
  }

  private var empty: some View {
    VStack(spacing: 10) {
      Image(systemName: "text.quote")
        .font(.system(size: 28, weight: .medium))
        .foregroundStyle(.tertiary)
      Text("No transcriptions yet")
        .font(.headline)
      HStack(spacing: 5) {
        Text("Hold")
        KeyCaps(labels: pushToTalk.keyCaps)
        Text("and speak")
      }
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

private struct TranscriptionRow: View {
  let transcription: Transcription
  let remove: () -> Void

  @State private var isHovered = false
  @State private var didCopy = false

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 12) {
      Text(transcription.date.formatted(date: .omitted, time: .shortened))
        .monospacedDigit()
        .foregroundStyle(.secondary)
        .frame(width: 44, alignment: .leading)
      Text(transcription.text)
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
      Text(transcription.clock)
        .monospacedDigit()
        .foregroundStyle(.tertiary)
        .opacity(isHovered ? 0 : 1)
        .overlay(alignment: .trailing) {
          if isHovered {
            Button(action: copy) {
              Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                .contentTransition(.symbolEffect(.replace))
            }
            .buttonStyle(.borderless)
            .help("Copy")
            .transition(.opacity)
          }
        }
    }
    .font(.callout)
    .padding(.horizontal, 12)
    .padding(.vertical, 10)
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .animation(.easeOut(duration: 0.12), value: isHovered)
    .contextMenu {
      Button("Copy", action: copy)
      Button("Delete", role: .destructive, action: remove)
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
