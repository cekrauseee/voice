import SwiftUI

/// The look of the app's window: quiet, neutral, and compact.
///
/// Everything is drawn in the primary color, at a few opacities over the window's
/// background. So it follows the theme, and nothing has a color of its own.
enum Design {
  // Space between and inside things, on a 4-point grid.
  static let tight = 4.0
  static let small = 8.0
  static let medium = 12.0
  static let large = 16.0
  static let wide = 20.0
  static let loose = 24.0

  /// The corners of a card.
  static let radius = 8.0
  /// The corners of what sits in a card, in the sidebar, or in the header.
  static let controlRadius = 6.0

  /// The side of an icon button, and the height of an item of the sidebar.
  static let control = 28.0
  static let sidebarWidth = 172.0
  /// The sidebar when it only shows icons: an icon with the sidebar's padding around it.
  static let railWidth = control + 2 * small

  /// How the window's parts change shape, like the pill does.
  static let morph = Animation.spring(duration: 0.32, bounce: 0.16)

  /// What a card and a control are filled with.
  static let surface = Color.primary.opacity(0.045)
  /// The line around a card, between its rows, and between the window's parts.
  static let hairline = Color.primary.opacity(0.09)
  /// What is under the pointer.
  static let hover = Color.primary.opacity(0.05)
  /// What is selected.
  static let selected = Color.primary.opacity(0.11)
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
}

/// A group of rows on one surface. Put a `Hairline` between the rows.
struct Card<Content: View>: View {
  @ViewBuilder let content: Content

  var body: some View {
    let shape = RoundedRectangle(cornerRadius: Design.radius, style: .continuous)
    VStack(spacing: 0) { content }
      .background(Design.surface)
      .clipShape(shape)
      .overlay(shape.strokeBorder(Design.hairline))
  }
}

/// The line between two rows of a card.
struct Hairline: View {
  var body: some View {
    Rectangle()
      .fill(Design.hairline)
      .frame(height: 1)
      .padding(.leading, Design.medium)
  }
}

/// The name of a group, above its card, in line with the text of its rows.
struct GroupTitle: View {
  let title: String

  var body: some View {
    Text(title)
      .font(.voiceLabel)
      .foregroundStyle(.secondary)
      .padding(.leading, Design.medium)
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
    .animation(Design.morph, value: selection)
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
