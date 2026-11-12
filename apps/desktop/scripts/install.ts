// Installs the production app on this Mac, or updates it. It builds the app and its disk image
// the way a release does, quits the app if it runs, puts the app from the image in Applications,
// and opens it. The app runs its server with apps/server/.env, the one `pnpm dev` uses, from the
// main checkout of the repository: installing from another worktree uses the same key.
//
//   node scripts/install.ts
//
// VERSION sets the version. By default it is what `git describe` says of the checkout: 0.1.0 on
// the tag v0.1.0, 0.1.0-2-g1a2b3c4 two commits after it. CODESIGN_IDENTITY works as it does for
// scripts/bundle.ts.

import { execFileSync } from "node:child_process";
import { existsSync, mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { dirname, join } from "node:path";
import { createLogger } from "@voice/log";
import { dmg } from "./dmg.ts";
import { quit } from "./quit.ts";
import { root, variant } from "./variants.ts";

const log = createLogger({ scope: "install" });
const { identifier, name } = variant("production");
const destination = join("/Applications", `${name}.app`);

function git(args: string[]): string {
  return execFileSync("git", args, { cwd: root, encoding: "utf8" }).trim();
}

/** The server's .env in the main checkout, whose .git directory every worktree shares. */
function environmentFile(): string {
  const common = git(["rev-parse", "--path-format=absolute", "--git-common-dir"]);
  return join(dirname(common), "apps", "server", ".env");
}

try {
  process.env.VERSION ??= git(["describe", "--tags", "--match", "v*", "--always", "--dirty"]);
  const image = dmg(log.child({ scope: "build" }));

  quit(identifier);
  const environment = environmentFile();
  if (!existsSync(environment)) {
    log.warn("server settings missing", {
      file: environment,
      hint: "run pnpm dev once, and add your OpenAI key to the file",
    });
  }
  execFileSync("defaults", ["write", identifier, "serverEnvFile", environment]);

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
    hint: "it lives in the menu bar, and runs its server",
  });
} catch (error) {
  log.error(error instanceof Error ? error.message : String(error));
  process.exit(1);
}
