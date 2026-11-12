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

  /// The corners of a card.
  static let radius = 8.0
  /// The corners of what sits in a card or in the sidebar.
  static let controlRadius = 6.0

  /// The height of the row that holds the window's buttons, and the section's title.
  static let barHeight = 32.0
  static let sidebarWidth = 164.0
  /// The sidebar when it only shows icons. It is as wide as the window's buttons need.
  static let railWidth = 76.0

  /// How the window's parts change shape, like the pill does.
  static let morph = Animation.spring(duration: 0.32, bounce: 0.16)

  /// What a card, the sidebar, and a control are filled with.
  static let surface = Color.primary.opacity(0.045)
  /// The line around a card and between its rows.
  static let hairline = Color.primary.opacity(0.09)
  /// What is under the pointer.
  static let hover = Color.primary.opacity(0.05)
  /// What is selected.
  static let selected = Color.primary.opacity(0.11)
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

/// The name of a group, above its card.
struct GroupTitle: View {
  let title: String

  var body: some View {
    Text(title.uppercased())
      .font(.system(size: 10.5, weight: .semibold))
      .kerning(0.6)
      .foregroundStyle(.secondary)
      .padding(.leading, Design.tight)
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
    .accessibilityAddTraits(isSelected ? .isSelected : [])
  }
}
