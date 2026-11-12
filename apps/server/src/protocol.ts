/** Messages exchanged with the dictation client. The contract is docs/protocol.md. */

export const DICTATION_PATH = "/v1/dictation";

/** Audio the client streams as binary frames: 16-bit little-endian mono PCM. */
export const SAMPLE_RATE = 24_000;

export type ErrorCode = "bad_request" | "transcription_failed" | "timeout";

/** What a dictation used, and what that costs. */
export interface Usage {
  /** Seconds of audio that were transcribed. */
  audio_seconds: number;
  /** Tokens the refinement read. */
  input_tokens: number;
  /** Tokens the refinement wrote. */
  output_tokens: number;
  /** The cost in US dollars, at the prices the server is configured with. */
  cost: number;
}

/** What OpenAI charges, in US dollars. */
export interface Prices {
  /** For a minute of audio transcribed. */
  transcribeMinute: number;
  /** For a million tokens the refinement reads. */
  refineInput: number;
  /** For a million tokens the refinement writes. */
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

export type ServerMessage =
  | { type: "ready" }
  | { type: "delta"; text: string }
  | { type: "done"; text: string; usage: Usage }
  | { type: "error"; code: ErrorCode; message: string };

export type ClientMessage = { type: "start"; instructions: string } | { type: "stop" };

export function parseClientMessage(raw: string): ClientMessage | undefined {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return undefined;
  }
  if (typeof value !== "object" || value === null || !("type" in value)) return undefined;
  if (value.type === "stop") return { type: "stop" };
  if (value.type === "start") {
    const instructions = "instructions" in value ? value.instructions : "";
    if (typeof instructions === "string") return { type: "start", instructions };
  }
  return undefined;
}
