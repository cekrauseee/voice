// Builds the app bundle: build/Voice Dev.app for development, build/Voice.app for production.
//
//   node scripts/bundle.ts [development|production]
//
// VERSION sets the app version. CODESIGN_IDENTITY picks the signing identity. By default
// the first Apple Development identity in the keychain is used, or an ad-hoc signature.

import { execFileSync } from "node:child_process";
import { cpSync, mkdirSync, rmSync } from "node:fs";
import { join, relative } from "node:path";
import { createLogger, type Logger } from "@voice/log";
import { root, type VariantName, variant } from "./variants.ts";

function run(command: string, args: string[]): string {
  return execFileSync(command, args, { cwd: root, encoding: "utf8", stdio: "pipe" }).trim();
}

function signingIdentity(): string | undefined {
  if (process.env.CODESIGN_IDENTITY) return process.env.CODESIGN_IDENTITY;
  const identities = run("security", ["find-identity", "-v", "-p", "codesigning"]);
  return /"(Apple Development: [^"]+)"/.exec(identities)?.[1];
}

/** Builds and signs the app. Returns the path of the bundle. */
export function bundle(name: VariantName, log: Logger): string {
  const { app, configuration, identifier, name: appName } = variant(name);
  const startedAt = Date.now();

  log.info("compiling", { build: name });
  try {
    run("swift", ["build", "-c", configuration, "--product", "Voice"]);
  } catch (error) {
    // The compiler's own output says what is wrong.
    const { stdout = "", stderr = "" } = error as { stdout?: string; stderr?: string };
    process.stderr.write(`${stdout}${stderr}`);
    throw new Error("compilation failed");
  }
  const binary = join(run("swift", ["build", "-c", configuration, "--show-bin-path"]), "Voice");

  const contents = join(app, "Contents");
  const plist = join(contents, "Info.plist");
  rmSync(app, { recursive: true, force: true });
  mkdirSync(join(contents, "MacOS"), { recursive: true });
  cpSync(binary, join(contents, "MacOS", "Voice"));
  cpSync(join(root, "Support", "Info.plist"), plist);
  const values = {
    CFBundleIdentifier: identifier,
    CFBundleName: appName,
    CFBundleShortVersionString: (process.env.VERSION ?? "").replace(/^v/, ""),
  };
  for (const [key, value] of Object.entries(values)) {
    if (value) run("plutil", ["-replace", key, "-string", value, plist]);
  }

  const identity = signingIdentity();
  run("codesign", ["--force", "--sign", identity ?? "-", app]);
  if (!identity) {
    log.warn("signed ad hoc", { hint: "macOS asks for the permissions again after every build" });
  }

  log.info("built", {
    app: relative(root, app),
    identifier,
    duration_ms: Date.now() - startedAt,
  });
  return app;
}

if (import.meta.main) {
  const log = createLogger({ scope: "build" });
  try {
    bundle(variant(process.argv[2] ?? "development").key, log);
  } catch (error) {
    log.error(error instanceof Error ? error.message : String(error));
    process.exit(1);
  }
}
