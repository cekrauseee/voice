import SwiftUI
import VoiceCore

/// The user's dictionary: a field to add a name or term, and the ones added, newest first.
struct DictionaryView: View {
  @Binding var terms: [String]

  @State private var draft = ""
  @FocusState private var isTyping: Bool

  var body: some View {
    VStack(alignment: .leading, spacing: Design.wide) {
      VStack(alignment: .leading, spacing: Design.small) {
        HStack(spacing: Design.tight) {
          TextField("Add a word or name", text: $draft)
            .textFieldStyle(.plain)
            .font(.voiceBody)
            .focused($isTyping)
            .onSubmit(add)
            .onChange(of: draft) { _, text in
              if text.count > Vocabulary.maxLength {
                draft = String(text.prefix(Vocabulary.maxLength))
              }
            }
          if !Vocabulary.term(draft).isEmpty {
            IconButton(symbol: "plus", help: "Add", action: add)
          }
        }
        .padding(.leading, Design.small)
        .padding(.trailing, Design.tight / 2)
        .frame(height: Design.control + Design.tight)
        .background(
          Design.surface,
          in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
        )
        Text("Names and terms you use, spelled the way you write them.")
          .font(.voiceCaption)
          .foregroundStyle(.secondary)
          .padding(.horizontal, Design.small)
      }
      .padding(.horizontal, Design.medium)
      .padding(.top, Design.medium)

      if terms.isEmpty {
        empty
      } else {
        ScrollView {
          LazyVStack(alignment: .leading, spacing: 2) {
            ForEach(terms, id: \.self) { term in
              TermRow(term: term) { terms.removeAll { $0 == term } }
            }
          }
          .padding(.horizontal, Design.medium)
          .padding(.bottom, Design.medium)
        }
        .animation(Design.move, value: terms)
      }
    }
  }

  private var empty: some View {
    VStack(spacing: Design.small) {
      Image(systemName: AppSection.dictionary.symbol)
        .font(.system(size: 22, weight: .medium))
        .foregroundStyle(.tertiary)
      Text("No words yet")
        .font(.voiceTitle)
      Text("Add the ones that come out wrong")
        .font(.voiceCaption)
        .foregroundStyle(.secondary)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
  }

  private func add() {
    guard !Vocabulary.term(draft).isEmpty else { return }
    terms = Vocabulary.adding(draft, to: terms)
    draft = ""
    isTyping = true
  }
}

/// A term in the dictionary. Under the pointer, a button removes it.
private struct TermRow: View {
  let term: String
  let remove: () -> Void

  @State private var isHovered = false

  var body: some View {
    HStack(spacing: Design.medium) {
      Text(term)
        .font(.voiceBody)
        .lineLimit(1)
        .truncationMode(.tail)
        .frame(maxWidth: .infinity, alignment: .leading)
      IconButton(symbol: "xmark", help: "Remove", action: remove)
        .opacity(isHovered ? 1 : 0)
    }
    .padding(.leading, Design.small)
    .padding(.trailing, Design.tight / 2)
    .frame(height: Design.control + Design.tight)
    .background(
      isHovered ? Design.hover : .clear,
      in: RoundedRectangle(cornerRadius: Design.controlRadius, style: .continuous)
    )
    .contentShape(Rectangle())
    .onHover { isHovered = $0 }
    .contextMenu {
      Button("Remove", role: .destructive, action: remove)
    }
  }
}
