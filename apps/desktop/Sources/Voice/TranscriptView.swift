import SwiftUI
import VoiceCore

/// The text of the dictation in the pill: its last lines, as it streams in.
///
/// New words come into focus where they land. When the text outgrows the view, all of it
/// moves up a line, and the oldest line leaves through the top.
struct TranscriptView: View {
  let transcript: Transcript

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    // A copy cut at the last line it may show gives the view its size. The whole text
    // lies over it, held by its bottom edge: a new line pushes the others up, out of sight.
    Text(transcript.text)
      .lineLimit(Streaming.lines)
      .hidden()
      .frame(maxWidth: .infinity, alignment: .leading)
      .overlay(alignment: .bottomLeading) {
        text.fixedSize(horizontal: false, vertical: true)
      }
      .modifier(Viewport(isAnimated: isAnimated))
      .font(.system(size: 13.5))
      .lineSpacing(2)
      // The text is a draft until it is refined, so it is shown dimmed.
      .opacity(transcript.isRefined ? 1 : 0.6)
      .contentTransition(.identity)
      .transaction { transaction in
        if reduceMotion { transaction.animation = nil }
      }
  }

  /// Whether new words come into focus and the lines move, rather than the text just
  /// changing.
  private var isAnimated: Bool {
    guard #available(macOS 15, *) else { return false }
    return !reduceMotion
  }

  @ViewBuilder private var text: some View {
    if #available(macOS 15, *), !reduceMotion {
      TimelineView(.animation) { timeline in
        transcript.stream.pieces
          .reduce(Text(transcript.stream.settled)) { text, piece in
            text + Text(piece.text).customAttribute(Arrival(time: piece.arrivedAt))
          }
          .textRenderer(AppearingRenderer(now: timeline.date))
      }
    } else {
      Text(transcript.text)
    }
  }
}

/// Where the text can be seen: the view's bounds, a little wider so that the blur of a word
/// at either side is not cut. As the lines move up, the one leaving fades out above the
/// bounds instead of being cut. Below, they cut: a line fading in there would show over
/// what is under the text.
private struct Viewport: ViewModifier {
  let isAnimated: Bool

  func body(content: Content) -> some View {
    if isAnimated {
      // A mask, not a clip: under a clip, the text the renderer draws can disappear for good.
      content.mask {
        VStack(spacing: 0) {
          LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
            .frame(height: Streaming.fade)
          Rectangle()
        }
        .padding(.horizontal, -Streaming.blur)
        .padding(.top, -Streaming.fade)
      }
    } else {
      content.clipped()
    }
  }
}

private enum Streaming {
  /// How many lines are shown.
  static let lines = 3
  /// How blurred a piece is when it arrives, and a line when it has left.
  static let blur = 5.0
  /// How far above the view a line fades as it leaves.
  static let fade = 8.0
  /// How far below its place a piece is when it arrives.
  static let rise = 3.0
  /// How long a line takes to go out of focus once the text moves up, in seconds.
  static let leave = 0.2
}

/// When a piece of the text arrived.
@available(macOS 15, *)
private struct Arrival: TextAttribute {
  let time: Date
}

/// Draws the text with its newest pieces coming into focus.
@available(macOS 15, *)
private struct AppearingRenderer: TextRenderer {
  let now: Date

  var displayPadding: EdgeInsets {
    EdgeInsets(
      top: 0, leading: Streaming.blur, bottom: Streaming.blur + Streaming.rise,
      trailing: Streaming.blur)
  }

  func draw(layout: Text.Layout, in context: inout GraphicsContext) {
    // Only the last lines can be seen. The one above them goes out of focus on its way
    // out, while the piece that opened the newest line comes in.
    let visible = layout.suffix(Streaming.lines)
    if layout.count > visible.count, let opened = visible.last?.first?[Arrival.self] {
      let left = min(max(now.timeIntervalSince(opened.time) / Streaming.leave, 0), 1)
      if left < 1 {
        var leaving = context
        leaving.opacity = 1 - left
        leaving.addFilter(.blur(radius: left * Streaming.blur))
        leaving.draw(layout[layout.count - visible.count - 1])
      }
    }
    for line in visible {
      for run in line {
        let progress = run[Arrival.self].map { TextStream.progress(since: $0.time, at: now) } ?? 1
        guard progress < 1 else {
          context.draw(run)
          continue
        }
        // Fast at first, then settling.
        let arrived = 1 - pow(1 - progress, 3)
        var piece = context
        piece.opacity = arrived
        piece.addFilter(.blur(radius: (1 - arrived) * Streaming.blur))
        piece.translateBy(x: 0, y: (1 - arrived) * Streaming.rise)
        piece.draw(run)
      }
    }
  }
}
