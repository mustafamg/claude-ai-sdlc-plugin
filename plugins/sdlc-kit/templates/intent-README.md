# intent/

Every non-trivial change starts here, before any code. Each feature gets a folder,
`intent/YYYY-MM-DD-<slug>/`, which accumulates `intent.md`, `spec.md`, and `plan.md`. Each file is
approved by merging its PR.

## Flow

1. **Intent (Stage 1, Plan).** Run `/sdlc-kit:new-intent <your idea>`. It interviews you, checks the
   code for evidence, drafts `intent.md` from [`_TEMPLATE.md`](_TEMPLATE.md), and opens a PR.
   Merging it is product-owner approval. Mark it `Status: accepted`.
2. **Spec (Stage 2, Design).** Run `/sdlc-kit:new-spec intent/<folder>`. It writes `spec.md`
   (numbered requirements, Given/When/Then acceptance criteria, and design), applies the project's
   policy skills, and flags conflicts for the owners to resolve. It tells you when a spec isn't needed
   (e.g. tooling or CI).
3. **Plan (Stage 3).** Run `/sdlc-kit:new-plan intent/<folder>`. It works in plan mode, checks the spec
   against current code, and drafts `plan.md`: a traceability table (acceptance criterion → test →
   step), files, ordered steps, risks, policy compliance, and verification.
4. **Build and test (Stages 3–4).** Run `/sdlc-kit:build intent/<folder> <step>` (or `next`) for each
   step:
   1. It writes the step's acceptance tests from the spec and confirms they fail for the right reason.
   2. It commits and **locks** them. Python test files are locked add-only; other files are locked
      whole.
   3. It writes code until the tests pass, runs the checks, and commits.
   4. The `verifier` subagent checks the step independently.

   `/sdlc-kit:build intent/<folder> finish` verifies everything and opens the PR with the evidence.
5. **Review and deploy (Stage 5).** Review the PR, collect the sign-offs it lists, merge it, then run
   `/sdlc-kit:deploy`.

Small fixes (typos, one-line bugs, dependency bumps) skip this and go straight to a PR.

## Unlocking tests
Only humans unlock, from the project root in their own terminal. The exact command, with the plugin's
path, is printed whenever the hook blocks an edit:
`"<plugin path>/bin/test-lock" unlock <file>`. Run it with no file to remove every lock, for example
after the feature PR merges.
