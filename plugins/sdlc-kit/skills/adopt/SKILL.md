---
name: adopt
description: Move a project that already builds with AI onto the sdlc-kit workflow. It surveys what the project uses today (agent instruction files, loose plans and todos, other planning tools, unfinished branches), sorts each into keep, move, remove or add, turns informal rules into policy skills, retires the old workflow, sets the kit up, and records unfinished work as follow-ups the `intents` tool tracks. Use when someone asks to adopt, migrate to, or switch an existing project to the SDLC kit. For a project with no workflow yet, use /sdlc-kit:init.
argument-hint: "[--survey]"
disable-model-invocation: true
---

# /sdlc-kit:adopt: move an existing project onto the AI-native SDLC

`/sdlc-kit:init` sets up a project that has no workflow. This skill is for a project that already has
one, even an informal one: rules in an instruction file, plans and todos in loose files, features half
built on branches, maybe another planning tool. It converts and retires what's there, then sets the
kit up.

The whole move is **one branch and one PR**, with no change to product code.
- **Finished work is never deleted or converted.** Old plans and specs stay where they are, as history.
- **Nothing is removed until the user confirms it,** row by row (§2).
- **Never merge the PR.** Merging is the human's approval.
- **Don't write specs for the system as it exists.** Specs are written per change, from the first
  intent on.
- `--survey` stops after §2: it reports and changes nothing.

## 0. Check the starting point
Stop and say what's needed whenever a check below fails.

- **A git repo with at least one commit.**
- **A clean working tree.** If `git status --porcelain` prints anything, stop: the user commits or
  stashes it first. Never commit, stash or discard their changes yourself.
- **A remote.** The kit counts a merged PR as approval, and works out every stage from the default
  branch. With no remote, run §1 and §2 so the user sees the survey, then stop: they add a remote
  first. With a remote but without `gh`, carry on, and in §10 push the branch and give the user the PR
  title and body to open by hand.
- **Already adopted?** If `intent/README.md` exists and `CLAUDE.md` mentions `/sdlc-kit:`, then
  `/sdlc-kit:init` ran here, or this skill did. Say so. Skip every step whose result already exists
  and do only what's left, usually §3 to §5 and §7. Never create a second copy of a file that's there.
  If the branch `chore/adopt-sdlc-kit` already exists, continue on it instead of starting over, and
  list what it already holds.

## 1. Survey (read-only)
Change nothing in this step. Find the **default branch** first, as `/sdlc-kit:init` §1 does: propose
the remote's (`git symbolic-ref --short refs/remotes/origin/HEAD`) and ask whether the team merges
somewhere else. Then look for:

- **Agent instruction files:** `CLAUDE.md`, `AGENTS.md`, `GEMINI.md`, `.cursorrules`,
  `.cursor/rules/`, `.github/copilot-instructions.md`. They hold the project's informal rules. They
  also show which other AI tools the team uses.
- **Loose planning files:** `PLAN.md`, `TODO.md`, `ROADMAP.md`, `docs/plans/`, `docs/superpowers/`,
  `tasks/`, `specs/`.
- **Other workflow tooling:** a `.specify/` folder, project skills or commands that plan, spec or
  build (`.claude/skills/`, `.claude/commands/`), and planning plugins enabled in
  `.claude/settings.json`.
- **Work in flight:**
  - `git branch -a --no-merged <default-branch>`: branches with unmerged work;
  - `gh pr list`: open PRs;
  - `git stash list`: stashes. List them; never apply or drop one;
  - unticked items in the plan and todo files.
- **How the team merges today:** `git log --merges --oneline -20` and `gh pr list --state merged`.
  Commits straight to the default branch mean the PR-per-stage habit is new for them (§8).
- **What `/sdlc-kit:init` §1 looks for:** each project's real check command and its result today, and
  tracked env files (`git ls-files | grep -E '(^|/)\.env'`).
- **Tests:** whether there are any, and in which language. It decides how the test lock behaves (§8).

If you find nothing but code, and `/sdlc-kit:init` hasn't run, say so and hand over to
`/sdlc-kit:init`. There's nothing to adopt from.

## 2. Sort
Show one table with every item the survey found:

| Item | Found at | Keep / move / remove / add | Reason |
|---|---|---|---|

The usual answers:
- **Keep, in place:** finished plans, specs, decision records and roadmaps. Code, tests and scripts
  may name paths inside them, and they were true when written.
