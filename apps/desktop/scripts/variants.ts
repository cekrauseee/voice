import { join } from "node:path";

/** The directory of the desktop package. */
export const root = join(import.meta.dirname, "..");

/**
 * The two builds of the app. They have different names, icons, and bundle identifiers, so macOS
 * keeps their permissions and settings apart and both can be installed at once. The production
 * app carries the server and runs it. The development app uses the one `pnpm dev` runs.
 */
const variants = {
  development: {
    name: "Voice (Development)",
    identifier: "eu.cekrause.voice.dev",
    configuration: "debug",
    icon: "AppIconDevelopment.icns",
    server: false,
  },
  production: {
    name: "Voice",
    identifier: "eu.cekrause.voice",
    configuration: "release",
    icon: "AppIcon.icns",
    server: true,
  },
} as const;

export type VariantName = keyof typeof variants;

/** Looks up a build by name, as given on the command line. */
export function variant(name: string) {
  if (!Object.hasOwn(variants, name)) {
    throw new Error(`unknown build "${name}": use development or production`);
  }
  const key = name as VariantName;
  return { ...variants[key], key, app: join(root, "build", `${variants[key].name}.app`) };
}
