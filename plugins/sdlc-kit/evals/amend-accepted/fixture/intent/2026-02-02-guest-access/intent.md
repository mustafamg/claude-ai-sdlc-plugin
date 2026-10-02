# Intent: Guest access to shared boards

- **Author:** sam
- **Date:** 2026-02-02
- **Status:** accepted
- **Approved by:** sam (2026-02-05)
- **Revisit:**

## Problem
Customers ask to share a board with people who have no account. Today sharing requires an invite and a
signup, and support sees roughly 12 requests a month for this (**assumed**: the number comes from a
support thread, not a query). The share endpoint rejects unauthenticated reads (**assumed**).

## Desired outcome
Sharing a board with someone outside the team should be easy and safe.

## Users affected
Board owners, and the guests they share with.

## Systems affected
- [x] api
- [x] web
- [ ] Datastores (schema, indexes, collections)
- [ ] Infrastructure / deployment

## Constraints
Should not slow down the existing board load.

## Out of scope

## Constraints
Should not slow down the existing board load. Idle guest sessions are purged from our session tables
after 60 days.

## Open questions
All three are resolved below.

## Decisions

| Question | Resolution | Who | Date |
|---|---|---|---|
| Do guest links expire? | Yes, 30 days, renewable | sam | 2026-02-05 |
| Can guests comment? | Read only | sam | 2026-02-05 |
| Audit trail of guest views? | Not in v1 | sam | 2026-02-05 |
