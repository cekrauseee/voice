import assert from "node:assert/strict";
import { test } from "node:test";
import type { Segment } from "./protocol.ts";
import { parseRevision } from "./reviser.ts";

const window: Segment[] = [
  { id: 4, channel: "me", start: 0, end: 2, text: "so um the plan is" },
  { id: 5, channel: "others", start: 2, end: 3, text: "uh huh" },
  { id: 6, channel: "me", start: 3, end: 5, text: "simple we ship friday" },
];

function answer(segments: object[]): string {
  return JSON.stringify({ segments });
}

test("the pieces of a revision are read in order, without the empty ones", () => {
  const pieces = parseRevision(
    answer([
      { anchor: 4, channel: "me", text: " So the plan is " },
      { anchor: 5, channel: "others", text: "" },
      { anchor: 6, channel: "me", text: "simple: we ship Friday." },
    ]),
    window,
  );
  assert.deepEqual(pieces, [
    { anchor: 4, channel: "me", text: "So the plan is" },
    { anchor: 6, channel: "me", text: "simple: we ship Friday." },
  ]);
});

test("a revision that does not fit the window is refused", () => {
  const bad = [
    "not json",
    answer([]),
    JSON.stringify({ pieces: [] }),
    answer([{ anchor: 7, channel: "me", text: "Outside." }]),
    answer([
      { anchor: 6, channel: "me", text: "Backwards." },
      { anchor: 4, channel: "me", text: "Backwards." },
    ]),
    answer([{ anchor: 4, channel: "you", text: "Whose side?" }]),
    answer([{ anchor: 4, channel: "me", text: "Short." }]),
    answer([{ anchor: 4, channel: "me", text: "Made up. ".repeat(20) }]),
    answer([{ anchor: 4, channel: "me", text: 7 }]),
  ];
  for (const text of bad) assert.throws(() => parseRevision(text, window), { name: "Error" });
});
