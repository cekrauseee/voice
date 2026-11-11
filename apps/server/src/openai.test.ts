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
import { until } from "./fixtures.ts";
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

/** A local stand-in for the OpenAI API: the realtime WebSocket and `POST /v1/responses`. */
async function fakeOpenAI(t: TestContext) {
  const state = {
    realtimeUrl: "",
    authorization: "",
    received: [] as { type: string; [key: string]: unknown }[],
    socket: undefined as WebSocket | undefined,
    responseRequest: undefined as Record<string, unknown> | undefined,
    responseText: "",
  };

  const http = createServer({ key, cert }, async (request, response) => {
    const chunks: Buffer[] = [];
    for await (const chunk of request) chunks.push(chunk);
    state.responseRequest = JSON.parse(Buffer.concat(chunks).toString());
    response.writeHead(200, { "content-type": "application/json" }).end(
      JSON.stringify({
        id: "resp_1",
        object: "response",
        output: [
          {
            type: "message",
            role: "assistant",
            content: [{ type: "output_text", text: state.responseText, annotations: [] }],
          },
        ],
      }),
    );
  });
  const sockets = new WebSocketServer({ server: http });
  sockets.on("connection", (socket, request) => {
    state.realtimeUrl = request.url ?? "";
    state.authorization = request.headers.authorization ?? "";
    state.socket = socket;
    socket.on("message", (data) => state.received.push(JSON.parse(data.toString())));
  });

  await new Promise<void>((resolve) => http.listen(0, "127.0.0.1", resolve));
  t.after(() => {
    sockets.close();
    http.close();
    http.closeAllConnections();
  });
  const { port } = http.address() as AddressInfo;
  const client = new OpenAI({ apiKey: "test-key", baseURL: `https://127.0.0.1:${port}/v1` });
  const emit = (event: object) => state.socket?.send(JSON.stringify(event));
  return { state, client, emit };
}

function transcription(type: string, itemId: string, fields: object) {
  return {
    type: `conversation.item.input_audio_transcription.${type}`,
    item_id: itemId,
    ...fields,
  };
}

test("the transcriber configures a transcription session before sending audio", async (t) => {
  const { state, client, emit } = await fakeOpenAI(t);
  let ready = false;
  const transcriber = createOpenAITranscriber(client, {
    model: "gpt-live-transcribe",
    languages: ["en", "pt"],
  })({ ready: () => (ready = true), delta() {}, final() {}, error() {} });
  t.after(() => transcriber.close());

  transcriber.append(Buffer.from([1, 2, 3, 4]));
  transcriber.commit();
  await until(() => state.received.length === 1);

  assert.equal(state.realtimeUrl, "/v1/realtime?intent=transcription");
  assert.equal(state.authorization, "Bearer test-key");
  assert.deepEqual(state.received, [
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

  emit({ type: "session.updated", session: {} });
  await until(() => state.received.length === 3);
  assert.deepEqual(state.received.slice(1), [
    { type: "input_audio_buffer.append", audio: "AQIDBA==" },
    { type: "input_audio_buffer.commit" },
  ]);
  assert.ok(ready);
});

test("the transcriber numbers segments by the order their items appear", async (t) => {
  const { state, client, emit } = await fakeOpenAI(t);
  const events: unknown[] = [];
  const transcriber = createOpenAITranscriber(client, { model: "m", languages: [] })({
    ready() {},
    delta: (segment, text) => events.push(["delta", segment, text]),
    final: (segment, text) => events.push(["final", segment, text]),
    error: (error) => events.push(["error", error.message]),
  });
  await until(() => state.socket !== undefined);

  emit(transcription("delta", "item_a", { delta: "one" }));
  emit({ type: "input_audio_buffer.committed", item_id: "item_a" });
  emit(transcription("delta", "item_b", { delta: "two" }));
  emit(transcription("completed", "item_b", { transcript: "two." }));
  emit(transcription("completed", "item_a", { transcript: "one." }));
  emit(transcription("failed", "item_c", { error: { message: "bad audio" } }));
  await until(() => events.length === 5);

  assert.deepEqual(events, [
    ["delta", 0, "one"],
    ["delta", 1, "two"],
    ["final", 1, "two."],
    ["final", 0, "one."],
    ["error", "bad audio"],
  ]);

  transcriber.close();
  await until(() => state.socket?.readyState === 3);
  assert.equal(events.length, 5);
});

test("the transcriber reports a connection that drops", async (t) => {
  const { state, client } = await fakeOpenAI(t);
  const errors: string[] = [];
  createOpenAITranscriber(client, { model: "m", languages: [] })({
    ready() {},
    delta() {},
    final() {},
    error: (error) => errors.push(error.message),
  });
  await until(() => state.socket !== undefined);
  state.socket?.close();
  await until(() => errors.length > 0);
});

test("the refiner asks for the segment to be rewritten, without reasoning or storage", async (t) => {
  const { state, client } = await fakeOpenAI(t);
  state.responseText = " Hello, world. ";
  const refiner = createOpenAIRefiner(client, "gpt-6-luna");

  const refined = await refiner.refine(
    { text: "hello world", previous: "Hi." },
    AbortSignal.timeout(2000),
  );

  assert.equal(refined, "Hello, world.");
  assert.equal(state.responseRequest?.model, "gpt-6-luna");
  assert.equal(
    state.responseRequest?.input,
    "<previous>Hi.</previous>\n<segment>hello world</segment>",
  );
  assert.deepEqual(state.responseRequest?.reasoning, { effort: "none" });
  assert.equal(state.responseRequest?.store, false);
});
