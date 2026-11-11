/** Messages exchanged with the dictation client. The contract is docs/protocol.md. */

export const DICTATION_PATH = "/v1/dictation";

/** Audio the client streams as binary frames: 16-bit little-endian mono PCM. */
export const SAMPLE_RATE = 24_000;

export type ErrorCode = "bad_request" | "transcription_failed" | "timeout";

export type ServerMessage =
  | { type: "ready" }
  | { type: "delta"; segment: number; text: string }
  | { type: "final"; segment: number; text: string }
  | { type: "refined"; segment: number; text: string }
  | { type: "done" }
  | { type: "error"; code: ErrorCode; message: string };

export type ClientMessage = { type: "stop" };

export function parseClientMessage(raw: string): ClientMessage | undefined {
  let value: unknown;
  try {
    value = JSON.parse(raw);
  } catch {
    return undefined;
  }
  if (typeof value === "object" && value !== null && "type" in value && value.type === "stop") {
    return { type: "stop" };
  }
  return undefined;
}
