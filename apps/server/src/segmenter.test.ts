import assert from "node:assert/strict";
import { test } from "node:test";
import { silence, speech } from "./fixtures.ts";
import { Segmenter, type SegmenterAction } from "./segmenter.ts";

function shape(actions: SegmenterAction[]): string {
  return actions.map((action) => action.type).join(" ");
}

function audioMs(actions: SegmenterAction[]): number {
  const bytes = actions.reduce((sum, a) => sum + (a.type === "audio" ? a.pcm.length : 0), 0);
  return bytes / 48;
}

/** The times of the segments: when each opened and when it was committed. */
function times(actions: SegmenterAction[]): number[] {
  return actions.flatMap((action) =>
    action.type === "open" ? [action.start] : action.type === "commit" ? [action.end] : [],
  );
}

test("silence produces nothing", () => {
  const segmenter = new Segmenter();
  assert.deepEqual(segmenter.push(silence(3000)), []);
  assert.deepEqual(segmenter.flush(), []);
});

test("speech followed by a pause is one segment, opened and committed with its times", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(Buffer.concat([silence(500), speech(1000), silence(1000)]));
  assert.equal(shape(actions), "open audio commit");
  // 300 ms of pre-roll, the speech, and the 800 ms pause that ended the segment.
  assert.equal(audioMs(actions), 300 + 1000 + 800);
  // It opens 300 ms before the speech and ends with the pause.
  assert.deepEqual(times(actions), [0.2, 2.3]);
});

test("the pre-roll keeps the audio from before the onset", () => {
  const segmenter = new Segmenter();
  const [, audio] = segmenter.push(Buffer.concat([silence(500), speech(200)]));
  assert.equal(audio?.type, "audio");
  assert.ok(audio?.type === "audio" && audio.pcm.subarray(0, 480).equals(silence(10)));
});

test("silence between segments is not forwarded", () => {
  const segmenter = new Segmenter();
  segmenter.push(Buffer.concat([speech(500), silence(900)]));
  assert.deepEqual(segmenter.push(silence(5000)), []);
});

test("each pause commits its own segment", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(
    Buffer.concat([speech(800), silence(1000), speech(800), silence(1000)]),
  );
  assert.equal(shape(actions), "open audio commit open audio commit");
  // The pre-roll of the second reaches back to the end of the first.
  assert.deepEqual(times(actions), [0, 1.6, 1.6, 3.4]);
});

test("a pause shorter than the limit keeps the segment open", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(Buffer.concat([speech(800), silence(500), speech(800)]));
  assert.equal(shape(actions), "open audio");
});

test("a long segment commits at a short pause", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(Buffer.concat([speech(15_500), silence(300), speech(500)]));
  assert.equal(shape(actions), "open audio commit open audio");
});

test("speech without pauses commits at the hard limit", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(speech(30_000));
  assert.equal(shape(actions), "open audio commit open audio");
  assert.equal(audioMs(actions.slice(0, 2)), 25_000);
});

test("flush commits the open segment", () => {
  const segmenter = new Segmenter();
  assert.equal(shape(segmenter.push(speech(500))), "open audio");
  assert.deepEqual(segmenter.flush(), [{ type: "commit", end: 0.5 }]);
  assert.deepEqual(segmenter.flush(), []);
});

test("the clock starts at the offset", () => {
  const segmenter = new Segmenter(undefined, 100);
  const actions = [...segmenter.push(speech(1000)), ...segmenter.flush()];
  assert.deepEqual(times(actions), [100, 101]);
  assert.equal(segmenter.time, 101);
});

test("chunk boundaries do not change the result", () => {
  const stream = Buffer.concat([silence(300), speech(900), silence(900), speech(400)]);
  const whole = new Segmenter();
  const expected = [...whole.push(stream), ...whole.flush()];

  const chunked = new Segmenter();
  const actions: SegmenterAction[] = [];
  for (let offset = 0; offset < stream.length; offset += 1001) {
    actions.push(...chunked.push(stream.subarray(offset, offset + 1001)));
  }
  actions.push(...chunked.flush());

  assert.equal(shape(actions).replaceAll(/audio( audio)+/g, "audio"), shape(expected));
  assert.equal(audioMs(actions), audioMs(expected));
  assert.deepEqual(times(actions), times(expected));
});
