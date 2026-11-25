import assert from "node:assert/strict";
import { test } from "node:test";
import { ProfileTurn } from "./conversation.ts";
import { audio, FakeAgent, FakeTranscriber, prices, settle, silent } from "./fixtures.ts";
import type { Profile, ProfileServerMessage } from "./protocol.ts";

const none: Profile = { instructions: "", transcriptionPrompt: "", languages: [], terms: [] };

function setup(log = silent) {
  const transcriber = new FakeTranscriber();
  const agent = new FakeAgent();
  const messages: ProfileServerMessage[] = [];
  let ended = false;
  const turn = new ProfileTurn({
    createTranscriber: transcriber.create,
    createLiveTranscriber: transcriber.createLive,
    createAgent: agent.create,
    prices,
    send: (message) => messages.push(message),
    end: () => {
      ended = true;
    },
    log,
  });
  return { turn, transcriber, agent, messages, ended: () => ended };
}

test("the agent is connected when the turn starts, and answers what was heard", async () => {
  const { turn, transcriber, agent, messages, ended } = setup();
  turn.start({ history: [], profile: none, vocabulary: [] });
  assert.equal(agent.created, 1);
  // What the speaker says fills in as they speak.
  assert.equal(transcriber.live, true);
  transcriber.events.ready();
  turn.audio(audio(1000));
  turn.stop();
  transcriber.events.final(0, " Sou desenvolvedor. ");
  assert.equal(agent.calls[0]?.input.said, "Sou desenvolvedor.");

  agent.calls[0]?.resolve({ reply: "Do que você fala?", inputTokens: 10, outputTokens: 5 });
  await settle();
  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "heard", text: "Sou desenvolvedor." },
    {
      type: "done",
      reply: "Do que você fala?",
      profile: null,
      add_terms: [],
      usage: { audio_seconds: 1, input_tokens: 10, output_tokens: 5, cost: 0.03 },
    },
  ]);
  assert.ok(ended());
  assert.ok(transcriber.closed && agent.closed);
});

test("a turn where nothing was heard ends without asking the agent", async () => {
  const { turn, transcriber, agent, messages } = setup();
  turn.start({ history: [], profile: none, vocabulary: [] });
  turn.stop();
  transcriber.events.final(0, " ");
  await settle();
  assert.equal(agent.calls.length, 0);
  assert.deepEqual(messages, [
    { type: "heard", text: "" },
    {
      type: "done",
      reply: "",
      profile: null,
      add_terms: [],
      usage: { audio_seconds: 0, input_tokens: 0, output_tokens: 0, cost: 0 },
    },
  ]);
});

test("an agent that fails ends the turn with an error, after what was heard", async () => {
  const { turn, transcriber, agent, messages, ended } = setup();
  turn.start({ history: [], profile: none, vocabulary: [] });
  turn.stop();
  transcriber.events.final(0, "Oi.");
  agent.calls[0]?.reply("Ol");
  agent.calls[0]?.reject(new Error("Response stalled"));
  await settle();
  assert.deepEqual(messages, [
    { type: "heard", text: "Oi." },
    { type: "reply", text: "Ol" },
    { type: "error", code: "agent_failed", message: "The agent did not answer" },
  ]);
  assert.ok(ended());
});

test("a client that goes away stops the agent", async () => {
  const { turn, transcriber, agent, messages } = setup();
  turn.start({ history: [], profile: none, vocabulary: [] });
  turn.stop();
  transcriber.events.final(0, "Oi.");
  const call = agent.calls[0];
  turn.close();
  assert.ok(call?.signal.aborted);
  call?.reject(new Error("Response aborted"));
  await settle();
  assert.deepEqual(messages, [{ type: "heard", text: "Oi." }]);
});

test("what was said and the profile are logged by their length only", async (t) => {
  const info = t.mock.fn(silent.info);
  const { turn, transcriber, agent } = setup({ ...silent, info });
  turn.start({
    history: [
      { role: "assistant", text: "O que você faz?" },
      { role: "user", text: "Programo." },
    ],
    profile: {
      instructions: "Mantenha os termos.",
      transcriptionPrompt: "Desenvolvedor.",
      languages: ["pt"],
      terms: ["merge"],
    },
    vocabulary: ["Claude"],
  });
  turn.stop();
  transcriber.events.final(0, "Falo de Git.");
  agent.calls[0]?.reply("Certo.");
  agent.calls[0]?.resolve({ reply: "Certo.", addTerms: ["Git"] });
  await settle();

  const records = info.mock.calls.map((call) => call.arguments);
  assert.deepEqual(records.find(([message]) => message === "started")?.[1], {
    history_messages: 2,
    history_chars: 24,
    instructions_chars: 19,
    prompt_chars: 14,
    languages: 1,
    terms: 1,
    vocabulary_terms: 1,
  });
  const answered = records.find(([message]) => message === "answered")?.[1];
  assert.equal(answered?.reply_chars, 6);
  assert.equal(answered?.add_terms, 1);
  assert.equal(answered?.profile_changed, false);
  const logged = JSON.stringify(records);
  for (const said of ["Programo", "Falo de Git", "Certo", "Mantenha", "Desenvolvedor"]) {
    assert.ok(!logged.includes(said), said);
  }
});
