# EXP-002 · Full-pipeline DNA A/B (powered n=6 slice)

**ID:** EXP-002 · **Date:** 2026-06-02 · **Kind:** Experiment (full-pipeline A/B) ·
**Status:** complete (slice, not full baseline).

This is the run that put **both** anti-Goodhart metrics on the table in one experiment and
produced the register's blunt headline: **"strictly better" is false.** It extends
[EXP-001](EXP-001-dna-model-capability-qa.md) from test-planning to the whole build pipeline,
and adds the cry-wolf control arm EXP-001's build layer lacked.

## Hypothesis

The reality-ledger DNA (evolved `tester` / `code-reviewer` / `production-validator`) catches
buried boundary gaps *anywhere in the build* better than the v3 baseline agents — and (the
hope being tested) does so **without** raising false positives on clean code.

## Method

A faithful **full-pipeline** A/B: per task, a buried-gap build —
`tester → coder (shared) → code-reviewer → production-validator` — ran under two pinned
agent-prompt arms, then an independent **blind judge** scored whether the planted gap was
caught *anywhere*, against the frozen `bench-core-v1/rubric.md`.

- **Arms:** `baseline @ ee77e4c` (v3 agents) vs `dna @ HEAD` (reality-ledger agents). Pinned:
  `tester`, `code-reviewer`, `production-validator`; the `coder` is **shared** (identical both
  arms).
- **Models:** `haiku` (floor) and `opus` (ceiling).
- **Gap tasks:** `T02` (fake-only reality) and `T08` (wiring + fake-only, unannounced).
- **Control tasks (cry-wolf):** `T06` (discount calculator) and `T12` (signup validation) —
  pure logic, no planted gap, no I/O boundary.
- **n = 3 runs/cell × 2 tasks = 6 datapoints per (arm, model)** — for each of catch and
  cry-wolf.
- **Human gates** satisfied by a frozen pre-authored Product Canvas per task (identical
  across arms) — no gate bypassed.
- **Cost:** gap run 120 sub-agents, 12.71M tokens, ~16 min; control run 120 agents, 11.1M
  tokens. Stage ordinal: tester=1 · coder=2 · reviewer=3 · validator=4 · missed=5.

## Results (as captured — BOTH metrics)

**Catch (escaped-defect rate on the gap tasks):**

| arm | model | n | mean_catch_stage | escaped_rate | where it caught |
|---|---|---:|---:|---:|---|
| baseline | haiku | 6 | 4.67 | **0.67** | none ×4, validator ×2 |
| dna | haiku | 6 | 3.33 | **0.33** | tester ×2, validator ×2, none ×2 |
| baseline | opus | 6 | 1.83 | 0.00 | tester ×3, coder ×2, validator ×1 |
| dna | opus | 6 | **1.00** | 0.00 | **tester ×6** |

**Cry-wolf (false-positive rate on the control tasks):**

| arm | model | n | false_positive_rate | cry-wolf stage |
|---|---|---:|---:|---|
| baseline | haiku | 6 | 0.00 | — |
| dna | haiku | 6 | 0.33 | reviewer ×2 |
| baseline | opus | 6 | 0.67 | validator ×4 |
| dna | opus | 6 | 0.17 | validator ×1 |

**Combined ledger (the honest verdict):**

| arm | model | escaped_defect_rate (gaps) | false_positive_rate (controls) |
|---|---|---:|---:|
| baseline | haiku | 0.67 | 0.00 |
| dna | haiku | 0.33 | 0.33 |
| baseline | opus | 0.00 | 0.67 |
| dna | opus | 0.00 | 0.17 |

## Honest interpretation

- **On Opus the DNA is a clean win:** same perfect catch (escape 0) with **~4× less cry-wolf
  (0.67 → 0.17)** — the "fire only on genuine boundary features" reflex fixes the frozen
  validator's chronic over-firing.
- **On sub-Opus (Haiku) the DNA is a tradeoff:** it **halves escapes (0.67 → 0.33) but raises
  false positives (0.00 → 0.33)**. The catch-gain on the weak model is partly bought with
  over-sensitivity — *the "no over-sensitivity" hope is partially falsified here.*
- **Counterintuitive:** Opus cries wolf *more* than Haiku on pure logic at baseline (0.67 vs
  0.00) — the stronger model over-applies the reality discipline where no boundary exists.
- **Front-loading reproduced:** on Opus the DNA caught at the test-planning stage in 6/6 runs
  (mean 1.00) vs baseline's later/mixed 1.83 — consistent with EXP-001's "5× recall at
  planning."
- **Net:** **"strictly better" is false. Net-positive on Opus, a tradeoff on sub-Opus** is the
  measured truth.

**What it does NOT show:** no statistical confidence (no p-value, no MDE claimed); not the
whole 12-task corpus; not a framework-vs-no-framework comparison (both arms use the framework).

## Limitations / confounds

- **n=6 is modest power.** The headline Haiku catch delta is 4-missed vs 2-missed —
  directionally clear and internally coherent (unlike the n=1 pilots), **not** full
  statistical confidence.
- **2 gap tasks, 2 control tasks** — both gap tasks are reality/boundary gaps; not the full
  corpus spread.
- **Judge-dependent** — catch/cry-wolf are scored by a blind judge.
- **No plain-mode arm** — the variable is the agent prompts, not "framework vs none."

## What we learned

- Any cost-optimization lever (the M7 risk-router / digest-broker) must be gated on **both**
  metrics — catch *and* cry-wolf, never catch alone — **precisely because this run showed the
  two can move in opposite directions.**
- The full powered baseline (12 tasks × 2 arms × 2 models × n≥3 ≈ ~76M tokens) would tighten
  these directional numbers; it has not been run.

## Evidence class

Full-pipeline A/B with blind judge, **n=6 per cell** for each of catch and cry-wolf,
2 model tiers. Directional and internally coherent; explicitly **not** a powered baseline.

## Source artifacts (read before writing)

- [`docs/benchmarks/2026-06-02-full-pipeline.md`](../benchmarks/2026-06-02-full-pipeline.md)
  — all numbers above traced here (both the catch table and the cry-wolf control table).
- Raw record: [`metrics/bench-2026-06-02-fullpipe-slice.md`](../../metrics/bench-2026-06-02-fullpipe-slice.md).
- Arms are git refs: `git show ee77e4c:core/tester.md` (baseline) vs `git show HEAD:core/tester.md` (dna).
- Rubric: `metrics/corpus/bench-core-v1/rubric.md`. Per-cell verdicts: workflow `wf_a4af4142-a90`.
</content>