- **Move:** rules, into policy skills (§4). Workflow instructions, into the intent loop (§5).
- **Remove:** other planning skills, commands and tooling. Two loops compete for the same requests.
- **Add:** `intent/`, `.claude/settings.json` entries, `.claude/protected-paths`, policy skills, and
  what else `/sdlc-kit:init` creates.

Ask the user to confirm or change each row. Nothing is written until they have. With `--survey`, stop
here.

## 3. Work in flight
For each unfinished item from §1, ask the user to choose:
- **Finish it the old way first.** They merge or close it, then run this skill again.
- **Make it a candidate intent.** Give it a slug and one line saying what's done and what's left.

**Never carry a half-built branch across.** `/sdlc-kit:build` finds progress through its own commit
names (`test(<slug>): step N:`, `feat(<slug>): step N:`) and `feat/<slug>` branches. An old branch
has neither, so the kit would treat it as not started. The branch stays where it is; the intent that
replaces it says what to reuse from it.

**A slug** is lowercase letters, digits and hyphens, and unique across `intent/`. Run `intents status`
(on your PATH while this plugin is enabled) and don't reuse a slug it lists.

**No tests, or a check command that fails today?** Add one more candidate, and list it first: a
working check command and a first set of tests around the behaviour that matters most. The build is
test-first and the verifier runs the check command, so without them the kit's gates check nothing.
Record today's result in `CLAUDE.md` under Known gaps, as `/sdlc-kit:init` does. A command that
fails today is recorded as failing, not hidden.

## 4. Rules into policy skills
Policy skills are the written rules that `/sdlc-kit:new-spec` and the build apply. Write them from the
instruction files the survey found. This replaces `/sdlc-kit:init` §6.

- **Only a rule someone could check becomes policy.** "Money is integer cents" is a rule. The project
  map, the commands and the tips stay in `CLAUDE.md`.
- **Ask which rules the team really enforces, and who owns each.** Don't turn a rule nobody follows
  into policy. One or two real policies beat five aspirational ones.
- **Group the rules by the area a spec touches,** not one skill per rule: for example money and
  external writes, service and data boundaries, customer data.
- For each group, create `.claude/skills/<name>/SKILL.md` from
  `${CLAUDE_PLUGIN_ROOT}/templates/policy-skill/SKILL.md`. The description starts with `Policy -`. It
  names its owner, lists the questions every spec must answer, and **points to the source document
  instead of copying it** when the project keeps a rule book (a constitution, a standards document).
- **Two files that disagree** (`CLAUDE.md` says one thing, `.cursorrules` says another): show both side
  by side, as a conflict for the owner. Never pick one yourself. Until the owner decides, neither
  version becomes policy, and the conflict goes in the PR as a decision left to the team (§10).

## 5. Retire the old way
- **Remove** what §2 marked remove, with `git rm`, and only the rows the user confirmed. Clean ignore
  and lint config of entries that only served what was removed.
- **Mark kept plan and todo files as history.** Add one line at the top: new work lives in `intent/`.
- **Rewrite the workflow parts of `CLAUDE.md`** to the intent loop (§6 adds the sections). Keep every
  project rule word for word; only the steps around them change. Say plainly where the old plans are
  and that they're history.
- **Other AI tools.** This plugin's hooks run only in Claude Code. If the team also uses another tool,
  tell them: the test lock and the env guard don't hold there. In that tool's instruction file
  (`AGENTS.md`, `.cursorrules`, and so on), replace the workflow parts with a short pointer to
  `CLAUDE.md` and `intent/README.md`, so every tool follows one workflow. Keep its rules.
- **A competing planning plugin.** If another plugin plans or brainstorms, it will answer the same
  requests. Offer to turn it off for this project in the checked-in `.claude/settings.json`:
  ```json
  { "enabledPlugins": { "<plugin>@<marketplace>": false } }
  ```
  If the user keeps it, add to `CLAUDE.md`'s Workflow section: call the `/sdlc-kit:*` commands by name.

## 6. Set up the kit
Read `${CLAUDE_PLUGIN_ROOT}/skills/init/SKILL.md` and follow its §2 to §5, §7 and §8: `CLAUDE.md`
sections, `intent/`, `.gitignore`, protected paths, the deployment runbook, and team settings. Skip
its §6, which §4 here replaces, and its §9, which §10 here replaces.

