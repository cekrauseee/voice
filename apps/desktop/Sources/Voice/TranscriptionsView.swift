import AppKit
import SwiftUI
import VoiceCore

/// The past transcriptions, day by day, newest first. Clicking one opens its page.
struct TranscriptionsView: View {
  let history: History
  let pushToTalk: Shortcut
  let open: (Transcription.ID) -> Void
  let remove: (Transcription.ID) -> Void

  var body: some View {
    if history.isEmpty {
      empty
    } else {
      ScrollView {
        LazyVStack(alignment: .leading, spacing: Design.loose) {
          ForEach(history.days(in: .current)) { day in
            VStack(alignment: .leading, spacing: Design.small) {
              GroupTitle(title: day.date.dayTitle)
              Card {
                ForEach(day.transcriptions) { transcription in
                  if transcription.id != day.transcriptions.first?.id { Hairline() }
                  TranscriptionRow(transcription: transcription) {
                    open(transcription.id)
                  } remove: {
                    remove(transcription.id)
                  }
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
}

/// One transcription in the list: when it was typed, the start of its text, and how long
/// the recording was. Under the pointer, the length gives way to a button that copies it.
private struct TranscriptionRow: View {
  let transcription: Transcription
  let open: () -> Void
  let remove: () -> Void

  @State private var isHovered = false
  @State private var didCopy = false

  var body: some View {
    Button(action: open) {
      HStack(alignment: .firstTextBaseline, spacing: Design.medium) {
        Text(transcription.date.formatted(date: .omitted, time: .shortened))
          .font(.voiceCaption)
          .monospacedDigit()
          .foregroundStyle(.secondary)
          .frame(width: 36, alignment: .leading)
        Text(transcription.text)
          .font(.voiceBody)
          .lineLimit(3)
          .multilineTextAlignment(.leading)
          .frame(maxWidth: .infinity, alignment: .leading)
        Text(transcription.clock)
          .font(.voiceCaption)
          .monospacedDigit()
          .foregroundStyle(.tertiary)
          .opacity(isHovered ? 0 : 1)
      }
      .padding(.horizontal, Design.medium)
      .padding(.vertical, 10)
      .background(isHovered ? Design.hover : .clear)
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointer()
    .overlay(alignment: .topTrailing) {
      if isHovered {
        Button(action: copy) {
          Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .frame(width: 24, height: 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .pointer()
        .help("Copy")
        .padding(.top, 6)
        .padding(.trailing, Design.small)
      }
    }
    .onHover { isHovered = $0 }
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
