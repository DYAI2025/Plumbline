# Full-pipeline benchmark — 2026-06-02 (powered slice)

> **Plumbline's rule: don't claim, prove — *and* state exactly what you did NOT prove.**
> This is an **n=6 slice**, not a full baseline. Read the caveats before the numbers.

## What this measured

A faithful **full-pipeline** A/B: for each task we ran a buried-gap build —
`tester → coder (shared) → code-reviewer → production-validator` — under two pinned
agent-prompt **arms**, then an independent **blind judge** scored whether the planted
gap was caught *anywhere* in the build, against the frozen `bench-core-v1/rubric.md`.

- **Arms:** `baseline @ ee77e4c` (the v3 agents) vs `dna @ HEAD` (the evolved reality-ledger agents). Pinned DNA agents: `tester`, `code-reviewer`, `production-validator`; the `coder` is shared (identical both arms).
- **Models:** `haiku` (weak) and `opus` (strong) — to measure floor-raising vs ceiling.
- **Tasks:** `T02` (fake-only-reality: only a fake `HttpClient` exists) and `T08` (wiring+fake-only, unannounced).
- **n = 3 runs/cell × 2 tasks = 6 datapoints per (arm, model).**
- **Human gates** were satisfied by a *frozen, pre-authored* Product Canvas per task (identical across arms) — no gate was bypassed.
- **Cost:** 120 sub-agents, **12.71M tokens**, ~16 min.

Stage ordinal (lower = caught earlier): `tester=1 · coder=2 · reviewer=3 · validator=4 · missed=5`.

## Results

| arm | model | n | mean_catch_stage | escaped_rate | where it caught |
|---|---|---:|---:|---:|---|
| baseline | **haiku** | 6 | 4.67 | **0.67** | none ×4, validator ×2 |
| dna | **haiku** | 6 | 3.33 | **0.33** | tester ×2, validator ×2, none ×2 |
| baseline | opus | 6 | 1.83 | 0.00 | tester ×3, coder ×2, validator ×1 |
| dna | opus | 6 | **1.00** | 0.00 | **tester ×6** |

### Three coherent signals
1. **Floor-raising on the weak model.** On `haiku`, the DNA **halved the escape rate** (0.67 → 0.33): a third of the otherwise-undetected boundary defects were rescued by the reality-ledger discipline.
2. **Front-loading.** On `opus` both arms escaped 0, but the DNA caught **at the test-planning stage in 6/6 runs** (mean 1.00) vs the baseline's later/mixed catch (1.83). This reproduces the project's earlier "5× recall at test-planning" finding.
3. **Model capability dominates.** `opus` 0% escape on both arms; `haiku` 33–67%. Consistent with the project's measured "real-boundary catch is Opus-class."

## Caveats — what this does NOT prove (read these as load-bearing)
- **Gap-only slice — no false-positive control.** Both tasks are planted gaps. A higher catch-rate must be weighed against crying wolf; this run **cannot** establish that the DNA's catch-gain isn't partly bought with more false positives. (A separate probe showed controls clean, but that is not in this powered run.)
- **n = 6 is modest power.** The headline `haiku` delta is 4-missed vs 2-missed — directionally clear and *internally coherent* (unlike the n=1 pilots), but **not full statistical confidence**. No p-value or MDE is claimed.
- **2 tasks, both reality/boundary gaps** — not the whole 12-task corpus.
- **No plain-mode arm.** Both arms use the agentic framework (the variable is the agent prompts). This run does **not** measure "framework vs no framework."

## Reproduce
Arms are git refs: `git show ee77e4c:core/tester.md` (baseline) vs `git show HEAD:core/tester.md` (dna), likewise `code-reviewer.md`, `testing/validation/production-validator.md`; shared `core/coder.md`. Rubric: `metrics/corpus/bench-core-v1/rubric.md`. Full per-cell verdicts: workflow `wf_a4af4142-a90`. Raw record: `metrics/bench-2026-06-02-fullpipe-slice.md`.

## The anti-Goodhart false-positive controls — RUN (2026-06-02)
A catch-rate is only half the ledger; the corpus's **anti-Goodhart law** is explicit: *a high catch-rate bought with a high false-positive-rate is not an improvement.* So we ran the same full-pipeline harness on the **pure-logic control tasks** — T06 (discount calculator) and T12 (signup validation), features with **no** planted gap and **no** I/O boundary — and a blind judge scored each arm's **false-positive ("cry-wolf") rate** (n=3/cell × 2 tasks = 6 per cell; 120 agents; 11.1M tokens).

| arm | model | n | false_positive_rate | cry-wolf stage |
|---|---|---:|---:|---|
| baseline | haiku | 6 | 0.00 | — |
| dna | haiku | 6 | 0.33 | reviewer ×2 |
| baseline | opus | 6 | 0.67 | validator ×4 |
| dna | opus | 6 | 0.17 | validator ×1 |

### Combined ledger (catch + cry-wolf) → the honest verdict
| arm | model | escaped_defect_rate (gaps) | false_positive_rate (controls) |
|---|---|---:|---:|
| baseline | haiku | 0.67 | 0.00 |
| dna | haiku | 0.33 | 0.33 |
| baseline | opus | 0.00 | 0.67 |
| dna | opus | 0.00 | 0.17 |

- **On Opus the DNA is a clean win:** same perfect catch (escape 0) with **~4× less cry-wolf (67% → 17%)** — the "fire only on genuine boundary features, never on pure logic" reflex fixes the frozen validator's chronic over-firing.
- **On sub-Opus (Haiku) the DNA is a trade-off:** it halves escapes (0.67 → 0.33) **but raises false positives (0.00 → 0.33)**. The catch-gain on the weak model is partly bought with over-sensitivity — *the "no over-sensitivity" hope is partially falsified here.*
- **Counterintuitive:** Opus cries wolf *more* than Haiku on pure logic (baseline 67% vs 0%) — the stronger model over-applies the reality discipline where no boundary exists.

**Net:** "strictly better" is false; **net-positive on Opus, a trade-off on sub-Opus** is the measured truth. (Caveats unchanged: n=6, 2 control tasks, judge-dependent.)

## Honest next step
The **full powered baseline** (all 12 corpus tasks × 2 arms × 2 models × n≥3 ≈ **~76M tokens**) would tighten these directional numbers. And any cost-optimization (the M7 risk-router / digest-broker) must be gated on **both** metrics — catch *and* cry-wolf, never catch alone — precisely because this run showed the two can move in opposite directions.
