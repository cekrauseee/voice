// Prepares apps/server/.env: creates it from .env.example, or adds the variables it is
// missing. Values already in .env are never changed. `pnpm dev` runs this first.

import { existsSync, readFileSync, writeFileSync } from "node:fs";
import { join } from "node:path";

/** A variable assignment, set or commented out. */
const ASSIGNMENT = /^\s*(?:#\s*)?([A-Za-z_][A-Za-z0-9_]*)=/;

function variables(lines: string[]): string[] {
  return lines.flatMap((line) => ASSIGNMENT.exec(line)?.[1] ?? []);
}

/**
 * Adds to `current` the variables of `example` it does not mention, with their comments.
 * Returns the new content and the names of the variables added.
 */
export function mergeEnv(example: string, current: string): { content: string; added: string[] } {
  const present = new Set(variables(current.split("\n")));
  const additions: string[] = [];
  const added: string[] = [];

  for (const block of example.trim().split(/\n{2,}/)) {
    const lines = block.split("\n");
    const missing = lines.filter((line) => variables([line]).some((name) => !present.has(name)));
    if (missing.length === 0) continue;
    // A block that is entirely new keeps its comments. Otherwise only the new lines are added.
    additions.push(missing.length === variables(lines).length ? block : missing.join("\n"));
    added.push(...variables(missing));
  }

  if (additions.length === 0) return { content: current, added };
  const existing = current.trim() === "" ? "" : `${current.trimEnd()}\n\n`;
  return { content: `${existing}${additions.join("\n\n")}\n`, added };
}

if (import.meta.main) {
  const directory = join(import.meta.dirname, "..");
  const path = join(directory, ".env");
  const exists = existsSync(path);
  const { content, added } = mergeEnv(
    readFileSync(join(directory, ".env.example"), "utf8"),
    exists ? readFileSync(path, "utf8") : "",
  );
  if (added.length > 0) {
    writeFileSync(path, content, { mode: 0o600 });
    console.log(
      exists
        ? `added to apps/server/.env: ${added.join(", ")}`
        : "created apps/server/.env from .env.example",
    );
  }
}
