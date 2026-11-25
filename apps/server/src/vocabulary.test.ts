import assert from "node:assert/strict";
import { test } from "node:test";
import { MAX_TERM_CHARS, MAX_TERMS, normalizeVocabulary } from "./vocabulary.ts";

test("each term is on one line, without surrounding spaces", () => {
  assert.deepEqual(normalizeVocabulary(["  Claude ", "Visual\nStudio  Code", "\tSupabase"]), [
    "Claude",
    "Visual Studio Code",
    "Supabase",
  ]);
});

test("angle brackets are taken out, since the transcription service rejects them", () => {
  assert.deepEqual(normalizeVocabulary(["<Claude>", "a<b", "<>"]), ["Claude", "ab"]);
});

test("blanks and terms already listed in another case are left out", () => {
  assert.deepEqual(normalizeVocabulary(["Claude", "", "   ", "claude", "CLAUDE", "Voice"]), [
    "Claude",
    "Voice",
  ]);
});

test("a term too long to be a word or a name is left out", () => {
  const long = "x".repeat(MAX_TERM_CHARS + 1);
  assert.deepEqual(normalizeVocabulary([long, "x".repeat(MAX_TERM_CHARS)]), [
    "x".repeat(MAX_TERM_CHARS),
  ]);
});

test("the first terms are kept when there are too many", () => {
  const terms = Array.from({ length: MAX_TERMS + 10 }, (_, i) => `term ${i}`);
  const vocabulary = normalizeVocabulary(terms);
  assert.equal(vocabulary.length, MAX_TERMS);
  assert.equal(vocabulary.at(-1), `term ${MAX_TERMS - 1}`);
});
