import assert from "node:assert/strict";
import { test } from "node:test";
import { MAX_LANGUAGES, MAX_PROMPT_CHARS, normalizeLanguages, normalizePrompt } from "./hints.ts";

test("a prompt is one paragraph, without control characters", () => {
  assert.equal(
    normalizePrompt("  A developer\r\ntalking\tabout\u0007 Git.  "),
    "A developer talking about Git.",
  );
  assert.equal(normalizePrompt(" \n "), "");
});

test("a prompt too long for the transcription is cut at a word", () => {
  const prompt = normalizePrompt("merge ".repeat(300));
  assert.ok(prompt.length <= MAX_PROMPT_CHARS);
  assert.ok(prompt.length > MAX_PROMPT_CHARS - 6);
  assert.ok(prompt.endsWith("merge"));

  const word = "x".repeat(MAX_PROMPT_CHARS + 50);
  assert.equal(normalizePrompt(word).length, MAX_PROMPT_CHARS);

  const longest = "y".repeat(MAX_PROMPT_CHARS);
  assert.equal(normalizePrompt(longest), longest);
});

test("languages are two-letter codes, each once, without a region", () => {
  assert.deepEqual(normalizeLanguages([" pt-BR", "EN", "en_US", "pt", "portuguese", "", "e"]), [
    "pt",
    "en",
  ]);
});

test("only the first languages are passed on", () => {
  const codes = ["aa", "bb", "cc", "dd", "ee", "ff", "gg", "hh", "ii", "jj", "kk", "ll"];
  assert.deepEqual(normalizeLanguages(codes), codes.slice(0, MAX_LANGUAGES));
});
