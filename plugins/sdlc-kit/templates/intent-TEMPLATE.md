# Intent: <short title>

- **Author:** <name>
- **Date:** YYYY-MM-DD
- **Status:** draft | accepted | deferred | rejected | superseded
- **Approved by:** <product owner, once accepted>
- **Revisit:** <YYYY-MM and who, when deferred>
- **Depends on:** <slugs of intents or stories, or #PR, comma-separated; delete if none>
- **Supersedes:** <slug of the intent this replaces; delete if none>

## Problem
What is wrong or missing today, and who feels it? Write it for the product owner, in a paragraph or
two: business terms, no file paths or class names. The technical findings go in **Evidence** at the
end.

## Desired outcome
What does "done" look like from the user's point of view? How will we know it worked? Number the
outcomes if the intent has stories, so each story can say which ones it delivers.

## Where we are today
What the product already does toward the outcome, and what's missing, in the same business terms as
the Problem. End each line with a link to its group in Evidence.

**Already supported**
- <what users can do today>. ([evidence](#<evidence-heading>))

**Not supported yet**
- <what the outcome needs that doesn't exist>. ([evidence](#<evidence-heading>))

**Known risks today** (delete if none)
- <current behaviour that could undermine the outcome>. ([evidence](#<evidence-heading>))

## Stories
Delete this section if the intent ships as one piece, which most do. Otherwise split it into 2–4
stories. Each one is specced, planned and built on its own, in its own folder (`<story-slug>/`), and
each must be safe to ship alone.

Give each story the block below, under its own `###` heading. Write it for the product owner, from
the user's side: what they can do once it ships, not how it's built. Keep each part to short
bullets. **Outcomes** names the numbered desired outcomes the story delivers. **Acceptance
criteria** are the first checks a user could make once it ships, in plain words; the spec turns
them into Given / When / Then rows.

**After** says what the story waits for. `After: S1` waits for S1's spec to merge, which is enough
to build against its contract. `After: S1 ships` waits for S1 to ship. Delete the line if the story
waits for nothing. Story slugs name branches and commits, so they must be unique across `intent/`.

### S1 <story-slug>: <title: what users can do once it ships>
<One sentence on what ships.>

- **Outcomes:** <numbers>
- **After:** <S1, S1 ships, or a slug; delete if none>
- **Actors:** <who uses it>
- **User story:** As a <role>, I want <to do something>, so <what it gets them>.

**What users get**
- <a capability, in the user's words>
- <what stays as it is today, when that matters>

**Acceptance criteria**
- <something a user can check: "an analyst can …", "a rule that … never …">
- <the main error or edge case, and what the user sees>

## Users affected
<Who uses the affected parts: end users, admins, operators, other services…>

## Systems affected
Tick what you expect to change, and note why.

- [ ] <project or service 1>
- [ ] <project or service 2>
- [ ] Datastores (schema, indexes, collections)
- [ ] Infrastructure / deployment

## Constraints
Performance, cost, privacy, compliance, localization, backward compatibility, deadlines. Name work
this depends on in **Depends on** above, by slug or PR number, so it can be checked.

## Out of scope
What we are deliberately *not* doing. When someone will do it later, end the item with
`→ follow-up: <slug>`, so the slug is reserved and `intents status` lists it under this intent until it's written.

## Open questions
Each with a proposed answer, so the approver can say "yes" or "no, because…". Business questions
change what users see or what the product does, and need the product owner, so they come first.
Technical ones can wait for the spec. Number them straight through both groups, and break each
proposed answer into short items. Delete a group that has no questions.

### Business

1. **<question, in business terms>?**
   *Proposed:*
   - <the answer>.
   - <what it means for users, or who confirms it>.

### Technical

2. **<question>?**
   *Proposed:*
   - <the answer>.
   - <which spec or story settles it>.

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

To drop a story, strike its heading through (`### ~~S3 <story-slug>: <title>~~`) and add the note
after it; a struck-through story no longer counts.

A struck-through line that turned out to be wrong is more useful to the next reader than a clean file
that hides the correction.

## Evidence
The technical findings behind *Where we are today*: code you read or ran, logs, metrics, user
reports. Group them under `###` headings, one per area, so the lines above can link to them. Mark
each item **verified** (you saw or ran it) or **assumed**, and link the code it cites.

### <area>
- **Verified.** <finding>, in [<file>:<line>](<relative path>).
- **Assumed.** <finding, and why it isn't checked yet>.
