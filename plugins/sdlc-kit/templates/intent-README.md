# intent/

Every non-trivial change starts here, before any code. Each feature gets a folder,
`intent/YYYY-MM-DD-<slug>/`, which accumulates `intent.md`, `spec.md`, and `plan.md`. Each file is
approved by merging its PR.

**Stories.** A larger intent can list 2–4 stories in its `## Stories` section, each under its own
heading, written from the user's side: a title, a user story, what users get, and plain acceptance
criteria. Each story is specced, planned and built on its own, in a folder of its own, `intent/YYYY-MM-DD-<slug>/<story-slug>/`. That
folder, or the intent's folder when it has no stories, is the **work folder** every stage after the
intent takes. Its name without a date is the slug that branches and commits use.

## Flow

1. **Intent (Stage 1, Plan).** Run `/sdlc-kit:new-intent <your idea>`. It interviews you, checks the
   code for evidence, drafts `intent.md` from [`_TEMPLATE.md`](_TEMPLATE.md), and opens a PR. It
   proposes stories when the idea is too big to ship in one piece.
2. **Review (Stage 1).** Run `/sdlc-kit:review-intent intent/<folder>`. It finds the gaps the draft
   leaves, resolves every open question with you, records them in the Decisions table, and sets
   `Status` to `accepted`, `deferred` (with a Revisit month), or `rejected`. Merging the PR is the
   product-owner approval. `/sdlc-kit:review-intent backlog` lists deferred intents that are due and
   promised work nobody has written yet.
3. **Spec (Stage 2, Design).** Run `/sdlc-kit:new-spec <work folder>`. It writes `spec.md`
   in two parts: one for the product owner (what users get, how they'll know it works, the
   decisions they need to make, non-goals), then the engineering detail (numbered requirements, Given/When/Then acceptance
   criteria, and design). It applies the project's policy skills and flags conflicts for the owners
   to resolve. It tells you when a spec isn't needed (e.g. tooling or CI).
4. **Plan (Stage 3).** Run `/sdlc-kit:new-plan <work folder>`. It works in plan mode, checks the spec
   against current code, and drafts `plan.md`: a traceability table (acceptance criterion → test →
   step), files, ordered steps, risks, policy compliance, and verification.
5. **Build and test (Stages 3–4).** Run `/sdlc-kit:build <work folder> <step>` (or `next`) for each
   step:
   1. It writes the step's acceptance tests from the spec and confirms they fail for the right reason.
   2. It commits and **locks** them. Python test files are locked add-only; other files are locked
      whole.
   3. It writes code until the tests pass, runs the checks, and commits.
   4. The `verifier` subagent checks the step independently.

   `/sdlc-kit:build <work folder> finish` verifies everything and opens the PR with the evidence. The
   intent's last story to finish also runs the intent's own "how we'll know it worked" checks.
6. **Review and deploy (Stage 5).** Review the PR, collect the sign-offs it lists, merge it, then run
   `/sdlc-kit:deploy`.

Small fixes (typos, one-line bugs, dependency bumps) skip this and go straight to a PR.

## Relations between intents
Write them so they can be checked, not as prose:
- **`Depends on:`** in the header names intents or stories by slug, or pull requests as `#N`. A
  story's own dependencies go on its `**After:**` line.
- **`Supersedes:`** names the intent this one replaces. The old intent's Status becomes `superseded`
  in the same PR.
- **`→ follow-up: <slug>`** at the end of an out-of-scope item reserves a slug for work someone will
  do later, so it isn't lost.

`intents status` shows where every intent and story stands, worked out from git: drafts on other
branches, specced, planned, building, shipped. It also lists reserved slugs and who waits on them.
`intents check` reports broken relations, and a hook runs it whenever Claude writes a file here.

## Unlocking tests
Only humans unlock, from the project root in their own terminal. The exact command, with the plugin's
path, is printed whenever the hook blocks an edit:
`"<plugin path>/bin/test-lock" unlock <file>`. Run it with no file to remove every lock, for example
after the feature PR merges.
