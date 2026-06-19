# council-review-catch-v1 — the review-catch measurement SUBSTRATE (Slice 3a)

## What this corpus IS

A FROZEN, council-INDEPENDENT review-catch corpus: a small set of code diffs, each
carrying

- a **seeded-defect oracle** (the catch truth) — defects planted at authoring time,
- a **clean-control region** (the cry-wolf truth) — defect-free code where any flag is
  a false positive,
- a **recall / no-narrowing control** — correct in-scope code that a narrowing reviewer
  might wrongly flag.

It is the input to the shared, judge-free flag-set scorer
`config/claude/metrics/council_review_scorer.py`, which scores ANY reviewer's flag-set
(Arm A = Claude-only via `config/claude/metrics/arm_a_review_runner.py`; Arm B = the
foreign council via the read-only instrument `config/claude/lib/deepseek_review.py`)
against this oracle and reports BOTH metric families together.

- Primary metric: `review_catch_rate`
- Secondary metrics: `review_cry_wolf_rate`, `review_recall_control`

The matching rule (OQ-DM-7) is a **deterministic FILE + LINE-RANGE OVERLAP** (inclusive
endpoints; a touch counts; wrong file is a miss; one flag matches at most one defect) —
no LLM judge for the primary.

## What this corpus IS NOT

- It is **NOT a measurement number.** Slice 3a builds the instrument; the
  foreign-vs-Claude review-catch comparison is **Slice 3b** (backlog BL-DM-002).
- It does **NOT reuse** `pipe-providedfake-v1` (a single task, no clean/recall control)
  or any existing corpus as the catch+cry-wolf+recall primary (BLOCKER-1 / NGOAL-DM-012).

## Real variance (BLOCKER-2)

The two tasks carry DISTINCT defect counts — `T1-auth-token` has 1 seeded defect,
`T2-pagination` has 2 — so under a fixed reviewer policy the per-task catch outcomes
differ (>=2 distinct outcomes). This is not a single saturated task; it lets Slice 3b
pin a noise threshold + minimum detectable effect. "Underpowered -> unmeasurable" is a
DISTINCT outcome from "refuted" in 3b — never laundered as a published null.

## NGOAL-DM-003 — the Goodhart tripwire (baked in)

This corpus is authored **INDEPENDENTLY of the council and is NEVER tuned to flatter any
arm.** Each defect was seeded BEFORE and independent of any review, from a known
anti-pattern — not selected because a model caught or missed it. The corpus is FROZEN
and version-stamped (`corpus_id` + a content `hash` over `oracle.json` + `diffs/` in
`manifest.json`).

> Tripwire: if any future change selects or drops diffs because of a model's catch/miss
> profile, the corpus is compromised and the measurement is Goodharted. Re-freeze from
> independent provenance instead of editing toward a result.

Verify the freeze:

```bash
python3 config/claude/metrics/council_review_scorer.py freeze-hash \
    --corpus metrics/corpus/council-review-catch-v1
# must equal manifest.json "hash"
```

## Layout

```
manifest.json            corpus_id, version, content hash, task index, provenance, variance note
oracle.json              machine-readable seeded-defect / clean-control / recall oracle (the matcher input)
diffs/<task-id>.md       the code diff under review (with the seeded defects)
oracles/<task-id>.md     human-readable oracle companion (mirrors the pipe-core-v1 idiom)
README.md                this file
```
