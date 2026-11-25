import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { type TestContext, test } from "node:test";
import { WebSocket } from "ws";
import {
  audio,
  FakeAgent,
  FakeRefiner,
  FakeTranscriber,
  prices,
  silent,
  until,
} from "./fixtures.ts";
import type { ProfileServerMessage, ServerMessage } from "./protocol.ts";
import { createServer } from "./server.ts";

async function start(t: TestContext) {
  const transcriber = new FakeTranscriber();
  const refiner = new FakeRefiner();
  const agent = new FakeAgent();
  const server = createServer({
    createTranscriber: transcriber.create,
    createLiveTranscriber: transcriber.createLive,
    createRefiner: refiner.create,
    createAgent: agent.create,
    prices,
    log: silent,
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => {
    server.close();
    server.closeAllConnections();
  });
  const { port } = server.address() as AddressInfo;
  return { transcriber, refiner, agent, host: `127.0.0.1:${port}` };
}

async function connect(host: string, path = "/v1/dictation", headers: Record<string, string> = {}) {
  const ws = new WebSocket(`ws://${host}${path}`, { headers });
  const messages: (ServerMessage | ProfileServerMessage)[] = [];
  let closeCode: number | undefined;
  ws.on("message", (data) => messages.push(JSON.parse(data.toString())));
  ws.on("close", (code) => {
    closeCode = code;
  });
  await new Promise((resolve, reject) => {
    ws.on("open", resolve);
    ws.on("error", reject);
  });
  return { ws, messages, closeCode: () => closeCode };
}

test("GET /health reports ok", async (t) => {
  const { host } = await start(t);
  const response = await fetch(`http://${host}/health`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "ok" });
});

test("a WebSocket on another path is refused", async (t) => {
  const { host } = await start(t);
  await assert.rejects(connect(host, "/other"), /404/);
});

test("a dictation streams audio in and text out, then closes", async (t) => {
  const { host, transcriber, refiner } = await start(t);
  const { ws, messages, closeCode } = await connect(host);

  ws.send(
    JSON.stringify({
      type: "start",
      instructions: "Write formally.",
      translate_to: "Spanish",
      vocabulary: ["Claude"],
      context: "Hola Ana,",
      live: true,
      transcription_prompt: "A developer\nspeaking Spanish.",
      languages: ["es-ES", "en"],
    }),
  );
  ws.send(audio(500));
  await until(() => transcriber.bytes === audio(500).length);
  assert.equal(transcriber.live, true);
  transcriber.events.ready();
  transcriber.events.delta(0, "hi");
  ws.send(JSON.stringify({ type: "stop" }));
  await until(() => transcriber.commits === 1);
  transcriber.events.final(0, "hi there");
  await until(() => refiner.calls.length === 1);
  assert.deepEqual(refiner.calls[0]?.input, {
    text: "hi there",
    instructions: "Write formally.",
    translateTo: "Spanish",
    vocabulary: ["Claude"],
    context: "Hola Ana,",
  });
  assert.deepEqual(transcriber.hints, {
    keywords: ["Claude"],
    prompt: "A developer speaking Spanish.",
    languages: ["es", "en"],
  });
  refiner.calls[0]?.resolve("Hi there.");
  await until(() => closeCode() !== undefined);

  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "delta", text: "hi" },
    {
      type: "done",
      text: " Hi there.",
      usage: { audio_seconds: 0.5, input_tokens: 0, output_tokens: 0, cost: 0.005 },
    },
  ]);
  assert.equal(closeCode(), 1000);
  assert.ok(transcriber.closed);
});

test("start needs no instructions, language, or vocabulary, and is not live", async (t) => {
  const { host, transcriber, refiner } = await start(t);
  const { ws } = await connect(host);
  ws.send(JSON.stringify({ type: "start" }));
  ws.send(JSON.stringify({ type: "stop" }));
  await until(() => transcriber.commits === 1);
  assert.equal(transcriber.live, false);
  transcriber.events.final(0, "hi");
  await until(() => refiner.calls.length === 1);
  assert.equal(refiner.calls[0]?.input.instructions, "");
  assert.equal(refiner.calls[0]?.input.translateTo, "");
  assert.deepEqual(refiner.calls[0]?.input.vocabulary, []);
  assert.equal(refiner.calls[0]?.input.context, "");
  ws.close();
  await until(() => transcriber.closed);
});

test("a message that is not part of the protocol ends the dictation with an error", async (t) => {
  const { host } = await start(t);
  for (const message of [
    "hello",
    '{"type":"other"}',
    '{"type":"start","instructions":7}',
    '{"type":"start","translate_to":7}',
    '{"type":"start","vocabulary":"Claude"}',
    '{"type":"start","vocabulary":["Claude",7]}',
    '{"type":"start","context":7}',
    '{"type":"start","live":"yes"}',
    '{"type":"start","transcription_prompt":7}',
    '{"type":"start","languages":"pt"}',
    '{"type":"start","languages":["pt",7]}',
  ]) {
    const { ws, messages, closeCode } = await connect(host);
    ws.send(message);
    await until(() => closeCode() !== undefined);
    assert.deepEqual(messages, [
      { type: "error", code: "bad_request", message: "Unexpected message" },
    ]);
  }
});

test("a client that disconnects releases the transcriber and the refiner", async (t) => {
  const { host, transcriber, refiner } = await start(t);
  const { ws } = await connect(host);
  ws.send(JSON.stringify({ type: "start" }));
  await until(() => refiner.created === 1);
  ws.close();
  await until(() => transcriber.closed && refiner.closed);
});

