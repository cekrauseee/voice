// Streams a WAV file to a running server at speaking pace and prints what comes back,
// with the time of each message. For tuning the pipeline without the desktop app.
//
//   pnpm dictate recording.wav [ws://127.0.0.1:8787] [--instructions "Write formally."]
//
// The file must be 16-bit mono PCM at 24 kHz:
//   afconvert -f WAVE -d LEI16@24000 -c 1 input.m4a recording.wav

import { readFileSync } from "node:fs";
import { parseArgs } from "node:util";
import { WebSocket } from "ws";
import { DICTATION_PATH, SAMPLE_RATE, type ServerMessage } from "../src/protocol.ts";

const CHUNK_MS = 20;
const CHUNK_BYTES = ((SAMPLE_RATE * CHUNK_MS) / 1000) * 2;

function fatal(message: string): never {
  console.error(`error: ${message}`);
  process.exit(1);
}

/** Returns the samples of a 16-bit mono 24 kHz WAV file. */
function readPcm(path: string): Buffer {
  const file = readFileSync(path);
  if (file.toString("ascii", 0, 4) !== "RIFF" || file.toString("ascii", 8, 12) !== "WAVE") {
    fatal(`${path} is not a WAV file.`);
  }
  let pcm: Buffer | undefined;
  let format = "";
  for (let offset = 12; offset + 8 <= file.length; ) {
    const id = file.toString("ascii", offset, offset + 4);
    const size = file.readUInt32LE(offset + 4);
    const body = file.subarray(offset + 8, offset + 8 + size);
    if (id === "fmt ") {
      format = `${body.readUInt16LE(0)}/${body.readUInt16LE(2)}/${body.readUInt32LE(4)}/${body.readUInt16LE(14)}`;
    } else if (id === "data") {
      pcm = body;
    }
    offset += 8 + size + (size % 2);
  }
  if (format !== `1/1/${SAMPLE_RATE}/16` || !pcm) {
    fatal(
      `${path} must be 16-bit mono PCM at 24 kHz. Convert it with:\n  afconvert -f WAVE -d LEI16@24000 -c 1 ${path} converted.wav`,
    );
  }
  return pcm;
}

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: { instructions: { type: "string", default: "" } },
});
const [path, server = "ws://127.0.0.1:8787"] = positionals;
if (!path) {
  fatal('usage: pnpm dictate recording.wav [ws://127.0.0.1:8787] [--instructions "..."]');
}

const pcm = readPcm(path);
const ws = new WebSocket(server + DICTATION_PATH);
const startedAt = Date.now();
const print = (text: string) =>
  console.log(`${String(Date.now() - startedAt).padStart(6)}ms  ${text}`);

ws.on("error", (error) => fatal(`Could not reach ${server}: ${error.message}`));
ws.on("close", () => process.exit(0));
ws.on("message", (data) => {
  const message: ServerMessage = JSON.parse(data.toString());
  switch (message.type) {
    case "delta":
    case "done":
      print(`${message.type.padEnd(5)}  ${JSON.stringify(message.text)}`);
      break;
    case "error":
      print(`error  ${message.code}: ${message.message}`);
      break;
    default:
      print(message.type);
  }
});
ws.on("open", () => {
  ws.send(JSON.stringify({ type: "start", instructions: values.instructions }));
  let offset = 0;
  const timer = setInterval(() => {
    // Send what real time has reached, so timer drift does not slow the stream down.
    const due = Math.floor((Date.now() - startedAt) / CHUNK_MS) * CHUNK_BYTES;
    while (offset < Math.min(due, pcm.length)) {
      ws.send(pcm.subarray(offset, offset + CHUNK_BYTES));
      offset += CHUNK_BYTES;
    }
    if (offset >= pcm.length) {
      clearInterval(timer);
      print("stop");
      ws.send(JSON.stringify({ type: "stop" }));
    }
  }, CHUNK_MS);
});
