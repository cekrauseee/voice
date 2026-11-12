// Builds the development app, runs it, and prints its log. Whenever what the app is built
// from changes, it builds the app again and runs the new build.

import { type ChildProcess, execFileSync, spawn } from "node:child_process";
import { watch } from "node:fs";
import { join } from "node:path";
import { createInterface } from "node:readline";
import { createLogger, type Level, parseLine } from "@voice/log";
import { bundle } from "./bundle.ts";
import { root, variant } from "./variants.ts";

const log = createLogger({ scope: "desktop" });
const { identifier, name } = variant("development");

/** The `open` that waits for the running app to quit. */
let running: ChildProcess | undefined;

function isRunning(): boolean {
  const answer = execFileSync("osascript", ["-e", `application id "${identifier}" is running`]);
  return answer.toString().trim() === "true";
}

/** Quits the app, and waits until it is gone: opening it before that opens nothing. */
function quit(): void {
  try {
    execFileSync("osascript", ["-e", `quit app id "${identifier}"`], { stdio: "ignore" });
    let tries = 0;
    while (isRunning() && tries < 100) tries++;
  } catch {
    // The app was not running.
  }
}

/** Builds the app and runs the new build. A build that fails leaves the running app alone. */
function run(): void {
  let app: string;
  try {
    app = bundle("development", log.child({ scope: "build" }));
  } catch (error) {
    log.error(error instanceof Error ? error.message : String(error), {
      hint: "the app is built again on the next change",
    });
    return;
  }

  // The app that quits now is the old build.
  running?.removeAllListeners("exit");
  quit();
  log.info("running", { app: name, hint: "it lives in the menu bar" });
  const opened = spawn("open", ["-W", app], { stdio: "ignore" });
  opened.on("exit", () => {
    running = undefined;
    log.info("quit", { app: name, hint: "it runs again on the next change" });
  });
  running = opened;
}

/** The level of a record in the system log. */
function level(messageType: string): Level {
  if (messageType === "Debug") return "debug";
  return messageType === "Error" || messageType === "Fault" ? "error" : "info";
}

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

run();

// An editor saves a file in several steps, and a change often touches several files.
let change: NodeJS.Timeout | undefined;
function changed(): void {
  clearTimeout(change);
  change = setTimeout(run, 300);
}
for (const directory of ["Sources", "Support"]) {
  watch(join(root, directory), { recursive: true }, changed);
}
watch(root, (_event, file) => {
  if (file === "Package.swift") changed();
});

function stop(code: number): never {
  quit();
  stream.kill();
  process.exit(code);
}
process.on("SIGINT", () => stop(130));
process.on("SIGTERM", () => stop(143));
