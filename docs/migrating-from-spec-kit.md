# Migrating a Spec Kit project to sdlc-kit

How an existing project that builds features with [GitHub Spec Kit](https://github.com/github/spec-kit)
moves to `sdlc-kit`. It is written from one real migration: a production monorepo with 39 finished
Spec Kit features, a constitution, and a written workflow document.

`/sdlc-kit:init` sets up a project that has no workflow yet. It never overwrites or removes files, so
on a Spec Kit project it leaves two workflows side by side. This guide covers the part `init` does
not: what to keep, what to move, what to remove, and in what order.

`/sdlc-kit:adopt` now does this for any existing workflow. This guide is the worked example it was
written from. `adopt` differs in one place: this migration finished every feature in flight first and
drafted no intents, while `adopt` can also record unfinished work as reserved follow-ups.

## The idea in one paragraph

Finished work stays where it is. The rules move to where sdlc-kit reads them. The Spec Kit tooling
is removed. Then the project is proven with the kit's own commands before the first intent starts.
The whole move is one branch and one PR, with no change to product code.

## How Spec Kit maps to sdlc-kit

| Spec Kit | sdlc-kit | What to do |
|---|---|---|
| `specs/NNN-slug/` (spec, plan, tasks, contracts) | `intent/YYYY-MM-DD-slug/` (intent, spec, plan) | Keep `specs/` as history. Do not convert it. |
| `.specify/memory/constitution.md` | Policy skills (description starts with `Policy -`) | Move the constitution into `docs/`, then write short policy skills that point to it. |
| The Constitution Check in `/speckit-plan` | The policy review in `/sdlc-kit:new-spec` | Reword the constitution's workflow section. |
| `/speckit-specify`, `/speckit-clarify` | `/sdlc-kit:new-intent`, `/sdlc-kit:review-intent`, `/sdlc-kit:new-spec` | Remove the old skills. |
| `/speckit-plan`, `/speckit-tasks`, `/speckit-analyze` | `/sdlc-kit:new-plan` | Remove the old skills. |
| `/speckit-implement`, `/speckit-converge` | `/sdlc-kit:build <folder> next`, `finish`, and the `verifier` agent | Remove the old skills. |
| `.specify/scripts`, `templates`, `workflows`, `integrations` | The plugin itself | Remove. |
| A feature number (`027`) and a "Depends on" column | A slug, `Depends on:` and `After:` | Keep the numbers as labels in the roadmap; use the slugs for intents. |
| One branch and one PR per feature | A PR per stage: intent, spec, plan, feature | Decide which of these run the full check command. |
| Review gates the workflow document asks for | Gates a hook or `intents deps` enforces | Rewrite the workflow document. |

## Step by step

### 1. Survey before changing anything

Read-only. The answers decide every later step.

```bash
ls .specify .claude/skills specs                       # what Spec Kit left in the repo
git grep -l -i -E 'speckit|\.specify|spec kit' -- . ':!specs' ':!.specify'   # documents that name it
git grep -l -E 'specs/[0-9]{3}' -- '*.ts' '*.py' '*.sh' '*.yaml' ':!specs'   # code that names spec paths
git grep -l 'constitution.md' -- . ':!specs' ':!.specify'                    # who links to the constitution
git ls-files | grep -E '(^|/)\.env'                    # tracked files the env guard or .gitignore would hit
git branch -a --no-merged <default-branch>             # features still in flight
```

Also note the test language (it decides how the test lock behaves, see below) and the real check
command.

### 2. Sort every item into keep, move, remove or add

| Item | Usual answer | Reason |
|---|---|---|
| `specs/` | Keep, in place | Code comments, tests and scripts often name paths inside it. Moving it breaks them for no gain. |
| The constitution | Move to `docs/constitution.md` | It is still the rule book. It should not live in a tool's folder. |
| The rest of `.specify/` | Remove | Tooling only. |
| `speckit-*` skills | Remove | Two loops compete for the same requests. |
| Other project skills | Keep | Not part of Spec Kit. |
| The workflow document, `CLAUDE.md` | Rewrite the workflow parts | They are what Claude reads at the start of every feature. |
| Roadmap or phase documents | Keep; reword only "Spec Kit feature" | The roadmap is independent of the tool. |
| Closed phases, ADRs, old specs | Leave untouched | They were true when written. |
| `intent/`, `.claude/settings.json`, `.claude/protected-paths`, policy skills, `docs/deployment.md` | Add | What sdlc-kit reads. |

### 3. Finish what is in flight

Merge or close every Spec Kit feature that is half built. Do not carry a feature across the two
workflows: sdlc-kit finds progress through its own commit names and merged files, and a Spec Kit
branch has neither.

### 4. Write the plan and record the decision

Put the sorted table and the stages in one checklist file on the migration branch, and tick it off
in the commits that do the work. If the project keeps decision records, add one: why the move, what
is kept, what is removed, and the consequences listed under "Things that behave differently".

### 5. Move what is kept

```bash
git mv .specify/memory/constitution.md docs/constitution.md
```

Then amend only the constitution's workflow section: the loop is intent → spec → plan → build, and
the Constitution Check becomes the policy review. Change no principle. Bump its version the way its
own governance section says. Fix the live links to its old path; links inside old specs can stay.

### 6. Remove Spec Kit

```bash
git rm -r .specify
git rm -r .claude/skills/speckit-*
```

Clean the ignore files (`.prettierignore`, linters) of `.specify` entries. Keep any entry for `specs/`.

### 7. Add what sdlc-kit needs

Either run `/sdlc-kit:init` on the migration branch, or add the same files by hand:

- `intent/README.md` and `intent/_TEMPLATE.md` from the plugin's templates.
- `.claude/settings.json` with the marketplace, the enabled plugin and, if the default branch is not
  the remote's, `INTENTS_BASE`.
- `.gitignore`: `.claude/test-lock` and `.claude/settings.local.json`.
- `.claude/protected-paths`: generated files, lockfiles, captured fixtures.
- `docs/deployment.md`: point to the runbooks the project already has.
- **Policy skills, written from the constitution.** Group the principles by the area a spec touches,
  not one skill per principle. Three short skills worked for nine principles: money and external
  writes, service and data boundaries, customer data. Each one names its owner, points to the
  constitution instead of copying it, and lists the questions every spec must answer.

### 8. Rewrite the procedure

- The workflow document becomes the intent loop. Keep the project's own rules word for word; only
  the steps around them change.
- `CLAUDE.md` gets the three sections the kit reads: **Workflow** (with the line "The default branch
  is `<branch>`."), **Verifying your work** (the real check command), and the names of the policy
  skills. Say plainly that `specs/` is history and new work lives in `intent/`.
- In the roadmap, each planned Spec Kit feature becomes one intent with the same slug. A large one is
  split into 2–4 stories. "Depends on" becomes `Depends on:` when the intent is drafted. Do not draft
  intents in the migration PR.

### 9. Prove it, then merge

- `intents status` and `intents check` run with no error.
- The guard hook refuses a read of `.env` and an edit of a protected path.
- A new session lists `/sdlc-kit:*` skills and no `speckit-*` skill.
- `git grep -i -E 'speckit|\.specify'` finds nothing outside history.
- The project's check command is green.
- A human merges the PR. The first feature is a small pilot intent; review the friction after its
  first story.

## Things that behave differently

Tell the team these before the first intent.

- **The test lock is whole-file for everything but Python.** Add-only locks need `test_*.py` or
  `*_test.py`. In a TypeScript, Go or PHP project, adding a test to a file an earlier step locked
  needs a human unlock. Rule for plans: **every step puts its tests in new files.**
- **More PRs per feature.** Intent, spec and plan are each approved by a merge. Decide once whether
  docs-only PRs run the full check command. Running it only on the feature PR worked.
- **The env guard matches by file name.** Any file whose name starts with `.env`, except
  `.env.example`, is blocked for Claude's file tools (Read, Edit, Write). That includes encrypted files that are
  tracked on purpose, such as `.env.staging.enc`. Edit those through the project's own command.
- **`init`'s `.gitignore` line `.env*` can match tracked files.** `init` stops when it does. If the
  existing rules already cover env files, skip that line.
- **Commit and branch names carry meaning.** `test(<slug>): step N: …`, `feat(<slug>): step N: …` and
  `feat/<slug>` are how `/sdlc-kit:build` finds progress.
- **Feature numbers stop.** Slugs identify work. Old numbers can stay as labels in the roadmap.
- **Enabling the plugin in `.claude/settings.json` does not install it.** A project-scope install is
  recorded per folder path, so a new clone or a new git worktree starts with the message "enabled in
  project settings but isn't installed" and no `/sdlc-kit:*` skills. Run
  `claude plugin install sdlc-kit@sdlc-kit --scope project` once in each worktree, or install at user
  scope.
- **Other planning plugins overlap.** If a brainstorming or plan-writing plugin is also installed,
  call the `/sdlc-kit:*` commands by name.

## See also

`/sdlc-kit:adopt` runs these steps for any existing workflow, not only Spec Kit. See "Adopting in an
existing project" in the [README](../README.md#adopting-in-an-existing-project).
