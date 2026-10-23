---
name: new-spec
description: Turn an approved intent.md into spec.md (Stage 2, Design, of the AI-native SDLC), checked against the project's policy skills. Use when someone asks to write or draft a spec, requirements, or design for a merged intent. Do NOT use for ideas without a merged intent (use /sdlc-kit:new-intent) or for implementation plans (use /sdlc-kit:new-plan).
argument-hint: "<work folder, e.g. intent/2026-01-15-guest-access, or …/<story-slug> for a story>"
---

# /sdlc-kit:new-spec: design an approved intent as `spec.md`

Work folder: **$ARGUMENTS**

The **work folder** is the intent's folder, or, for an intent with stories, the story's folder inside
it (`intent/<date>-<slug>/<story-slug>/`). The spec goes there. If the argument is empty, run
`intents status` and list the intents and stories at `accepted` (no spec yet), then ask which one. If
it's an intent folder whose intent has stories, list them and ask which story.

This is **Stage 2 only**. Do not write `plan.md` and do not change code. Describe *what* the system
must do and how it behaves, not which files change.

## 1. Gate
- The intent must be **merged to the default branch** with `Status: accepted`. If it isn't, stop and
  say so: a `draft` needs `/sdlc-kit:review-intent`, a `deferred` intent names the month it's revisited
  and needs a human to accept it first, and a `rejected` one needs a new intent.
- **For a story:** it's in the intent's Stories list and not struck through. Run
  `intents deps <work folder>`. Every dependency that needs **its spec merged** must be met, because
  this spec builds on that story's contract. Dependencies that need to **ship** block only the plan;
  note them in the spec's summary. If `intents` can't run, check by hand that each story this one
  comes `After:` has its `spec.md` on the default branch. Never skip the check.
- **Decide if a spec is needed.** Skip it when the change has no user-facing behavior, no API or data
  contract, and no policy surface (e.g. CI or tooling). In that case, say "go straight to
  `/sdlc-kit:new-plan`", explain why, suggest recording that decision in the intent, and stop.

## 2. Load context and policies
- Read `CLAUDE.md`, the intent (including its Decisions section), and any linked evidence. Every
  decision marked **deferred to spec** is a question this spec must answer.
- **For a story,** the intent's constraints and decisions apply to it as they stand. Also read the
  spec of each story it comes `After:`, for the contracts it builds on.
- **Load every policy skill:** skills in the project's `.claude/skills/` (or installed plugins) whose
  description starts with `Policy -`. Apply them while designing, not as a check afterwards.
- If no policy covers an area the feature touches (e.g. security, brand, UX, compliance, cost), note
  that in the spec. Never imply the design was checked against a policy that doesn't exist.
- If the intent links a design mock, the spec's UI states follow it; say where they differ.

## 3. Investigate
Read the code the intent touches: routes, models, UI, and the contracts between services. Mark each
claim about current behavior as **verified** or **assumed**. Never read real `.env*` files. If you
find the intent contradicts the code, flag it; the fix is an intent amendment, not a silent change.
Run `/sdlc-kit:review-intent <intent folder>`, which has an amendment mode for an accepted intent.

## 4. Ask before guessing
Interview the user, 3–5 questions at a time, about gaps the intent leaves open: edge cases, error
states, limits, and who can do what. Each policy skill lists questions a spec must answer; ask the
ones the intent doesn't already settle.

The person running this is often the product owner, who doesn't need to be technical. Ask business
questions in the user's terms ("what should a user see when…", "who may…"). Don't ask them to choose
between technical options: propose an answer, and list it under Technical questions for an engineer
to confirm on the PR.

## 5. Draft `<work folder>/spec.md`
For a story, design that story only. A contract other stories will use (an API, a token format, a
table) is designed in the story that provides it, and the others link to it.

The spec has two readers. The **product owner** approves it by merging the PR, and checks that it
still solves the problem the intent describes. **Engineers** plan and build from it. Write it in two
parts so each finds what they need. The product owner must be able to approve from Part 1 alone.

The header is the title, a link to `intent.md`, the author, the date and the status. Anything else
opens Part 2.

**Part 1: `## For the product owner`.** Plain words, from the user's side: no file paths, routes,
field names, status codes or library names. When the product owner needs to know a technical choice
(a session lasts 30 days, a limit of 5 tries an hour), say what it means for the user. Keep it to
about five minutes of reading; each item can link to the detail in Part 2 instead of repeating it. Write it last,
from the finished Part 2, so the two agree.
1. **Summary:** one paragraph, linking to `intent.md`. For a story, name it and the outcomes it
   delivers.
