# Intent: Guest access to shared boards

- **Author:** sam
- **Date:** 2026-02-02
- **Status:** draft
- **Approved by:**
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

## Open questions
1. Do guest links expire? Proposed: yes, 30 days.
2. Can guests comment, or only read? Proposed: read only.
3. Do we need an audit trail of guest views? Proposed: no, not for v1.

## Decisions
