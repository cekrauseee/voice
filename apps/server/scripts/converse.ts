// Holds a profile conversation with a running server: each WAV file is one turn, streamed at
// speaking pace, and the conversation so far goes with the next, as the app keeps it. Prints
// what was heard, the agent's reply as it comes, and how long each took after the stop.
//
//   pnpm converse turn1.wav turn2.wav... [--server ws://127.0.0.1:8787] [--opening "..."] [--profile profile.json] [--out profile.json]
//
// --profile starts from a profile, as the profile conversation writes it. --out writes the
// profile the conversation ends with, for `pnpm dictate --profile`. Terms the agent adds go to
// the dictionary the next turns are sent.
//
// The files must be 16-bit mono PCM at 24 kHz:
//   afconvert -f WAVE -d LEI16@24000 -c 1 input.m4a recording.wav

import { readFileSync, writeFileSync } from "node:fs";
import { parseArgs } from "node:util";
import { WebSocket } from "ws";
import {
  type ConversationEntry,
  PROFILE_PATH,
  type ProfileServerMessage,
  SAMPLE_RATE,
  type WireProfile,
} from "../src/protocol.ts";
import { fatal, readPcm } from "./wav.ts";

const CHUNK_MS = 20;
const CHUNK_BYTES = ((SAMPLE_RATE * CHUNK_MS) / 1000) * 2;

const { positionals, values } = parseArgs({
  allowPositionals: true,
  options: {
    server: { type: "string", default: "ws://127.0.0.1:8787" },
    opening: {
      type: "string",
      default: "Hi! Tell me about yourself: what do you do, and what do you usually dictate?",
    },
    profile: { type: "string" },
    out: { type: "string" },
  },
});
if (positionals.length === 0) {
  fatal(
    'usage: pnpm converse turn1.wav [turn2.wav]... [--server ws://127.0.0.1:8787] [--opening "..."] [--profile profile.json] [--out profile.json]',
  );
}

/** The wire history entry the app sends: the profile, when the agent changed it. */
type Entry = Omit<ConversationEntry, "profile"> & { profile?: WireProfile };

let profile: WireProfile = values.profile
  ? JSON.parse(readFileSync(values.profile, "utf8"))
  : { instructions: "", transcription_prompt: "", languages: [], terms: [] };
const vocabulary: string[] = [];
const history: Entry[] = [{ role: "assistant", text: values.opening }];
console.log(`agent  ${values.opening}`);

/** One turn: the recording in, the agent's answer out. */
function turn(path: string): Promise<void> {
  const pcm = readPcm(path);
  const ws = new WebSocket(values.server + PROFILE_PATH);
  const startedAt = Date.now();
  let stoppedAt = 0;
  let firstReply = 0;
  let reply = "";
  const since = () => `${String(Date.now() - stoppedAt).padStart(5)}ms after stop`;

  return new Promise((resolve) => {
    ws.on("error", (error) => fatal(`Could not reach ${values.server}: ${error.message}`));
    ws.on("close", () => resolve());
    ws.on("message", (data) => {
      const message: ProfileServerMessage = JSON.parse(data.toString());
      switch (message.type) {
        case "heard":
          console.log(`\nyou    ${message.text}  (${since()})`);
          history.push({ role: "user", text: message.text });
          break;
        case "reply":
          if (firstReply === 0) {
            firstReply = Date.now();
            process.stdout.write(`agent  (${since()}) `);
          }
          reply += message.text;
          process.stdout.write(message.text);
          break;
        case "done":
          if (reply === "") console.log(`agent  ${message.reply}`);
          else console.log();
          console.log(
            `       done ${since()}, profile ${message.profile ? "changed" : "unchanged"}, added ${JSON.stringify(message.add_terms)}, ${JSON.stringify(message.usage)}`,
          );
          if (message.reply !== "") {
            history.push({
              role: "assistant",
              text: message.reply,
              ...(message.profile && { profile: message.profile }),
            });
          }
          if (message.profile) profile = message.profile;
          vocabulary.unshift(...message.add_terms);
          break;
        case "error":
          console.log(`\nerror  ${message.code}: ${message.message}`);
          break;
        default:
          break;
      }
    });
    ws.on("open", () => {
      ws.send(JSON.stringify({ type: "start", history, profile, vocabulary }));
      let offset = 0;
      const timer = setInterval(() => {
        const due = Math.floor((Date.now() - startedAt) / CHUNK_MS) * CHUNK_BYTES;
        while (offset < Math.min(due, pcm.length)) {
          ws.send(pcm.subarray(offset, offset + CHUNK_BYTES));
          offset += CHUNK_BYTES;
        }
        if (offset >= pcm.length) {
          clearInterval(timer);
          stoppedAt = Date.now();
          ws.send(JSON.stringify({ type: "stop" }));
        }
      }, CHUNK_MS);
    });
  });
}

for (const path of positionals) await turn(path);
console.log(`\nprofile ${JSON.stringify(profile, null, 2)}`);
console.log(`dictionary ${JSON.stringify(vocabulary)}`);
if (values.out) writeFileSync(values.out, `${JSON.stringify(profile, null, 2)}\n`);
