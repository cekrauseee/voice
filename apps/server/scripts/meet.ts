// Streams the two channels of a meeting to a running server and prints what comes back,
// with the time of each message. For tuning the pipeline without the desktop app.
//
//   pnpm meet me.wav others.wav [ws://127.0.0.1:8787] [--rate 4]
//
// Either file may be `-` for a silent channel. The files must be 16-bit mono PCM at 24 kHz:
//   afconvert -f WAVE -d LEI16@24000 -c 1 input.m4a me.wav
//
// `--rate` sends the audio that many times faster than it was spoken.

import { readFileSync } from "node:fs";
import { parseArgs } from "node:util";
import { WebSocket } from "ws";
import { CHANNELS, MEETING_PATH, type MeetingServerMessage, SAMPLE_RATE } from "../src/protocol.ts";

const CHUNK_MS = 40;
const CHUNK_BYTES = ((SAMPLE_RATE * CHUNK_MS) / 1000) * 2;

function fatal(message: string): never {
  console.error(`error: ${message}`);
  process.exit(1);
}

/** Returns the samples of a 16-bit mono 24 kHz WAV file, or nothing for `-`. */
function readPcm(path: string): Buffer {
  if (path === "-") return Buffer.alloc(0);
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
  options: { rate: { type: "string", default: "1" } },
});
const [mePath, othersPath, server = "ws://127.0.0.1:8787"] = positionals;
const rate = Number(values.rate);
if (!mePath || !othersPath || !(rate > 0)) {
  fatal("usage: pnpm meet me.wav others.wav [ws://127.0.0.1:8787] [--rate 4]");
}

const channels = [readPcm(mePath), readPcm(othersPath)];
const ws = new WebSocket(server + MEETING_PATH);
const startedAt = Date.now();
const print = (text: string) =>
  console.log(`${String(Date.now() - startedAt).padStart(6)}ms  ${text}`);
const clock = (seconds: number) => {
  const whole = Math.floor(seconds);
  return `${Math.floor(whole / 60)}:${String(whole % 60).padStart(2, "0")}`;
};

ws.on("error", (error) => fatal(`Could not reach ${server}: ${error.message}`));
ws.on("close", () => process.exit(0));
ws.on("message", (data) => {
  const message: MeetingServerMessage = JSON.parse(data.toString());
  switch (message.type) {
    case "draft":
      print(`draft    ${message.channel.padEnd(6)} ${JSON.stringify(message.text)}`);
      break;
    case "segment":
      print(
        `segment  ${message.channel.padEnd(6)} #${message.id} ${clock(message.start)}-${clock(message.end)} ${JSON.stringify(message.text)}`,
      );
      break;
    case "usage":
      break;
    case "done":
      print(`done     ${JSON.stringify(message.usage)}`);
      break;
    case "error":
      print(`error    ${message.code}: ${message.message}`);
      break;
    default:
      print(message.type);
  }
});
ws.on("open", () => {
  ws.send(JSON.stringify({ type: "start" }));
  const offsets = [0, 0];
  const timer = setInterval(() => {
    // Send what the clock has reached, so timer drift does not slow the stream down.
    const due = Math.floor(((Date.now() - startedAt) * rate) / CHUNK_MS) * CHUNK_BYTES;
    let left = false;
    channels.forEach((pcm, index) => {
      while ((offsets[index] ?? 0) < Math.min(due, pcm.length)) {
        const offset = offsets[index] ?? 0;
        ws.send(Buffer.concat([Buffer.from([index]), pcm.subarray(offset, offset + CHUNK_BYTES)]));
        offsets[index] = offset + CHUNK_BYTES;
      }
      if ((offsets[index] ?? 0) < pcm.length) left = true;
    });
    if (!left) {
      clearInterval(timer);
      print("stop");
      ws.send(JSON.stringify({ type: "stop" }));
    }
  }, CHUNK_MS);
});

// The two channels are the two sides, in the order the protocol numbers them.
void CHANNELS;
