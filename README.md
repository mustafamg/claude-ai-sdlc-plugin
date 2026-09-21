# sdlc-kit

A Claude Code plugin that runs an **AI-native SDLC**, based on Anthropic's
[AI-native SDLC playbook](https://claude.com/blog/the-ai-native-sdlc-playbook). Claude does the work
at every stage. A human approves between stages by merging a PR. Rules that must hold are enforced by
hooks, not just requested in prompts.

```
idea ─► intent.md ─► spec.md ─► plan.md ─► test-first build ─► verified PR ─► gated deploy
       /new-intent  /new-spec  /new-plan   /build (per step)   /build finish   /deploy
```

## What's inside

| Component | Stage | What it does |
|---|---|---|
| `/sdlc-kit:init` | Setup | Scaffolds a project: `CLAUDE.md` sections, `intent/` templates, `.gitignore`, protected paths, starter policy skills, and optionally a runbook and team settings. |
| `/sdlc-kit:new-intent <idea>` | 1 Plan | Interviews you, gathers evidence from the code (verified vs. assumed), and drafts `intent.md`. |
| `/sdlc-kit:new-spec <folder>` | 2 Design | Writes numbered requirements, Given/When/Then acceptance criteria, and a design. Applies the project's policy skills, flags conflicts, and says when no spec is needed. |
| `/sdlc-kit:new-plan <folder>` | 3 Plan | Works in plan mode. Checks the spec against the code and writes `plan.md`: an acceptance criterion → test → step table, ordered steps, lanes, risks, and verification. |
| `/sdlc-kit:build <folder> [step\|next\|finish]` | 3–4 Build/Test | Test-first, one step at a time: tests from the spec, confirm they fail for the right reason, lock them, code until green, run checks, commit, verify. Resumes half-done steps and supports parallel lanes. `finish` opens the PR with evidence. |
| `verifier` subagent | 4 Test | Read-only. Checks locks, weakened tests, and test-support changes, runs every check, and grades each acceptance criterion PASS/FAIL/MISSING with quoted evidence. |
| `/sdlc-kit:deploy` | 5 Deploy | Follows the project's runbook: read-only status, then human go-ahead, then a rollback point, then one step at a time, then a report. |
| Guard hook | All | Blocks access to real `.env*` files and edits to paths listed in `.claude/protected-paths`. |
| Test-lock hook + `test-lock` | 3–4 | Freezes tests once written (below). |

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

**Requirements:** `git`, `jq`, `bash`, and `python3` (3.9+) for add-only locks. Without `python3`,
Python test files fall back to whole-file locks. `gh` is needed for PR steps.

## Conventions the kit relies on
- `CLAUDE.md` lists each project's check command. The build and the verifier run exactly those.
- Intent folders are `intent/YYYY-MM-DD-<slug>/`, and each file is approved by merging its PR.
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
