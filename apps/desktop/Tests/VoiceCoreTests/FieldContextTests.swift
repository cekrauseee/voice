import Testing

@testable import VoiceCore

@Suite struct FieldContextTests {
  @Test func takesTheTextBeforeTheCursor() {
    #expect(FieldContext.before("Hello Ana, thanks", cursor: 10) == "Hello Ana,")
    #expect(FieldContext.before("Hello", cursor: 5) == "Hello")
    #expect(FieldContext.before("Hello", cursor: 0) == "")
  }

  @Test func countsTheCursorInUTF16AsTheAccessibilityAPIDoes() {
    // The emoji takes two UTF-16 code units.
    #expect(FieldContext.before("Hi 👋 there", cursor: 5) == "Hi 👋")
  }

  @Test func readsNothingWhenTheCursorIsNotInTheText() {
    #expect(FieldContext.before("Hello", cursor: 6) == "")
    #expect(FieldContext.before("Hello", cursor: -1) == "")
  }

  @Test func readsNothingWhenThereIsOnlyWhitespace() {
    #expect(FieldContext.before("  \n", cursor: 3) == "")
  }

  @Test func keepsTheEndOfALongText() {
    let text = String(repeating: "word ", count: 1000) + "last"
    let context = FieldContext.before(text, cursor: text.utf16.count)
    #expect(context.utf16.count <= FieldContext.limit)
    #expect(context.hasSuffix(" word last"))
    // It starts with a whole word, not the end of one.
    #expect(context.hasPrefix("word "))
  }

  @Test func asksForTheLimitBeforeTheCursor() {
    #expect(FieldContext.window(cursor: 120) == 0..<120)
    #expect(FieldContext.window(cursor: 5000) == 3000..<5000)
    #expect(FieldContext.window(cursor: -1) == 0..<0)
  }

  @Test func dropsTheWordACutTextStartsInTheMiddleOf() {
    #expect(FieldContext.text("rd and more", isCut: true) == "and more")
    #expect(FieldContext.text("rd and more", isCut: false) == "rd and more")
    // Text without spaces, as in Japanese, is kept whole.
    let unspaced = String(repeating: "語", count: 100)
    #expect(FieldContext.text(unspaced, isCut: true) == unspaced)
  }
}
