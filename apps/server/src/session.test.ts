import assert from "node:assert/strict";
import { test } from "node:test";
import { audio, FakeRefiner, FakeTranscriber, settle, silent } from "./fixtures.ts";
import type { ServerMessage } from "./protocol.ts";
import { DictationSession } from "./session.ts";

function setup() {
  const transcriber = new FakeTranscriber();
  const refiner = new FakeRefiner();
  const messages: ServerMessage[] = [];
  let ended = false;
  const session = new DictationSession({
    createTranscriber: transcriber.create,
    createRefiner: refiner.create,
    send: (message) => messages.push(message),
    end: () => {
      ended = true;
    },
    log: silent,
  });
  return { session, transcriber, refiner, messages, ended: () => ended };
}

test("a dictation passes on the text heard, then ends with the refined text", async () => {
  const { session, transcriber, refiner, messages, ended } = setup();
  session.start("");
  transcriber.events.ready();
  session.audio(audio(500));
  transcriber.events.delta(" hello");
  transcriber.events.delta(" world");
  session.stop();
  transcriber.events.final(" hello world ");
  assert.deepEqual(refiner.calls[0]?.input, { text: "hello world", instructions: "" });

  refiner.calls[0]?.resolve("Hello, world.");
  await settle();

  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "delta", text: "hello" },
    { type: "delta", text: " world" },
    { type: "done", text: "Hello, world." },
  ]);
  assert.ok(ended());
  assert.ok(transcriber.closed);
  assert.ok(refiner.closed);
});

test("the audio is one turn: it is committed once, when the speaker stops", () => {
  const { session, transcriber } = setup();
  session.start("");
  session.audio(audio(2000));
  session.audio(audio(2000));
  assert.equal(transcriber.commits, 0);

  session.stop();
  session.stop();
  assert.equal(transcriber.commits, 1);

  session.audio(audio(500));
  assert.equal(transcriber.bytes, audio(4000).length);
});

test("the refiner is prepared when the dictation starts, and gets the speaker's instructions", () => {
  const { session, transcriber, refiner } = setup();
  session.start("Write formally.");
  assert.equal(refiner.created, 1);

  session.stop();
  transcriber.events.final("hey there");
  assert.deepEqual(refiner.calls[0]?.input, { text: "hey there", instructions: "Write formally." });
});

test("a failed refinement falls back to the transcript", async () => {
  const { session, transcriber, refiner, messages } = setup();
  session.start("");
  session.stop();
  transcriber.events.final("keep me");
  refiner.calls[0]?.reject(new Error("boom"));
  await settle();
  assert.deepEqual(messages, [{ type: "done", text: "keep me" }]);
});

test("an empty refinement falls back to the transcript", async () => {
  const { session, transcriber, refiner, messages } = setup();
  session.start("");
  session.stop();
  transcriber.events.final("keep me");
  refiner.calls[0]?.resolve("");
  await settle();
  assert.deepEqual(messages, [{ type: "done", text: "keep me" }]);
});

test("a dictation without words ends without refining", async () => {
  const { session, transcriber, refiner, messages, ended } = setup();
  session.start("");
  session.audio(audio(1000));
  session.stop();
  transcriber.events.final(" ");
  await settle();
  assert.deepEqual(messages, [{ type: "done", text: "" }]);
  assert.equal(refiner.calls.length, 0);
  assert.ok(ended());
});

test("a transcript that does not complete is replaced by the text heard", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, transcriber, refiner, messages } = setup();
  session.start("");
  transcriber.events.delta(" so far");
  transcriber.events.delta(" so good");
  session.stop();
  t.mock.timers.tick(5_000);
  assert.deepEqual(refiner.calls[0]?.input.text, "so far so good");

  transcriber.events.final("late");
  transcriber.events.delta(" later");
  refiner.calls[0]?.resolve("So far, so good.");
  await settle();
  assert.deepEqual(messages.slice(2), [{ type: "done", text: "So far, so good." }]);
  assert.equal(refiner.calls.length, 1);
});

test("a dictation that hears nothing and gets no transcript times out", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, messages, ended } = setup();
  session.start("");
  session.audio(audio(1000));
  session.stop();
  t.mock.timers.tick(5_000);
  assert.deepEqual(messages, [
    { type: "error", code: "timeout", message: "Transcription timed out" },
  ]);
  assert.ok(ended());
});

test("a transcription error ends the session", () => {
  const { session, transcriber, refiner, messages, ended } = setup();
  session.start("");
  transcriber.events.error(new Error("upstream"));
  assert.deepEqual(messages, [
    { type: "error", code: "transcription_failed", message: "Transcription failed" },
  ]);
  assert.ok(ended());
  assert.ok(refiner.closed);

  session.audio(audio(500));
  transcriber.events.delta("late");
  assert.equal(messages.length, 1);
});

test("a transcription error after the transcript is complete changes nothing", async () => {
  const { session, transcriber, refiner, messages } = setup();
  session.start("");
  session.stop();
  transcriber.events.final("text");
  transcriber.events.error(new Error("connection closed"));
  refiner.calls[0]?.resolve("Text.");
  await settle();
  assert.deepEqual(messages, [{ type: "done", text: "Text." }]);
});

test("audio or stop before start, or a second start, is rejected", () => {
  for (const act of [
    (session: DictationSession) => session.audio(audio(100)),
    (session: DictationSession) => session.stop(),
    (session: DictationSession) => {
      session.start("");
      session.start("");
    },
  ]) {
    const { session, messages, ended } = setup();
    act(session);
    assert.deepEqual(messages, [
      { type: "error", code: "bad_request", message: "Unexpected message" },
    ]);
    assert.ok(ended());
  }
});

test("closing drops the session without a message", async () => {
  const { session, transcriber, refiner, messages, ended } = setup();
  session.start("");
  session.stop();
  transcriber.events.final("text");
  session.close();
  assert.ok(refiner.calls[0]?.signal.aborted);

  refiner.calls[0]?.resolve("Text.");
  await settle();
  assert.deepEqual(messages, []);
  assert.ok(ended());
  assert.ok(transcriber.closed);
  assert.ok(refiner.closed);
});
