import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { type TestContext, test } from "node:test";
import { WebSocket } from "ws";
import { audio, FakeRefiner, FakeTranscriber, silent, until } from "./fixtures.ts";
import type { ServerMessage } from "./protocol.ts";
import { createServer } from "./server.ts";

async function start(t: TestContext) {
  const transcriber = new FakeTranscriber();
  const refiner = new FakeRefiner();
  const server = createServer({
    createTranscriber: transcriber.create,
    createRefiner: refiner.create,
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
  const messages: ServerMessage[] = [];
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
  transcriber.events.delta("hi");
  ws.send(JSON.stringify({ type: "stop" }));
  await until(() => transcriber.commits === 1);
  transcriber.events.final("hi there");
  await until(() => refiner.calls.length === 1);
  assert.deepEqual(refiner.calls[0]?.input, { text: "hi there", instructions: "Write formally." });
  refiner.calls[0]?.resolve("Hi there.");
  await until(() => closeCode() !== undefined);

  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "delta", text: "hi" },
    { type: "done", text: "Hi there." },
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
  transcriber.events.final("hi");
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
