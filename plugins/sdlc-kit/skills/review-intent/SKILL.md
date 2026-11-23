---
name: review-intent
description: Review a drafted intent.md for gaps, resolve every open question with the user, and record the decisions so a human can approve it by merging (Stage 1 of the AI-native SDLC). When the project sets SDLC_REVIEW=doc, the product owner reviews the draft as a Claude Doc this skill publishes and reads back. Use when someone asks to review, resolve, sign off, defer, or reject an intent, to read the product owner's comments on its review doc, to amend an intent that's already accepted, or asks what's blocking one. Do NOT use to draft a new intent (/sdlc-kit:new-intent), to design one (/sdlc-kit:new-spec), or to review code.
argument-hint: "[intent folder | backlog]"
---

# /sdlc-kit:review-intent: resolve an intent and record its decisions

Intent folder: **$ARGUMENTS**

If that's empty, run `intents status` (on your PATH while this plugin is enabled; if it can't run,
read `intent/*/intent.md` and search for `follow-up:` markers yourself) and list every
intent that isn't `accepted`, with its status, its open question count, and its PR if it has one.
Include drafts that exist only on other `docs/intent-*` branches; `intents status` shows them. Also
list `deferred` intents whose **Revisit** month has arrived, and the **reserved slugs**: work an
intent promised as a follow-up, or depends on, that nobody has written yet. Ask which one to review.
`backlog` lists those and stops.

This is **Stage 1 only**. Do not write `spec.md` or `plan.md` and do not change code.

**You do not approve the intent.** A human approves it by merging its PR. Your job is to make the
intent complete enough that the decision is easy, and to record what was decided.

## Language
Talk in the user's language; keep the file in English. Discuss each open question and decision in the
language the user writes in, with technical words kept in English. Write each decision to the
Decisions table in English, using the intent's terms and `CLAUDE.md`'s **Glossary**, and read it back
in the user's language before the status changes. The review doc, the PR and commits are English.
In an English conversation there's nothing to translate.

## 1. Load context
Read `CLAUDE.md`, `intent/README.md`, the intent itself, and the evidence it links to. If the intent
has a PR, read it and its review comments (`gh pr view --comments`); decisions already made there must
end up in the file. If the header has a **Review doc** link, the product owner reviews in a Claude
Doc: read its comments and edits as well (§8). Load the project's policy skills (those whose
description starts with `Policy -`) to know which surfaces need an owner's answer.

## 2. Amendment mode: the intent is already accepted
If the intent is on the default branch with `Status: accepted` (or `deferred`/`rejected`), this is an
**amendment**, not a first review. That is the normal case: `/sdlc-kit:new-spec` or
`/sdlc-kit:new-plan` found that the intent contradicts the code, or a decision turned out wrong
during the build.

- **Ask what forced the change,** and name the artifact that found it — a spec requirement, a plan
  step, a build step — with a link, so the reason outlives the conversation.
- **Don't change `Status`.** An accepted intent stays accepted; an amendment doesn't put the whole
  intent back up for approval. If the change is big enough to need re-approval, say so and let the
  user decide.
- **Keep the original wording, struck through** (`~~like this~~`), with the new wording beside it,
  and add a dated amendment note. The template's Decisions section explains the convention. Never
  overwrite silently: a reader has to see what changed and why.
- **Add a Decisions row per change:** what changed, what forced it, who decided, the date.
- **Adding or dropping a story is an amendment too.** Strike a dropped story's heading through, so
  it stops counting. Never renumber or reuse a story's id or slug.
- **Branch `docs/intent-<slug>-amend-<topic>`,** commit the intent alone, and open a PR against the default branch titled
  `docs(intent): amend <slug> — <what changed>`. Never merge it.
- Then work only the questions the amendment reopens. Don't re-interview what's already settled.
- **An amendment from Jira** (`/sdlc-kit:sync-jira` found a change made there): name the ticket and
  the person in the Decisions row, e.g. "from PROJ-12, comment by <name>".
