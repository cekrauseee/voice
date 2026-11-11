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

test("silence produces nothing", () => {
  const segmenter = new Segmenter();
  assert.deepEqual(segmenter.push(silence(3000)), []);
  assert.deepEqual(segmenter.flush(), []);
});

test("speech followed by a pause is one committed segment", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(Buffer.concat([silence(500), speech(1000), silence(1000)]));
  assert.equal(shape(actions), "audio commit");
  // 300 ms of pre-roll, the speech, and the 600 ms pause that ended the segment.
  assert.equal(audioMs(actions), 300 + 1000 + 600);
});

test("the pre-roll keeps the audio from before the onset", () => {
  const segmenter = new Segmenter();
  const [first] = segmenter.push(Buffer.concat([silence(500), speech(200)]));
  assert.equal(first?.type, "audio");
  assert.ok(first?.type === "audio" && first.pcm.subarray(0, 480).equals(silence(10)));
});

test("silence between segments is not forwarded", () => {
  const segmenter = new Segmenter();
  segmenter.push(Buffer.concat([speech(500), silence(700)]));
  assert.deepEqual(segmenter.push(silence(5000)), []);
});

test("each pause commits its own segment", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(
    Buffer.concat([speech(800), silence(700), speech(800), silence(700)]),
  );
  assert.equal(shape(actions), "audio commit audio commit");
});

test("a pause shorter than the limit keeps the segment open", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(Buffer.concat([speech(800), silence(400), speech(800)]));
  assert.equal(shape(actions), "audio");
});

test("a long segment commits at a short pause", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(Buffer.concat([speech(12_500), silence(300), speech(500)]));
  assert.equal(shape(actions), "audio commit audio");
});

test("speech without pauses commits at the hard limit", () => {
  const segmenter = new Segmenter();
  const actions = segmenter.push(speech(25_000));
  assert.equal(shape(actions), "audio commit audio");
  assert.equal(audioMs(actions.slice(0, 1)), 20_000);
});

test("flush commits the open segment", () => {
  const segmenter = new Segmenter();
  assert.equal(shape(segmenter.push(speech(500))), "audio");
  assert.equal(shape(segmenter.flush()), "commit");
  assert.deepEqual(segmenter.flush(), []);
});

test("chunk boundaries do not change the result", () => {
  const stream = Buffer.concat([silence(300), speech(900), silence(700), speech(400)]);
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
});
