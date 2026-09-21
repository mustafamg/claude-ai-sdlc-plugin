---
name: build
description: Implement one step of a merged plan.md test-first (Stage 3 Build / Stage 4 Test of the AI-native SDLC). It writes the step's acceptance tests from the spec, locks them, writes code until they pass, runs the project checks, and commits. `finish` verifies the whole intent and opens the PR. Use when someone asks to build, implement, or code a step of an intent whose plan.md is on the default branch. Do NOT use for ideas, specs, or plans (use /sdlc-kit:new-intent, /sdlc-kit:new-spec, /sdlc-kit:new-plan), or for small fixes without a plan.
argument-hint: <intent folder> [step number | next | finish]
---

# /sdlc-kit:build: implement a plan step test-first

Arguments: **$ARGUMENTS**. The first is always the intent folder. The second is a step number from
`plan.md`'s Order of work, `next` (the default; see §0.3), or `finish`. If the first argument isn't an
intent folder (e.g. `/sdlc-kit:build next`), ask for the folder instead of guessing.

**The test lock:** `test-lock` is on your PATH while this plugin is enabled (`lock`, `status`,
`check`). The user unlocks, in their own terminal from the project root, with:
`"${CLAUDE_PLUGIN_ROOT}/bin/test-lock" unlock <file>`. Never try to unlock yourself; a hook blocks it.

**Checks:** each project's check command comes from `CLAUDE.md` (its project table or "Verifying your
work" section) and the plan's Verification section. If the project has CI, the PR's checks must also
pass. If it has no CI, the local checks in this loop are the gate. Never skip them.

## 0. Gate and step selection
Stop and say why whenever a check below fails.

### 0.1 Approved plan
`<intent folder>/plan.md` is on the default branch. Merged means the build is approved.

### 0.2 Branch and lane
- `<slug>` is the intent folder name without its date (e.g. `guest-access`).
- **Lanes.** If the plan's Order of work groups steps that can run in parallel (e.g. "Steps 1–7
  (backend) and 8–9 (frontend) can run in parallel worktrees"), each group is a **lane**, named by its
  label. A plan with no such groups has a single lane containing every step.
- **Working sequentially:** use `feat/<slug>`, created from the default branch if missing. `next`
  considers every step.
- **Working in parallel:** each lane gets its own worktree on `feat/<slug>-<lane>`, created from the
  default branch. Identify the current lane from the branch name. If it doesn't identify a lane, ask
  which lane before picking a step. Lane branches are merged into `feat/<slug>` before `finish`.
- **Tooling freshness.** Claude Code loads this plugin's skills and hooks from the installed plugin,
  but project files (`CLAUDE.md`, policy skills) come from the checkout. If the feature branch is far
  behind the default branch, suggest merging it in before continuing.

### 0.3 Which step
First find each step's **state across all branches**, so progress in another worktree counts:
- **done:** `git log --all --grep='^feat(<slug>): step N:'` finds a commit.
- **tests committed:** `git log --all --grep='^test(<slug>): step N:'` finds a commit, but the step
  isn't done.
- **not started:** neither is found.

**`next`** is the lowest-numbered step **in the current lane** that isn't done. Skip a step whose tests
are committed only on another lane's branch: it's in progress there, so say so. If every step in the
lane is done, say so and suggest the other lane, merging lane branches, or `finish`.

**An explicit step number:** if it's done, say so and stop (redo only if the user explicitly asks). If
it belongs to a different lane than the current branch, warn and ask before continuing.

**Prerequisites:** every earlier step in the same lane is done on this branch (or merged into it). A
step depends on another lane only where the plan says so.

### 0.4 Start or resume
- **Not started:** do §1, then continue from §2.
- **Tests committed: resume. Don't rewrite the tests.**
  1. The step's `test(...)` commit must be reachable from this branch. If it exists only on another
     branch, stop: continue in that lane's worktree, or merge that branch first.
  2. Take the step's test files from that commit (`git show --name-only --format= <commit>`) and
     confirm they're unchanged since (`git diff --quiet <commit> -- <files>`). **If anything changed,
     stop and report it.**
  3. Make sure they and their shared test support are locked in this worktree (`test-lock status`);
     locks are per worktree. Lock any that aren't.
  4. Do §1, **skip §2 and §3**, run the locked tests to see what still fails, and continue at §4.
- **Uncommitted changes:** never discard or stash them. Show `git status`. If they're clearly this
  step's in-progress work (the files the plan lists for this step, and its tests), continue with them.
  Otherwise stop and ask what they are.

## 1. Load the step
Read `CLAUDE.md`, the project `CLAUDE.md` for each project the step touches, `spec.md`, and in
`plan.md`: the step, the Traceability rows for this step, Risks, and Verification. Apply every policy
skill (description starting `Policy -`) wherever the step touches its area.

**If the spec or plan contradicts the code, or is ambiguous for this step, stop and ask.** A fix to the
plan goes in `plan.md`. A behavior change needs a spec amendment PR.

## 2. Write the acceptance tests first
*Skip this section and §3 when resuming a step whose tests are already committed (§0.4).*

