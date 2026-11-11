# voice

Real-time voice dictation.

## Structure

- `apps/desktop`: the dictation client (not scaffolded yet)
- `apps/server`: transcription and LLM refinement (not scaffolded yet)
- `packages/eslint-config`: shared ESLint configuration
- `packages/typescript-config`: shared `tsconfig` base

## Commands

```sh
pnpm dev          # run all apps in watch mode
pnpm build        # build all apps and packages
pnpm lint         # lint
pnpm check-types  # type-check
```
