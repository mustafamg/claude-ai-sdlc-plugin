# CLAUDE.md

<One or two sentences: what this product is and how the repo is organized (single app, monorepo, …).>

## Projects

Run commands from inside each project's directory.

| Project | Path | Stack | Test / check |
|---|---|---|---|
| <name> | `<path>/` | <language, framework> | `<verified check command>` |

<How to run the whole thing locally, if there's one command for it.>

## Rules

- **Never read or write real `.env*` files.** Use `.env.example` to learn variable names, and ask for
  values you need. (Enforced by the sdlc-kit guard hook.)
- <Paths that must never be hand-edited, and why. List them in `.claude/protected-paths` too.>
- <Conventions that matter: migrations, API compatibility, i18n, money types, …>

## Workflow

- Non-trivial changes go `intent/<date>-<slug>/intent.md` → `spec.md` → `plan.md` → build (see
  `intent/README.md`):
  `/sdlc-kit:new-intent <idea>`, then `/sdlc-kit:new-spec <folder>`, then `/sdlc-kit:new-plan
  <folder>`, then `/sdlc-kit:build <folder> <step>`, then `/sdlc-kit:build <folder> finish`.
- The build is test-first. Tests are locked by a hook. Never edit a locked test; only a human
  unlocks.
- Policy skills (`<names>`) apply to every spec, plan, and change in their area.
- Branch off `<default branch>`; one concern per PR. Deploys follow `docs/deployment.md`
  (`/sdlc-kit:deploy`).

## Verifying your work

Before calling a task done, run the check command for **every project you touched** (table above)
and make sure it passes. Never skip, delete, or weaken a test to get green. For a bug fix, write the
failing test first, then fix the code without editing that test.

## Known gaps

- <Things that are broken, missing, or surprising today, e.g. "no CI yet", "X has no tests".>

When Claude repeats a mistake twice in this repo, add the correction here. Keep this file to about one page.
