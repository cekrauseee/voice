import type OpenAI from "openai";
import { ResponsesWS } from "openai/resources/responses/ws";

export interface ResponsesRequest {
  /** The system prompt. */
  instructions: string;
  /** The user message. */
  input: string;
  /** A JSON schema the answer must follow, by name. Without it, the answer is free text. */
  format?: { name: string; schema: Record<string, unknown> };
}

/** The model's answer, and the tokens it took. */
export interface ResponsesOutput {
  text: string;
  inputTokens: number;
  outputTokens: number;
}

/** One connection to the Responses API, for one request at a time. */
export interface Responses {
  /** Resolves with the model's answer. Rejects when the model fails or stops answering. */
  request(request: ResponsesRequest, signal: AbortSignal): Promise<ResponsesOutput>;
  close(): void;
}

export type CreateResponses = () => Responses;

export interface OpenAIResponsesOptions {
  model: string;
  /** How long the model may go without sending anything before the request is given up. */
  stallMs?: number;
}

const STALL_MS = 5_000;

/**
 * Asks the model through the OpenAI Responses API over a WebSocket.
 *
 * The connection opens when it is created, so the first request goes out on a connection
 * that is already there. A connection that is gone by the next request is opened again.
 */
export function createOpenAIResponses(
  client: OpenAI,
  { model, stallMs = STALL_MS }: OpenAIResponsesOptions,
): CreateResponses {
  return () => {
    let socket: ResponsesWS | undefined;
    // The request in progress: how to end it, and the text received so far.
    let settle: ((result: ResponsesOutput | Error) => void) | undefined;
    let output = "";
    let stall: NodeJS.Timeout | undefined;

    const finish = (result: ResponsesOutput | Error) => {
      clearTimeout(stall);
      settle?.(result);
      settle = undefined;
    };
    /** Gives the model a fresh `stallMs` to send its next event. */
    const watch = () => {
      clearTimeout(stall);
      if (settle) stall = setTimeout(() => finish(new Error("Response stalled")), stallMs);
    };
    const connect = () => {
      const ws = new ResponsesWS(client);
      const lose = (error: Error) => {
        if (socket !== ws) return;
        socket = undefined;
        ws.close();
        finish(error);
      };
      ws.on("error", lose);
      ws.on("close", () => lose(new Error("Response connection closed")));
      ws.on("event", watch);
      ws.on("response.output_text.delta", (event) => {
        output += event.delta;
      });
      ws.on("response.completed", (event) => {
        const { input_tokens = 0, output_tokens = 0 } = event.response.usage ?? {};
        finish({ text: output.trim(), inputTokens: input_tokens, outputTokens: output_tokens });
      });
      ws.on("response.incomplete", () => finish(new Error("Response incomplete")));
      ws.on("response.failed", (event) => {
        finish(new Error(event.response.error?.message ?? "Response failed"));
      });
      return ws;
    };
    socket = connect();

    return {
      request({ instructions, input, format }, signal) {
        return new Promise((resolve, reject) => {
          signal.throwIfAborted();
          const abort = () => {
            finish(signal.reason instanceof Error ? signal.reason : new Error("Response aborted"));
          };
          signal.addEventListener("abort", abort, { once: true });
          settle = (result) => {
            signal.removeEventListener("abort", abort);
            if (result instanceof Error) reject(result);
            else resolve(result);
          };
          output = "";
          // The connection opened at the start may be gone by now.
          socket ??= connect();
          socket.send({
            type: "response.create",
            model,
            instructions,
            input,
            ...(format && {
              text: {
                format: {
                  type: "json_schema",
                  name: format.name,
                  schema: format.schema,
                  strict: true,
                },
              },
            }),
            reasoning: { effort: "none" },
            store: false,
          });
          watch();
        });
      },
      close() {
        const ws = socket;
        socket = undefined;
        ws?.close();
        finish(new Error("Response closed"));
      },
    };
  };
}
