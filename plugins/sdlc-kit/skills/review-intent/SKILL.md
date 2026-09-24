---
name: review-intent
description: Review a drafted intent.md for gaps, resolve every open question with the user, and record the decisions so a human can approve it by merging (Stage 1 of the AI-native SDLC). Use when someone asks to review, resolve, sign off, defer, or reject an intent, or asks what's blocking one. Do NOT use to draft a new intent (/sdlc-kit:new-intent), to design one (/sdlc-kit:new-spec), or to review code.
argument-hint: "[intent folder | backlog]"
---

# /sdlc-kit:review-intent: resolve an intent and record its decisions

Intent folder: **$ARGUMENTS**

If that's empty, list every `intent/*/intent.md` that isn't `accepted`, with its status, its open
question count, and its PR if it has one. Also list `deferred` intents whose **Revisit** month has
arrived. Ask which one to review. `backlog` lists those and stops.

This is **Stage 1 only**. Do not write `spec.md` or `plan.md` and do not change code.

**You do not approve the intent.** A human approves it by merging its PR. Your job is to make the
intent complete enough that the decision is easy, and to record what was decided.

## 1. Load context
Read `CLAUDE.md`, `intent/README.md`, the intent itself, and the evidence it links to. If the intent
has a PR, read it and its review comments (`gh pr view --comments`); decisions already made there must
end up in the file. Load the project's policy skills (those whose description starts with `Policy -`)
to know which surfaces need an owner's answer.

## 2. Find the gaps
The listed open questions are the easy half. Review the whole intent for what it doesn't say:
- **Assumed claims.** Anything marked *assumed* that a cheap read-only check could settle: run it, and
  mark the claim *verified* with what you ran. Never read real `.env*` files.
- **An untestable outcome.** If "desired outcome" can't become Given/When/Then rows in a spec, it's
  too vague. Say what's missing.
- **Systems affected.** Ticked with no reason, or unticked though the code says otherwise.
- **Missing constraints,** especially ones `CLAUDE.md` or a policy skill calls out: performance, cost,
  privacy, compliance, localization, backward compatibility, deadlines.
- **No out-of-scope section,** or one that leaves the obvious adjacent work ambiguous.
- **An uncovered policy surface:** the intent touches an area no policy skill covers. Note it; never
  imply a policy checked it.
- **Duplicates.** Search `intent/*/intent.md` for an intent that overlaps, supersedes, or is
  superseded by this one.
- **A solution in place of a problem.** Ask what problem it solves.

Add each gap to the list to resolve, with your proposed answer. Report gaps you can't resolve as new
open questions rather than answering them yourself.

## 3. Resolve, with the user
Ask 3–5 questions at a time, each with your recommendation, so the user can say "yes" or "no,
because…". Keep going until every question has one of these resolutions:
- **Decided** — the answer, in the user's words.
- **Deferred to spec** — a genuine design question Stage 1 can't settle. Record why. `/sdlc-kit:new-spec`
  must ask it.
- **Out of scope** — moved to Non-goals.
- **Needs <name>** — only that person can answer (a policy owner, a customer, legal). Name them. The
  intent can't be accepted until they do.

Never mark something decided because the user didn't object, and never invent an answer to close a
question out.

## 4. Agree the outcome
**If the user already signalled the outcome** ("not this quarter", "we're not doing this", "this is
good, let's go"), say so back in your first reply and ask for what that outcome needs — for a
deferral, the revisit month and who revisits — rather than waiting until the questions are done. A
stated intention that never gets recorded is how a deferral turns into a forgotten file.

Otherwise, once the questions are resolved, summarize: what changed in the intent, what was decided,
and what's still open. Then ask the user which outcome they want. Never pick it yourself.
- **accepted** — ready to build. Every question is decided, deferred to spec, or out of scope.
- **deferred** — the intent is sound, but not now. Requires a **Revisit** month (`YYYY-MM`) and the
  person who revisits it. Merging it as `deferred` is how it enters the backlog.
- **rejected** — we're not doing this. Record why.
- **still draft** — blocked on someone, or the user wants more work first. Say exactly what's needed.

## 5. Write the intent
- Fill the **Decisions** table: each question, its resolution, who decided, and the date.
- Set **Status**, and **Approved by** (or **Revisit**, when deferred).
- Keep the rest of the file true: if a decision changes scope, constraints or non-goals, edit those
  sections too and note the change in Decisions. Never leave a decision that contradicts the body.
- Verified claims lose their *assumed* marker, and gain the evidence.

## 6. Commit, after the user confirms
Show the full diff and **ask before committing**. Once they confirm:
1. If the intent has an open PR, commit to its branch (`docs/intent-<slug>`) and push. Otherwise
   branch off the default branch and open one, titled `docs(intent): <title>`.
2. Message: `docs(intent): record decisions for <slug>`, or `docs(intent): defer <slug> to <YYYY-MM>`.
3. Update the PR body with the outcome and anything still blocking it.
4. **Never merge it.** Merging is the product owner's approval, including for `deferred` and
   `rejected`, which are merged so the record stays in `intent/`.

Then say what's next: `/sdlc-kit:new-spec intent/<folder>` once the PR is merged as `accepted`, or who
is being waited on.
