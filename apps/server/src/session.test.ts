import assert from "node:assert/strict";
import { test } from "node:test";
import { audio, FakeRefiner, FakeTranscriber, prices, settle, silent, unused } from "./fixtures.ts";
import type { ServerMessage } from "./protocol.ts";
import { RefinementError } from "./refiner.ts";
import { DictationSession } from "./session.ts";

function setup(log = silent) {
  const transcriber = new FakeTranscriber();
  const refiner = new FakeRefiner();
  const messages: ServerMessage[] = [];
  let ended = false;
  const session = new DictationSession({
    createTranscriber: transcriber.create,
    createLiveTranscriber: transcriber.createLive,
    createRefiner: refiner.create,
    prices,
    send: (message) => messages.push(message),
    end: () => {
      ended = true;
    },
    log,
  });
  return { session, transcriber, refiner, messages, ended: () => ended };
}

test("a dictation passes on the text heard, then ends with the refined text", async () => {
  const { session, transcriber, refiner, messages, ended } = setup();
  session.start({ live: true });
  transcriber.events.ready();
  session.audio(audio(500));
  transcriber.events.delta(0, " hello");
  transcriber.events.delta(0, " world");
  session.stop();
  transcriber.events.final(0, " hello world ");
  assert.deepEqual(refiner.calls[0]?.input, {
    text: "hello world",
    instructions: "",
    translateTo: "",
    vocabulary: [],
    context: "",
  });

  refiner.calls[0]?.resolve("Hello, world.", [3, 2]);
  await settle();

  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "delta", text: "hello" },
    { type: "delta", text: " world" },
    {
      type: "done",
      text: "Hello, world.",
      // Half a second of audio at a cent a second, 3 tokens read and 2 written.
      usage: { audio_seconds: 0.5, input_tokens: 3, output_tokens: 2, cost: 0.012 },
    },
  ]);
  assert.ok(ended());
  assert.ok(transcriber.closed);
  assert.ok(refiner.closed);
});

test("the audio is one turn: it is committed once, when the speaker stops", () => {
  const { session, transcriber } = setup();
  session.start({ live: true });
  session.audio(audio(2000));
  session.audio(audio(2000));
  assert.equal(transcriber.commits, 0);

  session.stop();
  session.stop();
  assert.equal(transcriber.commits, 1);

  session.audio(audio(500));
  assert.equal(transcriber.bytes, audio(4000).length);
});

test("the refiner is prepared when the dictation starts, and gets what the speaker asked for", () => {
  const { session, transcriber, refiner } = setup();
  session.start({
    instructions: "Write formally.",
    translateTo: "Spanish",
    context: "Hola Ana,",
    live: true,
  });
  assert.equal(refiner.created, 1);

  session.stop();
  transcriber.events.final(0, "hey there");
  assert.deepEqual(refiner.calls[0]?.input, {
    text: "hey there",
    instructions: "Write formally.",
    translateTo: "Spanish",
    vocabulary: [],
    context: "Hola Ana,",
  });
});

test("a dictation that continues the text before the cursor is spaced from it", async () => {
  const { session, transcriber, refiner, messages } = setup();
  session.start({ context: "Thanks for the update", live: true });
  session.stop();
  transcriber.events.final(0, "and see you friday");
  refiner.calls[0]?.resolve("and see you Friday.");
  await settle();
  assert.deepEqual(messages, [{ type: "done", text: " and see you Friday.", usage: unused }]);
});

test("the transcript a failed refinement falls back to is spaced from the context too", async () => {
  const { session, transcriber, refiner, messages } = setup();
  session.start({ context: "Thanks", live: true });
  session.stop();
  transcriber.events.final(0, "keep me");
  refiner.calls[0]?.reject(new Error("boom"));
  await settle();
  assert.deepEqual(messages, [{ type: "done", text: " keep me", usage: unused }]);
});

test("the context is logged by its length only", (t) => {
  const info = t.mock.fn(silent.info);
  const { session } = setup({ ...silent, info });
  session.start({ context: "Private words", live: true });
  const started = info.mock.calls.find((call) => call.arguments[0] === "started");
  assert.deepEqual(started?.arguments[1], {
    instructions_chars: 0,
    live: true,
    translates: false,
    vocabulary_terms: 0,
    context_chars: 13,
  });
});

