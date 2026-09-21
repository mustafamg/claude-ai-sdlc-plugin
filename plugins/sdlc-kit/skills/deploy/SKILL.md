---
name: deploy
description: Deploy (or roll back) the default branch by following the project's deployment runbook, with a human go-ahead before anything changes. Use when someone asks to deploy, ship, release, redeploy a service, roll back, or check what's deployed. Do NOT use for local runs, writing CI config, or debugging an outage without deploying (inspect read-only instead).
argument-hint: [status | <service...> | all | rollback [<tag>]]
disable-model-invocation: true
---

# /sdlc-kit:deploy: ship the default branch

Arguments: **$ARGUMENTS**. `status` (the default) is read-only: it reports what's deployed and what's
changed since. A list of services, or `all`, deploys those services. `rollback` restores the last
rollback point, or the one given.

**The project's runbook is the procedure.** Use the path `CLAUDE.md` names, or `docs/deployment.md`.
Read it in full first, from the default branch. If there's no runbook, stop and offer to draft one
from `${CLAUDE_PLUGIN_ROOT}/templates/deployment.md` instead of improvising a deploy. This skill only
adds the guardrails for running a runbook as Claude. If the runbook and the target disagree (a
hostname, path, port, or service name has changed), stop and report the difference. Offer to update
the runbook afterwards.

## 1. Status (always first, read-only)
- Find the deployed commit the way the runbook says, and compare it with the default branch
  (`git log`, `git diff --stat`).
- Check for local drift on the target (uncommitted changes in a server checkout, hand-edited config).
  Anything the runbook doesn't list as known drift is a blocker.
- Record the "before" state: running services and the runbook's health checks.
- Map changed paths to services, using the runbook's table. Flag migrations, secrets or env changes,
  and build-time configuration.
- For `status`, report and stop here.

## 2. Get the go-ahead
Show the user, in one message: the commit range, the services to rebuild, whether a migration runs
(and whether it changes or drops data, which means a backup first), any env or secret changes they
must make by hand, the rollback point you'll create, and the exact commands. **Wait for a clear yes.**
That approval covers only this plan. Ask again for anything outside it, including a rollback that turns
out to be needed.

## 3. Execute
Follow the runbook's steps in order, one step per command, so a failure stops right there. Never chain
the whole deploy into one long remote command.
- **Only deploy the default branch.** Never deploy a feature branch or uncommitted work.
- **Create the rollback point before building.**
- On any unexpected output (a failed pull, a non-zero migration, a build error, an unhealthy service,
  a failed smoke test), stop. If new services are already up, propose the runbook's rollback and wait
  for approval.
- Never print secrets or env file contents. Never run destructive or wide-reaching commands (teardown,
  prune, data restore, proxy/web-server changes, anything touching other apps on the same host) unless
  the user explicitly asks for that exact command.

## 4. Report
Report the old commit, the new commit, the services, any migration that ran, the rollback point, the
health and smoke-test results, and anything that deviated from the runbook. Record the same wherever
the runbook says (e.g. a deploy log).
