import SwiftUI

/// The keys of a shortcut, side by side.
struct KeyCaps: View {
  let labels: [String]

  var body: some View {
    HStack(spacing: 3) {
      ForEach(labels, id: \.self) { KeyCap(label: $0) }
    }
  }
}

private struct KeyCap: View {
  let label: String

  var body: some View {
    Text(label)
      .font(.system(size: 11, weight: .medium))
      .padding(.horizontal, 5)
      .frame(minWidth: 20, minHeight: 20)
      .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 5, style: .continuous))
  }
}
