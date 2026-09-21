---
name: <policy-name>
description: Policy - <one line naming the rules, e.g. "API and security rules (auth on every route, rate limits, no secrets in logs)">. Use when designing or reviewing a spec, plan, or change that <touches the areas this policy covers>.
---

# Policy: <title>

**Owner:** <name or role>. Changes to this file need the owner's review.
**Applies to:** every spec (via `/sdlc-kit:new-spec`), plan, and code change that touches the areas
below.

This is a policy, not a suggestion. If a design can't meet a rule, flag it as a **conflict** for the
owner. Don't quietly work around it.

## Rules

1. **<Rule, stated as a testable requirement.>** <Where it applies, with concrete paths or mechanisms
   in this codebase, and what "compliant" looks like.>
2. **<Rule.>** <…>

## Known violations (existing code that breaks these rules)

- **Rule <n> (must be fixed | accepted exception, <date>):** <what breaks it, with file paths and
  evidence>. <What's tracked to fix it, and what must not happen until then.>

## Questions every spec must answer (when relevant)

- **<Topic>:** <the question, phrased so the spec must commit to an answer. Say "ask the user, don't
  invent numbers" where a value is a business decision.>
