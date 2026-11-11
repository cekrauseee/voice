import assert from "node:assert/strict";
import type { AddressInfo } from "node:net";
import { type TestContext, test } from "node:test";
import { WebSocket } from "ws";
import { FakeRefiner, FakeTranscriber, silence, speech, until } from "./fixtures.ts";
import type { ServerMessage } from "./protocol.ts";
import { createServer } from "./server.ts";

async function start(t: TestContext) {
  const transcriber = new FakeTranscriber();
  const refiner = new FakeRefiner();
  const server = createServer({ createTranscriber: transcriber.create, refiner, log: () => {} });
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

test("a dictation streams audio in and refined text out, then closes", async (t) => {
  const { host, transcriber, refiner } = await start(t);
  const { ws, messages, closeCode } = await connect(host);

  transcriber.events.ready();
  ws.send(Buffer.concat([speech(500), silence(700)]));
  await until(() => transcriber.commits === 1);
  transcriber.events.delta(0, "hi");
  transcriber.events.final(0, "hi there");
  await until(() => refiner.calls.length === 1);
  ws.send(JSON.stringify({ type: "stop" }));
  refiner.calls[0]?.resolve("Hi there.");
  await until(() => closeCode() !== undefined);

  assert.deepEqual(messages, [
    { type: "ready" },
    { type: "delta", segment: 0, text: "hi" },
    { type: "final", segment: 0, text: "hi there" },
    { type: "refined", segment: 0, text: "Hi there." },
    { type: "done" },
  ]);
  assert.equal(closeCode(), 1000);
  assert.ok(transcriber.closed);
});

test("an unexpected text message ends the dictation with an error", async (t) => {
  const { host } = await start(t);
  const { ws, messages, closeCode } = await connect(host);
  ws.send("hello");
  await until(() => closeCode() !== undefined);
  assert.deepEqual(messages, [
    { type: "error", code: "bad_request", message: "Unexpected message" },
  ]);
});

test("a client that disconnects releases the transcriber", async (t) => {
  const { host, transcriber } = await start(t);
  const { ws } = await connect(host);
  ws.close();
  await until(() => transcriber.closed);
});
