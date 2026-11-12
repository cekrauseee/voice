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
  /// The edge of the screen the pill is at. It grows out of that edge, and away from it.
  let edge: VerticalEdge
  /// The notch the pill opens out of, black like it, instead of being a pill of its own.
  let notch: Notch?

  @Environment(\.colorScheme) private var colorScheme

  fileprivate static let morph = Animation.spring(duration: 0.42, bounce: 0.24)
  /// Going away it does not bounce, so it does not linger.
  private static let retract = Animation.spring(duration: 0.34, bounce: 0)
  /// The new content comes into focus as the surface reaches its shape. The old content
  /// leaves at once, so what is seen changing is the surface.
  private static let content = AnyTransition.asymmetric(
    insertion: AnyTransition(.blurReplace),
    removal: .opacity.animation(.easeOut(duration: 0.12)))

  var body: some View {
    ZStack(alignment: alignment) {
      if let notch {
        NotchSurface(notch: notch, isOpen: state != .hidden) { content }
          // It first shows closed, as the notch itself.
          .transition(.identity)
      } else if state != .hidden {
        // One container around whichever content is showing, so the surface is a single
        // view that resizes, instead of each content bringing its own.
        ZStack(alignment: alignment) { content }
          .background(colorScheme == .dark ? Color(white: 0.12) : .white)
          .clipShape(shape)
          .overlay(shape.strokeBorder(.primary.opacity(0.12)))
          .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
          .transition(.pill(from: edge))
      }
    }
    .animation(state == .hidden ? Self.retract : Self.morph, value: state)
    .animation(Self.morph, value: style)
    .animation(.smooth(duration: 0.3), value: transcript)
  }

  private var alignment: Alignment {
    edge == .bottom ? .bottom : .top
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
        .frame(height: notch == nil ? 28 : 34)
        .padding(.horizontal, notch == nil ? 0 : 8)
        // Out past the notch on either side, so its corners round out.
        .frame(minWidth: notch.map { CGFloat($0.width + 48) })
        .padding(.top, notch?.height ?? 0)
        .padding(.bottom, notch == nil ? 0 : 4)
        .transition(Self.content)
    } else if style == .minimal, let notch {
      // On either side of the notch, which hides what is under it, and a little below it.
      HStack(spacing: 0) {
        Image(systemName: "mic.fill")
          .font(.system(size: 12))
          .foregroundStyle(.secondary)
          .frame(width: 48)
        Color.clear.frame(width: notch.width)
        Waveform(feed: feed, barCount: 5, isLoading: isLoading)
          .frame(width: 24, height: 14)
          .frame(width: 48)
      }
      .frame(height: notch.height + 10)
      .transition(Self.content)
    } else if style == .minimal {
      Waveform(feed: feed, barCount: 7, isLoading: isLoading)
        .frame(width: 40, height: 16)
        .padding(.horizontal, 12)
        .frame(height: 28)
        .transition(Self.content)
    } else {
      detailed
        .padding(.top, notch?.height ?? 0)
        .transition(Self.content)
    }
  }

  private var detailed: some View {
    VStack(alignment: .leading, spacing: 10) {
      Waveform(feed: feed, barCount: 49, isLoading: isLoading)
        .frame(height: 36)
      if !transcript.isEmpty {
        TranscriptView(transcript: transcript)
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
    .padding(
      notch == nil
        ? EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
        : EdgeInsets(top: 10, leading: 22, bottom: 20, trailing: 22)
    )
    .frame(width: notch == nil ? 340 : 380)
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

/// How the pill comes and goes: it grows out of the edge it is at, coming into focus.
private struct PillPresence: ViewModifier {
  let isPresent: Bool
  let edge: VerticalEdge

  func body(content: Content) -> some View {
    content
      .scaleEffect(isPresent ? 1 : 0.55, anchor: edge == .bottom ? .bottom : .top)
      .blur(radius: isPresent ? 0 : 6)
      .opacity(isPresent ? 1 : 0)
  }
}

/// The pill at the notch: black like the notch, curving into the top of the screen as the
/// notch does. Closed, it hides inside the notch. It opens out of it and closes back into
/// it, and the content comes and goes with it.
private struct NotchSurface<Content: View>: View {
  let notch: Notch
  let isOpen: Bool
  @ViewBuilder let content: Content

  /// It first shows closed, so it opens out of the notch even when it shows open.
  @State private var hasAppeared = false

  var body: some View {
    ZStack(alignment: .top) {
      if isOpen, hasAppeared {
        // Toward the notch, coming into focus, like the pill out of the edge of the screen.
        content.transition(.pill(from: .top))
      }
    }
    // The content sets the size. Without it, it is closed, inside the notch.
    .frame(
      minWidth: notch.width - 2 * NotchShape.inset, minHeight: notch.height - NotchShape.inset,
      alignment: .top
    )
    .padding(.horizontal, NotchShape.flare)
    .background(.black)
    .clipShape(NotchShape(notch: notch))
    .shadow(color: .black.opacity(isOpen && hasAppeared ? 0.3 : 0), radius: 14, y: 6)
    .environment(\.colorScheme, .dark)
    .onAppear {
      withAnimation(PillView.morph) { hasAppeared = true }
    }
  }
}

/// The notch, and the pill as it opens out of it. Its shape follows how far out of the
/// notch it is, so it closes back into the notch the way it came out: next to the notch,
/// it has the notch's corners; away from it, its bottom corners round out and its top
/// corners curve out into the edge of the screen.
private struct NotchShape: Shape {
  let notch: Notch

  /// The room on either side for the top corners to curve out into.
  static let flare = 8.0
  /// How far inside the notch it is closed, so the notch hides all of it.
  static let inset = 2.0
  /// About the radius of the bottom corners of the notch itself.
  static let notchRadius = 8.0
  static let cornerRadius = 24.0
  /// How far out of the notch it takes its full shape.
  static let shaping = 10.0

  func path(in rect: CGRect) -> Path {
    let left = rect.minX + Self.flare
    let right = rect.maxX - Self.flare
    // How far out of the notch it is, at the sides and at the bottom.
    let side = (right - left - notch.width) / 2
    let bottom = rect.height - notch.height
    let flare = Self.flare * shaped(side)
    let radius = min(
      Self.notchRadius + (Self.cornerRadius - Self.notchRadius) * shaped(min(side, bottom)),
      rect.height - flare, (right - left) / 2)
    var path = Path()
    path.move(to: CGPoint(x: left - flare, y: rect.minY))
    path.addArc(
      tangent1End: CGPoint(x: left, y: rect.minY), tangent2End: CGPoint(x: left, y: rect.maxY),
      radius: flare)
    path.addArc(
      tangent1End: CGPoint(x: left, y: rect.maxY), tangent2End: CGPoint(x: right, y: rect.maxY),
      radius: radius)
    path.addArc(
      tangent1End: CGPoint(x: right, y: rect.maxY), tangent2End: CGPoint(x: right, y: rect.minY),
      radius: radius)
    path.addArc(
      tangent1End: CGPoint(x: right, y: rect.minY),
      tangent2End: CGPoint(x: right + flare, y: rect.minY), radius: flare)
    path.closeSubpath()
    return path
  }

  /// How much of its full shape it has, this far out of the notch.
  private func shaped(_ distance: Double) -> Double {
    min(max(distance / Self.shaping, 0), 1)
  }
}

extension AnyTransition {
  fileprivate static func pill(from edge: VerticalEdge) -> AnyTransition {
    .modifier(
      active: PillPresence(isPresent: false, edge: edge),
      identity: PillPresence(isPresent: true, edge: edge))
  }
}
