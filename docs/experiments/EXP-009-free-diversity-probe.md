# EXP-009 — Free-only Council Diversity Probe (n=2)

- **Date:** 2026-06-20
- **Kind:** Experiment (hypothesis-driven), best-effort + **underpowered**
- **Status:** complete (one run, no re-roll) — a directional hint, NOT a verdict
- **Source artifacts:** `docs/benchmarks/2026-06-20-free-diversity-probe.md` ·
  `config/claude/metrics/council_free_diversity_probe.py` ·
  `metrics/free-diversity-probe-prereg.json` · `docs/reality/free-diversity-probe.evidence.jsonl`

## Hypothesis
Does a multi-model **free** council catch more seeded review defects than a single strong
**free** model, without raising cry-wolf? (The no-budget reframe of EXP-008 — with no paid
tokens this is NOT "council vs Claude"; the baseline is a free model.)

## Pre-registration
`metrics/free-diversity-probe-prereg.json`, frozen before the run: baseline
`google/gemma-4-31b-it:free`; council `openai/gpt-oss-120b:free` +
`nvidia/nemotron-3-super-120b-a12b:free` (2 distinct families, distinct from baseline);
corpus `council-review-catch-v1` (hash `sha256:fb5f22df…`); `min_survivors=2`, `mde=0.5`;
at n=2 only `underpowered`/`tradeoff-signal` reachable.

## Method
Both arms in the same structured flag protocol, same `parse_flag_set`; council flags =
union of the two council models' sets; deterministic 3a scorer vs the seeded-defect oracle.
A separate probe harness that reuses the vetted primitives read-only (NOT the frozen 3b
instrument). Key header-only; one run, no re-roll.

## Results (both metrics together)
- outcome **`underpowered`**; survivors **2/2** (0 attrition; 6/6 calls OK); leak-check 0.
- **catch-delta 0.0** — both arms caught 100% on both tasks.
- **cry-wolf-delta +0.25** — council added false positives (T2: 4-flag union incl. 2
  non-defects vs baseline's 2 clean flags) with no catch gain.

## Honest interpretation
No catch advantage — but the n=2 corpus is **saturated** (100% ceiling), so there is no
headroom to detect one. The council **added cry-wolf without adding catch** — a directional
hint of the "more reviewers → more noise" failure mode, leaning *against* the naive
council-is-better hypothesis. `underpowered` (catch-delta below MDE), so NOT a verdict; the
cry-wolf signal is a direction to investigate at power, never sold as `demonstrated`.

## What it establishes
The measurement runs end-to-end on free models (real scoreable reviews; 0 attrition this
run, vs the pilot's 100%) — a `real-boundary-smoke`. Corpus-design finding: the corpus is
too easy to discriminate the arms; the powered run needs harder, single-model-defeating
tasks.

## Limitations / carried
n=2; NOT vs Claude (free baseline); saturated corpus; favorable free-tier reachability this
run (intermittent — see the pilot's 100% attrition); council-union vs single-baseline
flag-volume asymmetry disclosed. The value verdict needs: a paid Claude baseline, corpus
expansion with headroom, presets A/B/C, the frozen-line discipline. Distinct free model ids
are an outcome delta only, never proven cognitive diversity (RISK-B-007). See EXP-008 for
the still-pending powered vs-Claude run.
