import assert from "node:assert/strict";
import { test } from "node:test";
import {
  FakeReviser,
  FakeTranscribers,
  prices,
  settle,
  silence,
  silent,
  speech,
} from "./fixtures.ts";
import { type MeetingDeps, MeetingSession } from "./meeting.ts";
import type { MeetingServerMessage, MeetingStart } from "./protocol.ts";
import type { WindowOptions } from "./windows.ts";

const start: MeetingStart = {
  type: "start",
  instructions: "",
  first_id: 1,
  offsets: { me: 0, others: 0 },
};

/** A second of speech and the pause that ends it: 2.1 s sent, with the pre-roll. */
const utterance = Buffer.concat([speech(1000), silence(1000)]);

function setup(windows?: WindowOptions) {
  const sessions = new FakeTranscribers();
  const reviser = new FakeReviser();
  const messages: MeetingServerMessage[] = [];
  let ended = false;
  const deps: MeetingDeps = {
    createTranscriber: sessions.create,
    createReviser: reviser.create,
    prices,
    send: (message) => messages.push(message),
    end: () => {
      ended = true;
    },
    log: silent,
  };
  const session = new MeetingSession(windows ? { ...deps, windows } : deps);
  // The channels open their sessions in order: the speaker's, then the others'.
  const channels = () => {
    const [me, others] = sessions.all;
    if (!me || !others) throw new Error("The meeting did not open both channels");
    return { me, others };
  };
  return { session, sessions, reviser, channels, messages, ended: () => ended };
}

/** Windows that close at the first segment after any pause. */
const smallWindows: WindowOptions = {
  minSeconds: 1,
  minWords: 1,
  gapSeconds: 0.5,
  maxSeconds: 100,
};

