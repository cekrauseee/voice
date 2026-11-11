import { createServer as createHttpServer, type Server } from "node:http";
import type { Logger } from "@voice/log";
import { type RawData, WebSocketServer } from "ws";
import { DICTATION_PATH, parseClientMessage, type ServerMessage } from "./protocol.ts";
import type { Refiner } from "./refiner.ts";
import { DictationSession } from "./session.ts";
import type { CreateTranscriber } from "./transcriber.ts";

export interface ServerDeps {
  createTranscriber: CreateTranscriber;
  refiner: Refiner;
  log: Logger;
}

/** HTTP server with `GET /health` and the dictation WebSocket. One connection is one dictation. */
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

  server.on("upgrade", (request, socket, head) => {
    if (request.url !== DICTATION_PATH) {
      socket.end("HTTP/1.1 404 Not Found\r\n\r\n");
      return;
    }
    sockets.handleUpgrade(request, socket, head, (ws) => {
      dictations += 1;
      const session = new DictationSession({
        ...deps,
        log: deps.log.child({ scope: "dictation", fields: { dictation: dictations } }),
        send: (message: ServerMessage) => ws.send(JSON.stringify(message)),
        end: () => ws.close(1000),
      });

      ws.on("message", (data, isBinary) => {
        if (isBinary) {
          session.audio(toBuffer(data));
        } else if (parseClientMessage(toBuffer(data).toString("utf8"))) {
          session.stop();
        } else {
          session.reject();
        }
      });
      ws.on("close", () => session.close());
      ws.on("error", () => session.close());
    });
  });

  server.on("close", () => {
    for (const ws of sockets.clients) ws.terminate();
  });

  return server;
}

function toBuffer(data: RawData): Buffer {
  if (Buffer.isBuffer(data)) return data;
  return Array.isArray(data) ? Buffer.concat(data) : Buffer.from(data);
}
