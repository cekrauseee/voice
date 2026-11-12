import SwiftUI
import VoiceCore

/// The pill: a waveform while dictating, and a short message when something fails.
///
/// It is one surface that changes shape. Going from one state or style to another, the
/// surface grows or shrinks to the new content while the old content dissolves into it.
struct PillView: View {
  let state: PillState
  let style: PillStyle
  let feed: LevelFeed
  let transcript: Transcript
  let mode: RecordingMode
  let toggle: Shortcut

  @Environment(\.colorScheme) private var colorScheme

  private static let morph = Animation.spring(duration: 0.42, bounce: 0.24)
  /// The new content comes into focus as the surface reaches its shape. The old content
  /// leaves at once, so what is seen changing is the surface.
  private static let content = AnyTransition.asymmetric(
    insertion: AnyTransition(.blurReplace),
    removal: .opacity.animation(.easeOut(duration: 0.12)))

  var body: some View {
    ZStack(alignment: .bottom) {
      if state != .hidden {
        // One container around whichever content is showing, so the surface is a single
        // view that resizes, instead of each content bringing its own.
        ZStack(alignment: .bottom) { content }
          .background(colorScheme == .dark ? Color(white: 0.12) : .white)
          .clipShape(shape)
          .overlay(shape.strokeBorder(.primary.opacity(0.12)))
          .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
          .transition(.pill)
      }
    }
    .animation(Self.morph, value: state)
    .animation(Self.morph, value: style)
    .animation(.smooth(duration: 0.25), value: transcript)
  }

  private var shape: RoundedRectangle {
    RoundedRectangle(cornerRadius: isCompact ? 14 : 20, style: .continuous)
  }

  private var isCompact: Bool {
    if case .failed = state { return true }
    return style == .minimal
  }

  private var isLoading: Bool {
    state == .finishing
  }

  @ViewBuilder private var content: some View {
    if case .failed(let error) = state {
      Label(error.message, systemImage: "exclamationmark.triangle.fill")
        .font(.system(size: 12, weight: .medium))
        .padding(.horizontal, 12)
        .frame(height: 28)
        .transition(Self.content)
    } else if style == .minimal {
      Waveform(feed: feed, barCount: 7, isLoading: isLoading)
        .frame(width: 40, height: 16)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .transition(Self.content)
    } else {
      detailed
        .transition(Self.content)
    }
  }

  private var detailed: some View {
    VStack(alignment: .leading, spacing: 10) {
      Waveform(feed: feed, barCount: 49, isLoading: isLoading)
        .frame(height: 36)
      if !transcript.isEmpty {
        // The text is a draft until it is refined, so it is shown dimmed.
        Text(transcript.text)
          .font(.system(size: 13))
          .foregroundStyle(.primary.opacity(transcript.isRefined ? 1 : 0.4))
          .lineLimit(3)
          .truncationMode(.head)
          .frame(maxWidth: .infinity, alignment: .leading)
          .contentTransition(.interpolate)
          .transition(.blurReplace)
      }
      HStack(spacing: 12) {
        Label(status, systemImage: "mic.fill")
          .contentTransition(.interpolate)
        Spacer()
        if state != .finishing {
          Group {
            if mode == .toggle {
              Hint(title: "Stop", keyCaps: toggle.keyCaps)
            } else {
              Text("Release to stop")
            }
          }
          .transition(.blurReplace)
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
    state == .finishing ? "Finishing" : "Listening"
  }
}

private struct Hint: View {
  let title: String
  let keyCaps: [String]

  var body: some View {
    HStack(spacing: 4) {
      Text(title)
      KeyCaps(labels: keyCaps)
    }
  }
}

/// How the pill comes and goes: it grows out of its bottom edge, coming into focus.
private struct PillPresence: ViewModifier {
  let isPresent: Bool

  func body(content: Content) -> some View {
    content
      .scaleEffect(isPresent ? 1 : 0.55, anchor: .bottom)
      .blur(radius: isPresent ? 0 : 6)
      .opacity(isPresent ? 1 : 0)
  }
}

extension AnyTransition {
  fileprivate static var pill: AnyTransition {
    .modifier(active: PillPresence(isPresent: false), identity: PillPresence(isPresent: true))
  }
}
