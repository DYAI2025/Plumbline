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

## Honest next step
The **full powered baseline** (all 12 tasks incl. the false-positive controls × 2 arms × 2 models × n≥3 ≈ **~76M tokens**) is **not yet run**. Until it is, treat the above as a *directional* result, not a settled benchmark.
