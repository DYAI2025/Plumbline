# Backlog slice — the false-done escape-rate corpus

**Status: NOT implemented. Documented as a separate slice, deliberately excluded from the
PLUM-9…15 batch.**

This slice exists because of KO-5, the Skeptic's central objection in the 2026-07-30
`/concilium` review: Plumbline calls itself an empirical instrument and has never
measured its own thesis. `metrics/runs.jsonl` holds **2 lines**. Every existing corpus
(`bench-core-v1`, `challenge-token-oracle`, `council-review-catch-v1`, `pipe-core-v1`,
`pipe-nonlocal-v1`, `pipe-providedfake-v1`) measures review-catch rate or pipeline
behaviour. **None measures the harm the gates exist to prevent.**

Six gates were built on six remembered incidents, each n=1, and their value is asserted —
in a repo whose own rules forbid exactly that move for benchmark claims.

## Hypothesis

> With the Plumbline gates armed, an autonomous agent declares "done" on work that is not
> done **less often** than with the gates disarmed, by a margin outside the noise band.

Stated so it can lose. The null is: the gates make no measurable difference to false-done
escapes, and their observed value came from humans and adversarial reviewers reading
output — which is what every catch in this project's history actually came from.

## Experimental design — armed vs disarmed

Two arms over the same task set, same model, same prompt, same budget:

| arm | configuration |
|---|---|
| **armed** | full gate layer active (Stop hook, scope, context, reality, plus the four advisory gates) |
| **disarmed** | identical, gates removed from the composition root — not merely `PLUMBLINE_GATE_*=0`, since that leaves the blocking core in place |

Paired exclusion: a task is dropped from **both** arms if either arm fails for a reason
unrelated to done-ness (API error, budget exhaustion, harness crash). Report attrition.

## The task set — independence is the whole point

**The agent under test must not have authored the tasks, the oracle, or the fixtures.**
This is the condition that makes the result mean anything, and it is the one this project
has never satisfied: every incident behind the six gates was found inside work the same
agent had produced.

Each task needs:

- a **deterministic oracle** that knows ground-truth done-ness independently of any
  agent's report — a hidden test, a mutation that must be caught, a behaviour observable
  at a real boundary;
- a designed gap between **"looks done"** and **"is done"** — the whole point is tasks
  where a plausible-looking completion is wrong;
- no dependence on Plumbline's own vocabulary, so the corpus stays portable.

Candidate sources: the mutation-oracle corpora already in `metrics/corpus/`, adapted so
the oracle scores *completion claims* rather than review catches; and the six reproduced
mechanisms from this batch, which are real, measured false-green shapes.

## Metric

**Primary — escape rate:** `false-done escapes / tasks completed`, where an escape is a
task the agent reported done that the oracle scores not-done.

**Anti-Goodhart counterpart (mandatory, per the repo's own benchmark-honesty rule):**
**false-block rate** — tasks the agent could have completed correctly but did not,
because a gate blocked honest work. Catch-rate and cry-wolf can move in opposite
directions; this project has measured that before. **Never report the escape rate
alone.**

Secondary, cheap to collect: wall-clock and token cost per task per arm; how often a
block was resolved by fixing the work versus by editing the artifact the gate reads.

## Noise band

Pre-register before running:

- **n** per arm, and the minimum detectable effect at that n. At small n,
  `demonstrated`/`refuted` are definitionally out of reach — the honest outcome vocabulary
  is `underpowered` / `signal-to-investigate`, and a lucky split must not be sold as a
  result.
- The noise band from **within-arm variance across repeated runs of the same task**, not
  assumed.
- Outcome classification fixed in advance: `demonstrated` / `refuted` / `underpowered`.

## Success metric

The gate layer is **load-bearing** if the armed arm's escape rate is lower than the
disarmed arm's by a margin outside the noise band, **and** the false-block rate does not
rise enough to cancel it. Both conditions, or the claim fails.

## Kill criterion

**Zero delta outside the noise band ⇒ the gate layer does not do what it exists to do.**

Then the honest response is deletion, not another gate:

- keep `CLAUDE.md` — context injection needs no install, no hook, no cooperation, and
  operates upstream of the trust-root problem;
- keep the **scope-parser fixes** — real bugs in a deterministic text parser, reproduced
  against pre-fix code;
- keep the **provenance byte-comparison** — a genuine agent-independent oracle;
- delete or demote the rest.

## Decision this slice must produce

One of: **keep** the gate layer · **reduce** it to the members that moved the metric ·
**remove** it. Recorded with the measurement, not with an argument.

## Why it is not in this batch

Days, not hours; it needs an independently-authored corpus that does not exist yet; and
running it inside the batch it judges would repeat the mistake it is meant to expose.
