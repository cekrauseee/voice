// Reads recordings for the scripts that replay them against a running server.

import { readFileSync } from "node:fs";
import { SAMPLE_RATE } from "../src/protocol.ts";

export function fatal(message: string): never {
  console.error(`error: ${message}`);
  process.exit(1);
}

/** Returns the samples of a 16-bit mono 24 kHz WAV file. */
export function readPcm(path: string): Buffer {
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
