import OpenAI, { toFile } from "openai";
import { BYTES_PER_SECOND, SAMPLE_RATE } from "./protocol.ts";
import type { CreateTranscriber } from "./transcriber.ts";

export interface OpenAIRecordingTranscriberOptions {
  model: string;
  /** The languages spoken. */
  languages: string[];
  /** The longest part of a recording sent in one file. Five minutes unless set. */
  partSeconds?: number;
}

/** OpenAI transcribes no less than 100 ms of audio. */
const MIN_BYTES = BYTES_PER_SECOND / 10;

/**
 * A recording is sent in parts of at most five minutes. OpenAI takes files of up to 25 MB,
 * about nine minutes of this audio, and shorter parts are transcribed side by side.
 */
const PART_SECONDS = 300;

/** How far before the end of a part its quietest moment is looked for, to cut there. */
const PAUSE_WINDOW_SECONDS = 30;

/** How many parts of one recording are transcribed at once. */
const PARALLEL_PARTS = 4;

/**
 * Transcribes each turn once it is committed: the audio waits on the server while the
 * speaker talks, and nothing is heard before the stop. There is no connection to set up, so
 * the transcriber is ready at once.
 *
 * A turn is sent as one file, or, when it is long, as parts cut at pauses, transcribed side
 * by side and put back together in order.
 *
 * The hints are the ones the live transcriber gets, and every part gets them: the names and
 * terms, the description of the recording, and the languages spoken, in place of the
 * server's. When OpenAI refuses them, the part is transcribed again without them, with the
 * server's own languages, and so are the parts after it.
 */
export function createOpenAIRecordingTranscriber(
  client: OpenAI,
  options: OpenAIRecordingTranscriberOptions,
): CreateTranscriber {
  return (events, { keywords = [], prompt = "", languages = [] } = {}) => {
    const abort = new AbortController();
    /** Audio of the open turn. */
    let chunks: Buffer[] = [];
    let turns = 0;
    let closed = false;

    // The server's own languages are its configuration, not a hint: they stay when the hints go.
    const configured = options.languages.length > 0 ? { languages: options.languages } : {};
    const hints = {
      ...configured,
      ...(languages.length > 0 && { languages: [...languages] }),
      ...(keywords.length > 0 && { keywords: [...keywords] }),
      ...(prompt !== "" && { prompt }),
    };
    let hinted = languages.length > 0 || keywords.length > 0 || prompt !== "";
    const partBytes = (options.partSeconds ?? PART_SECONDS) * BYTES_PER_SECOND;

    const request = async (pcm: Buffer, hinted: boolean) => {
      const transcription = await client.audio.transcriptions.create(
        {
          file: await toFile(wav(pcm), "recording.wav", { type: "audio/wav" }),
          model: options.model,
          ...(hinted ? hints : configured),
        },
        { signal: abort.signal },
      );
      return transcription.text;
    };

    /** One part, with the hints unless OpenAI refused them. */
    const transcribePart = async (pcm: Buffer): Promise<string> => {
      if (!hinted) return request(pcm, false);
      try {
        return await request(pcm, true);
      } catch (error) {
        if (!(error instanceof OpenAI.BadRequestError)) throw error;
        // Parts sent side by side may each be refused: it is said once.
        if (hinted) {
          hinted = false;
          events.hintsRejected({ code: error.code ?? "", param: error.param ?? "" });
        }
        return request(pcm, false);
      }
    };

    const transcribe = async (turn: number, pcm: Buffer) => {
      try {
        const parts = splitAtPauses(pcm, partBytes, PAUSE_WINDOW_SECONDS * BYTES_PER_SECOND);
        const texts = await mapLimited(parts, PARALLEL_PARTS, transcribePart);
        const text = texts
          .map((part) => part.trim())
          .filter((part) => part !== "")
          .join(" ");
        if (!closed) events.final(turn, text);
      } catch (error) {
        if (!closed) events.error(error instanceof Error ? error : new Error(String(error)));
      }
    };

    queueMicrotask(() => {
      if (!closed) events.ready();
    });

    return {
      append(pcm) {
        chunks.push(pcm);
      },
      commit() {
        const turn = turns++;
        const pcm = Buffer.concat(chunks);
        chunks = [];
        if (pcm.length < MIN_BYTES) {
          // Too short to hold a word, and OpenAI would reject it.
          queueMicrotask(() => {
            if (!closed) events.final(turn, "");
          });
          return;
        }
        void transcribe(turn, pcm);
      },
      close() {
        closed = true;
        abort.abort();
      },
    };
  };
}

