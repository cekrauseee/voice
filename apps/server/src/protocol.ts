/** Messages exchanged with the dictation and meeting clients. The contract is docs/protocol.md. */

export const DICTATION_PATH = "/v1/dictation";
export const MEETING_PATH = "/v1/meeting";

/** Audio the client streams as binary frames: 16-bit little-endian mono PCM. */
export const SAMPLE_RATE = 24_000;
/** The audio is 16-bit mono at 24 kHz. */
export const BYTES_PER_SECOND = SAMPLE_RATE * 2;

export type ErrorCode = "bad_request" | "transcription_failed" | "timeout";

/** What a dictation or a meeting used, and what that costs. */
export interface Usage {
  /** Seconds of audio that were transcribed. */
  audio_seconds: number;
  /** Tokens the language model read. */
  input_tokens: number;
  /** Tokens the language model wrote. */
  output_tokens: number;
  /** The cost in US dollars, at the prices the server is configured with. */
  cost: number;
}

/** What OpenAI charges, in US dollars. */
export interface Prices {
  /** For a minute of audio transcribed. */
  transcribeMinute: number;
  /** For a million tokens the language model reads. */
  refineInput: number;
  /** For a million tokens the language model writes. */
  refineOutput: number;
}

export function usage(
  prices: Prices,
  audioSeconds: number,
  inputTokens: number,
  outputTokens: number,
): Usage {
  const cost =
    (audioSeconds / 60) * prices.transcribeMinute +
    (inputTokens * prices.refineInput + outputTokens * prices.refineOutput) / 1_000_000;
  return {
    audio_seconds: Math.round(audioSeconds * 10) / 10,
    input_tokens: inputTokens,
    output_tokens: outputTokens,
    cost: Math.round(cost * 1_000_000) / 1_000_000,
  };
}

// Dictation

export type ServerMessage =
  | { type: "ready" }
  | { type: "delta"; text: string }
  | { type: "done"; text: string; usage: Usage }
  | { type: "error"; code: ErrorCode; message: string };

export type ClientMessage = { type: "start"; instructions: string } | { type: "stop" };

export function parseClientMessage(raw: string): ClientMessage | undefined {
  const value = parseJson(raw);
  if (value === undefined) return undefined;
  if (value.type === "stop") return { type: "stop" };
  if (value.type === "start") {
    const instructions = value.instructions ?? "";
    if (typeof instructions === "string") return { type: "start", instructions };
  }
  return undefined;
}

// Meeting

/**
 * The two sides of a meeting, each an audio channel: the speaker's microphone, and what
 * the meeting app plays. The first byte of a binary frame says which channel its audio is.
 */
export type Channel = "me" | "others";
export const CHANNELS: readonly Channel[] = ["me", "others"];

/** Where each channel's clock starts, in seconds of the meeting. */
export type Offsets = Record<Channel, number>;

/** A stretch of speech on one channel, with its text. */
export interface Segment {
  id: number;
  channel: Channel;
  /** Seconds since the meeting started. */
  start: number;
  end: number;
  text: string;
}

export type MeetingServerMessage =
  | { type: "ready" }
  | { type: "draft"; channel: Channel; text: string }
  | ({ type: "segment" } & Segment)
  /** The segments from `from` to `to` are replaced by `segments`, revised. */
  | { type: "revised"; from: number; to: number; segments: Segment[] }
  | { type: "usage"; usage: Usage }
  | { type: "done"; usage: Usage }
  | { type: "error"; code: ErrorCode; message: string };

export interface MeetingStart {
  type: "start";
  instructions: string;
  /** The id of the first segment. */
  first_id: number;
  offsets: Offsets;
}

export type MeetingClientMessage = MeetingStart | { type: "stop" };

export function parseMeetingClientMessage(raw: string): MeetingClientMessage | undefined {
  const value = parseJson(raw);
  if (value === undefined) return undefined;
  if (value.type === "stop") return { type: "stop" };
  if (value.type !== "start") return undefined;
  const instructions = value.instructions ?? "";
  const firstId = value.first_id ?? 1;
  if (typeof instructions !== "string" || !Number.isInteger(firstId)) return undefined;
  const offsets: Offsets = { me: 0, others: 0 };
  const given = value.offsets ?? {};
  if (typeof given !== "object" || given === null) return undefined;
  for (const channel of CHANNELS) {
    const offset = (given as Record<string, unknown>)[channel] ?? 0;
    if (typeof offset !== "number" || !(offset >= 0)) return undefined;
    offsets[channel] = offset;
  }
  return { type: "start", instructions, first_id: firstId as number, offsets };
}

/** Splits a binary frame of a meeting into its channel and its audio. */
export function parseAudioFrame(frame: Buffer): { channel: Channel; pcm: Buffer } | undefined {
  const channel = CHANNELS[frame[0] ?? -1];
  if (channel === undefined || frame.length % 2 !== 1) return undefined;
  return { channel, pcm: frame.subarray(1) };
}

function parseJson(raw: string): Record<string, unknown> | undefined {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return undefined;
  }
  if (typeof value !== "object" || value === null || !("type" in value)) return undefined;
  return value as Record<string, unknown>;
}
