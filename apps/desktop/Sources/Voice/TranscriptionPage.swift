import AppKit
import SwiftUI
import VoiceCore

/// The page of one transcription: all of its text, to read and select, and its recording,
/// to listen to. One that failed can be tried again from here.
///
/// It opens out of its row: the time, the text, the voiceprint, and the length travel from
/// the row to their places on the page, and back.
struct TranscriptionPage: View {
  let transcription: Transcription
  let navigation: Navigation
  let history: HistoryStore
  let retry: Retry
  let shared: Namespace.ID

  /// The size the text is read at.
  static let readingSize = 20.0

  @State private var player = Player()
  @State private var levels: [Double] = []
  @State private var didCopy = false

  private var id: Transcription.ID { transcription.id }
  private var isOpen: Bool { navigation.isOpen }
  private var hasText: Bool { !transcription.text.isEmpty }

  var body: some View {
    VStack(spacing: 0) {
      TitleBar {
        BackButton(title: nil) { navigation.back() }
          .pagePart(isOpen: isOpen)
      } trailing: {
        HStack(spacing: 2) {
          if hasText {
            IconButton(symbol: didCopy ? "checkmark" : "doc.on.doc", help: "Copy", action: copy)
          }
          IconButton(symbol: "trash", help: "Delete") {
            navigation.back { withAnimation(Motion.settle) { history.remove(id) } }
          }
          .keyboardShortcut(.delete, modifiers: .command)
        }
        .pagePart(isOpen: isOpen)
      }
      ScrollView {
        VStack(alignment: .leading, spacing: 0) {
          header
          playerCard
            .padding(.top, 22)
          if transcription.failed {
            failure
              .padding(.top, 28)
              .pagePart(isOpen: isOpen)
          }
          if hasText {
            text
              .padding(.top, 34)
              .transition(.opacity)
          }
        }
        .padding(.horizontal, 48)
        .padding(.top, 6)
        .padding(.bottom, 40)
        .frame(maxWidth: .infinity, alignment: .leading)
        .animation(Motion.settle, value: transcription.text)
      }
      .scrollIndicators(.automatic)
    }
    .task {
      navigation.present()
      player.load(history.recording(of: id))
      levels = await history.voiceprint(of: id, count: 72) ?? []
      if navigation.playsWhenOpen {
        navigation.playsWhenOpen = false
        try? await Task.sleep(for: .seconds(0.3))
        if !player.isPlaying { player.toggle() }
      }
    }
    .onDisappear { player.stop() }
  }

  /// When it was dictated, how long it is, how many words it has, and how fast they came.
  private var header: some View {
    HStack(alignment: .firstTextBaseline) {
      HStack(alignment: .firstTextBaseline, spacing: Design.tight) {
        Text("\(transcription.date.dayTitle) at")
          .pagePart(isOpen: isOpen)
        Text(transcription.date.time)
          .shared(.time(id), in: shared, isSource: isOpen, isText: true)
          .sharedPart(isOpen: isOpen)
      }
      .font(.voiceTitle)
      .foregroundStyle(Design.ink)
      Spacer(minLength: Design.medium)
      HStack(spacing: Design.large) {
        Text(transcription.clock)
        if hasText {
          Text(transcription.words == 1 ? "1 word" : "\(transcription.words) words")
          if transcription.duration > 0 {
            Text(
              "\(Int((Double(transcription.words) / transcription.duration * 60).rounded())) wpm")
          }
        }
      }
      .font(.voiceMono(12))
      .foregroundStyle(Design.ink3)
      .pagePart(isOpen: isOpen)
    }
  }

