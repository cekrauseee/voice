import assert from "node:assert/strict";
import { test } from "node:test";
import { ReplyReader, readAnswer } from "./agent.ts";

/** What the reader passes on for each chunk. */
function read(...chunks: string[]): string[] {
  const reader = new ReplyReader();
  return chunks.map((chunk) => reader.push(chunk));
}

test("the reply is read as it comes, and nothing after it", () => {
  assert.deepEqual(read('{"re', 'ply": "Oi', ", tudo", ' bem?","profile":null}'), [
    "",
    "Oi",
    ", tudo",
    " bem?",
  ]);
  assert.deepEqual(read('{"reply":"Oi"', ',"add_terms":["x"]}'), ["Oi", ""]);
});

test("escapes in the reply are read once they are whole", () => {
  assert.deepEqual(read('{"reply":"Diz \\', '"merge\\"', "\\nok \\u00e9", '"}'), [
    "Diz ",
    '"merge"',
    "\nok é",
    "",
  ]);
  assert.deepEqual(read('{"reply":"\\u00', 'e9"'), ["", "é"]);
});

test("a character written as two escapes is passed on whole", () => {
  assert.deepEqual(read('{"reply":"\\ud83d', '\\ude80!"'), ["", "🚀!"]);
});

test("an answer that does not begin with the reply passes nothing on", () => {
  assert.deepEqual(read('{"profile":null,"reply":"Oi"}'), [""]);
});

test("the answer is read, and terms the speaker has are not suggested", () => {
  assert.deepEqual(
    readAnswer(
      JSON.stringify({
        reply: " Certo. ",
        profile: {
          instructions: " Seja breve. ",
          transcription_prompt: "Desenvolvedor\nfalando de Git.",
          languages: ["pt-BR", "en", "pt"],
          terms: ["Merge", "<rebase>", "claude", ""],
        },
        add_terms: [" Git ", "git"],
      }),
      ["Claude"],
    ),
    {
      reply: "Certo.",
      profile: {
        instructions: "Seja breve.",
        transcriptionPrompt: "Desenvolvedor falando de Git.",
        languages: ["pt", "en"],
        terms: ["Merge", "rebase"],
      },
      addTerms: ["Git"],
    },
  );
  assert.equal(readAnswer('{"reply":"Oi","profile":null,"add_terms":[]}', []).profile, undefined);
});
