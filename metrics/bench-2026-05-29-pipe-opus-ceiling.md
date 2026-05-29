# pipe-core-v1 — Opus CEILING (build tasks) (2026-05-29)

The strong-producer arm of the matrix. Question: does a more capable model change the
"no build-level differential" finding from the Haiku floor, or confirm it's model-robust?
3 build tasks × 2 arms × 2 runs on **Opus** (ceiling robustness pilot, N=2/cell — labelled)
+ the hardened mutation oracle (`mutate.py`, all `applied: True`).

## Result (Opus)

| task | baseline escaped | dna escaped |
|---|---|---|
| T08-account-deletion | 0/2 | 0/2 |
| T02-webhook | 0/2 | 0/2 |
| T03-overdraft-guard | 0/2 | 0/2 |

All 12 builds green; all 12 mutations applied and **caught** (red). **Escaped-defect-rate =
0% for both arms across every build task — no differential at the ceiling either.**

## Observation: the ceiling absorbs the DNA entirely
The Opus **baseline** arms (no DNA) wrote *even stronger* dark-zone guards unprompted than
Haiku did — e.g. a deterministic spy assertion "`store.delete_all` called exactly once with
the right user_id", composition-root reality tests, signature-tamper tests. A capable model
produces the guarding tests on its own, so the DNA's test-design nudges add nothing on top.
(The DNA arms also ran their Beat-0 gate and reality tests — same green outcome, no extra
caught defects.)

## Consolidated — floor + ceiling, model-robust

| dimension | metric | baseline | DNA-v4 | differential |
|---|---|---|---|---|
| Build T08/T02/T03 — **Haiku** | escaped-defect | 0% | 0% | none |
| Build T08/T02/T03 — **Opus** | escaped-defect | 0% | 0% | none |
| CTRL pure logic — Haiku | false-positive | 0% | 0% | none |
| RDIFF review — Haiku | non-wiring recall | 85% | 81% | none (noise) |

## Final verdict (bench arc complete)
The "no build-level differential" finding is now **robust across the Haiku floor and the
Opus ceiling**: on these tasks, both arms — at both capability levels — build increments
that guard the dark-zone behaviour, so the DNA produces **no measurable built-increment or
full-pipeline improvement**, and **no harm** (0% false-positives, no reviewer narrowing).
A stronger model *widens* this null by self-producing even better guards unprompted.

The DNA's measured, validated value is and remains confined to **test-PLAN derivation**
(bench-core-v1: FP parity + 5× recall). Everywhere the pipeline actually builds, tests, or
reviews — at either model tier — it is **precision-safe but outcome-neutral**. That is the
complete, multiply-replicated, model-robust, honest conclusion of the whole bench arc.

## Caveats
- Ceiling N=2/cell (floor was N=3); Opus build agents, 3 naturally-guarded features. The
  0%/0% rests on unanimous 12/12 caught, so the no-differential read is safe at this N.
- Still genuinely unrun: a LARGER/messier feature whose obvious acceptance test does NOT
  cover the dark zone — the one place a build-level differential could still hide. The
  corpus's tasks are all naturally-guarded; none showed a differential at either tier.