  /// The recording: a button, its voiceprint, which shows how far the player is and moves it
  /// when dragged, and the times.
  private var playerCard: some View {
    HStack(spacing: Design.large) {
      Button(action: player.toggle) {
        Image(systemName: player.isPlaying ? "pause.fill" : "play.fill")
          .font(.system(size: 14))
          .foregroundStyle(Design.ground)
          .contentTransition(.symbolEffect(.replace))
          .frame(width: 40, height: 40)
          .background(Design.ink, in: Circle())
          .contentShape(Circle())
      }
      .buttonStyle(.plain)
      .pointer()
      .keyboardShortcut(.space, modifiers: [])
      .help(player.isPlaying ? "Pause" : "Play")
      .accessibilityLabel(player.isPlaying ? "Pause" : "Play")
      .disabled(player.duration == 0)
      .pagePart(isOpen: isOpen)
      VStack(spacing: 6) {
        track
        HStack {
          Text(clock(player.time))
            .pagePart(isOpen: isOpen)
          Spacer()
          Text(transcription.clock)
            .shared(.duration(id), in: shared, isSource: isOpen, isText: true)
            .sharedPart(isOpen: isOpen)
        }
        .font(.voiceMono(11))
        .foregroundStyle(Design.ink3)
      }
    }
    .padding(EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 18))
    .background {
      RoundedRectangle(cornerRadius: 16, style: .continuous)
        .fill(Design.raised)
        .pagePart(isOpen: isOpen)
    }
  }

  private var track: some View {
    let fraction = player.duration > 0 ? player.time / player.duration : 0
    return VoiceprintView(
      levels: levels, played: player.time > 0 ? fraction : nil, color: Design.bar, barWidth: 3
    )
    .frame(height: 44)
    .frame(maxWidth: .infinity)
    .overlay(alignment: .leading) {
      GeometryReader { bar in
        // Where the player is: the live moment, in the signal.
        Capsule()
          .fill(Design.signal)
          .frame(width: 2, height: 52)
          .offset(x: bar.size.width * fraction - 1, y: -4)
          .opacity(player.time > 0 || player.isPlaying ? 1 : 0)
          .animation(.easeOut(duration: 0.16), value: player.isPlaying)
      }
    }
    .overlay {
      GeometryReader { bar in
        Color.clear
          .contentShape(Rectangle())
          .gesture(
            DragGesture(minimumDistance: 0).onChanged { drag in
              player.seek(to: drag.location.x / bar.size.width)
            })
      }
    }
    .pointer()
    .shared(.voiceprint(id), in: shared, isSource: isOpen)
    .sharedPart(isOpen: isOpen)
    .accessibilityElement()
    .accessibilityLabel("Recording, \(clock(player.time)) of \(transcription.clock)")
  }

  /// What went wrong, and the way to try again when there is a recording to try with.
  private var failure: some View {
    HStack(spacing: 10) {
      Image(systemName: "exclamationmark.triangle")
        .foregroundStyle(Design.ink2)
      Text(hasText ? "Typed as heard, not refined" : "Not transcribed. The recording is kept.")
        .foregroundStyle(Design.ink)
      Spacer(minLength: Design.small)
      if retry.running.contains(id) {
        ProgressView()
          .controlSize(.small)
      } else if history.recording(of: id) != nil {
        Button("Try Again") { retry.start(id) }
          .buttonStyle(QuietButtonStyle())
          .pointer()
      }
    }
    .font(.voiceBody)
    .padding(.leading, 14)
    .padding(.trailing, Design.medium)
    .frame(minHeight: 46)
    .background(Design.raised, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
  }

  private var text: some View {
    Text(transcription.text)
      .font(.voiceReading)
      .lineSpacing(8)
      .foregroundStyle(Design.ink)
      .textSelection(.enabled)
      .pointer(.text)
      .frame(maxWidth: 600, alignment: .leading)
      // On the way in and out it is set at the size of the row it comes from.
      .scaleEffect(isOpen ? 1 : 15 / Self.readingSize, anchor: .topLeading)
      .shared(.text(id), in: shared, isSource: isOpen, isText: true)
      .sharedPart(isOpen: isOpen)
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

  private func clock(_ seconds: TimeInterval) -> String {
    let seconds = Int(seconds.rounded())
    return "\(seconds / 60):" + (seconds % 60 < 10 ? "0" : "") + "\(seconds % 60)"
  }
}
