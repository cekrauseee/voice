import { execFileSync } from "node:child_process";

function isRunning(identifier: string): boolean {
  const answer = execFileSync("osascript", ["-e", `application id "${identifier}" is running`]);
  return answer.toString().trim() === "true";
}

/** Quits the app, and waits until it is gone: opening it before that opens nothing. */
export function quit(identifier: string): void {
  try {
    execFileSync("osascript", ["-e", `quit app id "${identifier}"`], { stdio: "ignore" });
    let tries = 0;
    while (isRunning(identifier) && tries < 100) tries++;
  } catch {
    // The app was not running.
  }
}
