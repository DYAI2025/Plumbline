# pipe-core-v1 — CTRL full-pipeline (pure-logic false-positive guard) (2026-05-29)

The pipeline-level false-positive control: a pure-logic discount calculator (no I/O, no
external service, no composition root). Measures whether the DNA's pipeline cries wolf —
invents a wiring/reality/external gap, marks RED-for-confidence, or BLOCKs a clean
increment. Full slice: build (tester DNA) → review gate (code-reviewer + product-owner DNA)
→ blind classify. Arms: baseline `@ee77e4c` vs DNA-v4 `@HEAD`. Haiku, 3 runs/arm.

## Result

| arm | CLEAN | FALSE_POSITIVE | verdicts | pipeline FP-rate |
|---|---|---|---|---|
| baseline | 3/3 | 0 | 3× SHIP | **0%** |
| dna (v4) | 3/3 | 0 | 3× SHIP | **0%** |

**No false positives, either arm.** Notably the DNA's machinery *engaged* and self-resolved
correctly: dna runs marked the wiring question "N/A" and one explicitly "judged the
reality-ledger low-risk and did not block." The v4 boundary gate concluded "pure → no
boundary" and shipped clean — confirming the precision fix holds in the FULL PIPELINE, not
just the isolated probe (bench-core-v1, where DNA-v1 had 100% FP on pure logic and v4 fixed
it to ~baseline).

## Consolidated pipe-core-v1 picture (Haiku, all dimensions run)

| dimension | metric | baseline | DNA-v4 | differential |
|---|---|---|---|---|
| T08 build (wiring+fake-only) | escaped-defect | 0% | 0% | none |
| T02 build (fake-only reality) | escaped-defect | 0% | 0% | none |
| T03 build (failure-mode guard) | escaped-defect | 0% | 0% | none |
| **CTRL (pure logic)** | **false-positive** | **0%** | **0%** | **none** |
| RDIFF-A/B/C (review)* | non-wiring recall | 85% | 81% | none (within noise) |

\* RDIFF measured in the separate reviewer-narrowing investigation (2026-05-29).

## Honest conclusion (full pipeline, complete)
On Haiku, across every pipe-core-v1 dimension, **DNA-v4 and baseline are statistically
indistinguishable at the pipeline level**:
- It does **not help** built-increment escaped-defects (the build forces the guarding test
  regardless of arm — threefold-replicated).
- It does **not hurt** precision: 0% pipeline false-positives on pure logic (the v4 gate
  holds end-to-end), and no reviewer narrowing.

The DNA's measured, validated value is confined to **test-PLAN derivation** (bench-core-v1:
FP parity + 5× recall). At the built-increment / full-pipeline level on these tasks it is
**precision-safe but outcome-neutral**. That is the complete, multiply-replicated, honest
verdict — neither the imposing win the harness's scale might suggest, nor a hidden harm.

## What remains genuinely unrun
- **Opus ceiling** (these runs were Haiku) — a stronger producer may absorb the DNA's
  value even more, or not; unmeasured.
- **Larger/messier features** where the obvious acceptance test does NOT cover the dark
  zone — the corpus's three were all naturally-guarded; a harder feature could in principle
  show a build-level differential. None of the three did.
Both are honest open edges, not claims.

## Caveats
N=3/cell, Haiku, single blind judge; review gate = code-reviewer+product-owner concatenated
(not the full multi-gate Phase-3). The 0%/0% results rest on unanimous 6/6 outcomes, so the
"no differential / no crying wolf" reading is safe at this N.
