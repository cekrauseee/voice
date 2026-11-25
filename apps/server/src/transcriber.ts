import OpenAI from "openai";
import { OpenAIRealtimeWS } from "openai/realtime/ws";
import type { RealtimeClientEvent } from "openai/resources/realtime/realtime";
import { SAMPLE_RATE } from "./protocol.ts";

export interface TranscriberEvents {
  /** The transcription session is configured and receiving audio. */
  ready(): void;
  /**
   * More text, heard while the speaker talks. Turns are numbered by commit order, from 0:
   * the open turn is the one after the last commit.
   */
  delta(turn: number, text: string): void;
  /** The complete transcript of a committed turn. Turns may complete out of order. */
  final(turn: number, text: string): void;
  error(error: Error): void;
  /**
   * OpenAI refused the hints, such as a prompt it finds too long. The transcription goes on
   * without them. `param` names the hint refused.
   */
  hintsRejected(rejection: { code: string; param: string }): void;
}

/** OpenAI could not be reached: the connection failed before anything was transcribed. */
export class UnreachableError extends Error {}

/**
 * Whether a transcription failed because OpenAI could not be reached, rather than because of
 * what it was sent or how it answered. The cause of an error is looked at too.
 */
export function isUnreachable(error: unknown): boolean {
  for (let depth = 0; error instanceof Error && depth < 5; depth += 1) {
    if (error instanceof UnreachableError || error instanceof OpenAI.APIConnectionError) {
      return true;
    }
    error = error.cause;
  }
  return false;
}

/** An error of the network itself, such as a refused connection or an unknown host. */
function isNetworkError(error: unknown): boolean {
  return error instanceof Error && "code" in error && typeof error.code === "string";
}

export interface Transcriber {
  append(pcm: Buffer): void;
  /** Ends the open turn. Its complete transcript follows. */
  commit(): void;
  close(): void;
}

/** What the transcriber is told about the audio it will hear. */
export interface TranscriptionHints {
  /** Names and terms that may be said, as they are spelled. */
  keywords: readonly string[];
}

export type CreateTranscriber = (
  events: TranscriberEvents,
  hints?: TranscriptionHints,
) => Transcriber;

export interface OpenAITranscriberOptions {
  model: string;
  languages: string[];
}

/** OpenAI rejects a commit of less audio than 100 ms. */
const MIN_COMMIT_BYTES = (SAMPLE_RATE / 10) * 2;

/**
 * Transcribes through an OpenAI realtime transcription session.
 *
 * The audio is sent as turns that the caller commits: a dictation is one turn, a meeting
 * channel many. The model hears each turn whole, so it punctuates and recognizes better
 * than on audio cut at every pause.
 */
export function createOpenAITranscriber(
  client: OpenAI,
  options: OpenAITranscriberOptions,
): CreateTranscriber {
  return (events, { keywords } = { keywords: [] }) => {
    const realtime = new OpenAIRealtimeWS({ intent: "transcription" }, client);
    // Item ids in order of first appearance. Each commit makes one item, so the index of
    // an item is its turn.
    const items: string[] = [];
    // Events wait here until the session is configured, so no audio precedes its format.
    let queued: RealtimeClientEvent[] | undefined = [];
    /** Audio of the open turn. */
    let bytes = 0;
    let skipped = 0;
    let closed = false;
    /** Whether the connection to OpenAI opened. */
    let opened = false;

    const turnOf = (itemId: string): number => {
      const index = items.indexOf(itemId);
      return index === -1 ? items.push(itemId) - 1 : index;
    };
    const send = (event: RealtimeClientEvent) => {
      if (queued) queued.push(event);
      else realtime.send(event);
    };
    const fail = (error: Error) => {
      if (closed) return;
      // A connection that never opened, for a reason of the network, never reached OpenAI.
      events.error(
        !opened && isNetworkError(error.cause)
          ? new UnreachableError(error.message, { cause: error })
          : error,
      );
    };

    realtime.socket.on("open", () => {
      opened = true;
      realtime.send({
        type: "session.update",
        session: {
          type: "transcription",
          audio: {
            input: {
              format: { type: "audio/pcm", rate: SAMPLE_RATE },
              transcription: {
                model: options.model,
                ...(options.languages.length > 0 && { languages: options.languages }),
                ...(keywords.length > 0 && { keywords: [...keywords] }),
              },
              turn_detection: null,
            },
          },
        },
      });
    });
    realtime.socket.on("close", () => fail(new Error("Transcription connection closed")));
    realtime.on("error", fail);

    realtime.on("session.updated", () => {
      if (!queued) return;
      const pending = queued;
      queued = undefined;
      for (const event of pending) realtime.send(event);
      events.ready();
    });
    realtime.on("input_audio_buffer.committed", (event) => {
      turnOf(event.item_id);
    });
    realtime.on("conversation.item.input_audio_transcription.delta", (event) => {
      if (event.delta) events.delta(turnOf(event.item_id), event.delta);
    });
    realtime.on("conversation.item.input_audio_transcription.completed", (event) => {
      events.final(turnOf(event.item_id), event.transcript);
    });
    realtime.on("conversation.item.input_audio_transcription.failed", (event) => {
      fail(new Error(event.error.message ?? "Transcription failed"));
    });

    return {
      append(pcm) {
        bytes += pcm.length;
        send({ type: "input_audio_buffer.append", audio: pcm.toString("base64") });
      },
      commit() {
        if (bytes >= MIN_COMMIT_BYTES) {
          send({ type: "input_audio_buffer.commit" });
        } else {
          // Too short to hold a word, and OpenAI would reject it. The turn takes an index
          // that no item will, so the turns after it keep their numbers.
          skipped += 1;
          const turn = turnOf(`skipped-${skipped}`);
          queueMicrotask(() => {
            if (!closed) events.final(turn, "");
          });
        }
        bytes = 0;
      },
      close() {
        closed = true;
        realtime.close();
      },
    };
  };
}
