import assert from "node:assert/strict";
import { test } from "node:test";
import type { Segment } from "./protocol.ts";
import { countWords, Windows } from "./windows.ts";

let next = 1;
function segment(start: number, end: number, words = 30): Segment {
  const id = next;
  next += 1;
  return { id, channel: "me", start, end, text: Array(words).fill("word").join(" ") };
}

const options = { minSeconds: 60, minWords: 50, gapSeconds: 1.5, maxSeconds: 120 };

test("a window closes before a segment that comes after a pause, once it is long enough", () => {
  const windows = new Windows(options);
  assert.equal(windows.push(segment(0, 30)), undefined);
  assert.equal(windows.push(segment(30, 61)), undefined);
  // Long enough, but there is no pause before the next segment.
  assert.equal(windows.push(segment(61.5, 70)), undefined);
  const closed = windows.push(segment(72, 80));
  assert.deepEqual(
    closed?.map((s) => [s.start, s.end]),
    [
      [0, 30],
      [30, 61],
      [61.5, 70],
    ],
  );
  assert.deepEqual(
    windows.flush()?.map((s) => s.start),
    [72],
  );
});

test("a window that is long but short of words stays open", () => {
  const windows = new Windows(options);
  windows.push(segment(0, 70, 5));
  assert.equal(windows.push(segment(80, 90, 5)), undefined);
  assert.equal(windows.push(segment(100, 110, 5)), undefined);
  assert.equal(windows.push(segment(115, 118, 5)), undefined);
  // Past the longest span, it closes without a pause.
  assert.equal(windows.push(segment(120.5, 125)), undefined);
  assert.equal(windows.push(segment(125, 130))?.length, 5);
});

test("the span is measured from the earliest start to the latest end, whatever the order", () => {
  const windows = new Windows(options);
  windows.push(segment(10, 65));
  windows.push(segment(0, 5));
  assert.equal(windows.push(segment(67, 70))?.length, 2);
});

test("flush closes what is open, once", () => {
  const windows = new Windows(options);
  assert.equal(windows.flush(), undefined);
  windows.push(segment(0, 1));
  assert.equal(windows.flush()?.length, 1);
  assert.equal(windows.flush(), undefined);
});

test("words are counted by the spaces between them", () => {
  assert.equal(countWords("  so the plan\nis simple  "), 5);
  assert.equal(countWords(""), 0);
});
