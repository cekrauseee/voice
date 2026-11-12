import SwiftUI

/// The look of the app's window: quiet, neutral, and compact.
///
/// Everything is drawn in the primary color, at a few opacities over the window's
/// background. So it follows the theme, and nothing has a color of its own. There are no
/// boxes around groups and no lines between rows: space and type tell things apart, and a
/// fill is kept for what can be clicked or typed in.
///
/// Almost nothing moves. What the pointer is over, what is selected, and what a click
/// shows change at once. Motion is kept for the two places where it says where something
/// went: a page that opens over a list, and the mark of a choice that moves to another,
/// which the knob of a switch is too.
enum Design {
  // Space between and inside things, on a 4-point grid.
  static let tight = 4.0
  static let small = 8.0
  static let medium = 12.0
  static let large = 16.0
  static let wide = 20.0
  static let loose = 24.0

  /// The corners of what can be clicked or typed in.
  static let controlRadius = 6.0

  /// The side of an icon button, and the height of an item of the sidebar.
  static let control = 30.0
  static let sidebarWidth = 168.0
  /// The sidebar when it only shows icons. Its icons are right under the button that
  /// closes the window.
  static let railWidth = control + 2 * tight

  /// How the few things that move do it: quickly, and slowing into place.
  static let move = Animation.timingCurve(0.2, 0, 0, 1, duration: 0.18)

  /// What a control and a place to type are filled with.
  static let surface = Color.primary.opacity(0.045)
  /// What is under the pointer.
  static let hover = Color.primary.opacity(0.05)
  /// What is selected.
  static let selected = Color.primary.opacity(0.11)
  /// A bar of a chart, and the one under the pointer.
  static let bar = Color.primary.opacity(0.28)
  static let barHover = Color.primary.opacity(0.6)
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

extension Font {
  /// The section's title, and what stands out in a row.
  static let voiceTitle = Font.system(size: 13, weight: .semibold)
  static let voiceBody = Font.system(size: 13)
  /// The items of the sidebar and the choices of a control.
  static let voiceLabel = Font.system(size: 12, weight: .medium)
  /// Times, lengths, and explanations.
  static let voiceCaption = Font.system(size: 11)
  /// A number that is what a page is about.
  static let voiceFigure = Font.system(size: 22, weight: .semibold).monospacedDigit()
}

/// The name of a group of rows, in line with their text.
struct GroupTitle: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.voiceLabel)
      .foregroundStyle(.secondary)
      .padding(.horizontal, Design.small)
  }
}

/// Something that is on or off. The knob slides to the side chosen.
struct Switch: View {
  let title: String
  @Binding var isOn: Bool

  var body: some View {
    Button {
      isOn.toggle()
    } label: {
      Capsule()
        .fill(Color.primary.opacity(isOn ? 0.85 : 0.2))
        .frame(width: 30, height: 18)
        .overlay(alignment: isOn ? .trailing : .leading) {
          Circle()
            .fill(Color(nsColor: .windowBackgroundColor))
            .padding(2)
        }
        .animation(Design.move, value: isOn)
        .contentShape(Rectangle())
    }
    .buttonStyle(.plain)
    .pointer()
    .accessibilityRepresentation { Toggle(title, isOn: $isOn) }
  }
}

/// A choice between a few options, side by side. The selection slides to the one chosen.
struct Segmented<Value: Hashable>: View {
  let options: [(value: Value, title: String)]
  @Binding var selection: Value

  @Namespace private var namespace

  var body: some View {
    HStack(spacing: 2) {
      ForEach(options, id: \.value) { option in
        segment(option.title, isSelected: option.value == selection) {
          selection = option.value
        }
      }
    }
    .padding(2)
    .background(
      Design.surface,
      in: RoundedRectangle(cornerRadius: Design.controlRadius + 1, style: .continuous)
    )
    .animation(Design.move, value: selection)
  }

  private func segment(
    _ title: String, isSelected: Bool, select: @escaping () -> Void
  ) -> some View {
    Button(action: select) {
      Text(title)
        .font(.voiceLabel)
        .opacity(isSelected ? 1 : 0.6)
        .padding(.horizontal, 10)
        .frame(height: 22)
        .background {
          if isSelected {
            RoundedRectangle(cornerRadius: Design.controlRadius - 1, style: .continuous)
              .fill(Design.selected)
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
