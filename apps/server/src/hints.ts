/**
 * What the transcription session is told about the speaker, besides their dictionary: a
 * description of their recordings, and the languages they speak. OpenAI rejects a whole
 * session update over a hint it does not take, which would fail the dictation, so the hints
 * are made safe here first.
 */

/**
 * The longest description of the recordings passed on. OpenAI rejects a prompt longer than
 * 1024 characters: this leaves room.
 */
export const MAX_PROMPT_CHARS = 1000;

/** The most languages passed on. A speaker names a few, not a list. */
export const MAX_LANGUAGES = 10;

/**
 * The languages `gpt-live-transcribe` takes, as ISO 639-1 codes, as OpenAI listed them in
 * November 2026. `iw` is an older code for Hebrew.
 */
export const TRANSCRIPTION_LANGUAGES = [
  "af",
  "ar",
  "az",
  "be",
  "bg",
  "bs",
  "ca",
  "cs",
  "cy",
  "da",
  "de",
  "el",
  "en",
  "es",
  "et",
  "fa",
  "fi",
  "fr",
  "gl",
  "he",
  "hi",
  "hr",
  "hu",
  "hy",
  "id",
  "is",
  "it",
  "iw",
  "ja",
  "kk",
  "kn",
  "ko",
  "lt",
  "lv",
  "mi",
  "mk",
  "mr",
  "ms",
  "ne",
  "nl",
  "no",
  "pl",
  "pt",
  "ro",
  "ru",
  "sk",
  "sl",
  "sr",
  "sv",
  "sw",
  "ta",
  "th",
  "tl",
  "tr",
  "uk",
  "ur",
  "vi",
  "zh",
] as const;

/**
 * A description of the recordings, ready for the transcription session: one paragraph,
 * without control characters, cut at a word to `MAX_PROMPT_CHARS`.
 */
export function normalizePrompt(text: string): string {
  // Control characters and line breaks become spaces, and runs of spaces one.
  // biome-ignore lint/suspicious/noControlCharactersInRegex: control characters are what it removes
  const prompt = text.replace(/[\u0000-\u001f\u007f-\u009f\s]+/g, " ").trim();
  if (prompt.length <= MAX_PROMPT_CHARS) return prompt;
  const cut = prompt.slice(0, MAX_PROMPT_CHARS + 1);
  const space = cut.lastIndexOf(" ");
  // A string of a thousand characters without a space is cut where it is.
  return (space > 0 ? cut.slice(0, space) : cut.slice(0, MAX_PROMPT_CHARS)).trim();
}

/**
 * The languages, as the transcription session takes them: two-letter lowercase codes, a
 * region left out (`pt-BR` is `pt`), each once, the first `MAX_LANGUAGES`. A code that is not
 * two letters is left out. One the model does not know is the transcriber's to handle.
 */
export function normalizeLanguages(codes: readonly string[]): string[] {
  const languages: string[] = [];
  for (const raw of codes) {
    const code = raw.trim().toLowerCase().split(/[-_]/)[0] ?? "";
    if (!/^[a-z]{2}$/.test(code) || languages.includes(code)) continue;
    languages.push(code);
    if (languages.length === MAX_LANGUAGES) break;
  }
  return languages;
}
