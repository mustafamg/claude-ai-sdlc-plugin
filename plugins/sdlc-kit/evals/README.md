# evals/

Eval cases for the kit's skills, run with `claude plugin eval`. They exist mainly to check
**routing**: `/sdlc-kit:review-intent` and `/sdlc-kit:new-intent` describe adjacent work, and a
description change on either one can make the wrong skill fire.

## Running

```bash
claude plugin eval plugins/sdlc-kit --scaffold --model claude-sonnet-5 --judge-model claude-sonnet-5
```

- **`--scaffold` is required.** Three cases build their workspace with a `setup.sh` that copies
  `fixture/` (an intent folder) into it. Without the flag the workspace is empty, and the cases
  quietly test nothing.
- **Cases cost money.** Each one also runs a no-plugin baseline arm, and the `llm` graders call a
  judge model. The whole suite is roughly $2 on Sonnet. Add `--max-cost-usd` for a hard ceiling.
- `--tag trigger` runs just the routing cases; `--tag behavior` runs the rest.
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

## Reading the scores

The **Δ against the no-plugin baseline is not the goal here.** The base model already reviews a
document well, so a criterion like "asks good questions" scores about the same with and without the
plugin. What the plugin changes is *which* skill fires and whether the SDLC's gates hold, which the
`tool_used` graders and the behavior cases measure. Treat a Δ near zero on a judged criterion as
normal; treat a `tool_used` failure as a real regression.

Judge criteria are deliberately written to accept a response that stops mid-interview to ask the
first batch of questions. That's what `review-intent` is supposed to do, and an earlier version of
these criteria scored it as a failure for not wrapping up.