/** The messages without the usage after each one, which the tests check on their own. */
function without(messages: MeetingServerMessage[], type: "usage"): MeetingServerMessage[] {
  return messages.filter((message) => message.type !== type);
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

test("the stop commits the open turns, revises what is left, and ends with done", async () => {
  const { session, channels, reviser, messages, ended } = setup();
  session.start(start);
  session.audio("me", speech(500));
  session.stop();
  const { me, others } = channels();
  assert.equal(me.commits, 1);
  assert.equal(others.commits, 0);
  assert.ok(!ended());

  me.events.final(0, "bye");
  assert.deepEqual(messages, [
    { type: "segment", id: 1, channel: "me", start: 0, end: 0.5, text: "bye" },
    {
      type: "usage",
      usage: { audio_seconds: 0.5, input_tokens: 0, output_tokens: 0, cost: 0.005 },
    },
  ]);
  assert.ok(!ended());

  reviser.calls[0]?.resolve([{ anchor: 1, channel: "me", text: "Bye." }], [50, 5]);
  await settle();
  const used = { audio_seconds: 0.5, input_tokens: 50, output_tokens: 5, cost: 0.065 };
  assert.deepEqual(messages.slice(2), [
    {
      type: "revised",
      from: 1,
      to: 1,
      segments: [{ id: 2, channel: "me", start: 0, end: 0.5, text: "Bye." }],
    },
    { type: "usage", usage: used },
    { type: "done", usage: used },
  ]);
  assert.ok(ended());
  assert.ok(me.closed && others.closed && reviser.closed);
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

test("a turn that does not complete after the stop is passed on as heard, then done", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, channels, reviser, messages } = setup();
  session.start(start);
  session.audio("others", speech(500));
  channels().others.events.delta(0, " heard");
  session.stop();
  t.mock.timers.tick(5_000);
  assert.deepEqual(
    messages.map((message) => message.type),
    ["draft", "segment", "usage", "draft"],
  );

  reviser.calls[0]?.resolve([{ anchor: 1, channel: "others", text: "Heard." }]);
  await settle();
  assert.deepEqual(
    messages.slice(4).map((message) => message.type),
    ["revised", "usage", "done"],
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

test("the segments are revised in windows, and the revision replaces them", async () => {
  const { session, channels, reviser, messages } = setup(smallWindows);
  session.start(start);
  const { me, others } = channels();
  // Two turns on each side, then a pause long enough to close the window before the next.
  session.audio("me", Buffer.concat([speech(1000), silence(1000), speech(1000), silence(3000)]));
  me.events.final(0, "so um the plan");
  me.events.final(1, "is simple");
  session.audio("others", Buffer.concat([speech(500), silence(1000)]));
  others.events.final(0, "sounds good");
  assert.equal(reviser.calls.length, 0);

  session.audio("me", Buffer.concat([speech(500), silence(1000)]));
  me.events.final(2, "friday then");
  assert.equal(reviser.calls.length, 1);
  assert.deepEqual(reviser.calls[0]?.input, {
    context: "",
    instructions: "",
    segments: [
      { id: 1, channel: "me", start: 0, end: 1.8, text: "so um the plan" },
      { id: 2, channel: "me", start: 1.8, end: 3.8, text: "is simple" },
      { id: 3, channel: "others", start: 0, end: 1.3, text: "sounds good" },
    ],
  });

  reviser.calls[0]?.resolve(
    [
      { anchor: 1, channel: "me", text: "So the plan is simple." },
      { anchor: 3, channel: "others", text: "Sounds good." },
    ],
    [100, 10],
  );
  await settle();
  assert.deepEqual(messages.slice(-2), [
    {
      type: "revised",
      from: 1,
      to: 3,
      segments: [
        { id: 5, channel: "me", start: 0, end: 3.8, text: "So the plan is simple." },
        { id: 6, channel: "others", start: 0, end: 1.3, text: "Sounds good." },
      ],
    },
    // 6.7 s of speech at a cent a second, and the tokens at a dollar and two a thousand.
    {
      type: "usage",
      usage: { audio_seconds: 6.7, input_tokens: 100, output_tokens: 10, cost: 0.187 },
    },
  ]);

  // The next window sees the revised text before it, and segments go on from the last id.
  session.audio("others", Buffer.concat([speech(500), silence(1000)]));
  others.events.final(1, "yes");
  session.stop();
  await settle();
  assert.equal(reviser.calls.length, 2);
  assert.equal(reviser.calls[1]?.input.context, "me: So the plan is simple.\nothers: Sounds good.");
  assert.deepEqual(
    reviser.calls[1]?.input.segments.map((s) => s.id),
    [4, 7],
  );
});

test("a window that cannot be revised keeps its text, and is the context of the next", async () => {
  const { session, channels, reviser, messages, ended } = setup(smallWindows);
  session.start(start);
  const { me } = channels();
  session.audio("me", Buffer.concat([speech(1000), silence(3000)]));
  me.events.final(0, "keep me");
  session.audio("me", Buffer.concat([speech(500), silence(1000)]));
  me.events.final(1, "and me");
  reviser.calls[0]?.reject(new Error("overloaded"));
  await settle();
  reviser.calls[1]?.reject(new Error("overloaded"));
  await settle();
  assert.equal(reviser.calls.length, 2);
  assert.ok(!messages.some((message) => message.type === "revised"));

  session.stop();
  await settle();
  assert.equal(reviser.calls[2]?.input.context, "me: keep me");
  reviser.calls[2]?.resolve([{ anchor: 2, channel: "me", text: "And me." }]);
  await settle();
  assert.deepEqual(without(messages, "usage").slice(-2), [
    {
      type: "revised",
      from: 2,
      to: 2,
      segments: [{ id: 3, channel: "me", start: 3.7, end: 5.3, text: "And me." }],
    },
    { type: "done", usage: { audio_seconds: 3.4, input_tokens: 0, output_tokens: 0, cost: 0.034 } },
  ]);
  assert.ok(ended());
  assert.ok(reviser.closed);
});

test("after the stop, the revisions left are waited for, up to a limit", async (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { session, channels, reviser, messages, ended } = setup(smallWindows);
  session.start(start);
  channels().me.events.ready();
  channels().others.events.ready();
  session.audio("me", speech(500));
  session.stop();
  channels().me.events.final(0, "bye");
  await settle();
  assert.equal(reviser.calls.length, 1);
  assert.ok(!ended());

  t.mock.timers.tick(90_000);
  assert.equal(messages.at(-1)?.type, "done");
  assert.ok(ended());
  assert.ok(reviser.calls[0]?.signal.aborted);
});

test("a revised piece covers the segments from its anchor to the next piece's", async () => {
  const { session, channels, reviser, messages } = setup(smallWindows);
  session.start(start);
  const { me, others } = channels();
  session.audio("me", Buffer.concat([speech(1000), silence(1000), speech(1000), silence(3000)]));
  me.events.final(0, "one");
  session.audio("others", Buffer.concat([speech(500), silence(1000)]));
  others.events.final(0, "two");
  me.events.final(1, "three");
  session.audio("me", Buffer.concat([speech(500), silence(1000)]));
  me.events.final(2, "four");
  // The three segments are 1 (me, 0-1.8), 2 (others, 0-1.3), 3 (me, 1.8-3.8). Two pieces
  // begin in segment 2: they share its time. The first piece takes segment 1 alone.
  reviser.calls[0]?.resolve([
    { anchor: 1, channel: "me", text: "One." },
    { anchor: 2, channel: "others", text: "Two" },
    { anchor: 2, channel: "me", text: "Three." },
  ]);
  await settle();
  const revised = messages.find((message) => message.type === "revised");
  assert.deepEqual(revised, {
    type: "revised",
    from: 1,
    to: 3,
    segments: [
      { id: 5, channel: "me", start: 0, end: 1.8, text: "One." },
      { id: 6, channel: "others", start: 0, end: 1.3, text: "Two" },
      { id: 7, channel: "me", start: 0, end: 3.8, text: "Three." },
    ],
  });
});
