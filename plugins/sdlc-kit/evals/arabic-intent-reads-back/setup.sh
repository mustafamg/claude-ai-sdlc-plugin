#!/usr/bin/env bash
# Builds the eval workspace: a git repo set up for intents (README and a short template) and nothing
# else, so a new intent can be drafted. Run with --scaffold.
set -euo pipefail
git init -q -b main && git config user.email eval@example.com && git config user.name eval
mkdir -p intent
cat > intent/README.md <<'EOF'
# intent/
One folder per feature: `intent/<YYYY-MM-DD>-<slug>/intent.md`, from `_TEMPLATE.md`. A product owner
approves an intent by merging its PR.
EOF
cat > intent/_TEMPLATE.md <<'EOF'
# Intent: <short title>

- **Author:** <name>
- **Date:** YYYY-MM-DD
- **Status:** draft | accepted | deferred | rejected | superseded
- **Approved by:** <product owner, once accepted>

## Problem
What is wrong or missing today, and who feels it? Business terms, for the product owner.

## Desired outcome
What "done" looks like from the user's point of view, and how we'll know it worked.

## Where we are today
What the product already does toward the outcome, and what's missing.

## Users affected

## Systems affected
- [ ] <project or service>

## Constraints

## Out of scope
Later work ends with `→ follow-up: <slug>`.

## Open questions
### Business
1. **<question>?**
   *Proposed:*
   - <the answer>.

### Technical

## Decisions
| Question | Resolution | Who | Date |
|---|---|---|---|

## Evidence
### <area>
- **Verified.** / **Assumed.** <finding>
EOF
cat > CLAUDE.md <<'EOF'
# Clinic booking
A web app clinics use to book patient appointments. Receptionists manage the calendar; patients book
online. Projects: `api/` (bookings, patients), `web/` (patient and reception UI).
EOF
mkdir -p api web && echo "# api" > api/README.md && echo "# web" > web/README.md
git add -A && git commit -qm "chore: init"