- **A Review doc that doesn't say it's closed yet:** add its closing line (§8).

## 3. Find the gaps
The listed open questions are the easy half. Review the whole intent for what it doesn't say:
- **Assumed claims.** Anything marked *assumed* that a cheap read-only check could settle: run it, and
  mark the claim *verified* with what you ran. Never read real `.env*` files.
- **Technical detail in the business sections.** File paths, class names or code findings in the
  Problem or *Where we are today* belong in **Evidence** at the end; move them there and leave a
  plain-language line with a link. An older intent with no Evidence section is fine as it is.
- **An untestable outcome.** If "desired outcome" can't become Given/When/Then rows in a spec, it's
  too vague. Say what's missing. The same goes for a story's acceptance criteria. A story written
  in technical terms, or with no title, user story, *What users get* or acceptance criteria, needs
  them in the template's form. An older one-line story is fine as it is.
- **Systems affected.** Ticked with no reason, or unticked though the code says otherwise.
- **Missing constraints,** especially ones `CLAUDE.md` or a policy skill calls out: performance, cost,
  privacy, compliance, localization, backward compatibility, deadlines.
- **No out-of-scope section,** or one that leaves the obvious adjacent work ambiguous.
- **An uncovered policy surface:** the intent touches an area no policy skill covers. Note it; never
  imply a policy checked it.
- **Duplicates.** Look for an intent that overlaps, supersedes, or is superseded by this one: in
  `intent/*/intent.md`, and in the drafts on other branches that `intents status` lists. A draft is
  invisible from this branch otherwise. If this intent replaces one, record it with **Supersedes**,
  and say the other's PR should be closed.
- **A solution in place of a problem.** Ask what problem it solves.
- **Too big for one story.** A dependency or sign-off that blocks only part of the outcome, or parts
  useful on their own to different users, mean it should split into stories. Two separate problems
  mean two intents linked by **Depends on**. More than five stories usually means two intents. Each
  story must be safe to ship on its own.
- **Relations written as prose.** "A separate intent", "a follow-up", "depends on the X work" can't
  be checked. Propose a **Depends on** or **Supersedes** entry, or a `→ follow-up: <slug>` marker,
  with the slug. Run `intents check intent/<folder>/intent.md`. Every error must be fixed, and its
  warnings point at prose like this. If `intents` can't run, read the Out of scope and Constraints
  sections for such prose yourself.
- **A dependency on unwritten work.** Depending on a reserved slug is fine, but the plan is blocked
  until that work ships. Say so, and ask who will write it.

Add each gap to the list to resolve, with your proposed answer. Report gaps you can't resolve as new
open questions rather than answering them yourself, under **Business** or **Technical** as the
template lays them out. If the existing questions mix the two or bury the answer in a paragraph,
regroup them and break each answer into items; keep their numbers, since the Decisions table and
other text cite them.

## 4. Resolve, with the user
Ask 3–5 questions at a time, each with your recommendation, so the user can say "yes" or "no,
because…". Ask the business questions first, then the technical ones. Lay each out as in the
template: the question in bold, then the recommendation as short items. Keep going until every question has one of these resolutions:
- **Decided** — the answer, in the user's words.
- **Deferred to spec** — a genuine design question Stage 1 can't settle. Record why. `/sdlc-kit:new-spec`
  must ask it.
- **Out of scope** — moved to Non-goals.
- **Needs <name>** — only that person can answer (a policy owner, a customer, legal). Name them. The
  intent can't be accepted until they do.

Never mark something decided because the user didn't object, and never invent an answer to close a
question out.

## 5. Agree the outcome
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

## 6. Write the intent
*In amendment mode (§2), keep `Status` as it is and strike through what you replace.*

- Fill the **Decisions** table: each question, its resolution, who decided, and the date.
- Set **Status**, and **Approved by** (or **Revisit**, when deferred).
- Keep the rest of the file true: if a decision changes scope, constraints or non-goals, edit those
  sections too and note the change in Decisions. Never leave a decision that contradicts the body.
