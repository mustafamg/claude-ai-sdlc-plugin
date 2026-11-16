---
name: init
description: Set up a project for the sdlc-kit AI-native SDLC. It scaffolds CLAUDE.md sections, the intent/ folder and templates, .gitignore entries, protected paths, starter policy skills, and optionally a deployment runbook and team plugin settings. Use when someone asks to set up, initialize, bootstrap, or adopt the SDLC kit in a repo.
argument-hint: [--minimal]
disable-model-invocation: true
---

# /sdlc-kit:init: set a project up for the AI-native SDLC

Templates live in `${CLAUDE_PLUGIN_ROOT}/templates/`. Everything you create is proposed, shown, and
committed on a branch for review. **Never overwrite an existing file.** Merge into it, show the diff,
and ask first. `--minimal` skips the optional steps (6–8), but never §8's default branch.

## 1. Look before writing
- **If the project already has a workflow,** stop and suggest `/sdlc-kit:adopt` instead. Signs: rules in
  `AGENTS.md` or `.cursorrules`; a `CLAUDE.md` that already describes how features get planned; loose plan or todo files; a `.specify/` folder
  or project skills that plan or build; unfinished feature branches. This skill only adds; `adopt` also
  converts and retires what's there.
- Read the repo: `README`, the existing `CLAUDE.md` (if any), build and test config (package.json,
  pyproject, Makefile, etc.), CI config, and which folders are vendored or generated.
- Find each project's **real** test/check command. Run the cheap ones to confirm they work and to
  record their current result. A command that fails today is recorded as such, not hidden.
- Find the **default branch**: the branch every PR merges into and every stage gates on. Propose the
  remote's (`git symbolic-ref --short refs/remotes/origin/HEAD`) and ask whether the team merges
  somewhere else, such as `develop`. §2 and §8 record the answer.
- Summarize what you found and what you'll create, then ask the user to confirm.

## 2. `CLAUDE.md`
- **If it's missing,** draft it from `templates/CLAUDE.md`, filled with what §1 found: the project
  map, the verified check commands, rules, and known gaps. Keep it to about one page.
- **If it exists,** add only the missing sections, adapted from the template: Workflow (the
  `/sdlc-kit:*` commands), "Verifying your work", and Known gaps. Show the diff.
- Either way, the Rules name the default branch from §1 (the template's "The default branch is" line).

## 3. `intent/`
Copy `templates/intent-README.md` to `intent/README.md` and `templates/intent-TEMPLATE.md` to
`intent/_TEMPLATE.md`. Replace the template's "Systems affected" placeholder with this repo's real
projects or services.

## 4. `.gitignore`
Add any of these that are missing, with a short comment:
```
.env*
!.env.example
.claude/settings.local.json
.claude/test-lock
```
If tracked files would newly match `.env*`, stop and tell the user. Never untrack or delete anything
yourself.

## 5. Protected paths
Ask which paths must never be hand-edited (vendored code, generated files, lockfiles you don't
regenerate by hand). Write them to `.claude/protected-paths`, one bash glob per line with a `# reason`.
The plugin's guard hook blocks edits to them. Skip if there are none.

## 6. Policy skills
Explain that policy skills are written rules the design and build stages apply (see
`/sdlc-kit:new-spec`). Ask which rules the team actually enforces today (security, data/privacy,
accessibility, localization, brand, cost), and who owns each. For each real one, create
`.claude/skills/<name>/SKILL.md` from `templates/policy-skill/SKILL.md`:
- the description must start with `Policy -`;
- name the owner;
- list the rules, known violations in current code (with evidence), and the questions every spec must
  answer.

Don't invent policies nobody follows. One or two real ones beat five aspirational ones.

## 7. Deployment runbook (optional)
If the project deploys somewhere, offer to draft `docs/deployment.md` from `templates/deployment.md`,
using what's knowable from the repo, and marking everything unverified. Never connect to a server to
fill it in without asking.

## 8. Team settings
**The default branch, if it isn't the remote's (required).** `intents`, and the hooks and skills that
run it, otherwise follow `origin/HEAD`. Merge this into the checked-in `.claude/settings.json`:
```json
{ "env": { "INTENTS_BASE": "origin/<branch>" } }
```
Use the remote branch, so it reads what's merged rather than a stale local copy. Tell the user that
running `intents` from their own shell or CI needs the same `INTENTS_BASE` exported, or `--base`.

**Where the product owner reviews drafts (optional).** Ask whether the product owner reviews draft
intents in GitHub pull requests, or would rather read and comment on a Claude Doc (they need a
claude.ai account in the organization). Only for a doc, merge `"SDLC_REVIEW": "doc"` into the `env`
block. Pull requests are the default, so write nothing for them.

**Jira (optional).** Ask "Does this project track work in Jira?" Only on a yes, ask for the project
key, and merge `"SDLC_JIRA_PROJECT": "<KEY>"` into the `env` block. Add a type, link or status
override only when the user names one that differs from the defaults in `/sdlc-kit:sync-jira`
(`Epic`, `Story`, `Subtask`, `Blocks`, `Won't Do`). Subtasks from plan steps are off unless they ask
for `"SDLC_JIRA_SUBTASKS": "on"`. On a no, write nothing: no skill mentions Jira without the key.
Tell them the Atlassian connector has to be signed in (`/mcp`) by whoever runs the sync.

**The plugin (optional).** Offer to add the marketplace and plugin to the checked-in
`.claude/settings.json`, so teammates get the kit automatically. Ask for the marketplace repo (default `mustafamg/claude-ai-sdlc-plugin`; a fork works too) and merge, don't overwrite:
```json
{
  "extraKnownMarketplaces": {
    "sdlc-kit": { "source": { "source": "github", "repo": "mustafamg/claude-ai-sdlc-plugin" } }
  },
  "enabledPlugins": { "sdlc-kit@sdlc-kit": true }
}
```
Also suggest `"permissions": { "deny": ["Read(./.env)", "Read(./**/.env)"] }` as a second layer
behind the hook.

## 9. Commit for review
Branch off the default branch as `chore/adopt-sdlc-kit`, commit the new and changed files, and open a
PR against it that lists what was created, the verified check commands and their current results,
and any decisions left to the team. **Never merge it.** Then suggest starting the first feature with
`/sdlc-kit:new-intent <idea>`.
