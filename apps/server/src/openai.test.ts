import assert from "node:assert/strict";
import { execFileSync } from "node:child_process";
import { mkdtempSync, readFileSync } from "node:fs";
import { createServer } from "node:https";
import type { AddressInfo } from "node:net";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { type TestContext, test } from "node:test";
import tls from "node:tls";
import OpenAI from "openai";
import { type WebSocket, WebSocketServer } from "ws";
import { audio, until } from "./fixtures.ts";
import { createOpenAIRefiner } from "./refiner.ts";
import { createOpenAITranscriber } from "./transcriber.ts";

/** The SDK only opens realtime sockets over TLS, so the stand-in needs a certificate to trust. */
function certificate() {
  const dir = mkdtempSync(join(tmpdir(), "voice-test-"));
  const [key, cert] = [join(dir, "key.pem"), join(dir, "cert.pem")];
  execFileSync(
    "openssl",
    [
      "req",
      "-x509",
      "-newkey",
      "rsa:2048",
      "-nodes",
      "-days",
      "1",
      "-keyout",
      key,
      "-out",
      cert,
    ].concat(["-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1"]),
    { stdio: "ignore" },
  );
  return { key: readFileSync(key), cert: readFileSync(cert, "utf8") };
}

const { key, cert } = certificate();
tls.setDefaultCACertificates([...tls.getCACertificates("default"), cert]);

/** One side of the stand-in: what a kind of connection received, and a way to answer it. */
class Endpoint {
  url = "";
  authorization = "";
  connections = 0;
  socket: WebSocket | undefined;
  readonly received: { type: string; [key: string]: unknown }[] = [];

  emit(event: object): void {
    this.socket?.send(JSON.stringify(event));
  }
}

/** A local stand-in for the OpenAI API: the realtime and the Responses WebSockets. */
async function fakeOpenAI(t: TestContext) {
  const realtime = new Endpoint();
  const responses = new Endpoint();

  const http = createServer({ key, cert }, (_request, response) => {
    response.writeHead(404).end();
  });
  const sockets = new WebSocketServer({ server: http });
  sockets.on("connection", (socket, request) => {
    const endpoint = request.url?.startsWith("/v1/responses") ? responses : realtime;
    endpoint.url = request.url ?? "";
    endpoint.authorization = request.headers.authorization ?? "";
    endpoint.connections += 1;
    endpoint.socket = socket;
    socket.on("message", (data) => endpoint.received.push(JSON.parse(data.toString())));
  });

  await new Promise<void>((resolve) => http.listen(0, "127.0.0.1", resolve));
  t.after(() => {
    sockets.close();
    http.close();
    http.closeAllConnections();
  });
  const { port } = http.address() as AddressInfo;
  const client = new OpenAI({ apiKey: "test-key", baseURL: `https://127.0.0.1:${port}/v1` });
  return { realtime, responses, client };
}

function transcription(type: string, fields: object) {
  return {
    type: `conversation.item.input_audio_transcription.${type}`,
    item_id: "item",
    ...fields,
  };
}

test("the transcriber configures a transcription session before sending audio", async (t) => {
  const { realtime, client } = await fakeOpenAI(t);
  let ready = false;
  const transcriber = createOpenAITranscriber(client, {
    model: "gpt-live-transcribe",
    languages: ["en", "pt"],
  })({ ready: () => (ready = true), delta() {}, final() {}, error() {} });
  t.after(() => transcriber.close());

  transcriber.append(audio(100));
  transcriber.commit();
  await until(() => realtime.received.length === 1);

  assert.equal(realtime.url, "/v1/realtime?intent=transcription");
  assert.equal(realtime.authorization, "Bearer test-key");
  assert.deepEqual(realtime.received, [
    {
      type: "session.update",
      session: {
        type: "transcription",
        audio: {
          input: {
            format: { type: "audio/pcm", rate: 24000 },
            transcription: { model: "gpt-live-transcribe", languages: ["en", "pt"] },
            turn_detection: null,
          },
        },
      },
    },
  ]);
  assert.ok(!ready);

  realtime.emit({ type: "session.updated", session: {} });
  await until(() => realtime.received.length === 3);
  assert.deepEqual(realtime.received.slice(1), [
    { type: "input_audio_buffer.append", audio: audio(100).toString("base64") },
    { type: "input_audio_buffer.commit" },
  ]);
  assert.ok(ready);
});

