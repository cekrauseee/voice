import type OpenAI from "openai";
import { OpenAIRealtimeWS } from "openai/realtime/ws";
import type { RealtimeClientEvent } from "openai/resources/realtime/realtime";
import { SAMPLE_RATE } from "./protocol.ts";

export interface TranscriberEvents {
  /** The transcription session is configured and receiving audio. */
  ready(): void;
  /** New live text for a segment. Segments are numbered by commit order, from 0. */
  delta(segment: number, text: string): void;
  /** The complete transcript of a committed segment. Order across segments is not guaranteed. */
  final(segment: number, text: string): void;
  error(error: Error): void;
}

export interface Transcriber {
  append(pcm: Buffer): void;
  /** Ends the current segment. */
  commit(): void;
  close(): void;
}

export type CreateTranscriber = (events: TranscriberEvents) => Transcriber;

export interface OpenAITranscriberOptions {
  model: string;
  languages: string[];
}

/** Transcribes through an OpenAI realtime transcription session, one per dictation. */
export function createOpenAITranscriber(
  client: OpenAI,
  options: OpenAITranscriberOptions,
): CreateTranscriber {
  return (events) => {
    const realtime = new OpenAIRealtimeWS({ intent: "transcription" }, client);
    // Item ids in order of first appearance. Each commit creates one item, so the index is the segment.
    const items: string[] = [];
    // Events wait here until the session is configured, so no audio precedes its format.
    let queued: RealtimeClientEvent[] | undefined = [];
    let closed = false;

    const segmentOf = (itemId: string): number => {
      const index = items.indexOf(itemId);
      return index === -1 ? items.push(itemId) - 1 : index;
    };
    const send = (event: RealtimeClientEvent) => {
      if (queued) queued.push(event);
      else realtime.send(event);
    };
    const fail = (error: Error) => {
      if (!closed) events.error(error);
    };

    realtime.socket.on("open", () => {
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
      segmentOf(event.item_id);
    });
    realtime.on("conversation.item.input_audio_transcription.delta", (event) => {
      if (event.delta) events.delta(segmentOf(event.item_id), event.delta);
    });
    realtime.on("conversation.item.input_audio_transcription.completed", (event) => {
      events.final(segmentOf(event.item_id), event.transcript);
    });
    realtime.on("conversation.item.input_audio_transcription.failed", (event) => {
      fail(new Error(event.error.message ?? "Transcription failed"));
    });

    return {
      append(pcm) {
        send({ type: "input_audio_buffer.append", audio: pcm.toString("base64") });
      },
      commit() {
        send({ type: "input_audio_buffer.commit" });
      },
      close() {
        closed = true;
        realtime.close();
      },
    };
  };
}
