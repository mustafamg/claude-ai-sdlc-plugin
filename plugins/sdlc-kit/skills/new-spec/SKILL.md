---
name: new-spec
description: Turn an approved intent.md into spec.md (Stage 2, Design, of the AI-native SDLC), checked against the project's policy skills. Use when someone asks to write or draft a spec, requirements, or design for a merged intent. Do NOT use for ideas without a merged intent (use /sdlc-kit:new-intent) or for implementation plans (use /sdlc-kit:new-plan).
argument-hint: <intent folder, e.g. intent/2026-01-15-guest-access>
---

# /sdlc-kit:new-spec: design an approved intent as `spec.md`

Intent folder: **$ARGUMENTS**

If it's empty, list the `intent/*/` folders that have an `intent.md` but no `spec.md`, and ask which one.

This is **Stage 2 only**. Do not write `plan.md` and do not change code. Describe *what* the system
must do and how it behaves, not which files change.

## 1. Gate
- The intent must be **merged to the default branch** with `Status: accepted`. If it isn't, stop and
  say so: a `draft` needs `/sdlc-kit:review-intent`, a `deferred` intent names the month it's revisited
  and needs a human to accept it first, and a `rejected` one needs a new intent.
- **Decide if a spec is needed.** Skip it when the change has no user-facing behavior, no API or data
  contract, and no policy surface (e.g. CI or tooling). In that case, say "go straight to
  `/sdlc-kit:new-plan`", explain why, suggest recording that decision in the intent, and stop.

## 2. Load context and policies
- Read `CLAUDE.md`, the intent (including its Decisions section), and any linked evidence. Every
  decision marked **deferred to spec** is a question this spec must answer.
- **Load every policy skill:** skills in the project's `.claude/skills/` (or installed plugins) whose
  description starts with `Policy -`. Apply them while designing, not as a check afterwards.
- If no policy covers an area the feature touches (e.g. security, brand, UX, cost), note that in the
  spec. Never imply the design was checked against a policy that doesn't exist.

## 3. Investigate
Read the code the intent touches: routes, models, UI, and the contracts between services. Mark each
claim about current behavior as **verified** or **assumed**. Never read real `.env*` files. If you
find the intent contradicts the code, flag it; the fix is an intent amendment, not a silent change.

## 4. Ask before guessing
Interview the user, 3–5 questions at a time, about gaps the intent leaves open: edge cases, error
states, limits, and who can do what. Each policy skill lists questions a spec must answer; ask the
ones the intent doesn't already settle.

## 5. Draft `<intent folder>/spec.md`
Use these sections:
1. **Summary:** one paragraph, linking to `intent.md`.
2. **Requirements:** numbered and testable (`R1`, `R2`, …), split into functional and non-functional
   (latency, cost, limits).
3. **Acceptance criteria:** a table of Given / When / Then rows, each labeled with the requirement it
   proves, e.g. `A1 (R1)`. These become the tests in `plan.md`.
4. **Design:** user flows and UI states (including every locale/direction the product supports), API
   contracts (method, path, auth, request/response, errors), data model changes, and which services
   talk to which.
5. **Policy review:** for each loaded policy, the rules that apply and how the design meets them.
   Also **Conflicts** (policy vs. intent, or two policies), each with options and a recommendation,
   and **Gaps** (areas no policy covers).
6. **Non-goals:** carried from the intent, plus anything decided out during design.
7. **Open questions:** each with a proposed answer.

A conflict must be resolved by the policy owner or product owner, not by you. Leave it in the spec,
flagged clearly.

## 6. Review, then open a PR
Go through the draft with the user, starting with conflicts. Then:
1. Branch off the default branch as `docs/spec-<slug>` and commit only `spec.md`.
2. Open a PR titled `docs(spec): <title>`. The body lists the conflicts and open questions that need a
   decision, and tags the policy owners named in the policy skills.
3. **Never merge it.** Merging means the product owner approves building it. The next step is
   `/sdlc-kit:new-plan`.
