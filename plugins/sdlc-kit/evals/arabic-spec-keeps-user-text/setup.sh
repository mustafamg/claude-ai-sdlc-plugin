#!/usr/bin/env bash
# Builds the eval workspace: a git repo whose main branch has an accepted English intent with no
# stories, ready for its spec. Run with --scaffold.
set -euo pipefail
git init -q -b main && git config user.email eval@example.com && git config user.name eval
cat > CLAUDE.md <<'EOF'
# Clinic booking
A web app clinics use to book patient appointments. Receptionists manage the calendar; patients book
online. Projects: `api/` (bookings, patients), `web/` (patient and reception UI). Patients see the
product in Arabic.
EOF
mkdir -p api web && echo "# api" > api/README.md && echo "# web" > web/README.md
I=intent/2026-02-10-appointment-reminders
mkdir -p $I
cat > $I/intent.md <<'EOF'
# Intent: SMS reminders so patients confirm or cancel appointments

- **Author:** mona
- **Date:** 2026-02-10
- **Status:** accepted
- **Approved by:** karim (2026-02-12)

## Problem
About 20% of appointments last month were no-shows (غياب), per the reception report, so doctors sit
idle and other patients can't get those slots.

## Desired outcome
1. A patient gets one SMS reminder 24 hours before their appointment.
2. The patient can confirm or cancel by replying to the SMS.
3. A cancelled appointment's slot becomes bookable again.

We'll know it worked when no-shows drop below 10% within two months.

## Users affected
Patients, and receptionists.

## Systems affected
- [x] api: send reminders, take replies, free cancelled slots.
- [x] web: show confirmed and cancelled status on the reception calendar.

## Constraints
- One SMS per appointment.
- The SMS text is in Arabic.

## Out of scope
- WhatsApp reminders.
- Prepayment.

## Decisions
| Question | Resolution | Who | Date |
|---|---|---|---|
| Appointment booked less than 24 hours ahead? | No reminder. | karim | 2026-02-12 |
| What the patient replies with | deferred to spec | karim | 2026-02-12 |
EOF
git add -A && git commit -qm "docs(intent): accept appointment reminders"
