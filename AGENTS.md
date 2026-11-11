# Voice

Real-time voice dictation for macOS: a Swift menu bar app (`apps/desktop`) and a TypeScript server (`apps/server`). Start with [README.md](README.md), then [docs/architecture.md](docs/architecture.md).

- `pnpm verify` must pass before a change is done. It checks formatting, lint, types, and tests, and CI runs the same command. `pnpm format` fixes formatting.
- A change to the messages between the app and the server updates [docs/protocol.md](docs/protocol.md), `apps/server/src/protocol.ts`, and `apps/desktop/Sources/VoiceCore/ServerMessage.swift` together.
- Logic that does not need the system goes in `VoiceCore` with tests. The `Voice` target stays thin glue over macOS APIs.
- The server runs TypeScript directly on Node.js: only erasable syntax, and relative imports end in `.ts`.
- UI copy is short, plain English.

<!-- BEGIN:turborepo-agent-rules -->

# This is NOT the Turborepo you know

Turborepo configuration, task behavior, and CLI commands can vary between installed versions and may differ from your training data. Resolve the `turbo` package from this file's directory or relevant workspace; in monorepos, it may not be visible from the repository root. For example, run `node -p "require.resolve('turbo/package.json')"` from a workspace that depends on `turbo`.

Read `docs/README.md` inside that installed package first, then read the relevant pages from its `docs/` directory before changing Turborepo configuration or commands. Heed deprecation notices. These bundled docs match the installed package version and are available without network access.

This block is written and re-added by `turbo` before repository-scoped commands when an AI agent is detected. In the Turborepo source repository, its template is defined in `crates/turborepo-cli/src/cli/agent_guidance.rs`. Removing the managed block while updates are enabled means a later qualifying invocation will add it again. Set `"agentGuidance": true` in the root `turbo.json` or `turbo.jsonc` to opt in; this does not remove an existing block. Keep the block committed with your work to avoid an uncommitted change on the next agent invocation.
<!-- END:turborepo-agent-rules -->
