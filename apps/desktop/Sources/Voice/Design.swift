import AppKit
import SwiftUI

/// The look of the app's windows: a ground, ink in three strengths, and one signal color.
///
/// The signal only marks the live moment: the pill while it listens, today in a chart, the
/// playhead of a recording. A choice is shown in inverted ink, never in the signal. Words
/// come first: a transcription is set larger than anything around it, while numbers, times,
/// and keys are set in the monospaced face, like the readouts of an instrument. A fill sets
/// apart what can be clicked or typed in, and a card holds a group of settings. Nothing else
/// has a box.
enum Design {
  // Space between and inside things, on a 4-point grid.
  static let tight = 4.0
  static let small = 8.0
  static let medium = 12.0
  static let large = 16.0
  static let wide = 20.0
  static let loose = 24.0

  /// The corners of what can be clicked or typed in.
  static let controlRadius = 8.0
  /// The corners of a card.
  static let cardRadius = 14.0
  /// The side of an icon button.
  static let control = 30.0

  /// What the window is drawn on.
  static let ground = Color(nsColor: groundColor)
  static let groundColor = NSColor.dynamic(
    light: NSColor(hex: 0xF7F7F5), dark: NSColor(hex: 0x111112))
  /// A card, and what stands above the ground.
  static let raised = Color(
    nsColor: .dynamic(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0x1A1A1C)))
  /// What a control and a place to type are filled with.
  static let fill = Color(
    nsColor: .dynamic(light: NSColor(hex: 0xEAEAE7), dark: NSColor(hex: 0x262629)))
  /// Text, from what matters most to what matters least. Each reads at 4.5:1 or more on the
  /// ground and on a card.
  static let ink = Color(
    nsColor: .dynamic(light: NSColor(hex: 0x141415), dark: NSColor(hex: 0xF4F4F2)))
  static let ink2 = Color(
    nsColor: .dynamic(light: NSColor(hex: 0x5B5B61), dark: NSColor(hex: 0xA6A6AB)))
  static let ink3 = Color(
    nsColor: .dynamic(light: NSColor(hex: 0x6C6C73), dark: NSColor(hex: 0x88888F)))
  /// A line between rows.
  static let line = Color(
    nsColor: .dynamic(light: .black.withAlpha(0.08), dark: .white.withAlpha(0.08)))
  /// A bar of a chart.
  static let bar = Color(
    nsColor: .dynamic(light: .black.withAlpha(0.14), dark: .white.withAlpha(0.2)))
  /// What is under the pointer.
  static let hover = Color(
    nsColor: .dynamic(light: .black.withAlpha(0.045), dark: .white.withAlpha(0.06)))
  /// A key, and the edge under it.
  static let key = Color(
    nsColor: .dynamic(light: NSColor(hex: 0xFFFFFF), dark: NSColor(hex: 0x232326)))
  static let keyEdge = Color(
    nsColor: .dynamic(light: .black.withAlpha(0.1), dark: .black.withAlpha(0.55)))
  /// The live moment: the pill while it listens, today in a chart, the playhead.
  static let signal = Color(nsColor: signalColor)
  static let signalColor = NSColor(hex: 0xFF5B37)
  /// The pill, black like the notch in both themes.
  static let lamp = Color(nsColor: NSColor(hex: 0x0B0B0C))
}

/// How things move.
///
/// Motion says where something came from and where it goes. What two pages share travels
/// from one to the other, and the rest of a page fades. Feedback is immediate, what leaves
/// goes faster than what arrives, and nothing loops but the pill while it listens. With
/// Reduce Motion on, the window only fades.
enum Motion {
  /// A control answering a click: a choice, a field opening. Quick, without overshoot.
  static let snappy = Animation.spring(duration: 0.3, bounce: 0)
  /// The knob of a switch, and a small thing that changes place: a touch of overshoot.
  static let knob = Animation.spring(duration: 0.32, bounce: 0.18)
  /// What two pages share, travelling from one to the other. No overshoot, so text never
  /// wobbles on the way.
  static let morph = Animation.spring(duration: 0.44, bounce: 0)
  /// Rows and bars finding their place.
  static let settle = Animation.spring(duration: 0.5, bounce: 0.1)
  /// What the pointer is over.
  static let hover = Animation.easeOut(duration: 0.11)
  /// What leaves: at once.
  static let leave = Animation.easeOut(duration: 0.12)
  /// What arrives with a page, a beat after it.
  static let arrive = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.24).delay(0.06)
  /// What waits for the shared elements to land before it comes back.
  static let arriveLate = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.24).delay(0.17)
  /// The copy of a shared element that is going to stay, taking over at once.
  static let takeOver = Animation.easeOut(duration: 0.08)
  /// The copy of a shared element that is going away, gone before the two part ways.
  static let handOff = Animation.easeOut(duration: 0.07)
}

