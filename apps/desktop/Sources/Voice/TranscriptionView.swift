import SwiftUI
import VoiceCore

/// The page of one transcription: all of its text, to read and select, and its recording,
/// to listen to. One that failed can be tried again from here.
struct TranscriptionView: View {
  let transcription: Transcription
  /// The file of the recording, if it was kept.
  let recording: URL?
  let isRetrying: Bool
  let retry: () -> Void

  @State private var player = Player()

  var body: some View {
    ScrollView {
      VStack(alignment: .leading, spacing: Design.large) {
        Text(summary)
          .font(.voiceCaption)
          .foregroundStyle(.secondary)
        if recording != nil {
          // The button's icon, not its edge, lines up with the text.
          PlayerBar(player: player)
            .padding(.leading, -Design.small)
        }
        if transcription.failed { failure }
        if !transcription.text.isEmpty {
          Text(transcription.text)
            .font(.voiceBody)
            .lineSpacing(3)
            .textSelection(.enabled)
            .pointer(.text)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
      }
      .padding(Design.wide)
    }
    .onChange(of: recording, initial: true) { player.load(recording) }
    .onDisappear { player.stop() }
  }

  /// When it was dictated, how long the recording is, and how many words it has.
  private var summary: String {
    var parts = [transcription.date.dateAndTime, transcription.clock]
    if !transcription.text.isEmpty {
      parts.append(transcription.words == 1 ? "1 word" : "\(transcription.words) words")
    }
    return parts.joined(separator: "  ·  ")
  }

  /// What went wrong, and the way to try again when there is a recording to try with.
  private var failure: some View {
    HStack(spacing: Design.small) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(.secondary)
      Text(transcription.text.isEmpty ? "Not transcribed" : "Typed as heard, not refined")
      Spacer(minLength: Design.small)
      if isRetrying {
        ProgressView()
          .controlSize(.small)
      } else if recording != nil {
        Button("Try Again", action: retry)
          .pointer()
      }
    }
    .font(.voiceBody)
    .padding(.horizontal, Design.medium)
    .frame(minHeight: 40)
    .background(
      Design.surface, in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
    )
  }
}

/// Plays a recording: a button, how far into it the player is, and the times.
private struct PlayerBar: View {
  let player: Player

  var body: some View {
    HStack(spacing: Design.small) {
      IconButton(
        symbol: player.isPlaying ? "pause.fill" : "play.fill",
        help: player.isPlaying ? "Pause" : "Play", action: player.toggle
      )
      .keyboardShortcut(.space, modifiers: [])
      GeometryReader { bar in
        let fraction = player.duration > 0 ? player.time / player.duration : 0
        ZStack(alignment: .leading) {
          Capsule().fill(Design.selected)
          Capsule().fill(.secondary).frame(width: max(4, bar.size.width * fraction))
        }
        .frame(height: 4)
        .frame(maxHeight: .infinity)
        .contentShape(Rectangle())
        .gesture(
          DragGesture(minimumDistance: 0).onChanged { drag in
            player.seek(to: drag.location.x / bar.size.width)
          })
      }
      .frame(height: Design.control)
      .pointer()
      Text("\(clock(player.time)) / \(clock(player.duration))")
        .font(.voiceCaption)
        .monospacedDigit()
        .foregroundStyle(.secondary)
    }
  }

  private func clock(_ seconds: TimeInterval) -> String {
    let seconds = Int(seconds.rounded())
    return "\(seconds / 60):" + (seconds % 60 < 10 ? "0" : "") + "\(seconds % 60)"
  }
}