/** The length of the frames whose loudness is compared to find a pause: a tenth of a second. */
const FRAME_BYTES = BYTES_PER_SECOND / 10;

/**
 * Cuts 16-bit PCM into parts of at most `maxBytes`. Each cut is at the quietest tenth of a
 * second in the `windowBytes` before the limit, so that it falls between words rather than
 * in one: the latest of the quietest, and never in the first half of a part, so parts stay
 * long.
 */
export function splitAtPauses(pcm: Buffer, maxBytes: number, windowBytes: number): Buffer[] {
  const parts: Buffer[] = [];
  let start = 0;
  while (pcm.length - start > maxBytes) {
    const end = start + maxBytes;
    const from = Math.max(start + evenHalf(maxBytes), end - windowBytes);
    let cut = end;
    let quietest = Number.POSITIVE_INFINITY;
    // Frames half overlap, every 50 ms, so a short pause is not missed.
    for (let frame = from; frame + FRAME_BYTES <= end; frame += FRAME_BYTES / 2) {
      const loudness = energy(pcm, frame, frame + FRAME_BYTES);
      if (loudness <= quietest) {
        quietest = loudness;
        cut = frame + FRAME_BYTES / 2;
      }
    }
    parts.push(pcm.subarray(start, cut));
    start = cut;
  }
  parts.push(pcm.subarray(start));
  return parts;
}

/** Half of a length in bytes, on a sample. */
function evenHalf(bytes: number): number {
  return Math.floor(bytes / 4) * 2;
}

/** The mean square of the 16-bit samples from `from` to `to`, both even byte offsets. */
function energy(pcm: Buffer, from: number, to: number): number {
  let sum = 0;
  for (let offset = from; offset < to; offset += 2) {
    const sample = pcm.readInt16LE(offset);
    sum += sample * sample;
  }
  return sum / ((to - from) / 2);
}

/** Maps the items, at most `limit` at a time, keeping their order. */
async function mapLimited<T, R>(
  items: readonly T[],
  limit: number,
  map: (item: T) => Promise<R>,
): Promise<R[]> {
  const results: R[] = new Array(items.length);
  let next = 0;
  const work = async () => {
    while (next < items.length) {
      const index = next++;
      results[index] = await map(items[index] as T);
    }
  };
  await Promise.all(Array.from({ length: Math.min(limit, items.length) }, work));
  return results;
}

/** 16-bit mono PCM at the protocol's rate, in a WAV file. */
export function wav(pcm: Buffer): Buffer {
  const header = Buffer.alloc(44);
  header.write("RIFF", 0, "ascii");
  header.writeUInt32LE(36 + pcm.length, 4);
  header.write("WAVE", 8, "ascii");
  header.write("fmt ", 12, "ascii");
  header.writeUInt32LE(16, 16);
  header.writeUInt16LE(1, 20);
  header.writeUInt16LE(1, 22);
  header.writeUInt32LE(SAMPLE_RATE, 24);
  header.writeUInt32LE(BYTES_PER_SECOND, 28);
  header.writeUInt16LE(2, 32);
  header.writeUInt16LE(16, 34);
  header.write("data", 36, "ascii");
  header.writeUInt32LE(pcm.length, 40);
  return Buffer.concat([header, pcm]);
}