extension NSColor {
  /// A color with one value in light mode and another in dark mode.
  static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
    NSColor(name: nil) { $0.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light }
  }

  convenience init(hex: UInt32) {
    self.init(
      srgbRed: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255,
      blue: Double(hex & 0xFF) / 255, alpha: 1)
  }

  fileprivate func withAlpha(_ alpha: Double) -> NSColor {
    withAlphaComponent(alpha)
  }
}

extension Font {
  /// The title of a page, a group, and what stands out in a row.
  static let voiceTitle = Font.system(size: 13, weight: .semibold)
  static let voiceBody = Font.system(size: 13)
  /// The name of a setting.
  static let voiceSetting = Font.system(size: 14)
  /// The label of a figure, and the choices of a control.
  static let voiceLabel = Font.system(size: 12, weight: .medium)
  /// What explains a setting.
  static let voiceCaption = Font.system(size: 12)
  /// A transcription in the list.
  static let voiceRow = Font.system(size: 15)
  /// A transcription on its page, to be read.
  static let voiceReading = Font.system(size: 20)

  /// Numbers, times, and keys.
  static func voiceMono(_ size: Double, weight: Font.Weight = .regular) -> Font {
    .system(size: size, weight: weight, design: .monospaced)
  }
}

/// What the pointer looks like over a part of the window.
enum PointerKind {
  /// The pointing hand, over what can be clicked.
  case link
  /// The text cursor, over text that can be selected.
  case text
}

extension View {
  /// Sets what the pointer looks like over this view.
  func pointer(_ kind: PointerKind = .link) -> some View {
    modifier(Pointer(kind: kind))
  }
}

private struct Pointer: ViewModifier {
  let kind: PointerKind

  @State private var isInside = false

  func body(content: Content) -> some View {
    if #available(macOS 15, *) {
      content.pointerStyle(kind == .link ? .link : .horizontalText)
    } else {
      content
        .onHover { inside in
          guard inside != isInside else { return }
          isInside = inside
          if inside {
            (kind == .link ? NSCursor.pointingHand : .iBeam).push()
          } else {
            NSCursor.pop()
          }
        }
        .onDisappear {
          if isInside { NSCursor.pop() }
          isInside = false
        }
    }
  }
}

extension EnvironmentValues {
  /// How tall the title bar is, for a page that draws its header in it.
  @Entry var titleBarHeight: CGFloat = 52
}

/// The header of a page, in the title bar beside the button that closes the window.
struct TitleBar<Leading: View, Trailing: View>: View {
  @ViewBuilder let leading: Leading
  @ViewBuilder let trailing: Trailing

  @Environment(\.windowButtonsWidth) private var windowButtonsWidth
  @Environment(\.titleBarHeight) private var height

  var body: some View {
    HStack(spacing: Design.small) {
      leading
      Spacer(minLength: 0)
      trailing
    }
    .padding(.leading, windowButtonsWidth + Design.small)
    .padding(.trailing, 14)
    .frame(height: height)
  }
}

/// The way back from a page, which Escape also takes, and the page's name beside it.
struct BackButton: View {
  let title: String?
  let action: () -> Void

  var body: some View {
    HStack(spacing: Design.tight) {
      IconButton(symbol: "chevron.left", help: "Back", action: action)
        .keyboardShortcut(.cancelAction)
      if let title {
        Text(title)
          .font(.voiceTitle)
          .foregroundStyle(Design.ink)
      }
    }
  }
}

/// A button that is an icon, with a quiet highlight under the pointer.
struct IconButton: View {
  let symbol: String
  let help: String
  let action: () -> Void

  @State private var isHovered = false

