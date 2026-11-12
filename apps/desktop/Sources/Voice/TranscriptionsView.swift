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
        LazyVStack(alignment: .leading, spacing: Design.wide) {
          ForEach(history.days(in: .current)) { day in
            VStack(alignment: .leading, spacing: 2) {
              GroupTitle(title: day.date.dayTitle)
                .padding(.bottom, Design.tight)
              ForEach(day.transcriptions) { transcription in
                TranscriptionRow(transcription: transcription) {
                  open(transcription.id)
                } remove: {
                  remove(transcription.id)
                }
              }
            }
          }
        }
        .padding(Design.medium)
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

/// One transcription in the list: when it was dictated, the start of its text, and how
/// long the recording was. Under the pointer, the length gives way to a button that copies
/// the text.
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
        Group {
          if transcription.text.isEmpty {
            Text("Not transcribed").foregroundStyle(.secondary)
          } else {
            Text(transcription.text)
          }
        }
        .font(.voiceBody)
        .lineLimit(3)
        .multilineTextAlignment(.leading)
        .frame(maxWidth: .infinity, alignment: .leading)
        HStack(spacing: Design.tight) {
          if transcription.failed {
            Image(systemName: "exclamationmark.triangle")
              .help("This dictation failed")
          }
          Text(transcription.clock)
            .monospacedDigit()
        }
        .font(.voiceCaption)
        .foregroundStyle(.tertiary)
        .opacity(isHovered && canCopy ? 0 : 1)
      }
      .padding(Design.small)
      .background(
        isHovered ? Design.hover : .clear,
        in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
      )
      .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointer()
    .overlay(alignment: .topTrailing) {
      if isHovered && canCopy {
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
        .padding(.top, 4)
        .padding(.trailing, Design.tight)
      }
    }
    .onHover { isHovered = $0 }
    .contextMenu {
      if canCopy { Button("Copy", action: copy) }
      Button("Delete", role: .destructive, action: remove)
    }
  }

  private var canCopy: Bool {
    !transcription.text.isEmpty
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