test("the speaker's vocabulary goes to the transcriber and the refiner, cleaned up", () => {
  const { session, transcriber, refiner } = setup();
  session.start({ vocabulary: [" Claude ", "claude", "", "Supa\nbase", "<Voice>"], live: true });
  assert.deepEqual(transcriber.hints, { keywords: ["Claude", "Supa base", "Voice"] });

  session.stop();
  transcriber.events.final(0, "ask cloud");
  assert.deepEqual(refiner.calls[0]?.input.vocabulary, ["Claude", "Supa base", "Voice"]);
});

test("a failed refinement falls back to the transcript", async () => {
  const { session, transcriber, refiner, messages } = setup();
  session.start({ live: true });
  session.stop();
  transcriber.events.final(0, "keep me");
  refiner.calls[0]?.reject(new Error("boom"));
  await settle();
  assert.deepEqual(messages, [{ type: "done", text: "keep me", usage: unused }]);
});

test("a failed translation falls back to the transcript and counts the rewrite's tokens", async (t) => {
  const warn = t.mock.fn(silent.warn);
  const { session, transcriber, refiner, messages } = setup({ ...silent, warn });
  session.start({ translateTo: "Spanish", live: true });
  session.stop();
  transcriber.events.final(0, "um keep me");
  refiner.calls[0]?.reject(
    new RefinementError(new Error("boom"), { inputTokens: 4, outputTokens: 2 }),
  );
  await settle();

  assert.deepEqual(messages, [
    {
      type: "done",
      text: "um keep me",
      usage: { audio_seconds: 0, input_tokens: 4, output_tokens: 2, cost: 0.008 },
    },
  ]);
  assert.equal(warn.mock.calls.length, 1);
  assert.equal(warn.mock.calls[0]?.arguments[0], "refinement failed");
});

test("an empty refinement falls back to the transcript", async () => {
  const { session, transcriber, refiner, messages } = setup();
  session.start({ live: true });
  session.stop();
  transcriber.events.final(0, "keep me");
  refiner.calls[0]?.resolve("", [4, 0]);
  await settle();
  // The tokens it read were paid for, so they are counted.
  assert.deepEqual(messages, [
    {
      type: "done",
      text: "keep me",
      usage: { audio_seconds: 0, input_tokens: 4, output_tokens: 0, cost: 0.004 },
    },
  ]);
});

test("a dictation without words ends without refining", async () => {
  const { session, transcriber, refiner, messages, ended } = setup();
  session.start({ context: "Text before", live: true });
  session.audio(audio(1000));
  session.stop();
  transcriber.events.final(0, " ");
  await settle();
  assert.deepEqual(messages, [
    {
      type: "done",
      text: "",
      usage: { audio_seconds: 1, input_tokens: 0, output_tokens: 0, cost: 0.01 },
    },
  ]);
  assert.equal(refiner.calls.length, 0);
  assert.ok(ended());
});

test("a transcript that does not complete is replaced by the text heard", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, transcriber, refiner, messages } = setup();
  session.start({ live: true });
  transcriber.events.ready();
  transcriber.events.delta(0, " so far");
  transcriber.events.delta(0, " so good");
  session.stop();
  t.mock.timers.tick(5_000);
  assert.deepEqual(refiner.calls[0]?.input.text, "so far so good");

  transcriber.events.final(0, "late");
  transcriber.events.delta(0, " later");
  refiner.calls[0]?.resolve("So far, so good.");
  await settle();
  assert.deepEqual(messages.slice(3), [{ type: "done", text: "So far, so good.", usage: unused }]);
  assert.equal(refiner.calls.length, 1);
});

test("a dictation that hears nothing and gets no transcript times out", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, transcriber, messages, ended } = setup();
  session.start({ live: true });
  transcriber.events.ready();
  session.audio(audio(1000));
  session.stop();
  t.mock.timers.tick(5_000);
  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "error", code: "timeout", message: "Transcription timed out" },
  ]);
  assert.ok(ended());
});

test("text that keeps coming after the stop keeps the transcript awaited", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, transcriber, refiner } = setup();
  session.start({ live: true });
  transcriber.events.ready();
  session.stop();
  for (const word of [" a", " long", " recording"]) {
    t.mock.timers.tick(4_000);
    transcriber.events.delta(0, word);
  }
  assert.equal(refiner.calls.length, 0);

  transcriber.events.final(0, "A long recording.");
  assert.equal(refiner.calls[0]?.input.text, "A long recording.");
});

