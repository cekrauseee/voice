import { createServer as createHttpServer, type Server } from "node:http";
import type { Logger } from "@voice/log";
import { type RawData, type WebSocket, WebSocketServer } from "ws";
import type { CreateAgent } from "./agent.ts";
import { ProfileTurn } from "./conversation.ts";
import {
  DICTATION_PATH,
  PROFILE_PATH,
  type Prices,
  type ProfileServerMessage,
  parseClientMessage,
  parseProfileClientMessage,
  type ServerMessage,
} from "./protocol.ts";
import type { CreateRefiner } from "./refiner.ts";
import { DictationSession } from "./session.ts";
import type { CreateTranscriber } from "./transcriber.ts";

export interface ServerDeps {
  /** Transcribes the recording once the speaker stops. */
  createTranscriber: CreateTranscriber;
  /** Transcribes while the speaker talks, for a dictation that asks for it. */
  createLiveTranscriber: CreateTranscriber;
  createRefiner: CreateRefiner;
  createAgent: CreateAgent;
  prices: Prices;
  log: Logger;
}

/**
 * HTTP server with `GET /health`, the dictation WebSocket, and the WebSocket of the profile
 * conversation. One connection is one dictation, or one turn of the conversation.
 */
export function createServer(deps: ServerDeps): Server {
  const server = createHttpServer((request, response) => {
    if (request.method === "GET" && request.url === "/health") {
      response.writeHead(200, { "content-type": "application/json" }).end('{"status":"ok"}');
    } else {
      response.writeHead(404).end();
    }
  });

  const sockets = new WebSocketServer({ noServer: true, maxPayload: 1 << 20 });
  let dictations = 0;
  let turns = 0;

  server.on("upgrade", (request, socket, head) => {
    if (request.url !== DICTATION_PATH && request.url !== PROFILE_PATH) {
      socket.end("HTTP/1.1 404 Not Found\r\n\r\n");
      return;
    }
    // A web page can open a WebSocket to the loopback address too, and only a browser says
    // where it comes from: the app does not.
    if (request.headers.origin !== undefined) {
      deps.log.warn("connection refused", { path: request.url, reason: "origin" });
      socket.end("HTTP/1.1 403 Forbidden\r\n\r\n");
      return;
    }
    sockets.handleUpgrade(request, socket, head, (ws) => {
      if (request.url === PROFILE_PATH) {
        turns += 1;
        profileTurn(ws, deps, turns);
      } else {
        dictations += 1;
        dictation(ws, deps, dictations);
      }
    });
  });

  server.on("close", () => {
    for (const ws of sockets.clients) ws.terminate();
  });

  return server;
}

function dictation(ws: WebSocket, deps: ServerDeps, number: number): void {
  const session = new DictationSession({
    ...deps,
    log: deps.log.child({ scope: "dictation", fields: { dictation: number } }),
    send: (message: ServerMessage) => ws.send(JSON.stringify(message)),
    end: () => ws.close(1000),
  });

  ws.on("message", (data, isBinary) => {
    if (isBinary) {
      session.audio(toBuffer(data));
      return;
    }
    const message = parseClientMessage(toBuffer(data).toString("utf8"));
    if (message?.type === "start") {
      session.start(message);
    } else if (message?.type === "stop") session.stop();
    else session.reject();
  });
  ws.on("close", () => session.close());
  ws.on("error", () => session.close());
}

function profileTurn(ws: WebSocket, deps: ServerDeps, number: number): void {
  const turn = new ProfileTurn({
    ...deps,
    log: deps.log.child({ scope: "profile", fields: { turn: number } }),
    send: (message: ProfileServerMessage) => ws.send(JSON.stringify(message)),
    end: () => ws.close(1000),
  });

  ws.on("message", (data, isBinary) => {
    if (isBinary) {
      turn.audio(toBuffer(data));
      return;
    }
    const message = parseProfileClientMessage(toBuffer(data).toString("utf8"));
    if (message?.type === "start") turn.start(message);
    else if (message?.type === "stop") turn.stop();
    else turn.reject();
  });
  ws.on("close", () => turn.close());
  ws.on("error", () => turn.close());
}

function toBuffer(data: RawData): Buffer {
  if (Buffer.isBuffer(data)) return data;
  return Array.isArray(data) ? Buffer.concat(data) : Buffer.from(data);
}
