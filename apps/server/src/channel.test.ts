import assert from "node:assert/strict";
import { test } from "node:test";
import { Channel, type ChannelOptions } from "./channel.ts";
import { FakeTranscriber, silence, silent, speech } from "./fixtures.ts";
import type { ResilientEvents } from "./resilient.ts";

function setup(options: ChannelOptions = {}) {
  const transcriber = new FakeTranscriber();
  let inner!: ResilientEvents;
  const events: unknown[] = [];
  const channel = new Channel(
    (resilient) => {
      inner = resilient;
      return transcriber.create(resilient);
    },
    {
      ready: () => events.push("ready"),
      draft: (text) => events.push(["draft", text]),
      segment: (segment) => events.push(["segment", segment]),
      drained: () => events.push("drained"),
      error: (error) => events.push(["error", error.message]),
    },
    options,
    silent,
  );
  return { channel, transcriber, events, inner: () => inner };
}

/** A second of speech and the pause that ends it. */
const utterance = Buffer.concat([speech(1000), silence(1000)]);

test("speech becomes a turn, its text a draft, and its transcript a segment", () => {
  const { channel, transcriber, events, inner } = setup();
  inner().ready();
  channel.audio(utterance);
  assert.equal(transcriber.commits, 1);
  // The speech and the pause that ended it. Nothing came before it to keep as pre-roll.
  assert.equal(transcriber.bytes, 1800 * 48);
  assert.equal(channel.speechBytes, 1800 * 48);

  inner().delta(0, " hello");
  inner().delta(0, " there");
  inner().final(0, " Hello there. ");
  assert.deepEqual(events, [
    "ready",
    ["draft", "hello"],
    ["draft", "hello there"],
    ["segment", { start: 0, end: 1.8, text: "Hello there." }],
    ["draft", ""],
  ]);
});

test("segments go out in the order they were spoken", () => {
  const { channel, events, inner } = setup();
  channel.audio(Buffer.concat([utterance, utterance]));
  inner().final(1, "Second.");
  // Its text is still a draft, because the turn before it is not out yet.
  assert.deepEqual(events, [["draft", "Second."]]);

  inner().final(0, "First.");
  assert.deepEqual(events.slice(1), [
    ["segment", { start: 0, end: 1.8, text: "First." }],
    ["segment", { start: 1.8, end: 3.8, text: "Second." }],
    ["draft", ""],
  ]);
});

test("a turn that does not complete in time passes on what was heard", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { channel, events, inner } = setup();
  channel.audio(utterance);
  inner().delta(0, " so far");
  t.mock.timers.tick(5_000);
  inner().final(0, "So far, so good.");
  assert.deepEqual(events, [
    ["draft", "so far"],
    ["segment", { start: 0, end: 1.8, text: "so far" }],
    ["draft", ""],
  ]);
});

test("a turn with nothing heard that does not complete makes no segment", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { channel, events, inner } = setup();
  channel.audio(Buffer.concat([utterance, utterance]));
  t.mock.timers.tick(5_000);
  assert.deepEqual(events, []);

  channel.audio(utterance);
  inner().final(2, "Third.");
  assert.deepEqual(events, [["segment", { start: 3.8, end: 5.8, text: "Third." }]]);
});

test("a restart voids the text heard for the turns that are not final", () => {
  const { channel, events, inner } = setup();
  channel.audio(utterance);
  channel.audio(speech(500));
  inner().final(0, "Done.");
  inner().delta(1, " going");
  inner().restarted();
  inner().delta(1, " again");
  assert.deepEqual(events, [
    ["segment", { start: 0, end: 1.8, text: "Done." }],
    ["draft", "going"],
    ["draft", ""],
    ["draft", "again"],
  ]);
});

test("the stop commits the open turn and the channel drains once its segments are out", () => {
  const { channel, transcriber, events, inner } = setup();
  channel.audio(speech(500));
  channel.stop();
  assert.equal(transcriber.commits, 1);
  assert.deepEqual(events, []);

  inner().final(0, "Bye.");
  assert.deepEqual(events, [["segment", { start: 0, end: 0.5, text: "Bye." }], "drained"]);
  channel.audio(speech(500));
  assert.equal(transcriber.commits, 1);
});

test("a channel with nothing pending drains at the stop", () => {
  const { channel, events } = setup();
  channel.audio(silence(1000));
  channel.stop();
  assert.deepEqual(events, ["drained"]);
});

test("the offset moves the clock", () => {
  const { channel, events, inner } = setup({ offset: 100 });
  channel.audio(utterance);
  inner().final(0, "Late.");
  assert.deepEqual(events, [["segment", { start: 100, end: 101.8, text: "Late." }]]);
});

test("closing closes the transcriber", () => {
  const { channel, transcriber } = setup();
  channel.close();
  assert.ok(transcriber.closed);
});
