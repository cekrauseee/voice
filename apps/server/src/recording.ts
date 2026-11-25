import OpenAI, { toFile } from "openai";
import { BYTES_PER_SECOND, SAMPLE_RATE } from "./protocol.ts";
import type { CreateTranscriber } from "./transcriber.ts";

export interface OpenAIRecordingTranscriberOptions {
  model: string;
  /** The languages spoken. */
  languages: string[];
}

/** OpenAI transcribes no less than 100 ms of audio. */
const MIN_BYTES = BYTES_PER_SECOND / 10;

/**
 * Transcribes each turn once it is committed, as one file: the audio waits on the server
 * while the speaker talks, and nothing is heard before the stop. There is no connection to
 * set up, so the transcriber is ready at once.
 *
 * The hints are the ones the live transcriber gets. When OpenAI refuses them, the turn is
 * transcribed again without them.
 */
export function createOpenAIRecordingTranscriber(
  client: OpenAI,
  options: OpenAIRecordingTranscriberOptions,
): CreateTranscriber {
  return (events, { keywords } = { keywords: [] }) => {
    const abort = new AbortController();
    /** Audio of the open turn. */
    let chunks: Buffer[] = [];
    let turns = 0;
    let closed = false;

    const hints = {
      ...(options.languages.length > 0 && { languages: options.languages }),
      ...(keywords.length > 0 && { keywords: [...keywords] }),
    };

    const request = async (pcm: Buffer, hinted: boolean) => {
      const transcription = await client.audio.transcriptions.create(
        {
          file: await toFile(wav(pcm), "recording.wav", { type: "audio/wav" }),
          model: options.model,
          ...(hinted && hints),
        },
        { signal: abort.signal },
      );
      return transcription.text;
    };

    const transcribe = async (turn: number, pcm: Buffer) => {
      try {
        let text: string;
        try {
          text = await request(pcm, Object.keys(hints).length > 0);
        } catch (error) {
          if (!(error instanceof OpenAI.BadRequestError) || Object.keys(hints).length === 0) {
            throw error;
          }
          events.hintsRejected({ code: error.code ?? "", param: error.param ?? "" });
          text = await request(pcm, false);
        }
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
