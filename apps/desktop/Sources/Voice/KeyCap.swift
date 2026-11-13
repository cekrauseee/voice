import SwiftUI

/// The keys of a shortcut, side by side.
struct KeyCaps: View {
  let labels: [String]
  var size = KeyCap.Size.small

  var body: some View {
    HStack(spacing: size == .large ? 5 : 3) {
      ForEach(labels, id: \.self) { KeyCap(label: $0, size: size) }
    }
  }
}

/// A key, drawn as one: raised on its edge, in the monospaced face.
struct KeyCap: View {
  enum Size {
    /// In a line of text, and in the pill.
    case small
    /// On its own, as in the settings.
    case large
  }

  let label: String
  var size = Size.small

  var body: some View {
    let isLarge = size == .large
    Text(label)
      .font(.voiceMono(isLarge ? 13 : 11, weight: .medium))
      .padding(.horizontal, isLarge ? 10 : 5)
      .frame(minWidth: isLarge ? 30 : 20, minHeight: isLarge ? 30 : 20)
      .background {
        RoundedRectangle(cornerRadius: isLarge ? 8 : 5, style: .continuous)
          .fill(Design.key)
          .overlay(alignment: .bottom) {
            // The edge under the key.
            RoundedRectangle(cornerRadius: isLarge ? 8 : 5, style: .continuous)
              .strokeBorder(Design.keyEdge, lineWidth: isLarge ? 2 : 1.5)
              .mask(alignment: .bottom) {
                Rectangle().frame(height: isLarge ? 3 : 2)
              }
          }
          .overlay {
            RoundedRectangle(cornerRadius: isLarge ? 8 : 5, style: .continuous)
              .strokeBorder(Design.line)
          }
      }
  }
}
