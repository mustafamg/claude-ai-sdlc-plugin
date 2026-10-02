# Intent: <short title>

- **Author:** <name>
- **Date:** YYYY-MM-DD
- **Status:** draft | accepted | deferred | rejected | superseded
- **Approved by:** <product owner, once accepted>
- **Revisit:** <YYYY-MM and who, when deferred>

## Problem
What is wrong or missing today, and who feels it? Include evidence (user reports, metrics, logs, code
you read or ran), marking each item **verified** or **assumed**.

## Desired outcome
What does "done" look like from the user's point of view? How will we know it worked?

## Users affected
<Who uses the affected parts: end users, admins, operators, other services…>

## Systems affected
Tick what you expect to change, and note why.

- [ ] <project or service 1>
- [ ] <project or service 2>
- [ ] Datastores (schema, indexes, collections)
- [ ] Infrastructure / deployment

## Constraints
Performance, cost, privacy, compliance, localization, backward compatibility, dependencies on other
work, deadlines.

## Out of scope
What we are deliberately *not* doing.

## Open questions
Each with a proposed answer, so the approver can say "yes" or "no, because…".

## Decisions
Filled in by `/sdlc-kit:review-intent`. One row per question: the question, its
resolution (decided / deferred to spec / out of scope / needs <name>), who decided, and the date.

| Question | Resolution | Who | Date |
|---|---|---|---|

**Amending this intent after it's accepted.** The spec or the plan will sometimes prove part of this
file wrong. When that happens, don't overwrite it:

- strike the original wording (`~~a 60-day purge of idle sessions~~`) and put the new wording beside
  it, so the change is visible in place;
- mark it `(Amended YYYY-MM-DD: <what changed and what forced it>)`, naming the spec section, plan
  step or PR that found the problem;
- add a row here for each amendment;
- leave `Status` alone. An amendment doesn't re-run approval of the whole intent.

A struck-through line that turned out to be wrong is more useful to the next reader than a clean file
that hides the correction.