2. **What users get:** the main use cases for each kind of user, each as numbered steps followed by
   *If something goes wrong* and *Limits* bullets; then what stays as today, and anything the design
   changes from the intent.
3. **How you'll know it works:** the acceptance criteria in plain words, as checks the product owner
   could make once it ships. Start from the intent's (a story's Acceptance criteria, or the intent's
   *We'll know it worked when*), and add what the design settled. Each one names the rows in Part 2's
   acceptance criteria that test it, e.g. `(A4, A14)`. Checks only engineers run (lint, build, test
   suites) stay in Part 2. Don't title this section "Acceptance criteria": that heading belongs to
   the table in Part 2, which `intents export` reads.
4. **Decisions:** three lists. Write each item as the question on one line, ending with who decided
   it and when (or who decides), then the answer, options and reasons as short bullets under it:
   ```markdown
   - *How a conversation from the other identity is shown* (left to the spec): Decided by mst,
     2026-10-18 (D1, D3).
     - read-only, with a banner;
     - hidden after log out, kept visible after a session that ran out.
   ```
   - **Answered from the intent:** each question the intent deferred to the spec, with its answer,
     or where it's carried forward (a story, the plan, the build PR, a follow-up).
   - **Decided while designing:** every conflict and business question settled while drafting or in
     review, with its answer and why.
   - **Needs a decision:** every conflict and business question still open, numbered, with the
     options and your recommendation as bullets. Who decides is the product owner, or for a conflict
     with a policy, that policy's owner by name. Technical questions continue the numbering in Part
     2. If none, say "Nothing needs your decision."

   When one is decided, move it to Decided while designing with who decided and the date, so the
   spec records what was decided as well as what was asked.
5. **Non-goals:** carried from the intent, plus anything decided out during design. Work that
   belongs to another story names that story; work someone will do later ends with
   `→ follow-up: <slug>`.

**Part 2: `## Engineering detail`.** What engineers plan against. It opens with what the spec was
checked against: the commit of the code you read, each policy skill applied with the commit or
plugin version it was read at, and the sdlc-kit version. Number its sections on from Part 1.
6. **Requirements:** numbered and testable (`R1`, `R2`, …), split into functional and non-functional
   (latency, cost, limits).
7. **Acceptance criteria:** a table of Given / When / Then rows, each labeled with the requirement it
   proves, e.g. `A1 (R1)`. These become the tests in `plan.md`. Every check in Part 1's How you'll
   know it works becomes at least one row. Say which you couldn't keep, and why.
8. **Design:** user flows and UI states (including every locale/direction the product supports), API
   contracts (method, path, auth, request/response, errors), data model changes, and which services
   talk to which.
9. **Policy review:** for each loaded policy, the rules that apply and how the design meets them.
   Also **Conflicts** (policy vs. intent, or two policies), each with options and a recommendation,
   and **Gaps** (areas no policy covers). Each conflict also appears, in plain words, under Part 1's
   Needs a decision.
10. **Technical questions:** each with a proposed answer as short items, numbered on from Part 1's
   decisions.

A conflict must be resolved by the policy owner or product owner, not by you. Leave it in the spec,
flagged clearly. Every item under Needs a decision is settled before the spec merges, so no open
concern reaches engineering.

## 6. Review, then open a PR
Go through the draft with the user, starting with Part 1's Needs a decision. Then reread Part 1 as
the product owner: if any of it needs Part 2 to make sense, rewrite it. Then:
1. Branch off the default branch as `docs/spec-<slug>` (`<slug>` is the work folder's name without its
   date), and commit only `spec.md`.
2. Open a PR against the default branch titled `docs(spec): <title>`. The body quotes the request
   this spec was written from, links Part 1 for the product owner, lists the decisions and technical
   questions still open, and tags the owner of each policy with a conflict. If `CLAUDE.md` or a policy
   skill classes the change as higher risk, also ask for a technical lead's review.
3. **Never merge it.** Merging means the product owner approves building it, and it waits until
   nothing is left under Needs a decision. The next step is
   `/sdlc-kit:new-plan <work folder>`. If `SDLC_JIRA_PROJECT` is set, also say that
   `/sdlc-kit:sync-jira <slug>` adds the spec and its acceptance tests to the ticket once it's merged.