Its rules hold here too: never overwrite a file, merge into it and show the diff; stop if `.env*`
would newly match tracked files.

## 7. Record the adoption as the first intent
Unfinished work that's only described in a PR gets lost once the PR merges, because nothing reads it.
So the adoption is written as an intent, and each candidate from §3 becomes a follow-up that `intents`
tracks.

Write `intent/<today>-adopt-sdlc-kit/intent.md` from `intent/_TEMPLATE.md`:
- **Problem** and **Desired outcome:** why the project is moving, in the user's own words.
- **Decisions:** the confirmed table from §2, with who decided each row.
- **Out of scope:** one line per candidate, each ending with its marker:
  ```markdown
  ## Out of scope
  - A working check command and first tests around checkout. → follow-up: test-baseline
  - The CSV export started on `export-wip`: the endpoint exists, the download button doesn't. → follow-up: csv-export
  ```
- **Status:** `accepted`. Leave **Approved by** for the person who merges the PR.
- Delete the sections that don't apply (Stories, Depends on, Supersedes).

Commit everything from §4 to §7 on the branch with this subject, exactly:

```
feat(adopt-sdlc-kit): step 1: adopt sdlc-kit
```

That subject is how `intents` knows the adoption shipped: once the PR merges, `intents status` shows it
as `shipped`, with no spec or plan, and lists every candidate as a **reserved** slug.
`/sdlc-kit:new-intent` picks a reserved slug up when someone starts that work, and
`/sdlc-kit:review-intent backlog` lists the ones nobody has written.

## 8. Say what changes for the team
Put these in the PR body. Where one is a rule, put it in `CLAUDE.md` too.

- **Small fixes skip the loop.** Typos, one-line bugs and dependency bumps go straight to a PR. Say
  this first: the loop is for features.
- **Approval is a merged PR.** The intent, the spec, the plan and the feature each get one. If the team
  committed straight to the default branch until now, suggest protecting it.
- **Ask whether docs-only PRs run the full check command,** and record the answer in `CLAUDE.md`.
  Running it only on the feature PR is a reasonable choice.
- **The test lock is whole-file for everything but Python.** Add-only locks need `test_*.py` or
  `*_test.py`. In any other language, adding a test to a file an earlier step locked needs a human
  unlock. For those projects, add this rule to `CLAUDE.md`: every plan step puts its tests in new
  files.
- **The env guard matches by file name.** Any file whose name starts with `.env`, except
  `.env.example`, is blocked for reading and writing. That includes encrypted files tracked on
  purpose, such as `.env.staging.enc`. Edit those through the project's own command.
- **Commit and branch names carry meaning.** `test(<slug>): step N: …`, `feat(<slug>): step N: …` and
  `feat/<slug>` are how `/sdlc-kit:build` finds progress.
- **Enabling the plugin in `.claude/settings.json` may not install it** in a new clone or worktree. If
  the `/sdlc-kit:*` skills are missing there, run `claude plugin install sdlc-kit@sdlc-kit`.
- **Start with one small pilot intent,** and review the friction after it ships.

## 9. Prove it
Run these and keep the output for the PR:
- `intents status` and `intents check`: no errors, and the candidates listed as reserved.
- Each project's check command. Compare with the result §1 recorded: adopting must not change it.
- A search for leftover references to anything §5 removed (`git grep -n -i '<name>'`), outside the
  files kept as history.

Fix what these find before opening the PR. If a check failed before the adoption and still fails,
say so; don't fix product code here.

## 10. Open the PR
Work on the branch `chore/adopt-sdlc-kit`, off the default branch. Push it and open one PR against the
default branch, titled `chore: adopt sdlc-kit`, with these sections:

- **What was found:** the survey, in a few lines.
- **Keep / move / remove / add:** the confirmed table.
- **Policy skills:** each one, its owner, and where its rules came from.
- **Unfinished work (reserved slugs):** each candidate, with `/sdlc-kit:new-intent <slug>` to start it.
- **What changes for the team:** §8.
- **Proof:** the output from §9.
- **Decisions left to the team:** unresolved rule conflicts, and anything the user deferred.

Tell the user the adoption is one commit, so reverting the merge undoes it. **Never merge the PR.**
After they merge it, suggest starting with the smallest reserved slug as the pilot.