test("the transcriber passes on the text heard, the transcript, and failures", async (t) => {
  const { realtime, client } = await fakeOpenAI(t);
  const events: unknown[] = [];
  const transcriber = createOpenAITranscriber(client, { model: "m", languages: [] })({
    ready() {},
    delta: (turn, text) => events.push(["delta", turn, text]),
    final: (turn, text) => events.push(["final", turn, text]),
    error: (error) => events.push(["error", error.message]),
  });
  await until(() => realtime.socket !== undefined);

  realtime.emit(transcription("delta", { delta: " one" }));
  realtime.emit(transcription("delta", { delta: " two" }));
  realtime.emit(transcription("completed", { transcript: "One, two." }));
  realtime.emit(transcription("failed", { error: { message: "bad audio" } }));
  await until(() => events.length === 4);

  assert.deepEqual(events, [
    ["delta", 0, " one"],
    ["delta", 0, " two"],
    ["final", 0, "One, two."],
    ["error", "bad audio"],
  ]);

  transcriber.close();
  await until(() => realtime.socket?.readyState === 3);
  assert.equal(events.length, 4);
});

test("the transcriber completes a recording too short to commit by itself", async (t) => {
  const { realtime, client } = await fakeOpenAI(t);
  const finals: string[] = [];
  const transcriber = createOpenAITranscriber(client, { model: "m", languages: [] })({
    ready() {},
    delta() {},
    final: (_turn, text) => finals.push(text),
    error() {},
  });
  t.after(() => transcriber.close());
  await until(() => realtime.received.length === 1);
  realtime.emit({ type: "session.updated", session: {} });

  transcriber.append(audio(60));
  transcriber.commit();
  await until(() => finals.length === 1);
  await until(() => realtime.received.length === 2);

  assert.deepEqual(finals, [""]);
  assert.deepEqual(
    realtime.received.map((event) => event.type),
    ["session.update", "input_audio_buffer.append"],
  );
});

test("the transcriber reports a connection that drops", async (t) => {
  const { realtime, client } = await fakeOpenAI(t);
  const errors: string[] = [];
  createOpenAITranscriber(client, { model: "m", languages: [] })({
    ready() {},
    delta() {},
    final() {},
    error: (error) => errors.push(error.message),
  });
  await until(() => realtime.socket !== undefined);
  realtime.socket?.close();
  await until(() => errors.length > 0);
});

test("the refiner connects ahead, then asks for the transcript to be rewritten", async (t) => {
  const { responses, client } = await fakeOpenAI(t);
  const refiner = createOpenAIRefiner(client, { model: "gpt-6-luna" })();
  t.after(() => refiner.close());
  await until(() => responses.socket !== undefined);
  assert.equal(responses.url, "/v1/responses");
  assert.equal(responses.authorization, "Bearer test-key");
  assert.equal(responses.received.length, 0);

  const refined = refiner.refine(
    { text: "hello world", instructions: "" },
    AbortSignal.timeout(2000),
  );
  await until(() => responses.received.length === 1);
  const [first] = responses.received;
  assert.ok(first);
  const { instructions, ...request } = first;
  assert.deepEqual(request, {
    type: "response.create",
    model: "gpt-6-luna",
    input: "<transcript>\nhello world\n</transcript>",
    reasoning: { effort: "none" },
    store: false,
  });
  assert.match(String(instructions), /^You turn dictated speech into written text\./);
  assert.doesNotMatch(String(instructions), /<instructions>/);

  responses.emit({ type: "response.output_text.delta", delta: " Hello," });
  responses.emit({ type: "response.output_text.delta", delta: " world. " });
  responses.emit({
    type: "response.completed",
    response: { usage: { input_tokens: 210, output_tokens: 4, total_tokens: 214 } },
  });
  assert.deepEqual(await refined, { text: "Hello, world.", inputTokens: 210, outputTokens: 4 });
  assert.equal(responses.connections, 1);
});

