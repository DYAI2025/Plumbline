# Free-only Council Diversity Probe — n=2 (2026-06-20)

The no-budget reframe of the powered run (#1). With no paid tokens, the original
"council vs **Claude**" question is unanswerable (a paid Claude baseline is impossible), so
this is honestly a **free-only diversity probe**: a single strong FREE model (baseline)
vs a council of distinct strong FREE families. A **real captured live run** against
OpenRouter; key loaded at runtime from `~/.openclaw/.env`, used only in the `Authorization`
header, **never** in this trace (leak-check = 0). Harness:
`config/claude/metrics/council_free_diversity_probe.py` (a separate probe that REUSES the
vetted 3a scorer + the 3b `run_arm_a`/`classify_outcome` read-only — it is NOT the frozen
3b instrument, which pins `council_presets.py` byte-unchanged and cannot be repointed).

> **What this probe IS.** A best-effort, **underpowered** (n=2) diversity probe + a
> free-tier reachability datapoint — NOT a value verdict, and NOT "vs Claude". At n=2 only
> `underpowered` / `tradeoff-signal-to-investigate` are reachable. ONE run, no re-roll.

## Reachability context (free-tier is intermittent)
Two reachability probes ~minutes apart returned **2/5** then **5/8** reachable — free-tier
rate-limits shift minute to minute. The pilot (`2026-06-20-council-measurement-pilot.md`)
hit **100% attrition**; this run hit **0%**. The model set below is the one reachable at
run time; reachability luck is itself a confound and the reason n must grow.

## Method
- **Arm A (baseline)** = `google/gemma-4-31b-it:free` (1 model, google family).
- **Arm B (council)** = `openai/gpt-oss-120b:free` + `nvidia/nemotron-3-super-120b-a12b:free`
  (2 distinct families, both distinct from the baseline → diversity gate satisfied).
- Both arms prompted in the **same** structured flag protocol; both parsed by the **same**
  `parse_flag_set`; council flags = the **union** of the two council models' flag-sets.
- Scored by the read-only deterministic 3a scorer against the frozen seeded-defect oracle.
- Pre-registered (`metrics/free-diversity-probe-prereg.json`): `min_survivors=2`, `mde=0.5`,
  corpus_hash-pinned to `sha256:fb5f22df…`.

## Captured result

| Field | Value |
|---|---|
| outcome | **`underpowered`** (catch-delta below MDE) |
| survivors | **2 / min 2** (0 attrition this run; 6/6 calls OK) |
| catch-delta (council − baseline) | **0.0** |
| cry-wolf-delta (council − baseline) | **+0.25** |
| leak-check | **0** |

| Task | Baseline (Gemma) | Council (GPT-OSS + Nemotron) |
|---|---|---|
| T1-auth-token | catch 1.0 · cry-wolf 0.0 (1 flag) | catch 1.0 · cry-wolf 0.0 (1 flag) |
| T2-pagination | catch 1.0 · cry-wolf 0.0 (2 flags) | catch 1.0 · cry-wolf **0.5** (4 flags) |

## Honest interpretation (a directional hint that leans AGAINST the council)
- **No catch advantage.** Both arms caught **100%** of seeded defects on both tasks. The
  catch-delta is **0** — but largely because the n=2 corpus is **saturated** for these
  strong models (a single free model already aces it). There is **no headroom** here to
  detect a council catch advantage; that requires HARDER tasks where a single model misses.
- **The council ADDED cry-wolf without adding catch** (+0.25, all from T2 where the
  2-model union produced 4 flags incl. 2 that hit no seeded defect, vs the baseline's 2
  clean flags). This is a directional hint of exactly the **"more reviewers → more noise"**
  failure mode the framework exists to detect — the council-union flag-volume asymmetry
  manifesting as false positives, not catches. It leans *against* the naive
  "council is strictly better" hypothesis.
- **`underpowered`, not a verdict.** Per the frozen rubric the catch-delta (0) is below the
  MDE (0.5) → `underpowered`; the cry-wolf signal is a *direction to investigate at power*,
  not a result. A lucky 2/2 split is **not** sold as `demonstrated`.

## What this DOES establish
- The measurement mechanism runs end-to-end on **free** models (0 attrition this run; both
  arms produced real, scoreable structured reviews) — a `real-boundary-smoke`.
- A concrete corpus-design finding for the powered run: **the current corpus is too easy**
  (ceiling at 100% catch) to discriminate baseline vs council — the powered run needs
  harder, single-model-defeating tasks.

## Honest ceiling / carried to the powered run
n=2, NOT vs Claude (baseline is free Gemma), saturated corpus, favorable reachability luck
this run, and the council-union vs single-baseline flag-volume asymmetry (disclosed). The
real value verdict still needs: a Claude baseline (paid), corpus expansion with headroom
(n ≫ 2, harder tasks), presets A/B/C, and the same frozen-line discipline. Distinct free
model ids are an outcome delta only, never proven cognitive diversity (RISK-B-007).
