import assert from "node:assert/strict";
import { test } from "node:test";
import { audio, FakeTranscribers, silent } from "./fixtures.ts";
import { createResilientTranscriber, type ResilientOptions } from "./resilient.ts";

function setup(options: Partial<ResilientOptions> = {}) {
  const sessions = new FakeTranscribers();
  const events: unknown[] = [];
  const transcriber = createResilientTranscriber(sessions.create, { log: silent, ...options })({
    ready: () => events.push("ready"),
    delta: (turn, text) => events.push(["delta", turn, text]),
    final: (turn, text) => events.push(["final", turn, text]),
    restarted: () => events.push("restarted"),
    error: (error) => events.push(["error", error.message]),
  });
  return { sessions, events, transcriber };
}

test("turns are numbered by commit order and passed through", () => {
  const { sessions, events, transcriber } = setup();
  transcriber.append(audio(100));
  transcriber.commit();
  transcriber.append(audio(200));
  const session = sessions.last;
  session.events.ready();
  session.events.delta(1, " two");
  session.events.final(0, "One.");
  assert.equal(session.commits, 1);
  assert.equal(session.bytes, audio(300).length);
  assert.deepEqual(events, ["ready", ["delta", 1, " two"], ["final", 0, "One."]]);
});

test("a failed session is replaced, and the turns not final yet are sent again", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { sessions, events, transcriber } = setup();
  transcriber.append(audio(100));
  transcriber.commit();
  transcriber.append(audio(200));
  const first = sessions.last;
  first.events.ready();
  first.events.delta(1, " lost");
  first.events.error(new Error("gone"));
  assert.ok(first.closed);
  assert.equal(sessions.all.length, 1);

  t.mock.timers.tick(1000);
  const second = sessions.last;
  assert.equal(sessions.all.length, 2);
  assert.deepEqual(
    second.appended.map((chunk) => chunk.length),
    [audio(100).length, audio(200).length],
  );
  assert.equal(second.commits, 1);

  // The second session numbers the turns as it got them, which is the same order.
  second.events.ready();
  second.events.final(0, "One.");
  second.events.delta(1, " two");
  first.events.delta(1, " late");
  assert.deepEqual(events, [
    "ready",
    ["delta", 1, " lost"],
    "restarted",
    ["final", 0, "One."],
    ["delta", 1, " two"],
  ]);
});

test("a turn that is final is not sent again, and the next session numbers from the rest", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { sessions, events, transcriber } = setup();
  transcriber.append(audio(100));
  transcriber.commit();
  sessions.last.events.final(0, "First.");
  transcriber.append(audio(50));
  transcriber.commit();
  transcriber.append(audio(70));
  sessions.last.events.error(new Error("gone"));
  t.mock.timers.tick(1000);

  const second = sessions.last;
  assert.deepEqual(
    second.appended.map((chunk) => chunk.length),
    [audio(50).length, audio(70).length],
  );
  second.events.final(0, "Second.");
  second.events.delta(1, " third");
  assert.deepEqual(events, [
    ["final", 0, "First."],
    "restarted",
    ["final", 1, "Second."],
    ["delta", 2, " third"],
  ]);
});

test("audio that arrives while no session is open waits for the next one", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { sessions, transcriber } = setup();
  sessions.last.events.error(new Error("gone"));
  transcriber.append(audio(100));
  transcriber.commit();
  assert.equal(sessions.all.length, 1);

  t.mock.timers.tick(1000);
  assert.equal(sessions.last.bytes, audio(100).length);
  assert.equal(sessions.last.commits, 1);
});

test("the wait before another session doubles, and starts over once a session is ready", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { sessions } = setup();
  sessions.last.events.error(new Error("1"));
  t.mock.timers.tick(999);
  assert.equal(sessions.all.length, 1);
  t.mock.timers.tick(1);
  assert.equal(sessions.all.length, 2);

  sessions.last.events.error(new Error("2"));
  t.mock.timers.tick(1999);
  assert.equal(sessions.all.length, 2);
  t.mock.timers.tick(1);
  assert.equal(sessions.all.length, 3);

  sessions.last.events.ready();
  sessions.last.events.error(new Error("3"));
  t.mock.timers.tick(1000);
  assert.equal(sessions.all.length, 4);
});

test("ready is reported once, however many sessions it takes", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { sessions, events } = setup();
  sessions.last.events.ready();
  sessions.last.events.error(new Error("gone"));
  t.mock.timers.tick(1000);
  sessions.last.events.ready();
  assert.deepEqual(events, ["ready", "restarted"]);
});

test("it gives up after failures in a row", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { sessions, events } = setup({ maxFailures: 2 });
  sessions.last.events.error(new Error("one"));
  t.mock.timers.tick(1000);
  sessions.last.events.error(new Error("two"));
  t.mock.timers.tick(10_000);
  assert.equal(sessions.all.length, 2);
  assert.deepEqual(events, ["restarted", ["error", "two"]]);
});

test("a session that has lived long enough is replaced at the next commit", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout", "Date"] });
  const { sessions, events, transcriber } = setup({ maxSessionMs: 60_000 });
  transcriber.append(audio(100));
  transcriber.commit();
  sessions.last.events.final(0, "Old.");
  t.mock.timers.tick(60_000);
  transcriber.append(audio(200));
  assert.equal(sessions.all.length, 1);

  transcriber.commit();
  assert.equal(sessions.all.length, 2);
  assert.ok(sessions.all[0]?.closed);
  assert.deepEqual(
    sessions.last.appended.map((chunk) => chunk.length),
    [audio(200).length],
  );
  assert.equal(sessions.last.commits, 1);
  sessions.last.events.final(0, "New.");
  assert.deepEqual(events, [["final", 0, "Old."], "restarted", ["final", 1, "New."]]);
});

test("closing closes the session and opens no other", (t) => {
  t.mock.timers.enable({ apis: ["setTimeout"] });
  const { sessions, transcriber } = setup();
  sessions.last.events.error(new Error("gone"));
  transcriber.close();
  t.mock.timers.tick(5000);
  assert.equal(sessions.all.length, 1);

  const { sessions: other, transcriber: open } = setup();
  open.close();
  assert.ok(other.last.closed);
});
