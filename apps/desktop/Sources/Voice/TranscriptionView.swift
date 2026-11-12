import SwiftUI
import VoiceCore

/// The page of one transcription: all of its text, to read and select, what is known about
/// it, and what was heard before it was refined.
struct TranscriptionView: View {
  let transcription: Transcription

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Design.loose) {
        Card { text(transcription.text) }

        group("Details") {
          DetailRow(name: "Date", value: transcription.date.dateAndTime)
          Hairline()
          DetailRow(name: "Length", value: transcription.clock)
          Hairline()
          DetailRow(name: "Words", value: "\(transcription.words)")
        }

        if let heard = transcription.heard {
          group("As heard") {
            text(heard).foregroundStyle(.secondary)
          }
        }
      }
      .padding(.horizontal, Design.wide)
      .padding(.vertical, Design.large)
    }
  }

  private func text(_ text: String) -> some View {
    Text(text)
      .font(.voiceBody)
      .textSelection(.enabled)
      .pointer(.text)
      .frame(maxWidth: .infinity, alignment: .leading)
      .padding(.horizontal, Design.medium)
      .padding(.vertical, 10)
  }

  private func group(_ title: String, @ViewBuilder rows: () -> some View) -> some View {
    VStack(alignment: .leading, spacing: Design.small) {
      GroupTitle(title: title)
      Card(content: rows)
    }
  }
}

/// Something known about a transcription: its name, and its value.
private struct DetailRow: View {
  let name: String
  let value: String

  var body: some View {
    HStack(spacing: Design.medium) {
      Text(name)
      Spacer(minLength: Design.medium)
      Text(value)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
    .font(.voiceBody)
    .padding(.horizontal, Design.medium)
    .frame(minHeight: 36)
  }
}
