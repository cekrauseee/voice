import SwiftUI
import VoiceCore

/// The pill: a waveform while dictating, and a short message when something fails.
struct PillView: View {
  let state: PillState
  let style: PillStyle
  let levels: [Float]
  let transcript: Transcript
  let mode: RecordingMode
  let toggle: Shortcut

  @Environment(\.colorScheme) private var colorScheme

  private static let spring = Animation.spring(duration: 0.35, bounce: 0.2)

  var body: some View {
    ZStack(alignment: .bottom) {
      if state != .hidden {
        content
          .background(colorScheme == .dark ? Color(white: 0.12) : .white, in: shape)
          .overlay(shape.strokeBorder(.primary.opacity(0.12)))
          .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
          .transition(.scale(scale: 0.5, anchor: .bottom).combined(with: .opacity))
      }
    }
    .animation(Self.spring, value: state)
    .animation(Self.spring, value: transcript.isEmpty)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: isCompact ? 14 : 20, style: isCompact ? .circular : .continuous)
  }

  private var isCompact: Bool {
    if case .failed = state { return true }
    return style == .minimal
  }

  private var isLoading: Bool {
    state != .listening
  }

  @ViewBuilder private var content: some View {
    if case .failed(let error) = state {
      Label(error.message, systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
    } else if style == .minimal {
      Waveform(levels: levels.suffix(9), isLoading: isLoading)
        .frame(width: 44, height: 14)
        .padding(.horizontal, 12)
        .frame(height: 28)
    } else {
      detailed
    }
  }

  private var detailed: some View {
    VStack(alignment: .leading, spacing: 10) {
      Waveform(levels: levels[...], isLoading: isLoading)
        .frame(height: 36)
      if !transcript.isEmpty {
        Text(transcriptText)
          .font(.system(size: 13))
          .lineLimit(3)
          .truncationMode(.head)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      HStack(spacing: 12) {
        Label(status, systemImage: "mic.fill")
        Spacer()
        if state != .finishing {
          if mode == .toggle {
            Hint(title: "Stop", keyCaps: toggle.keyCaps)
          } else {
            Text("Release to stop")
          }
        }
        Hint(title: "Cancel", keyCaps: ["esc"])
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
    }
    .padding(14)
    .frame(width: 340)
  }

  private var status: String {
    switch state {
    case .connecting: "Connecting"
    case .finishing: "Finishing"
    default: "Listening"
    }
  }

  /// Text that is not refined yet can still change, so it is shown dimmed.
  private var transcriptText: AttributedString {
    transcript.segments.reduce(into: AttributedString()) { text, segment in
      var part = AttributedString(segment.text + " ")
      part.foregroundColor = segment.isRefined ? .primary : .primary.opacity(0.4)
      text.append(part)
    }
  }
}

private struct Hint: View {
  let title: String
  let keyCaps: [String]

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
      ForEach(keyCaps, id: \.self) { KeyCap(label: $0) }
    }
  }
}

struct KeyCap: View {
  let label: String

  var body: some View {
    Text(label)
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 5)
      .frame(minWidth: 20, minHeight: 20)
      .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
  }
}
