---
name: new-intent
description: Turn a feature idea into an intent.md ready for approval (Stage 1, Plan, of the AI-native SDLC). Use when someone has a new feature, product change, or "I have an idea for…", or asks to create/draft an intent. Do NOT use for bug fixes, typos, dependency bumps, or other small changes; those go straight to a PR.
argument-hint: <feature idea, rough is fine>
---

# /sdlc-kit:new-intent: capture a feature as `intent.md`

The idea: **$ARGUMENTS**

If that's empty, ask the user for the idea in a sentence or two, and who asked for it or why now.

This is **Stage 1 only**. Do not write `spec.md` or `plan.md`, do not change any code, and don't
design the implementation beyond what's needed to state constraints.

## 1. Load context
Read `CLAUDE.md`, `intent/README.md`, `intent/_TEMPLATE.md`, and the most recent
`intent/*/intent.md` as an example of format and level of evidence. If `intent/` doesn't exist,
suggest running `/sdlc-kit:init` first.

## 2. Screen the request
If it's a small fix (typo, one-line bug, dependency bump, doc tweak), say so and suggest a direct
PR instead. Those skip the intent process. Stop unless the user insists.

## 3. Interview
Ask 3–5 questions at a time until the idea is concrete:
- What's the problem, and what evidence do we have for it?
- Who is affected?
- What does "done" look like, and how will we know it worked?
- What are the constraints (performance, cost, privacy, compliance, deadlines, anything `CLAUDE.md`
  or the project's policy skills call out)?
- What's out of scope?

Push back when the user describes a solution instead of a problem. Ask what problem that solution
solves.

## 4. Investigate the current state
Find the services, routes, models, and UI the idea touches, using `CLAUDE.md`'s project map. Run
cheap, read-only checks (existing tests, scripts, grep) to gather evidence. For each finding, record
whether it's **verified** (you saw or ran it) or **assumed**. Never read real `.env*` files.

## 5. Draft
Write `intent/<YYYY-MM-DD>-<slug>/intent.md` from the template, using today's date.
- Tick only the systems you have evidence the change touches.
- Put evidence in the Problem section, and mark anything still assumed.
- Give every open question your proposed answer, so the approver can say "yes" or "no, because…".

## 6. Review, then open a PR
Show the draft and fix it with the user until they're happy. Then:
1. Branch off the default branch as `docs/intent-<slug>`, and commit only the intent file.
2. Open a PR titled `docs(intent): <title>`. The body summarizes the problem, key evidence, and the
   decisions needed.
3. **Never merge it.** Merging the PR is the product-owner approval. The approver also sets
   `Status: accepted`. The next step is `/sdlc-kit:new-spec`.
