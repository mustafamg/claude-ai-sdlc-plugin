# Deployment runbook

Used by `/sdlc-kit:deploy`. Keep it exact: hostnames, paths, and service names here must match the
target, or the deploy stops.

## 1. Topology
- **Target:** <host / platform, how to reach it (e.g. `ssh <alias>`)>
- **Checkout / artifact location:** <path or registry>
- **Services:** <name → what it is → health check URL or command>
- **Secrets:** <where env files live on the target; who sets them; they're never printed>

### Known drift
<Anything that differs from the repo on purpose (hand-edited config, extra files), so a status check
doesn't treat it as a blocker.>

## 2. Rules
- Only the default branch is deployed.
- A human approves each deploy plan before anything changes.
- A rollback point (image tags, release, snapshot) is created before every build.
- Migrations run as their own step, with a backup first if they change or drop data.

## 3. Deploying a change
### 3.1 Decide what to deploy
<How to find the deployed commit, and a table mapping changed paths to services.>

| Changed path | Rebuild / restart |
|---|---|
| `<path>/` | `<service>` |

### 3.2 Update the checkout / artifact
<Exact commands.>

### 3.3 Create the rollback point
<Exact commands, e.g. tag current images as `rollback-<date>-<commit>`.>

### 3.4 Migrations (only when migration files changed)
<Exact commands, and how to confirm the new revision.>

### 3.5 Build and restart
<Exact commands, one service at a time if possible.>

### 3.6 Verify
<Health checks and a smoke test of the main user flow, with expected output.>

### 3.7 Record it
<Where to log: old commit, new commit, services, migration, rollback point, results.>

## 4. Rolling back
<Exact commands to restore the last rollback point, and how to handle migrations that already ran.>

## 5. Housekeeping
<Pruning old rollback points, logs, disk space.>
