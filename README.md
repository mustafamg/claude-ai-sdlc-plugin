# sdlc-kit

A Claude Code plugin that runs an **AI-native SDLC**, based on Anthropic's
[AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook). Claude does the work
at every stage. A human approves between stages by merging a PR. Rules that must hold are enforced by
hooks, not just requested in prompts.

```
idea ─► intent.md ──────► spec.md ─────► plan.md ────► test-first build ─► verified PR ───► gated deploy
        (1+ stories)      (per story)    (per spec)    (per step)          (per story)
        /new-intent       /new-spec      /new-plan     /build              /build finish    /deploy
        /review-intent
```

An intent with no `## Stories` section is a single story, and its spec and plan sit in the intent's
folder. A larger intent lists 2–4 stories, and each one gets its own spec, plan, build and PR.

## What's inside

| Component | Stage | What it does |
|---|---|---|
| `/sdlc-kit:init` | Setup | Scaffolds a project: `CLAUDE.md` sections, `intent/` templates, `.gitignore`, protected paths, starter policy skills, and optionally a runbook and team settings. |
| `/sdlc-kit:new-intent <idea>` | 1 Plan | Interviews you, gathers evidence from the code (verified vs. assumed), and drafts `intent.md`. |
| `/sdlc-kit:review-intent [folder]` | 1 Plan | Finds the gaps a draft intent leaves, resolves every open question with you, records the Decisions table, and sets the status to accepted, deferred (with a revisit month) or rejected. It never merges: that's still the human's approval. With `SDLC_REVIEW=doc` it publishes the draft as a Claude Doc for the product owner and reads their comments back. |
| `/sdlc-kit:new-spec <folder>` | 2 Design | Writes the spec in two parts: a plain-language part the product owner approves from (what users get, how they'll know it works, the decisions they need to make, non-goals), then the engineering detail (numbered requirements, Given/When/Then acceptance criteria, design, policy review). Applies the project's policy skills, flags conflicts, and says when no spec is needed. |
| `/sdlc-kit:new-plan <folder>` | 3 Plan | Works in plan mode. Checks the spec against the code and writes `plan.md`: an acceptance criterion → test → step table, ordered steps, lanes, risks, and verification. |
| `/sdlc-kit:build <folder> [step\|next\|finish]` | 3–4 Build/Test | Test-first, one step at a time: tests from the spec, confirm they fail for the right reason, lock them, code until green, run checks, commit, verify. Resumes half-done steps and supports parallel lanes. `finish` opens the PR with evidence. |
| `verifier` subagent | 4 Test | Read-only. Checks locks, weakened tests, and test-support changes, runs every check, and grades each acceptance criterion PASS/FAIL/MISSING with quoted evidence. |
| `/sdlc-kit:sync-jira [slug] [--pull]` | Optional | Only with `SDLC_JIRA_PROJECT` set. Mirrors accepted intents into Jira: an epic per intent with stories, a Jira story per story, blocked-by links, and optionally a subtask per plan step. Edits and comments made in Jira come back as intent amendments, never straight into the repo. |
| `/sdlc-kit:deploy` | 5 Deploy | Follows the project's runbook: read-only status, then human go-ahead, then a rollback point, then one step at a time, then a report. |
| Guard hook | All | Blocks access to real `.env*` files and edits to paths listed in `.claude/protected-paths`. |
| Test-lock hook + `test-lock` | 3–4 | Freezes tests once written (below). |
| `intents` + intents hook | All | Derives the stage of every intent and story from git, checks the relations between them, and answers whether a story's dependencies are met (below). |

## The test lock
A skill can only *ask* Claude not to weaken tests. The lock *enforces* it:
- **`test-lock lock <files>`** runs during `/sdlc-kit:build` after the tests are committed. It records
  the commit in `.claude/test-lock`, which is local and gitignored.
- **Python test files (`test_*.py`) are locked add-only.** Later steps can add tests, fixtures, and
  imports. Anything that existed at a lock point can't change: tests, fixtures, helpers, constants,
  decorators. The comparison is by AST, so formatting and comments don't count. Nothing may be added
  that silently affects locked tests, such as a module-level `pytestmark`, a skip, or an autouse
  fixture.
- **Other files (harnesses, helpers, non-Python tests) are locked whole.**
- **A PreToolUse hook enforces it.** It blocks Edit/Write/MultiEdit that would break a lock, and Bash
  commands that write to a locked file or tamper with the lock.
- **`test-lock check`** proves with git that nothing locked changed. The verifier runs it as the
  backstop.
- **Only humans unlock,** from the project root, in their own terminal. The hook prints the exact
  command, including the plugin's install path:
  ```bash
  "<plugin path>/bin/test-lock" unlock <file>     # one file
  "<plugin path>/bin/test-lock" unlock            # everything (e.g. after the feature PR merges)
  ```

## Intents, stories and relations
An intent can be split into stories that are specced, planned and built on their own. Intents can
also depend on, replace, and promise each other. Written as prose ("this is a separate intent"),
those relations get lost, because nothing reads them. So `intents` reads three fixed forms, all in
plain markdown. Everything is identified by a **slug**: an intent folder's name without its date
(`intent/2026-09-13-guest-chat/` is `guest-chat`), or a story's own slug.

### Stories
A larger intent lists its stories in a `## Stories` section of `intent.md`. Each story gets a `###`
heading with a title, and is written for the product owner, from the user's side, in short bullets:

```markdown
## Stories

### S1 guest-token: Chat without signing up
Visitors get a guest pass that lets them chat before they create an account.

- **Outcomes:** 1
- **Actors:** visitors who haven't signed up
- **User story:** As a visitor, I want to ask a question straight away, so I can see if the product
  helps before I sign up.

**What users get**
- A chat that opens without a sign-up form.
- The same limits and safety checks as signed-in users.

**Acceptance criteria**
- A visitor can send a message and get an answer without signing up.
- A visitor who reaches the guest limit is asked to sign up, and keeps the conversation.

### S2 chat-ui: Keep the guest conversation across visits
- **Outcomes:** 2, 3
- **After:** S1
…

### S3 usage-dashboard: See how guests use the chat
- **Outcomes:** 4
- **After:** S1 ships
…
```

- **`S1`** is the story's number inside this intent, and **`guest-token`** is its slug. The slug must
  be unique across `intent/`, because the story's folder, branches and commits are named after it.
  Its spec and plan live in `intent/2026-09-13-guest-chat/guest-token/`.
- **Outcomes** says which of the intent's numbered *Desired outcome* items the story delivers.
- **Acceptance criteria** are plain checks a user could make once the story ships. The story's spec
  turns each one into Given / When / Then rows.
- **After** says what the story has to wait for. There are two kinds of wait:
  - **`After: S1`** waits for S1's **spec** to merge. S2 only needs S1's design, such as the shape
    of the token, to write its own spec and plan against. After that, S1 and S2 can be built in
    parallel.
  - **`After: S1 ships`** waits for S1's **feature PR** to merge, for when S3 needs S1's working
    code, not just its design.

  Anything outside this intent (another intent, its story, or a pull request like `#12`) always
  has to ship.
- `/sdlc-kit:new-spec` won't start a story until its spec-level waits (`After: S1`) are over.
  `/sdlc-kit:new-plan` waits for all of them, including `ships`. `intents deps chat-ui` shows what a
  story is waiting for.
- **To drop a story,** strike its heading through (`### ~~S3 usage-dashboard: …~~`). It stops counting.
- The older one-line form, `- **S1 guest-token**: what ships. Outcomes: 1. After: S2.`, is still
  read, so existing intents don't need rewriting.

An intent with no Stories section is a single story, and its spec and plan sit in the intent's folder.

### Dependencies and replacements
Two optional header lines in `intent.md` relate whole intents:

```markdown
- **Depends on:** chatui-login, #42 (session isolation)
- **Supersedes:** admin-feedback (an earlier draft; its agreed points are folded in)
```

- **`Depends on`** names intents or stories by slug, or pull requests as `#N`. Every story of this
  intent waits for each one to ship. A note can follow in parentheses or after a full stop.
- **`Supersedes`** names the intent this one replaces. If that intent was merged, its Status becomes
  `superseded` in the same PR, and `intents check` reports it if not. If it's a draft that never
  merged, close its PR; `intents status` shows it as superseded.

### Follow-ups
When an intent leaves work for later, give that work a slug instead of only describing it:

```markdown
## Out of scope
- Deleting old guest conversations. → follow-up: guest-chat-retention
```

That **reserves** `guest-chat-retention`:
- `intents status` lists it under *Reserved*, with the file and line that promised it, until an
  intent or story with that slug exists.
- When someone starts that work, `/sdlc-kit:new-intent` sees the reservation and gives the new intent
  that slug, so the promise is kept by name.
- Depending on work nobody has written yet reserves its slug the same way.

The marker works anywhere in an intent folder (intent, spec or plan) and in policy skills. If Claude
writes "a separate intent" or "a follow-up" with no marker, the hook adds a reminder.

Four commands, on PATH while the plugin is enabled. None of them changes anything:
- **`intents status [<slug>]`** derives every stage from git and is never declared: draft (including
  drafts that exist only on `docs/intent-*` branches), the intent's Status, then specced, planned,
  building and shipped. It also lists reserved slugs and who waits on them.
- **`intents check [<file>...]`** reports broken relations and layout: a Supersedes whose old intent
  isn't marked superseded, a dependency cycle, a slug used twice, a spec outside its story's folder.
- **`intents deps <slug or work folder>`** exits 1 unless a story's dependencies are met. Pull
  requests are checked with `gh`.
- **`intents export [<slug>]`** prints merged intents as JSON for a tracker: each story's title, a
  ready-made description and its digest, what it's blocked by, its stage, and once they're merged,
  its spec's acceptance table and its plan's steps. `/sdlc-kit:sync-jira` builds tickets from it,
  and a team on another tracker can build its own sync the same way.

The skills rely on these:
- `/sdlc-kit:new-intent` and `/sdlc-kit:review-intent` read `status` to find overlaps, drafts on other
  branches, and reserved work.
- `/sdlc-kit:new-spec` and `/sdlc-kit:new-plan` gate on `deps`.
- When an intent's last story finishes, `/sdlc-kit:build finish` runs the intent's own outcome checks.

**A PostToolUse hook runs `check`** on every markdown file Claude writes in an intent folder, and on
policy skills. Relation errors go back to Claude to fix in the same change. Prose that promises later
work ("a separate intent") with no follow-up marker only adds a note, and only for the text that edit
wrote: wording heuristics never block.

## The default branch
Every stage branches off, opens its PR against, and gates on one **default branch**: an intent counts
as accepted, a spec or plan as merged, and a story as shipped only once it's there. It's usually
the repo's default branch on GitHub, but it doesn't have to be. A team that merges into `develop`
can use that instead:
- **`CLAUDE.md` names it** (`The default branch is develop.`), and the skills and the verifier read
  it from there. `/sdlc-kit:init` asks for it.
- **`INTENTS_BASE` tells `intents`.** Without it, `intents` follows `origin/HEAD`, then `origin/main`,
  `origin/master`, `main` and `master`. When the default branch is anything else, set
  `INTENTS_BASE` in the `env` block of the checked-in `.claude/settings.json` (`init` does this), so
  the hooks and Claude's commands use it too:
  ```json
  { "env": { "INTENTS_BASE": "origin/develop" } }
  ```
  Use the remote branch (`origin/develop`, after a `git fetch`), not a local copy that may be behind.
  In your own shell or CI, export the same variable or pass `--base origin/develop`. `intents status`
  prints the branch it read, and a name that doesn't exist is an error, not an empty list.
- **Deploys ship the same branch.** If production deploys from somewhere else (`develop` is
  released to `main`, say), write that release step into `docs/deployment.md`.

The default branch is one per repo, not per intent. To build one intent against a release branch,
point `INTENTS_BASE` and `CLAUDE.md` at it for that work.

## Jira and product-owner review (optional)
Two features for teams whose product owner works outside GitHub. Both are off unless the project
turns them on in the `env` block of its checked-in `.claude/settings.json`, and they don't depend on
each other. `/sdlc-kit:init` asks about both.

```json
{ "env": { "SDLC_REVIEW": "doc", "SDLC_JIRA_PROJECT": "KAL" } }
```

**Review drafts in a Claude Doc (`SDLC_REVIEW=doc`).** `/sdlc-kit:review-intent` publishes the draft
intent as a Claude Doc and links it from the intent's header and its PR. The product owner reads the
doc and comments on it; the next `review-intent` run brings each comment into the review, edits
`intent.md`, updates the doc in place and replies in the thread. Approval stays on GitHub: the
product owner approves the PR, and merging it accepts the intent. The doc then points to where the
discussion continues. It needs the Claude Docs connector, and someone shares the doc with the
product owner from its **Share** button.

**Mirror accepted intents in Jira (`SDLC_JIRA_PROJECT=<KEY>`).** `/sdlc-kit:sync-jira` turns each
merged intent into tickets:

| Intent | Jira |
|---|---|
| An intent with stories | an epic: its Problem, Desired outcome and story list |
| Each `### Sn` story | a story under the epic: the user story, *What users get* and acceptance criteria |
| An intent without stories | one story, no epic |
| `After:`, `Depends on:` | "is blocked by" links |
| A merged spec | its link and acceptance tests, added to the story |
| A merged plan | one subtask per step, only with `SDLC_JIRA_SUBTASKS=on` |
| A dropped story | a comment, then `Won't Do` |

- **The repo stays the source.** Every ticket is labelled `sdlc:<slug>`, so the sync updates the same
  tickets each time and never duplicates them. Nothing is written back into an accepted intent.
- **Jira changes come back as amendments.** Before writing, the sync reads each ticket. A
  description someone edited in Jira isn't overwritten: it becomes an amendment through
  `/sdlc-kit:review-intent`, in a PR a human merges. `--pull` does only this half.
- **The team moves tickets by hand.** The sync never changes a ticket's status, except to close a
  dropped story.
- **Settings:** `SDLC_JIRA_EPIC_TYPE`, `SDLC_JIRA_STORY_TYPE`, `SDLC_JIRA_SUBTASK_TYPE`,
  `SDLC_JIRA_BLOCKS_LINK` and `SDLC_JIRA_DROPPED_STATUS` override the names when the project's Jira
  differs (`Epic`, `Story`, `Subtask`, `Blocks`, `Won't Do`).
- **It needs the Atlassian connector,** signed in with `/mcp` by whoever runs the sync. Run it after an
  intent, spec, plan or amendment merges.

Without `SDLC_JIRA_PROJECT`, no skill mentions Jira, and `/sdlc-kit:sync-jira` stops with these setup
steps rather than asking for a key.

## Install
There are two ways to install. Both install the plugin for your user, so every project and session
picks it up.

**From a terminal (shell).** This works everywhere, including for the Claude desktop app:
```bash
claude plugin marketplace add mustafamg/claude-ai-sdlc-plugin   # or a local path to this repo
claude plugin install sdlc-kit@sdlc-kit
```

**Inside an interactive Claude Code session** (`claude` in a terminal, or an IDE extension), type:
```text
/plugin marketplace add mustafamg/claude-ai-sdlc-plugin
/plugin install sdlc-kit@sdlc-kit
```
The `/plugin` command opens an interactive terminal UI, so in the Claude desktop app's Code tab, use
the shell commands above instead. Start a new session after installing so the plugin loads.

Then, inside a Claude Code session in your project, run `/sdlc-kit:init`. It's a skill, so it doesn't
run from a shell.

**Note on names:** the GitHub repo is `mustafamg/claude-ai-sdlc-plugin`, but the marketplace it
defines and the plugin inside it are both named `sdlc-kit`. You add the marketplace by its repo
(`mustafamg/claude-ai-sdlc-plugin`), then install and refer to the plugin as `sdlc-kit@sdlc-kit`
(`<plugin>@<marketplace>`), and its skills as `/sdlc-kit:<skill>`.

**For a team,** check this into the project's `.claude/settings.json` (`/sdlc-kit:init` can add it):
```json
{
  "extraKnownMarketplaces": { "sdlc-kit": { "source": { "source": "github", "repo": "mustafamg/claude-ai-sdlc-plugin" } } },
  "enabledPlugins": { "sdlc-kit@sdlc-kit": true }
}
```

**Requirements:** `git`, `jq`, `bash`, and `python3` (3.9+) for add-only locks and `intents`.
Without `python3`, Python test files fall back to whole-file locks and the intents hook does nothing.
`gh` is needed for PR steps.

## Conventions the kit relies on
- `CLAUDE.md` lists each project's check command. The build and the verifier run exactly those.
- Intent folders are `intent/YYYY-MM-DD-<slug>/`, and each file is approved by merging its PR. An
  intent with stories gives each story a folder inside it. Every stage after the intent takes that
  **work folder** (the intent's, or the story's), and its name without a date is the `<slug>`.
- Commits: `test(<slug>): step N: …` for tests, `feat(<slug>): step N: …` for code, and
  `docs(plan): …` for plan updates. `/sdlc-kit:build` finds progress through these.
- **Policy skills** are project skills whose description starts with `Policy -`.
  `templates/policy-skill/SKILL.md` is the starting point.
- Plans may group steps into labeled **lanes** for parallel worktrees.

## Lessons baked in
These were learned the hard way on the first project that used this kit:
- **Skills are advice; hooks are enforcement.** Anything that must hold gets a hook, and a separate
  read-only verifier checks the builder.
- **Whole-file test locks are too blunt** when a plan spreads one test file across steps. That forced
  an unlock every step, and each unlock reset the lock. The fix was add-only locks with a lock point
  per step.
- **Lock the harness too.** A test can be weakened through its fixtures as easily as through its
  assertions.
- **Keep tooling current on feature branches,** or a long-lived branch quietly runs old rules. Shipping
  the tooling as a plugin fixes this.
- **Hook heuristics must target writes, not mentions.** A commit message that names a locked file must
  not be blocked.
- **With stacked PRs, retarget the child PR before merging the parent,** or the child merges into a
  dead branch.

## Development
```bash
bash tests/run-tests.sh                  # the lock, hook and guard regression suite
claude plugin validate plugins/sdlc-kit  # manifest and component validation
```

## License
MIT. See [LICENSE](LICENSE).
