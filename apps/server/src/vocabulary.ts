/** The most terms a dictation passes on. Each one adds to every refinement request. */
export const MAX_TERMS = 500;

/** A longer term is not a word or a name, and is dropped. */
export const MAX_TERM_CHARS = 100;

/**
 * The speaker's terms, ready to send to the models: each on one line, without the angle
 * brackets the transcription service rejects, without blanks or terms already listed in
 * another case. The first terms are kept when there are too many.
 */
export function normalizeVocabulary(terms: readonly string[]): string[] {
  const seen = new Set<string>();
  const vocabulary: string[] = [];
  for (const raw of terms) {
    const term = raw.replace(/[<>]/g, "").replace(/\s+/g, " ").trim();
    const key = term.toLowerCase();
    if (term === "" || term.length > MAX_TERM_CHARS || seen.has(key)) continue;
    seen.add(key);
    vocabulary.push(term);
    if (vocabulary.length === MAX_TERMS) break;
  }
  return vocabulary;
}
