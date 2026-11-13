import SwiftUI
import VoiceCore

/// The pill: a waveform while dictating, a meeting while one records, the offer to record
/// a call, and a short message when something fails.
///
/// It is one surface that changes shape. Going from one content or style to another, the
/// surface grows or shrinks to the new content while the old content dissolves into it.
struct PillView: View {
  let content: PillContent
  let style: PillStyle
  let feed: LevelFeed
  let transcript: Transcript
  let mode: RecordingMode
  let toggle: Shortcut
  /// The meeting the pill shows, when it shows one, and what can be done with it.
  let meeting: MeetingController
  /// Opens the page of the meeting being recorded.
  let open: () -> Void
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
        NotchSurface(notch: notch, isOpen: content != .hidden) { surface }
          // It first shows closed, as the notch itself.
          .transition(.identity)
      } else if content != .hidden {
        // One container around whichever content is showing, so the surface is a single
        // view that resizes, instead of each content bringing its own.
        ZStack(alignment: alignment) { surface }
          .background(colorScheme == .dark ? Color(white: 0.12) : .white)
          .clipShape(shape)
          .overlay(shape.strokeBorder(.primary.opacity(0.12)))
          .shadow(color: .black.opacity(0.2), radius: 12, y: 4)
          .transition(.pill(from: edge))
      }
    }
    .animation(content == .hidden ? Self.retract : Self.morph, value: content)
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
    switch content {
    case .dictation(.failed), .offer, .meetingFailed: true
    case .hidden, .dictation, .meeting: style == .minimal
    }
  }

  @ViewBuilder private var surface: some View {
    switch content {
    case .dictation(.failed(let error)):
      message(error.message)
    case .meetingFailed(let error):
      message(error.message)
    case .offer(let user):
      offer(user)
    case .meeting(let isFinishing):
      if style == .minimal, let notch {
        meetingAtNotch(notch, isFinishing: isFinishing)
      } else if style == .minimal {
        meetingMinimal(isFinishing: isFinishing)
      } else {
        meetingDetailed(isFinishing: isFinishing)
      }
    case .dictation(let state):
      dictation(state)
    case .hidden:
      dictation(.hidden)
    }
  }

  // MARK: Messages

  private func message(_ text: String) -> some View {
    Label(text, systemImage: "exclamationmark.triangle.fill")
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 12)
      .frame(height: notch == nil ? 28 : 34)
      .padding(.horizontal, notch == nil ? 0 : 8)
      // Out past the notch on either side, so its corners round out.
      .frame(minWidth: notch.map { CGFloat($0.width + 48) })
      .padding(.top, notch?.height ?? 0)
      .padding(.bottom, notch == nil ? 0 : 4)
      .transition(Self.content)
  }

  /// Another app is in a call: record it, or not.
  private func offer(_ user: MicrophoneUser) -> some View {
    HStack(spacing: 10) {
      Image(systemName: "person.2.wave.2")
        .font(.system(size: 13))
        .foregroundStyle(.secondary)
      VStack(alignment: .leading, spacing: 1) {
        Text("Meeting detected")
          .font(.system(size: 12, weight: .medium))
        Text("\(user.name) is using the microphone")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
          .lineLimit(1)
      }
      Spacer(minLength: 10)
      PillButton(title: "Start recording", action: meeting.start)
      PillIconButton(symbol: "xmark", help: "Dismiss", action: meeting.dismissPrompt)
    }
    .padding(.leading, 14)
    .padding(.trailing, 8)
    .padding(.vertical, 8)
    .frame(width: notch == nil ? 340 : 380)
    .padding(.top, notch?.height ?? 0)
    .padding(.bottom, notch == nil ? 0 : 4)
    .transition(Self.content)
  }

  // MARK: Dictation

  @ViewBuilder private func dictation(_ state: PillState) -> some View {
    let isLoading = state == .starting || state == .finishing
    if style == .minimal, let notch {
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
      dictationDetailed(state, isLoading: isLoading)
        .padding(.top, notch?.height ?? 0)
        .transition(Self.content)
    }
  }

  private func dictationDetailed(_ state: PillState, isLoading: Bool) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Waveform(feed: feed, barCount: 49, isLoading: isLoading)
        .frame(height: 36)
      if !transcript.isEmpty {
        TranscriptView(transcript: transcript)
          .transition(.blurReplace)
      }
      HStack(spacing: 12) {
        Label(status(state), systemImage: "mic.fill")
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
    .modifier(Detailed(notch: notch))
  }

  private func status(_ state: PillState) -> String {
    switch state {
    case .starting: "Starting"
    case .finishing: "Finishing"
    default: "Listening"
    }
  }

  // MARK: Meeting

  /// On either side of the notch: the time on the left, the sound and Stop on the right.
  private func meetingAtNotch(_ notch: Notch, isFinishing: Bool) -> some View {
    HStack(spacing: 0) {
      clock(isFinishing: isFinishing)
        .frame(width: 76)
      Color.clear.frame(width: notch.width)
      HStack(spacing: 8) {
        Waveform(feed: meeting.levels, barCount: 5, isLoading: isFinishing)
          .frame(width: 24, height: 14)
        stop(isFinishing: isFinishing)
      }
      .frame(width: 76)
    }
    .frame(height: notch.height + 10)
    .contentShape(Rectangle())
    .onTapGesture(perform: open)
    .pointer()
    .transition(Self.content)
  }

  private func meetingMinimal(isFinishing: Bool) -> some View {
    HStack(spacing: 10) {
      clock(isFinishing: isFinishing)
      Waveform(feed: meeting.levels, barCount: 7, isLoading: isFinishing)
        .frame(width: 40, height: 16)
      stop(isFinishing: isFinishing)
    }
    .padding(.leading, 12)
    .padding(.trailing, 6)
    .frame(height: 28)
    .contentShape(Rectangle())
    .onTapGesture(perform: open)
    .pointer()
    .transition(Self.content)
  }

  private func meetingDetailed(isFinishing: Bool) -> some View {
    VStack(alignment: .leading, spacing: 10) {
      Waveform(feed: meeting.levels, barCount: 49, isLoading: isFinishing)
        .frame(height: 36)
      if let live = meeting.live, !recent(live).characters.isEmpty {
        // The end of the conversation: what does not fit is cut at the start.
        Text(recent(live))
          .font(.system(size: 13))
          .lineLimit(3)
          .truncationMode(.head)
          .frame(maxWidth: .infinity, alignment: .leading)
      }
      if meeting.isMissingSystemAudio {
        Label("Only the microphone is recorded", systemImage: "speaker.slash")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
      }
      HStack(spacing: 12) {
        clock(isFinishing: isFinishing)
        Text(isFinishing ? "Finishing" : "Recording")
          .contentTransition(.interpolate)
        Spacer()
        PillIconButton(symbol: "arrow.up.forward.square", help: "Open", action: open)
        PillButton(title: "Stop", action: meeting.stop)
          .disabled(isFinishing)
      }
      .font(.system(size: 11))
      .foregroundStyle(.secondary)
    }
    .modifier(Detailed(notch: notch))
    .padding(.top, notch?.height ?? 0)
    .transition(Self.content)
  }

  /// A red dot while recording, and how long the meeting has run.
  private func clock(isFinishing: Bool) -> some View {
    HStack(spacing: 6) {
      Circle()
        .fill(isFinishing ? Color.secondary : .red)
        .frame(width: 7, height: 7)
      TimelineView(.periodic(from: .now, by: 1)) { _ in
        Text(meeting.elapsed.clock)
          .monospacedDigit()
      }
    }
    .font(.system(size: 11, weight: .medium))
  }

  private func stop(isFinishing: Bool) -> some View {
    PillIconButton(symbol: "stop.fill", help: "Stop", action: meeting.stop)
      .disabled(isFinishing)
  }

  /// The last paragraphs, and after them what is being heard, dimmed.
  private func recent(_ live: LiveMeeting) -> AttributedString {
    var text = AttributedString(
      live.meeting.paragraphs.suffix(2).map { "\($0.channel.title): \($0.text)" }
        .joined(separator: "\n"))
    for channel in Channel.allCases {
      guard let draft = live.drafts[channel] else { continue }
      var piece = AttributedString(
        (text.characters.isEmpty ? "" : "\n") + "\(channel.title): \(draft)")
      piece.foregroundColor = .secondary
      text += piece
    }
    return text
  }
}

/// The room and width of the detailed pill, under the notch or on its own.
private struct Detailed: ViewModifier {
  let notch: Notch?

  func body(content: Content) -> some View {
    content
      .padding(
        notch == nil
          ? EdgeInsets(top: 14, leading: 14, bottom: 14, trailing: 14)
          : EdgeInsets(top: 10, leading: 22, bottom: 20, trailing: 22)
      )
      .frame(width: notch == nil ? 340 : 380)
  }
}

/// A button of the pill, with a word on it.
private struct PillButton: View {
  let title: String
  let action: () -> Void

  var body: some View {
    Button(title, action: action)
      .buttonStyle(.plain)
      .font(.system(size: 12, weight: .medium))
      .padding(.horizontal, 10)
      .frame(height: 24)
      .background(
        Design.selected,
        in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
      )
      .pointer()
  }
}

/// A button of the pill, with a symbol on it.
private struct PillIconButton: View {
  let symbol: String
  let help: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 11, weight: .medium))
        .foregroundStyle(.secondary)
        .frame(width: 24, height: 24)
        .background(
          isHovered ? Design.hover : .clear,
          in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
        )
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .help(help)
    .pointer()
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