- Verified claims lose their *assumed* marker, and gain the evidence.
- If it **Supersedes** a merged intent, amend that intent's Status to `superseded` in the same commit.

## 7. Commit, after the user confirms
Show the full diff and **ask before committing**. Once they confirm:
1. If the intent has an open PR, commit to its branch (`docs/intent-<slug>`) and push. Otherwise
   branch off the default branch and open one against it, titled `docs(intent): <title>`.
2. Message: `docs(intent): record decisions for <slug>`, or `docs(intent): defer <slug> to <YYYY-MM>`.
3. Update the PR body with the outcome and anything still blocking it.
4. **Never merge it.** Merging is the product owner's approval, including for `deferred` and
   `rejected`, which are merged so the record stays in `intent/`.
5. With `SDLC_REVIEW=doc`, publish or update the review doc now (§8), so it matches what you pushed.

Then say what's next: `/sdlc-kit:new-spec intent/<folder>` once the PR is merged as `accepted` (for an
intent with stories, `intent/<folder>/<story-slug>`, starting with a story that waits on nothing), or
who is being waited on. If `SDLC_JIRA_PROJECT` is set, also say that `/sdlc-kit:sync-jira <slug>`
creates the Jira tickets once the PR is merged.

## 8. Review in a Claude Doc (`SDLC_REVIEW=doc`)
Run `echo "SDLC_REVIEW=$SDLC_REVIEW"`. When it says `doc`, the product owner reviews drafts as a
Claude Doc, which reads better than a PR and takes comments on the rendered text. Unset, `pr`, or a
command you can't run means review stays in the PR: skip this section, and don't mention the doc.

The doc is a copy to read and comment on. `intent.md` stays the source, and **approval stays on
GitHub**. This needs the Claude Docs connector. If it isn't available, say so, carry on in the PR,
and tell the user to enable it. Before the first docs call, call the connector's `guide` for
`topic.index` and `topic.comments`.

**The first time** (the header has no **Review doc** link), after §7 pushes the branch:
1. Create a doc named `Intent: <title>` from `intent.md`, without its Evidence section, which is for
   engineers. In its place, put one line linking to `intent.md` on the branch. Under the title, add:
   "Draft for review. Comment on anything here; agreed changes go into the intent and this doc is
   updated to match. To approve, approve the pull request: <PR link>."
2. Add `- **Review doc:** <doc link>` to the intent's header, and a `Review doc:` line to the PR body.
   Commit it as `docs(intent): link the review doc for <slug>`, and push.
3. No tool can share a doc. Tell the user to click **Share** in the doc and give the product owner
   comment access.

**On later runs:**
1. **Read the feedback:** list the doc's comment threads, and compare its text with `intent.md` to
   find edits made directly in the doc. Each open thread and each edit becomes a gap in §3, with your
   proposed answer, resolved with the user in §4 like any other. An edit is a suggestion, never a
   decision.
2. **Update the doc after §7 commits.** Change only the sections that changed, rewording in place,
   so comments on unchanged text stay attached. If a change would remove words a comment is attached
   to, narrow it; if you can't, ask in that thread.
3. **Reply in each thread you acted on,** once the user agrees the answer: what changed, or why
   nothing did, in a line or two. Never resolve a thread the product owner wrote in. They close it.

**Approval:** a comment saying "approved" isn't the approval. Reply with the PR link and ask them to
approve it there. Someone then merges it, with their name in **Approved by**.

**Once the intent is merged,** the doc stops changing. Add a line under its title: "Accepted on
<date>. Discussion continues in Jira: <link to the epic or story>" when the project uses Jira
(`/sdlc-kit:sync-jira` adds it when it creates the tickets), or "…continues in amendment pull
requests: <link to intent.md on the default branch>" when it doesn't. Later changes are amendments
(§2), not doc edits.
