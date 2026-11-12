import assert from "node:assert/strict";
import { test } from "node:test";
import { FakeTranscribers, prices, silence, silent, speech } from "./fixtures.ts";
import { MeetingSession } from "./meeting.ts";
import type { MeetingServerMessage, MeetingStart } from "./protocol.ts";

const start: MeetingStart = {
  type: "start",
  instructions: "",
  first_id: 1,
  offsets: { me: 0, others: 0 },
};

/** A second of speech and the pause that ends it: 2.1 s sent, with the pre-roll. */
const utterance = Buffer.concat([speech(1000), silence(1000)]);

function setup() {
  const sessions = new FakeTranscribers();
  const messages: MeetingServerMessage[] = [];
  let ended = false;
  const session = new MeetingSession({
    createTranscriber: sessions.create,
    prices,
    send: (message) => messages.push(message),
    end: () => {
      ended = true;
    },
    log: silent,
  });
  // The channels open their sessions in order: the speaker's, then the others'.
  const channels = () => {
    const [me, others] = sessions.all;
    if (!me || !others) throw new Error("The meeting did not open both channels");
    return { me, others };
  };
  return { session, sessions, channels, messages, ended: () => ended };
}

test("a meeting passes on the segments of both channels, numbered from where the client says", () => {
  const { session, channels, messages } = setup();
  session.start({ ...start, first_id: 7 });
  const { me, others } = channels();
  me.events.ready();
  assert.deepEqual(messages, []);
  others.events.ready();

  session.audio("me", utterance);
  me.events.delta(0, " hi");
  me.events.final(0, "Hi.");
  session.audio("others", Buffer.concat([speech(500), silence(1000)]));
  others.events.final(0, "Hello.");

  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "draft", channel: "me", text: "hi" },
    { type: "segment", id: 7, channel: "me", start: 0, end: 1.8, text: "Hi." },
    // 1.8 s of speech at a cent a second.
    {
      type: "usage",
      usage: { audio_seconds: 1.8, input_tokens: 0, output_tokens: 0, cost: 0.018 },
    },
    { type: "draft", channel: "me", text: "" },
    { type: "segment", id: 8, channel: "others", start: 0, end: 1.3, text: "Hello." },
    {
      type: "usage",
      usage: { audio_seconds: 3.1, input_tokens: 0, output_tokens: 0, cost: 0.031 },
    },
  ]);
});

test("the offsets move the clocks of the channels", () => {
  const { session, channels, messages } = setup();
  session.start({ ...start, offsets: { me: 60, others: 59.5 } });
  session.audio("others", utterance);
  channels().others.events.final(0, "Late.");
  assert.deepEqual(messages, [
    { type: "segment", id: 1, channel: "others", start: 59.5, end: 61.3, text: "Late." },
    {
      type: "usage",
      usage: { audio_seconds: 1.8, input_tokens: 0, output_tokens: 0, cost: 0.018 },
    },
  ]);
});

test("the stop commits the open turns and ends with done once they are out", () => {
  const { session, channels, messages, ended } = setup();
  session.start(start);
  session.audio("me", speech(500));
  session.stop();
  const { me, others } = channels();
  assert.equal(me.commits, 1);
  assert.equal(others.commits, 0);
  assert.ok(!ended());

  me.events.final(0, "Bye.");
  assert.deepEqual(messages, [
    { type: "segment", id: 1, channel: "me", start: 0, end: 0.5, text: "Bye." },
    {
      type: "usage",
      usage: { audio_seconds: 0.5, input_tokens: 0, output_tokens: 0, cost: 0.005 },
    },
    { type: "done", usage: { audio_seconds: 0.5, input_tokens: 0, output_tokens: 0, cost: 0.005 } },
  ]);
  assert.ok(ended());
  assert.ok(me.closed && others.closed);
});

test("a stop with nothing pending ends at once", () => {
  const { session, messages, ended } = setup();
  session.start(start);
  session.audio("me", silence(1000));
  session.stop();
  assert.deepEqual(messages, [
    { type: "done", usage: { audio_seconds: 0, input_tokens: 0, output_tokens: 0, cost: 0 } },
  ]);
  assert.ok(ended());
});

test("a turn that does not complete after the stop is passed on as heard, then done", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, channels, messages } = setup();
  session.start(start);
  session.audio("others", speech(500));
  channels().others.events.delta(0, " heard");
  session.stop();
  t.mock.timers.tick(5_000);
  assert.deepEqual(
    messages.map((message) => message.type),
    ["draft", "segment", "usage", "draft", "done"],
  );
});

test("transcription that does not get ready times out", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, channels, messages, ended } = setup();
  session.start(start);
  channels().me.events.ready();
  t.mock.timers.tick(10_000);
  assert.deepEqual(messages, [
    { type: "error", code: "timeout", message: "Transcription timed out" },
  ]);
  assert.ok(ended());
});

test("a channel whose transcription gives up ends the meeting with an error", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, sessions, messages, ended } = setup();
  session.start(start);
  sessions.all[0]?.events.ready();
  sessions.all[1]?.events.ready();
  for (let failure = 1; failure <= 5; failure++) {
    sessions.last.events.error(new Error("gone"));
    t.mock.timers.tick(1000 * 2 ** (failure - 1));
  }
  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "error", code: "transcription_failed", message: "Transcription failed" },
  ]);
  assert.ok(ended());
  assert.ok(sessions.all.every((transcriber) => transcriber.closed));
});

test("audio or stop before start, a second start, or audio after the stop is rejected or dropped", () => {
  for (const act of [
    (session: MeetingSession) => session.audio("me", speech(100)),
    (session: MeetingSession) => session.stop(),
    (session: MeetingSession) => {
      session.start(start);
      session.start(start);
    },
  ]) {
    const { session, messages, ended } = setup();
    act(session);
    assert.deepEqual(messages, [
      { type: "error", code: "bad_request", message: "Unexpected message" },
    ]);
    assert.ok(ended());
  }

  const { session, channels } = setup();
  session.start(start);
  session.stop();
  session.audio("me", speech(500));
  assert.equal(channels().me.bytes, 0);
});

test("closing drops the connection without a message", () => {
  const { session, channels, messages, ended } = setup();
  session.start(start);
  session.audio("me", speech(500));
  session.close();
  assert.deepEqual(messages, []);
  assert.ok(ended());
  assert.ok(channels().me.closed && channels().others.closed);
});
