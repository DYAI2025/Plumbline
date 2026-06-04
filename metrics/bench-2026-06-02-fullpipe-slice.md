# bench-2026-06-02 — full-pipeline powered slice (M4-Sub-B)

**Mode:** full_pipeline (faithful buried-gap build: tester→coder(shared)→code-reviewer→production-validator, blind-judged vs `bench-core-v1/rubric.md`).
**Arms:** `baseline@ee77e4c` vs `dna@HEAD` (pinned DNA agents: tester, code-reviewer, production-validator; coder shared). **Models:** haiku, opus. **Tasks:** T02 (fake-only-reality), T08 (wiring+fake-only-unannounced). **n = 3/cell × 2 tasks = 6 per (arm,model).**
**Cost:** 120 agents, 12.71M tokens, ~16 min. **Frozen human-gate inputs** (Canvas per task) so no gate was bypassed.

Stage ordinal: tester=1 · coder=2 · reviewer=3 · validator=4 · **missed=5** (lower = caught earlier).

| arm | model | n | mean_catch_stage | escaped_rate | stage histogram |
|---|---|---:|---:|---:|---|
| baseline | haiku | 6 | 4.67 | **0.67** | none×4, validator×2 |
| dna | haiku | 6 | 3.33 | **0.33** | tester×2, validator×2, none×2 |
| baseline | opus | 6 | 1.83 | 0.00 | tester×3, coder×2, validator×1 |
| dna | opus | 6 | 1.00 | 0.00 | tester×6 |

## Findings (n=6, directionally coherent; not full statistical confidence)
1. **Floor-raising on the weak model:** haiku escaped_rate baseline 0.67 → dna 0.33 (the DNA halves escapes where the model can't reliably reach the real boundary).
2. **Front-loading:** opus both arms escape 0, but dna catches at the test-plan stage 6/6 (mean 1.00) vs baseline mixed/later (1.83) — reproduces the prior "5× recall at test-planning" finding.
3. **Model capability dominates:** opus 0% escape both arms; haiku 33–67%. Consistent with the repo's measured "real-boundary catch is Opus-class."

## Caveats
- **Gap-only slice — no false-positive control**, so the anti-Goodhart net (catch-rate vs cry-wolf) is NOT established here; a higher catch could in principle come with more false positives (earlier probe showed controls clean, but not in this powered run).
- n=6 is modest power (the haiku 0.67→0.33 delta is 4-missed vs 2-missed).
- 2 tasks (both reality/boundary gaps), not the full corpus.

## Cost basis for the full matrix
~529k tokens/cell (full-pipeline). Full bench-core-v1 matrix = 12 tasks × 2 arms × 2 models × 3 runs = 144 cells ≈ **~76M tokens**, ~720 agents, multi-hour — and must add the control tasks (T06/T07/T09/T10/T12) to measure false_positive_rate.

> Per-cell raw verdicts: see workflow `wf_a4af4142-a90`. NOT recorded to `runs.jsonl` as an /agileteam baseline (this is a bench A/B, not a single-run record).

---

## Anti-Goodhart FP-control addendum (2026-06-02) — controls T06, T12

Same full-pipeline harness on pure-logic controls (no gap, no I/O boundary). n=3/cell × 2 tasks = 6 per cell; 120 agents; 11.1M tokens. Verdict = clean | false_positive (cry-wolf). Workflow `wf_bc7c1f82-a48`.

| arm | model | false_positive_rate | cry-wolf stage |
|---|---|---:|---|
| baseline | haiku | 0.00 | — |
| dna | haiku | 0.33 | reviewer ×2 |
| baseline | opus | 0.67 | validator ×4 |
| dna | opus | 0.17 | validator ×1 |

**Combined verdict:** DNA is **net-positive on Opus** (same catch, ~4× less cry-wolf: 67%→17%) and a **trade-off on sub-Opus** (escape 0.67→0.33 BUT false-positive 0.00→0.33). "Strictly better" is false. Cost levers (M7) must be gated on BOTH metrics. See `docs/benchmarks/2026-06-02-full-pipeline.md`.
