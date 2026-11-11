// Forgets the app's permissions and settings, so it starts like a first launch.
//
//   node scripts/reset.ts [development|production]

import { spawnSync } from "node:child_process";
import { createLogger } from "@voice/log";
import { variant } from "./variants.ts";

const log = createLogger({ scope: "reset" });

try {
  const { identifier, name } = variant(process.argv[2] ?? "development");
  spawnSync("osascript", ["-e", `quit app id "${identifier}"`]);
  for (const permission of ["Accessibility", "Microphone"]) {
    const { status, stderr } = spawnSync("tccutil", ["reset", permission, identifier], {
      encoding: "utf8",
    });
    // macOS does not know an app that never ran, and then there is nothing to forget.
    if (status !== 0 && !stderr.includes("No such bundle identifier")) {
      throw new Error(`could not reset ${permission}: ${stderr.trim()}`);
    }
  }
  // Fails when there are no settings yet, which is the state wanted.
  spawnSync("defaults", ["delete", identifier]);
  log.info("reset permissions and settings", { app: name, identifier });
} catch (error) {
  log.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
