// Builds the development app, runs it, and prints its log until it quits.

import { execFileSync, spawn } from "node:child_process";
import { createInterface } from "node:readline";
import { createLogger, type Level, parseLine } from "@voice/log";
import { bundle } from "./bundle.ts";
import { variant } from "./variants.ts";

const log = createLogger({ scope: "desktop" });
const { identifier, name } = variant("development");

function quit(): void {
  try {
    execFileSync("osascript", ["-e", `quit app id "${identifier}"`], { stdio: "ignore" });
  } catch {
    // The app was not running.
  }
}

/** The level of a record in the system log. */
function level(messageType: string): Level {
  if (messageType === "Debug") return "debug";
  return messageType === "Error" || messageType === "Fault" ? "error" : "info";
}

let app: string;
try {
  app = bundle("development", log.child({ scope: "build" }));
} catch (error) {
  log.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}

quit();

// The app writes to the system log. Its records are read back and printed like every other log.
const stream = spawn(
  "log",
  [
    "stream",
    "--level",
    "debug",
    "--style",
    "ndjson",
    "--predicate",
    `subsystem == "${identifier}"`,
  ],
  { stdio: ["ignore", "pipe", "ignore"] },
);
createInterface({ input: stream.stdout }).on("line", (line) => {
  if (!line.startsWith("{")) return;
  const record = JSON.parse(line) as {
    messageType: string;
    category: string;
    eventMessage: string;
  };
  const { message, fields } = parseLine(record.eventMessage);
  log.child({ scope: record.category })[level(record.messageType)](message, fields);
});

log.info("running", { app: name, hint: "it lives in the menu bar" });
const running = spawn("open", ["-W", app], { stdio: "ignore" });

function stop(code: number): never {
  quit();
  stream.kill();
  process.exit(code);
}
running.on("exit", () => {
  log.info("quit", { app: name });
  stop(0);
});
process.on("SIGINT", () => stop(130));
process.on("SIGTERM", () => stop(143));
