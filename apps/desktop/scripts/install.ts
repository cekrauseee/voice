// Installs the production app on this Mac, or updates it. It builds the app and its disk image
// the way a release does, quits the app if it runs, puts the app from the image in Applications,
// and opens it.
//
//   node scripts/install.ts
//
// VERSION sets the version. By default it is what `git describe` says of the checkout: 0.1.0 on
// the tag v0.1.0, 0.1.0-2-g1a2b3c4 two commits after it. CODESIGN_IDENTITY works as it does for
// scripts/bundle.ts.

import { execFileSync } from "node:child_process";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createLogger } from "@voice/log";
import { dmg } from "./dmg.ts";
import { quit } from "./quit.ts";
import { root, variant } from "./variants.ts";

const log = createLogger({ scope: "install" });
const { identifier, name } = variant("production");
const destination = join("/Applications", `${name}.app`);

function describe(): string {
  return execFileSync("git", ["describe", "--tags", "--match", "v*", "--always", "--dirty"], {
    cwd: root,
    encoding: "utf8",
  }).trim();
}

try {
  process.env.VERSION ??= describe();
  const image = dmg(log.child({ scope: "build" }));

  quit(identifier);
  const volume = mkdtempSync(join(tmpdir(), "voice-volume-"));
  execFileSync("hdiutil", ["attach", image, "-readonly", "-nobrowse", "-mountpoint", volume], {
    stdio: "pipe",
  });
  try {
    rmSync(destination, { recursive: true, force: true });
    execFileSync("ditto", [join(volume, `${name}.app`), destination]);
  } finally {
    execFileSync("hdiutil", ["detach", volume, "-quiet"]);
    rmSync(volume, { recursive: true, force: true });
  }

  execFileSync("open", [destination]);
  log.info("installed", {
    app: destination,
    version: process.env.VERSION.replace(/^v/, ""),
    hint: "it lives in the menu bar, and needs the server running",
  });
} catch (error) {
  log.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