For each acceptance criterion in this step, write the test the traceability table names (same file and
test name), asserting exactly the spec's Given / When / Then. Follow the project's existing test
patterns. To add tests to a Python test file an earlier step locked, use the Edit tool (add-only; no
unlock needed).

Run them and confirm they fail **for the right reason**:
- **Normal tests must FAIL** because the behavior doesn't exist yet: an assertion, a 404, or a missing
  symbol under construction. A failure from a typo, a broken fixture, or the environment doesn't count;
  fix the test harness and re-run. A test that already passes proves nothing.
- **Baseline tests** (characterization tests the plan says must pass against unchanged code) **must
  PASS** now, before any code changes.

## 3. Commit and lock the tests
1. Commit only the test files, plus shared test support they need: `test(<slug>): step N: <criterion ids>`.
2. Lock the test files **and the shared test support** they rely on: `test-lock lock <repo-relative files>`.
   The mode comes from the file name:
   - **Python test files (`test_*.py`, `*_test.py`) are locked add-only.** Later steps may add new
     tests, fixtures, and imports, with no unlock. Nothing that existed at a lock point may change or
     disappear, and nothing may be added that affects locked tests without editing them (module-level
     `pytestmark`/skip, autouse fixtures). Run `lock` on them again after each step's test commit; that
     adds a lock point protecting this step's new tests.
   - **Everything else is locked whole:** support and harness files, and non-Python tests. Changing
     them needs the unlock gate in §4.
   - **Shared test support** means helpers, harnesses, fixtures, and factories written for these tests.
     A test can be weakened through its harness as easily as through its assertions.
   - **Don't lock project-wide config such as `conftest.py`.** Later steps legitimately add defaults
     there. The verifier reviews its changes instead.
3. Run `test-lock status` and show the output.

## 4. Implement
Write the code the plan names for this step until the locked tests pass. Reuse the existing code and
patterns the plan points to.

**If a locked test turns out to be wrong,** don't work around it. Stop, explain what's wrong, and ask
the user. Only they can unlock. If the fix changes behavior, it needs a spec amendment first.

**Never skip, xfail, delete, or weaken any test,** new or existing, to get green.

**If the plan requires extending a whole-locked support file** (e.g. a harness gains wiring this step
adds to production code), treat it as a gated test change:
1. **Stop and ask the user to unlock only that file:** `"${CLAUDE_PLUGIN_ROOT}/bin/test-lock" unlock
   <file>`, in their own terminal. Name the file, the plan text that requires it, and exactly what
   you'll add.
2. **Make only that extension.** It must mirror production wiring and must not change what existing
   tests assert, how they're set up, or which tests run.
3. **Run the project's whole test suite.** Every previously passing locked test must still pass.
4. **Commit it alone:** `test(<slug>): step N: extend <file> (<what>)`. Lock it again and show
   `test-lock status`.
5. Continue with the step.

**Never change a support file to make a failing test pass.** If one looks wrong, stop and ask.

## 5. Run the checks
Run the full check command for **every project the step touched**, not just the new tests. If the
step touches a database and the plan names integration tests, run them against a disposable database
(see the `verifier` agent). Everything must pass, and `test-lock check` must report every lock intact.

## 6. Commit the step
1. Commit the code: `feat(<slug>): step N: <step title>`.
2. **If the implementation departed from the plan,** update `plan.md` (the step, the Files table, and
   a Deviations entry with the reason) in a `docs(plan): ...` commit.
3. **Delegate verification** to the `verifier` subagent (`sdlc-kit:verifier`) with scope `N`. If its
   verdict is NOT READY, fix the code (never the locked tests) and repeat §5 and §6.
4. Report: the step, its criteria and statuses, the commands run with pass counts, and the next step
   in this lane, or which lane or `finish` comes next.

## `finish`
1. You're on `feat/<slug>`, every lane branch is merged into it, and every step has a
   `feat(<slug>): step N:` commit reachable from it (`git log --grep`, **without** `--all`).
2. Run the `verifier` subagent with scope `all`. **Continue only on VERDICT: READY.**
3. Run the plan's end-to-end check and record what you observed.
4. Push `feat/<slug>` (`git push -u origin feat/<slug>`) and open a PR titled `feat: <intent title>`.
   Pass the body with `--body-file` (a file), not inline. Its body contains:
   - links to `intent.md`, `spec.md`, and `plan.md`;
   - **Evidence:** every check command with pass/fail/skip counts, the verifier's criteria table, the
     `test-lock check` output, and the end-to-end result (essential when there's no CI);
   - MANUAL checks a human must do;
   - sign-offs carried from the spec and plan, each unchecked;
   - policy compliance and deviations from the plan.
5. **Never merge it.** After merge, tell the user to run `"${CLAUDE_PLUGIN_ROOT}/bin/test-lock"
   unlock` in their own terminal.

## Hard rules
- Tests before code, for every step. You never edit locked tests, and you edit whole-locked test
  support only through the unlock gate in §4, after the user unlocks that one file.
- Never skip, xfail, delete, or weaken a test. Never mark a criterion as passing without test output.
- Never read real `.env*` files. Put new config in `.env.example` files.
- Never merge. Merging the PR is the human approval.
