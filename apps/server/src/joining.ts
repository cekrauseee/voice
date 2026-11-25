/**
 * Joining a dictation to the text before the cursor.
 *
 * The dictated text is typed right after the text already in the field. When that text ends
 * in the middle of a line, the two need a space between them, unless one side is punctuation
 * that attaches to the other or a script written without spaces.
 */

/** Scripts written without spaces between words, CJK punctuation, and full-width forms. */
const UNSPACED =
  /[\p{Script=Han}\p{Script=Hiragana}\p{Script=Katakana}\p{Script=Thai}\p{Script=Lao}\p{Script=Khmer}\p{Script=Myanmar}\u{3000}-\u{303f}\u{ff00}-\u{ffef}]/u;

/** What opens a phrase: the text after it attaches to it. */
const OPENING = /[([{“‘«‹¿¡/]/u;

/** What closes a phrase or attaches to the word before it. */
const CLOSING = /^[.,;:!?)\]}”’»›…%]/u;

/**
 * The text to type after `context`: `text` with a space before it when the two would
 * otherwise run together. Empty when the text is.
 */
export function joinAfter(context: string, text: string): string {
  if (text === "" || context === "") return text;
  const end = Array.from(context.slice(-4));
  const last = end.at(-1) ?? "";
  const before = end.at(-2) ?? "";
  const first = String.fromCodePoint(text.codePointAt(0) ?? 0);
  const attached =
    /\s/u.test(last) ||
    OPENING.test(last) ||
    // A straight quote opens a quotation after a space, and closes one after a word.
    (/^["']$/u.test(last) && /^\s?$/u.test(before)) ||
    UNSPACED.test(last) ||
    UNSPACED.test(first) ||
    CLOSING.test(first);
  return attached ? text : ` ${text}`;
}
