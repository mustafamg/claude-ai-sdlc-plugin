---
name: init
description: Set up a project for the sdlc-kit AI-native SDLC. It scaffolds CLAUDE.md sections, the intent/ folder and templates, .gitignore entries, protected paths, starter policy skills, and optionally a deployment runbook and team plugin settings. Use when someone asks to set up, initialize, bootstrap, or adopt the SDLC kit in a repo.
argument-hint: [--minimal]
disable-model-invocation: true
---

# /sdlc-kit:init: set a project up for the AI-native SDLC

Templates live in `${CLAUDE_PLUGIN_ROOT}/templates/`. Everything you create is proposed, shown, and
committed on a branch for review. **Never overwrite an existing file.** Merge into it, show the diff,
and ask first. `--minimal` skips the optional steps (6–8).

## 1. Look before writing
- Read the repo: `README`, the existing `CLAUDE.md` (if any), build and test config (package.json,
  pyproject, Makefile, etc.), CI config, and which folders are vendored or generated.
- Find each project's **real** test/check command. Run the cheap ones to confirm they work and to
  record their current result. A command that fails today is recorded as such, not hidden.
- Summarize what you found and what you'll create, then ask the user to confirm.

## 2. `CLAUDE.md`
- **If it's missing,** draft it from `templates/CLAUDE.md`, filled with what §1 found: the project
  map, the verified check commands, rules, and known gaps. Keep it to about one page.
- **If it exists,** add only the missing sections, adapted from the template: Workflow (the
  `/sdlc-kit:*` commands), "Verifying your work", and Known gaps. Show the diff.

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

## 8. Team settings (optional)
Offer to add the marketplace and plugin to the checked-in `.claude/settings.json`, so teammates get the
kit automatically. Ask for the marketplace repo (e.g. `org/sdlc-kit`) and merge, don't overwrite:
```json
{
  "extraKnownMarketplaces": {
    "sdlc-kit": { "source": { "source": "github", "repo": "<org>/sdlc-kit" } }
  },
  "enabledPlugins": { "sdlc-kit@sdlc-kit": true }
}
```
Also suggest `"permissions": { "deny": ["Read(./.env)", "Read(./**/.env)"] }` as a second layer
behind the hook.

## 9. Commit for review
Branch off the default branch as `chore/adopt-sdlc-kit`, commit the new and changed files, and open a
PR that lists what was created, the verified check commands and their current results, and any
decisions left to the team. **Never merge it.** Then suggest starting the first feature with
`/sdlc-kit:new-intent <idea>`.
