// Builds the production app and puts it in a disk image, build/Voice.dmg, with a link to
// Applications to drag it to. A release publishes this image, and `install.ts` installs from it.
// Only the image is kept: an app left in build/ would be a second Voice in Spotlight.
//
//   node scripts/dmg.ts
//
// VERSION and CODESIGN_IDENTITY work as they do for scripts/bundle.ts.

import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, symlinkSync } from "node:fs";
import { tmpdir } from "node:os";
import { basename, join, relative } from "node:path";
import { createLogger, type Logger } from "@voice/log";
import { bundle } from "./bundle.ts";
import { root, variant } from "./variants.ts";

/** hdiutil now and then finds the disk busy, mostly on CI runners, and succeeds when tried again. */
function createImage(args: string[], log: Logger): void {
  for (let attempt = 1; ; attempt++) {
    try {
      execFileSync("hdiutil", ["create", ...args], { stdio: "pipe" });
      return;
    } catch (error) {
      if (attempt === 3) throw error;
      log.warn("disk image failed", { attempt, error: (error as Error).message.trim() });
      execFileSync("sleep", ["2"]);
    }
  }
}

/** Builds the app and its disk image. Returns the path of the image. */
export function dmg(log: Logger): string {
  const { name } = variant("production");
  const app = bundle("production", log);
  const image = join(root, "build", `${name}.dmg`);

  const staging = mkdtempSync(join(tmpdir(), "voice-dmg-"));
  try {
    execFileSync("ditto", [app, join(staging, basename(app))]);
    symlinkSync("/Applications", join(staging, "Applications"));
    createImage(["-volname", name, "-srcfolder", staging, "-format", "UDZO", "-ov", image], log);
  } finally {
    rmSync(staging, { recursive: true, force: true });
    rmSync(app, { recursive: true, force: true });
  }

  log.info("packaged", { image: relative(root, image) });
  return image;
}

if (import.meta.main) {
  const log = createLogger({ scope: "build" });
  try {
    dmg(log);
  } catch (error) {
    log.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
