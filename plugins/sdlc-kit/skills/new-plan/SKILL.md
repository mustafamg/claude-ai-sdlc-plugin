---
name: new-plan
description: Turn an approved intent (and its spec) into plan.md, the Stage 3 implementation plan of the AI-native SDLC, written in plan mode. Use when someone asks to plan, break down, or prepare the implementation of an intent whose spec is merged (or that /sdlc-kit:new-spec said needs no spec). Do NOT use for ideas (/sdlc-kit:new-intent), designs (/sdlc-kit:new-spec), or small fixes that go straight to a PR.
argument-hint: <intent folder>
---

# /sdlc-kit:new-plan: plan the build of an approved intent as `plan.md`

Intent folder: **$ARGUMENTS**

If that's empty, list the `intent/*/` folders that have an accepted `intent.md`, a merged `spec.md`
(or a recorded "no spec needed"), and no `plan.md`, then ask which one.

This is **Stage 3 only**. Write no code and change no tests. The output is a plan a new team member
could build from without asking questions.

## 1. Gate
Stop and say why if any of these fail:
- `intent.md` is on the default branch with `Status: accepted`.
- `spec.md` is on the default branch, **or** the intent records that no spec is needed. In that case,
  the intent's Decisions section takes the spec's place.
- **Dependencies are met.** Check the intent's Constraints (e.g. "depends on PR #10") against reality,
  using `gh pr view` or `git log`.
- If `plan.md` already exists, switch to **update mode**: change only what the user asks, and keep the
  rest.

## 2. Enter plan mode
Call `EnterPlanMode` before exploring. Stay read-only until the plan is approved.

## 3. Load context
- `CLAUDE.md`, plus the `CLAUDE.md` / `README.md` of every project the plan touches.
- `intent.md` and `spec.md`, including every amendment, decision, conflict resolution, and sign-off
  the spec carries to the implementation PR.
- Every policy skill (description starting `Policy -`) that applies.

## 4. Check the spec against today's code
Specs age. For each design claim the plan relies on (routes, tables, settings, file locations), check
it on the current default branch, and mark it **verified** or **assumed**. **If the code contradicts
the spec, don't plan around it silently.** Stop and flag it. The fix is a spec amendment in its own PR.

## 5. Draft the plan
Write it into the plan-mode plan file with these sections:

1. **Context:** links to the intent and spec, a one-paragraph goal, and each dependency's status.
2. **Traceability:** a table with one row per acceptance criterion:
   `Acceptance criterion (e.g. A3 (R2)) | Test (file::test name) | Step`.
   Every requirement in the spec must appear. A requirement with no test is a gap. Name it, don't
   hide it.
   - **Prefer one test file per step or feature area that a single step owns.** When several steps
     must share a test file, that's fine for Python (`test_*.py` files are locked add-only), but
     other test files are locked whole, so give each step its own.
3. **Files:** a table of new and changed files, grouped by project. Describe repeated patterns once,
   with a few example paths. Reuse existing code and patterns, and name them with paths.
   - If a shared test harness will need to grow in later steps, say which steps. Harness files are
     locked whole, so each extension goes through the unlock gate in `/sdlc-kit:build`.
4. **Order of work:** numbered steps (`1. **Title.**`), each small enough to review on its own, each
   ending with the exact command that proves it (the project's check command from `CLAUDE.md`, or a
   specific test).
   - Tests come before or alongside the code they prove, never after merge.
   - If some steps can run in parallel, group them into labeled lanes (e.g. "Steps 1–7 (backend) and
     8–9 (frontend) can run in parallel worktrees"). `/sdlc-kit:build` reads these labels.
   - Call out migrations, config and env changes (update `.env.example` files, never real `.env*`
     files), and build-time values.
5. **Risks:** what could break for existing users, the riskiest step, and what can't be tested
   offline. Give each risk a mitigation and, for data or auth changes, a rollback.
6. **Policy compliance:** for each applicable policy rule, how the implementation meets it, plus the
   sign-offs carried from the spec that the implementation PR must collect.
7. **Verification:** the check commands for every touched project, plus an end-to-end check of the
   main flow.
8. **Deviations from the spec:** ideally "none". Otherwise, each with its reason, flagged for
   approval. During the build, `/sdlc-kit:build` appends deviations here.

## 6. Interrogate before presenting
Answer these in the plan itself, not in chat:
- What's the riskiest step, and why is it placed where it is?
- What happens to existing users and data at each step if we stop halfway?
- Which acceptance criterion is hardest to test offline, and how does the plan cover it?

Then call `ExitPlanMode`. If the user asks for changes, revise and ask for approval again.

## 7. After approval, commit the plan
1. Branch off the default branch as `docs/plan-<slug>`.
2. Write the approved plan to `<intent folder>/plan.md`, and commit only that file.
3. Open a PR titled `docs(plan): <title>`. The body lists the steps, the risks, and any spec
   deviations or gaps that need a decision.
4. **Never merge it.** Merging approves the build. The next step is `/sdlc-kit:build`.

## Hard rules
- No code, no test edits, no spec edits in this skill.
- Tests come from the spec's acceptance criteria. Never plan to skip, weaken, or delete a test.
- Never read real `.env*` files.