  var body: some View {
    Button(action: action) {
      Image(systemName: symbol)
        .font(.system(size: 13))
        .foregroundStyle(isHovered ? Design.ink : Design.ink2)
        .contentTransition(.symbolEffect(.replace))
        .frame(width: Design.control, height: Design.control)
        .background(
          isHovered ? Design.hover : .clear,
          in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .animation(Motion.hover, value: isHovered)
    }
    .buttonStyle(.plain)
    .onHover { isHovered = $0 }
    .pointer()
    .help(help)
    .accessibilityLabel(help)
  }
}

/// The button of what a page is for: filled with ink.
struct PrimaryButtonStyle: ButtonStyle {
  @Environment(\.isEnabled) private var isEnabled

  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.system(size: 13, weight: .medium))
      .foregroundStyle(isEnabled ? Design.ground : Design.ink3)
      .padding(.horizontal, Design.large)
      .frame(height: 30)
      .background(
        isEnabled ? Design.ink : Design.fill,
        in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
      )
      .opacity(configuration.isPressed ? 0.8 : 1)
      .contentShape(Rectangle())
  }
}

/// A button among other things, filled like a control.
struct QuietButtonStyle: ButtonStyle {
  func makeBody(configuration: Configuration) -> some View {
    configuration.label
      .font(.voiceLabel)
      .foregroundStyle(Design.ink)
      .padding(.horizontal, 10)
      .frame(height: 26)
      .background(
        Design.fill,
        in: RoundedRectangle(cornerRadius: Design.controlRadius - 1, style: .continuous)
      )
      .opacity(configuration.isPressed ? 0.75 : 1)
      .contentShape(Rectangle())
  }
}

/// The name of a group, over it.
struct GroupTitle: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.voiceTitle)
      .foregroundStyle(Design.ink)
      .padding(.leading, Design.tight)
      .padding(.bottom, 10)
  }
}

/// Rows on a card. A `CardLine` goes between two of them.
struct Card<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    VStack(spacing: 0) { content }
      .background(
        Design.raised, in: RoundedRectangle(cornerRadius: Design.cardRadius, style: .continuous))
  }
}

/// The line between two rows of a card, from where their text starts.
struct CardLine: View {
  var body: some View {
    Rectangle()
      .fill(Design.line)
      .frame(height: 1)
      .padding(.leading, 18)
  }
}

/// Something that is on or off. The knob slides to the side chosen, and stretches while it
/// is held.
struct Switch: View {
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      EmptyView()
    }
    .buttonStyle(SwitchStyle(isOn: isOn))
    .pointer()
    .accessibilityRepresentation { Toggle(title, isOn: $isOn) }
  }
}

private struct SwitchStyle: ButtonStyle {
  let isOn: Bool

  func makeBody(configuration: Configuration) -> some View {
    Capsule()
      .fill(isOn ? Design.ink : Design.fill)
      .frame(width: 36, height: 22)
      .overlay(alignment: isOn ? .trailing : .leading) {
        Capsule()
          .fill(isOn ? Design.ground : Design.ink3)
          .frame(width: configuration.isPressed ? 19 : 16, height: 16)
          .padding(3)
      }
      .animation(Motion.knob, value: isOn)
      .animation(Motion.snappy, value: configuration.isPressed)
      .contentShape(Capsule())
  }
}

/// A choice between options that are too many, or too long, to stand side by side: the
/// one chosen, and a menu of them all.
struct Select<Value: Hashable>: View {
  let options: [(value: Value, title: String)]
  @Binding var selection: Value

  var body: some View {
    Menu {
      ForEach(options, id: \.value) { option in
        Toggle(
          option.title,
          isOn: Binding {
            option.value == selection
          } set: { _ in
            selection = option.value
          })
      }
    } label: {
      HStack(spacing: Design.small) {
        Text(options.first { $0.value == selection }?.title ?? "")
          .font(.voiceLabel)
          .foregroundStyle(Design.ink)
          .contentTransition(.interpolate)
        Image(systemName: "chevron.up.chevron.down")
          .font(.system(size: 9, weight: .semibold))
          .foregroundStyle(Design.ink2)
      }
      .padding(.leading, 11)
      .padding(.trailing, Design.small)
      .frame(height: 28)
      .background(
        Design.fill, in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
      )
      .contentShape(Rectangle())
      .animation(Motion.snappy, value: selection)
    }
    .menuStyle(.button)
    .buttonStyle(.plain)
    .menuIndicator(.hidden)
    .fixedSize()
    .pointer()
  }
}

/// A choice between a few options, side by side. The choice is inverted ink, and slides to
/// the option chosen.
struct Segmented<Value: Hashable>: View {
  let options: [(value: Value, title: String)]
  @Binding var selection: Value
  /// What the control is drawn on: a card on the ground, a fill on a card.
  var track: Color = Design.raised

