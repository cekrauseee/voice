import { createServer as createHttpServer, type Server } from "node:http";
import type { Logger } from "@voice/log";
import { type RawData, type WebSocket, WebSocketServer } from "ws";
import { MeetingSession } from "./meeting.ts";
import {
  DICTATION_PATH,
  MEETING_PATH,
  type MeetingServerMessage,
  type Prices,
  parseAudioFrame,
  parseClientMessage,
  parseMeetingClientMessage,
  type ServerMessage,
} from "./protocol.ts";
import type { CreateRefiner } from "./refiner.ts";
import { DictationSession } from "./session.ts";
import type { CreateTranscriber } from "./transcriber.ts";

export interface ServerDeps {
  createTranscriber: CreateTranscriber;
  createRefiner: CreateRefiner;
  prices: Prices;
  log: Logger;
}

/**
 * HTTP server with `GET /health`, the dictation WebSocket, and the meeting WebSocket. One
 * connection is one dictation, or one connection of a meeting.
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
  let meetings = 0;

  server.on("upgrade", (request, socket, head) => {
    if (request.url === DICTATION_PATH) {
      sockets.handleUpgrade(request, socket, head, (ws) => {
        dictations += 1;
        dictation(ws, deps, dictations);
      });
    } else if (request.url === MEETING_PATH) {
      sockets.handleUpgrade(request, socket, head, (ws) => {
        meetings += 1;
        meeting(ws, deps, meetings);
      });
    } else {
      socket.end("HTTP/1.1 404 Not Found\r\n\r\n");
    }
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
    if (message?.type === "start") session.start(message.instructions);
    else if (message?.type === "stop") session.stop();
    else session.reject();
  });
  ws.on("close", () => session.close());
  ws.on("error", () => session.close());
}

function meeting(ws: WebSocket, deps: ServerDeps, number: number): void {
  const session = new MeetingSession({
    ...deps,
    log: deps.log.child({ scope: "meeting", fields: { meeting: number } }),
    send: (message: MeetingServerMessage) => ws.send(JSON.stringify(message)),
    end: () => ws.close(1000),
  });

  ws.on("message", (data, isBinary) => {
    if (isBinary) {
      const frame = parseAudioFrame(toBuffer(data));
      if (frame) session.audio(frame.channel, frame.pcm);
      else session.reject();
      return;
    }
    const message = parseMeetingClientMessage(toBuffer(data).toString("utf8"));
    if (message?.type === "start") session.start(message);
    else if (message?.type === "stop") session.stop();
    else session.reject();
  });
  ws.on("close", () => session.close());
  ws.on("error", () => session.close());
}

function toBuffer(data: RawData): Buffer {
  if (Buffer.isBuffer(data)) return data;
  return Array.isArray(data) ? Buffer.concat(data) : Buffer.from(data);
}