test("the refiner puts the speaker's instructions after its own", async (t) => {
  const { responses, client } = await fakeOpenAI(t);
  const refiner = createOpenAIRefiner(client, { model: "m" })();
  t.after(() => refiner.close());

  const refined = refiner.refine(
    { text: "hi", instructions: " Write formally. " },
    AbortSignal.timeout(2000),
  );
  await until(() => responses.received.length === 1);
  const instructions = String(responses.received[0]?.instructions);
  assert.match(instructions, /^You turn dictated speech into written text\./);
  assert.ok(instructions.endsWith("<instructions>\nWrite formally.\n</instructions>"));

  responses.emit({ type: "response.completed", response: {} });
  assert.deepEqual(await refined, { text: "", inputTokens: 0, outputTokens: 0 });
});

test("the refiner gives up on a model that stops answering", async (t) => {
  const { responses, client } = await fakeOpenAI(t);
  const refiner = createOpenAIRefiner(client, { model: "m", stallMs: 40 })();
  t.after(() => refiner.close());

  const refined = refiner.refine({ text: "hi", instructions: "" }, AbortSignal.timeout(2000));
  await until(() => responses.received.length === 1);
  responses.emit({ type: "response.output_text.delta", delta: "Hi" });
  await assert.rejects(refined, /stalled/);
});

test("the refiner reports a response that fails", async (t) => {
  const { responses, client } = await fakeOpenAI(t);
  const refiner = createOpenAIRefiner(client, { model: "m" })();
  t.after(() => refiner.close());

  const failed = refiner.refine({ text: "hi", instructions: "" }, AbortSignal.timeout(2000));
  await until(() => responses.received.length === 1);
  responses.emit({ type: "response.failed", response: { error: { message: "model overloaded" } } });
  await assert.rejects(failed, /model overloaded/);

  const refused = refiner.refine({ text: "hi", instructions: "" }, AbortSignal.timeout(2000));
  await until(() => responses.received.length === 2);
  responses.emit({ type: "error", error: { message: "invalid request" } });
  await assert.rejects(refused, /invalid request/);
});

test("the refiner connects again when its connection is gone", async (t) => {
  const { responses, client } = await fakeOpenAI(t);
  const refiner = createOpenAIRefiner(client, { model: "m" })();
  t.after(() => refiner.close());
  await until(() => responses.socket !== undefined);
  const first = responses.socket;
  first?.close();
  await until(() => first?.readyState === 3);
  await new Promise((resolve) => setTimeout(resolve, 50));

  const refined = refiner.refine({ text: "hi", instructions: "" }, AbortSignal.timeout(2000));
  await until(() => responses.received.length === 1);
  assert.equal(responses.connections, 2);
  responses.emit({ type: "response.output_text.delta", delta: "Hi." });
  responses.emit({ type: "response.completed", response: {} });
  assert.equal((await refined).text, "Hi.");
});

test("closing the refiner ends the request in progress", async (t) => {
  const { responses, client } = await fakeOpenAI(t);
  const refiner = createOpenAIRefiner(client, { model: "m" })();

  const refined = refiner.refine({ text: "hi", instructions: "" }, AbortSignal.timeout(2000));
  await until(() => responses.received.length === 1);
  refiner.close();
  await assert.rejects(refined, /closed/);
  await until(() => responses.socket?.readyState === 3);
});
