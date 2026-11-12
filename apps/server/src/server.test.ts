import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { type TestContext, test } from "node:test";
import { WebSocket } from "ws";
import {
  audio,
  FakeRefiner,
  FakeTranscriber,
  FakeTranscribers,
  prices,
  silence,
  silent,
  speech,
  until,
} from "./fixtures.ts";
import type { MeetingServerMessage, ServerMessage } from "./protocol.ts";
import { createServer } from "./server.ts";

async function start(t: TestContext) {
  const transcriber = new FakeTranscriber();
  const refiner = new FakeRefiner();
  const server = createServer({
    createTranscriber: transcriber.create,
    createRefiner: refiner.create,
    prices,
    log: silent,
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => {
    server.close();
    server.closeAllConnections();
  });
  const { port } = server.address() as AddressInfo;
  return { transcriber, refiner, host: `127.0.0.1:${port}` };
}

async function connect(host: string, path = "/v1/dictation") {
  const ws = new WebSocket(`ws://${host}${path}`);
  const messages: (ServerMessage | MeetingServerMessage)[] = [];
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

  ws.send(JSON.stringify({ type: "start", instructions: "Write formally." }));
  ws.send(audio(500));
  await until(() => transcriber.bytes === audio(500).length);
  transcriber.events.ready();
  transcriber.events.delta(0, "hi");
  ws.send(JSON.stringify({ type: "stop" }));
  await until(() => transcriber.commits === 1);
  transcriber.events.final(0, "hi there");
  await until(() => refiner.calls.length === 1);
  assert.deepEqual(refiner.calls[0]?.input, { text: "hi there", instructions: "Write formally." });
  refiner.calls[0]?.resolve("Hi there.");
  await until(() => closeCode() !== undefined);

  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "delta", text: "hi" },
    {
      type: "done",
      text: "Hi there.",
      usage: { audio_seconds: 0.5, input_tokens: 0, output_tokens: 0, cost: 0.005 },
    },
  ]);
  assert.equal(closeCode(), 1000);
  assert.ok(transcriber.closed);
});

test("start needs no instructions", async (t) => {
  const { host, transcriber, refiner } = await start(t);
  const { ws } = await connect(host);
  ws.send(JSON.stringify({ type: "start" }));
  ws.send(JSON.stringify({ type: "stop" }));
  await until(() => transcriber.commits === 1);
  transcriber.events.final(0, "hi");
  await until(() => refiner.calls.length === 1);
  assert.equal(refiner.calls[0]?.input.instructions, "");
  ws.close();
  await until(() => transcriber.closed);
});

test("a message that is not part of the protocol ends the dictation with an error", async (t) => {
  const { host } = await start(t);
  for (const message of ["hello", '{"type":"other"}', '{"type":"start","instructions":7}']) {
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

async function startMeetings(t: TestContext) {
  const transcribers = new FakeTranscribers();
  const server = createServer({
    createTranscriber: transcribers.create,
    createRefiner: new FakeRefiner().create,
    prices,
    log: silent,
  });
  await new Promise<void>((resolve) => server.listen(0, "127.0.0.1", resolve));
  t.after(() => {
    server.close();
    server.closeAllConnections();
  });
  const { port } = server.address() as AddressInfo;
  return { transcribers, host: `127.0.0.1:${port}` };
}

/** A binary frame of a meeting: the channel, then the audio. */
function frame(channel: number, pcm: Buffer): Buffer {
  return Buffer.concat([Buffer.from([channel]), pcm]);
}

test("a meeting streams the audio of two channels in and segments out, then closes", async (t) => {
  const { host, transcribers } = await startMeetings(t);
  const { ws, messages, closeCode } = await connect(host, "/v1/meeting");

  ws.send(JSON.stringify({ type: "start", first_id: 3, offsets: { me: 10, others: 10 } }));
  ws.send(frame(0, Buffer.concat([speech(1000), silence(1000)])));
  ws.send(frame(1, Buffer.concat([speech(500), silence(1000)])));
  await until(() => transcribers.all.length === 2 && transcribers.all[1]?.commits === 1);
  const [me, others] = transcribers.all;
  me?.events.ready();
  others?.events.ready();
  others?.events.final(0, "Hello.");
  me?.events.final(0, "Hi.");
  ws.send(JSON.stringify({ type: "stop" }));
  await until(() => closeCode() !== undefined);

  assert.deepEqual(
    messages.filter((message) => message.type !== "usage"),
    [
      { type: "ready" },
      { type: "segment", id: 3, channel: "others", start: 10, end: 11.3, text: "Hello." },
      { type: "segment", id: 4, channel: "me", start: 10, end: 11.8, text: "Hi." },
      {
        type: "done",
        usage: { audio_seconds: 3.1, input_tokens: 0, output_tokens: 0, cost: 0.031 },
      },
    ],
  );
  assert.equal(closeCode(), 1000);
  assert.ok(me?.closed && others?.closed);
});

test("a meeting frame that names no channel, or a bad start, ends it with an error", async (t) => {
  const { host } = await startMeetings(t);
  for (const message of [
    frame(2, speech(100)),
    '{"type":"start","offsets":{"me":-1}}',
    '{"type":"start","first_id":1.5}',
  ]) {
    const { ws, messages, closeCode } = await connect(host, "/v1/meeting");
    if (typeof message === "string") ws.send(message);
    else ws.send(JSON.stringify({ type: "start" }), () => ws.send(message));
    await until(() => closeCode() !== undefined);
    assert.deepEqual(messages, [
      { type: "error", code: "bad_request", message: "Unexpected message" },
    ]);
  }
});
