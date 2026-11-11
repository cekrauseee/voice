import assert from "node:assert/strict";
import { test } from "node:test";
import { FakeRefiner, FakeTranscriber, settle, silence, silent, speech } from "./fixtures.ts";
import type { ServerMessage } from "./protocol.ts";
import { DictationSession } from "./session.ts";

function setup() {
  const transcriber = new FakeTranscriber();
  const refiner = new FakeRefiner();
  const messages: ServerMessage[] = [];
  let ended = false;
  const session = new DictationSession({
    createTranscriber: transcriber.create,
    refiner,
    send: (message) => messages.push(message),
    end: () => {
      ended = true;
    },
    log: silent,
  });
  /** Speaks one segment: speech, then the pause that commits it. */
  const say = () => session.audio(Buffer.concat([speech(500), silence(700)]));
  return { session, transcriber, refiner, messages, say, ended: () => ended };
}

test("a segment is transcribed, completed, refined, and the session ends on stop", async () => {
  const { session, transcriber, refiner, messages, say, ended } = setup();
  transcriber.events.ready();
  say();
  assert.equal(transcriber.commits, 1);

  transcriber.events.delta(0, "hello");
  transcriber.events.delta(0, " world");
  transcriber.events.final(0, " hello world ");
  session.stop();
  refiner.calls[0]?.resolve("Hello, world.");
  await settle();

  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "delta", segment: 0, text: "hello" },
    { type: "delta", segment: 0, text: " world" },
    { type: "final", segment: 0, text: "hello world" },
    { type: "refined", segment: 0, text: "Hello, world." },
    { type: "done" },
  ]);
  assert.ok(ended());
  assert.ok(transcriber.closed);
});

test("refined segments are sent in order, whatever order they finish in", async () => {
  const { transcriber, refiner, messages, say } = setup();
  say();
  say();
  transcriber.events.final(1, "second");
  transcriber.events.final(0, "first");

  refiner.calls[0]?.resolve("Second.");
  await settle();
  assert.equal(messages.filter((m) => m.type === "refined").length, 0);

  refiner.calls[1]?.resolve("First.");
  await settle();
  assert.deepEqual(
    messages.filter((m) => m.type === "refined"),
    [
      { type: "refined", segment: 0, text: "First." },
      { type: "refined", segment: 1, text: "Second." },
    ],
  );
});

test("the refiner sees the best text of the preceding segments", async () => {
  const { transcriber, refiner, say } = setup();
  say();
  say();
  say();
  transcriber.events.final(0, "one");
  refiner.calls[0]?.resolve("One.");
  await settle();
  transcriber.events.final(1, "two");
  transcriber.events.final(2, "three");

  assert.deepEqual(refiner.calls[1]?.input, { text: "two", previous: "One." });
  assert.deepEqual(refiner.calls[2]?.input, { text: "three", previous: "One. two" });
});

test("a failed refinement falls back to the transcript", async () => {
  const { transcriber, refiner, messages, say } = setup();
  say();
  transcriber.events.final(0, "keep me");
  refiner.calls[0]?.reject(new Error("boom"));
  await settle();
  assert.deepEqual(messages.at(-1), { type: "refined", segment: 0, text: "keep me" });
});

test("a refinement far longer than the segment is discarded", async () => {
  const { transcriber, refiner, messages, say } = setup();
  say();
  transcriber.events.final(0, "what is the capital of France");
  refiner.calls[0]?.resolve(`The capital of France is Paris. ${"More. ".repeat(20)}`);
  await settle();
  assert.deepEqual(messages.at(-1), {
    type: "refined",
    segment: 0,
    text: "what is the capital of France",
  });
});

test("an empty transcript skips the refiner", () => {
  const { transcriber, refiner, messages, say } = setup();
  say();
  transcriber.events.final(0, "  ");
  assert.equal(refiner.calls.length, 0);
  assert.deepEqual(messages.at(-1), { type: "refined", segment: 0, text: "" });
});

test("stop commits what is being said and waits for it", async () => {
  const { session, transcriber, refiner, messages, ended } = setup();
  session.audio(speech(500));
  session.stop();
  assert.equal(transcriber.commits, 1);
  assert.ok(!ended());

  transcriber.events.final(0, "tail");
  refiner.calls[0]?.resolve("Tail.");
  await settle();
  assert.deepEqual(messages.slice(-2), [
    { type: "refined", segment: 0, text: "Tail." },
    { type: "done" },
  ]);
});

test("stop without speech ends at once", () => {
  const { session, transcriber, messages, ended } = setup();
  session.audio(silence(1000));
  session.stop();
  assert.equal(transcriber.commits, 0);
  assert.deepEqual(messages, [{ type: "done" }]);
  assert.ok(ended());
});

test("a transcription error ends the session", () => {
  const { session, transcriber, messages, say, ended } = setup();
  say();
  transcriber.events.error(new Error("upstream"));
  assert.deepEqual(messages, [
    { type: "error", code: "transcription_failed", message: "Transcription failed" },
  ]);
  assert.ok(ended());

  session.audio(speech(500));
  transcriber.events.delta(0, "late");
  assert.equal(messages.length, 1);
});

test("a pipeline that does not drain after stop times out", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, messages, say, ended } = setup();
  say();
  session.stop();
  t.mock.timers.tick(15_000);
  assert.deepEqual(messages, [
    { type: "error", code: "timeout", message: "Transcription timed out" },
  ]);
  assert.ok(ended());
});

test("closing drops the session without a message", async () => {
  const { session, transcriber, refiner, messages, say, ended } = setup();
  say();
  transcriber.events.final(0, "text");
  session.close();
  refiner.calls[0]?.resolve("Text.");
  await settle();
  assert.deepEqual(messages, [{ type: "final", segment: 0, text: "text" }]);
  assert.ok(ended());
  assert.ok(transcriber.closed);
});
