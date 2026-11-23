# evals/

Eval cases for the kit's skills, run with `claude plugin eval`. They check two things:
- **Routing:** `/sdlc-kit:review-intent` and `/sdlc-kit:new-intent` describe adjacent work, and a
  description change on either one can make the wrong skill fire.
- **Gates and judgement:** the behaviour the skills promise, such as holding the approval gate,
  splitting an intent along a partial dependency, or refusing to plan a story whose dependency
  hasn't shipped.

## Running

```bash
claude plugin eval plugins/sdlc-kit --scaffold --allow-tools Bash Write Edit --no-publish \
  --model claude-sonnet-5 --judge-model claude-sonnet-5 --max-cost-usd 15
```

- **`--scaffold` is required.** Most cases build their workspace with a `setup.sh`. The older ones
  copy `fixture/` (an intent folder) into it. The stories cases build a small git repo instead, with
  intents merged on `main` or drafted on a `docs/intent-*` branch, because the skills now check that
  state with `intents`. Without the flag the workspace is empty, and the cases quietly test nothing.
- **`--allow-tools Bash` is required for the stories cases.** They list Bash in `allowed_tools` so
  the skills can try `intents status`, `check` and `deps`, and Bash needs an operator grant. The
  language cases also need **`Write Edit`**, because they check the file the skill writes.
- **These cases test the skills without `intents`.** The eval sandbox doesn't put the plugin's
  `bin/` on PATH, so `intents` reports "not found" or "operation not permitted". On macOS, `git`
  fails there too, because its `xcrun` wrapper can't write its cache. The skills then fall back to
  checking by hand, which is what these scores measure. In a normal session `intents` is on PATH.
  The tool itself is covered by `tests/run-tests.sh`.
- **Cases cost money.** Each one also runs a no-plugin baseline arm, and the `llm` graders call a
  judge model. The whole suite of ten cases cost $9.60 on Sonnet in October 2026, and took about 12
  minutes with `-j 4`. Keep `--max-cost-usd` as a hard ceiling.
- **The command-line `claude` must be logged in** (`claude auth status`). The desktop app's sign-in
  doesn't reach the processes `plugin eval` starts, and a run that can't authenticate stops after a
  few seconds with `auth_failed`.
- **Add `--keep-temp` to investigate a failure.** It keeps each run's workspace and `trace.jsonl`; the
  report itself has only the judge's votes, not the transcript.
- `--tag trigger` runs just the routing cases; `--tag behavior` runs the rest; `--tag language`
  runs the cases for Arabic and English conversations.
- **Grade with Sonnet.** The default judge is Haiku, and it produced a unanimous false FAIL on a
  `defer-outcome` response that plainly deferred the intent and asked for the revisit month. The
  judged criteria here need a judge that reads a whole answer carefully.
- Needs a recent CLI. Older builds report `plugin eval is currently in early access`.
- Results land in `results/`, which is gitignored.

## Cases

| Case | Tag | What it checks |
|---|---|---|
| `review-intent-trigger` | trigger | A drafted intent with open questions routes to `review-intent`, `new-intent` stays out, and the review raises gaps the intent doesn't list instead of answering them itself. |
| `new-intent-not-hijacked` | trigger | The reverse: a fresh idea still routes to `new-intent`, and `review-intent` doesn't steal it. |
| `approval-gate` | behavior | Told "approve it and merge, you have my sign-off", Claude doesn't merge and says approval is the human's. |
| `defer-outcome` | behavior | "Right idea, not this quarter" becomes `Status: deferred` with a revisit month, not a rejection. |
| `amend-accepted` | behavior | An accepted intent the spec proved wrong gets amended — status untouched, record preserved — not re-reviewed from scratch. |
| `split-on-partial-dependency` | behavior | A draft whose dependency blocks only part of its outcome gets a split proposed, into stories or separate intents. |
| `follow-up-gets-a-slug` | behavior | Later work promised only in prose ("that's a follow-up intent") is flagged as untracked and given a `→ follow-up: <slug>` marker. |
| `new-intent-adopts-reserved-slug` | behavior | A new idea that another intent already reserved as a follow-up takes that reserved slug. |
| `plan-waits-for-dependency` | behavior | A story marked `After: S1 ships` isn't planned while S1 has only a plan. The gate says S1 has to ship first. |
| `sync-jira-off` | behavior | Asked for Jira tickets in a project without `SDLC_JIRA_PROJECT`, the sync stops, says how to turn Jira on, and creates nothing. (`review-intent-trigger` also checks that a review in such a project stays in the PR.) |
| `spec-asks-for-a-story` | behavior | Asked to spec an intent that has stories, the spec is written for one story, not for the whole intent. |
| `arabic-idea-routes-to-new-intent` | trigger | An idea told in Arabic, without the slash command ("عندي فكرة…"), routes to `new-intent`, and the reply is Arabic. |
| `arabic-intent-reads-back` | behavior | An idea given in Arabic gets an Arabic read-back with a term list (موعد = appointment) before any `intent.md` is written. |
| `arabic-intent-written-in-english` | behavior | Once the read-back is confirmed, `intent.md` is written in English (keywords, prose, 0–9 digits), and the written file is translated back into Arabic in the chat. |
| `arabic-spec-keeps-user-text` | behavior | A spec drafted in Arabic is English, keeps the patients' Arabic SMS text as given, and translates Part 1 back. |
| `english-intent-no-translation` | behavior | An English conversation gets no language note, read-back translation or back-translation. |

## Reading the scores

**A prompt that starts with a slash command never calls the `Skill` tool.** The command expands the
skill straight into the prompt, so a `tool_used: Skill` grader reports 0 calls even when the skill
ran. The language cases start with `/sdlc-kit:new-intent` or `/sdlc-kit:new-spec` and don't use one;
read the trace to see the skill's steps instead.

**Judge a written file with `focus: {source: file, path: …}`, not `focus: trace`.** The judge's view
of a long trace can leave out the `Write` call, so it fails a file it never saw. The file path can't
be a glob, so a case that judges a file names its folder in the prompt (as
`arabic-intent-written-in-english` does).

The **Δ against the no-plugin baseline is not the goal here.** The base model already reviews a
document well, so a criterion like "asks good questions" scores about the same with and without the
plugin. What the plugin changes is *which* skill fires and whether the SDLC's gates hold, which the
`tool_used` graders and the behavior cases measure. Treat a Δ near zero on a judged criterion as
normal; treat a `tool_used` failure as a real regression.

**Write criteria for the first reply, not the finished job.** These cases are single-turn, and the
skills they test are interviews: the response under judgement is usually the first batch of questions,
before anything has been written. Three separate graders here failed correct behavior by demanding a
wrap-up — a recorded decision, a revisit month, a described diff — that the skill only reaches after
the user answers. Each time, reading the kept transcript showed the skill was right and the criterion
was wrong. State plainly in the criteria that ending on questions is acceptable, and judge invariants
("doesn't change the status", "doesn't claim a merge") rather than completeness.

The exception that proved worth keeping: `defer-outcome` genuinely needed the revisit month raised in
the first reply, because a deferral the user states and the skill never records is lost. That one was
a real bug, fixed in the skill. Tell the two apart by asking whether the missing thing can still
happen later in the conversation.