  @Namespace private var namespace

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.value) { option in
        segment(option.title, isSelected: option.value == selection) {
          selection = option.value
        }
      }
    }
    .padding(3)
    .background(
      track, in: RoundedRectangle(cornerRadius: Design.controlRadius + 2, style: .continuous)
    )
    .animation(Motion.snappy, value: selection)
  }

  private func segment(
    _ title: String, isSelected: Bool, select: @escaping () -> Void
  ) -> some View {
    Button(action: select) {
      Text(title)
        .font(.voiceLabel)
        .foregroundStyle(isSelected ? Design.ground : Design.ink2)
        .padding(.horizontal, 11)
        .frame(height: 24)
        .background {
          if isSelected {
            RoundedRectangle(cornerRadius: Design.controlRadius - 1, style: .continuous)
              .fill(Design.ink)
              .matchedGeometryEffect(id: "selection", in: namespace)
          }
        }
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointer()
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}

/// The light of a dictation: lit in the signal while Voice listens, grey while the
/// microphone starts and while the text is on its way. Lit, it breathes.
struct Lamp: View {
  let isLit: Bool
  var size = 8.0

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  var body: some View {
    Circle()
      .fill(isLit ? Design.signal : Color(white: 0.54))
      .frame(width: size, height: size)
      .background {
        if isLit {
          if reduceMotion {
            Circle().fill(Design.signal.opacity(0.3)).frame(width: size + 6, height: size + 6)
          } else {
            PhaseAnimator([false, true]) { out in
              Circle()
                .fill(Design.signal.opacity(out ? 0 : 0.32))
                .frame(width: size + (out ? 10 : 4), height: size + (out ? 10 : 4))
            } animation: { _ in
              .easeInOut(duration: 1.6)
            }
          }
        }
      }
      .animation(.easeOut(duration: 0.22), value: isLit)
  }
}

/// A recording drawn small: a bar for each stretch of it, as tall as that stretch is loud.
struct VoiceprintView: View {
  let levels: [Double]
  /// How far a player is into the recording, from 0 to 1. What it played is drawn in ink.
  var played: Double?
  var color: Color = Design.ink3
  var barWidth = 2.0

  var body: some View {
    Canvas { context, size in
      guard !levels.isEmpty else { return }
      let step = size.width / Double(levels.count)
      let width = min(barWidth, step * 0.6)
      for (index, level) in levels.enumerated() {
        let height = max(width, level * size.height)
        let rect = CGRect(
          x: (Double(index) + 0.5) * step - width / 2, y: (size.height - height) / 2,
          width: width, height: height)
        let isPlayed = played.map { (Double(index) + 0.5) / Double(levels.count) < $0 } ?? false
        context.fill(
          Path(roundedRect: rect, cornerRadius: width / 2),
          with: .color(isPlayed ? Design.ink : color))
      }
    }
    .accessibilityHidden(true)
  }
}

/// What a page shares with the list under it.
enum Shared: Hashable {
  case time(UUID)
  case text(UUID)
  case voiceprint(UUID)
  case duration(UUID)
  /// Today's words, and the words of the period on the statistics.
  case figure
  case unit
  /// A day of the week.
  case bar(Int)
}

extension View {
  /// Marks a view the list and a page both show, so it travels from one to the other.
  ///
  /// Only one of the two is the source at a time: the page's while it is open, the list's
  /// otherwise. Text travels by its corner and keeps its own lines, so it never reflows on
  /// the way. With Reduce Motion on, nothing travels.
  func shared(
    _ id: Shared, in namespace: Namespace.ID, isSource: Bool, isText: Bool = false
  ) -> some View {
    modifier(SharedElement(id: id, namespace: namespace, isSource: isSource, isText: isText))
  }
}

private struct SharedElement: ViewModifier {
  let id: Shared
  let namespace: Namespace.ID
  let isSource: Bool
  let isText: Bool

  @Environment(\.accessibilityReduceMotion) private var reduceMotion

  func body(content: Content) -> some View {
    if reduceMotion {
      content
    } else {
      content.matchedGeometryEffect(
        id: id, in: namespace, properties: isText ? .position : .frame,
        anchor: isText ? .topLeading : .center, isSource: isSource)
    }
  }
}