test("a speaker who stops before transcription is ready is waited for", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, transcriber, refiner, messages, ended } = setup();
  session.start({ live: true });
  session.audio(audio(1000));
  session.stop();
  assert.equal(transcriber.commits, 1);
  t.mock.timers.tick(8_000);
  assert.ok(!ended());

  transcriber.events.ready();
  t.mock.timers.tick(4_000);
  transcriber.events.final(0, "made it");
  refiner.calls[0]?.resolve("Made it.");
  await settle();
  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "done", text: "Made it.", usage: { ...unused, audio_seconds: 1, cost: 0.01 } },
  ]);
});

test("transcription that does not get ready times out", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, messages, ended } = setup();
  session.start({ live: true });
  session.audio(audio(1000));
  t.mock.timers.tick(10_000);
  assert.deepEqual(messages, [
    { type: "error", code: "timeout", message: "Transcription timed out" },
  ]);
  assert.ok(ended());
});

test("a transcription error ends the session", () => {
  const { session, transcriber, refiner, messages, ended } = setup();
  session.start({ live: true });
  transcriber.events.error(new Error("upstream"));
  assert.deepEqual(messages, [
    { type: "error", code: "transcription_failed", message: "Transcription failed" },
  ]);
  assert.ok(ended());
  assert.ok(refiner.closed);

  session.audio(audio(500));
  transcriber.events.delta(0, "late");
  assert.equal(messages.length, 1);
});

test("a transcription error after the transcript is complete changes nothing", async () => {
  const { session, transcriber, refiner, messages } = setup();
  session.start({ live: true });
  session.stop();
  transcriber.events.final(0, "text");
  transcriber.events.error(new Error("connection closed"));
  refiner.calls[0]?.resolve("Text.");
  await settle();
  assert.deepEqual(messages, [{ type: "done", text: "Text.", usage: unused }]);
});

test("audio or stop before start, or a second start, is rejected", () => {
  for (const act of [
    (session: DictationSession) => session.audio(audio(100)),
    (session: DictationSession) => session.stop(),
    (session: DictationSession) => {
      session.start({ live: true });
      session.start({ live: true });
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
  session.start({ live: true });
  session.stop();
  transcriber.events.final(0, "text");
  session.close();
  assert.ok(refiner.calls[0]?.signal.aborted);

  refiner.calls[0]?.resolve("Text.");
  await settle();
  assert.deepEqual(messages, []);
  assert.ok(ended());
  assert.ok(transcriber.closed);
  assert.ok(refiner.closed);
});

test("a dictation that is not live is transcribed once recorded, at the recording's price", async () => {
  const { session, transcriber, refiner, messages } = setup();
  session.start();
  assert.equal(transcriber.live, false);
  transcriber.events.ready();
  session.audio(audio(1000));
  session.stop();
  transcriber.events.final(0, "hello");
  refiner.calls[0]?.resolve("Hello.");
  await settle();
  assert.deepEqual(messages, [
    { type: "ready" },
    {
      type: "done",
      text: "Hello.",
      // A second of audio at half a cent a second.
      usage: { audio_seconds: 1, input_tokens: 0, output_tokens: 0, cost: 0.005 },
    },
  ]);
});

test("a recording has longer than live text to be transcribed", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, transcriber, messages } = setup();
  session.start();
  transcriber.events.ready();
  session.audio(audio(500));
  session.stop();
  t.mock.timers.tick(30_000);
  assert.deepEqual(messages, [{ type: "ready" }]);
  // A minute, and a tenth of the half second recorded.
  t.mock.timers.tick(30_049);
  assert.deepEqual(messages, [{ type: "ready" }]);
  t.mock.timers.tick(1);
  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "error", code: "timeout", message: "Transcription timed out" },
  ]);
});

test("rejected hints are logged, and the dictation goes on", (t) => {
  const warn = t.mock.fn(silent.warn);
  const { session, transcriber, messages } = setup({ ...silent, warn });
  session.start({ vocabulary: ["Claude"] });
  transcriber.events.hintsRejected({ code: "invalid_value", param: "keywords" });
  assert.deepEqual(warn.mock.calls[0]?.arguments, [
    "transcription hints rejected",
    { code: "invalid_value", param: "keywords", hint: "the dictation goes on without them" },
  ]);
  assert.deepEqual(messages, []);
});