test("a WebSocket from a web page is refused", async (t) => {
  const { host } = await start(t);
  for (const path of ["/v1/dictation", "/v1/profile"]) {
    await assert.rejects(connect(host, path, { origin: "https://example.com" }), /403/);
  }
});

test("a turn of the profile conversation hears the speaker, then streams the agent's answer", async (t) => {
  const { host, transcriber, agent, refiner } = await start(t);
  const { ws, messages, closeCode } = await connect(host, "/v1/profile");
  const profile = {
    instructions: "Keep Git terms in English.",
    transcription_prompt: "A developer\nspeaking Portuguese.",
    languages: ["pt-BR", "en"],
    terms: ["rebase"],
  };
  ws.send(
    JSON.stringify({
      type: "start",
      history: [
        { role: "assistant", text: "O que você faz?" },
        { role: "user", text: "Sou desenvolvedor." },
        { role: "assistant", text: "Que termos você usa?", profile },
      ],
      profile,
      vocabulary: ["Claude"],
    }),
  );
  ws.send(audio(500));
  await until(() => transcriber.bytes === audio(500).length);
  // The speaker's profile helps hear them.
  assert.deepEqual(transcriber.hints, {
    keywords: ["Claude"],
    prompt: "A developer speaking Portuguese.",
    languages: ["pt", "en"],
  });
  transcriber.events.ready();
  transcriber.events.delta(0, "falo de merge");
  ws.send(JSON.stringify({ type: "stop" }));
  await until(() => transcriber.commits === 1);
  transcriber.events.final(0, "Falo de merge e rebase.");
  await until(() => agent.calls.length === 1);

  const call = agent.calls[0];
  assert.ok(call);
  assert.equal(call.input.said, "Falo de merge e rebase.");
  assert.equal(call.input.history.length, 3);
  assert.deepEqual(call.input.history[2]?.profile, {
    instructions: "Keep Git terms in English.",
    transcriptionPrompt: "A developer\nspeaking Portuguese.",
    languages: ["pt-BR", "en"],
    terms: ["rebase"],
  });
  assert.deepEqual(call.input.vocabulary, ["Claude"]);
  // There is no rewrite: what was heard goes to the agent as it is.
  assert.equal(refiner.created, 0);

  call.reply("Entendi.");
  call.reply(" Mais algo?");
  call.resolve({
    reply: "Entendi. Mais algo?",
    profile: {
      instructions: "Keep merge and rebase in English.",
      transcriptionPrompt: "A developer.",
      languages: ["pt", "en"],
      terms: ["merge"],
    },
    addTerms: ["rebase"],
    inputTokens: 1000,
    outputTokens: 100,
  });
  await until(() => closeCode() !== undefined);

  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "delta", text: "falo de merge" },
    { type: "heard", text: "Falo de merge e rebase." },
    { type: "reply", text: "Entendi." },
    { type: "reply", text: " Mais algo?" },
    {
      type: "done",
      reply: "Entendi. Mais algo?",
      profile: {
        instructions: "Keep merge and rebase in English.",
        transcription_prompt: "A developer.",
        languages: ["pt", "en"],
        terms: ["merge"],
      },
      add_terms: ["rebase"],
      // Half a second of audio at a cent a second, and the tokens at a dollar and two a thousand.
      usage: { audio_seconds: 0.5, input_tokens: 1000, output_tokens: 100, cost: 1.205 },
    },
  ]);
  assert.equal(closeCode(), 1000);
  assert.ok(transcriber.closed && agent.closed);
});

test("a turn of the profile conversation needs no history or profile", async (t) => {
  const { host, transcriber, agent } = await start(t);
  const { ws } = await connect(host, "/v1/profile");
  ws.send(JSON.stringify({ type: "start" }));
  ws.send(JSON.stringify({ type: "stop" }));
  await until(() => transcriber.commits === 1);
  transcriber.events.final(0, "Oi.");
  await until(() => agent.calls.length === 1);
  assert.deepEqual(agent.calls[0]?.input.history, []);
  assert.deepEqual(agent.calls[0]?.input.profile, {
    instructions: "",
    transcriptionPrompt: "",
    languages: [],
    terms: [],
  });
  ws.close();
  await until(() => agent.closed);
});

test("a message that is not part of the profile conversation ends the turn with an error", async (t) => {
  const { host } = await start(t);
  for (const message of [
    "hello",
    '{"type":"other"}',
    '{"type":"start","history":"hi"}',
    '{"type":"start","history":[{"role":"system","text":"hi"}]}',
    '{"type":"start","history":[{"role":"user","text":7}]}',
    '{"type":"start","history":[{"role":"assistant","text":"hi","profile":"x"}]}',
    '{"type":"start","profile":[]}',
    '{"type":"start","profile":{"instructions":7}}',
    '{"type":"start","profile":{"languages":"pt"}}',
    '{"type":"start","profile":{"terms":[7]}}',
    '{"type":"start","vocabulary":"Claude"}',
  ]) {
    const { ws, messages, closeCode } = await connect(host, "/v1/profile");
    ws.send(message);
    await until(() => closeCode() !== undefined);
    assert.deepEqual(messages, [
      { type: "error", code: "bad_request", message: "Unexpected message" },
    ]);
  }
});
