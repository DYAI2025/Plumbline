# Bench — tester isolated-probe, DNA-v2 (boundary gate) vs baseline & DNA-v1 (2026-05-29)

Same corpus/conditions as `bench-2026-05-29-tester-probe.md`: bench-core-v1, 8 tester
tasks (4 gap / 4 control), Haiku producers, 3 runs/cell, blind Opus judges, term-agnostic
rubric. This run measured **DNA-v2** = DNA + a new **Beat-0 boundary gate** ("does this
feature cross a real boundary? pure → skip the reality/wiring probe; boundary → run it").
Baseline & DNA-v1 numbers are from the same-session prior run (baseline arm is
byte-identical; reuse stated for honesty).

## 3-way result (both metrics: lower is better)

| arm | escaped-defect-rate (gap) | false-positive-rate (control) |
|---|---|---|
| baseline `@ee77e4c` | 41.7% (5/12) | **8.3%** (1/12) |
| DNA-v1 (no gate) | **0.0%** (0/12) | 100% (12/12) |
| **DNA-v2 (boundary gate)** | 8.3% (1/12) | **58.3%** (7/12) |

Per-task DNA-v2 — caught/3 (gap): T01 3/3 · T02 2/3 · T03 3/3 · T08 3/3.
Per-task DNA-v2 — clean/3 (control): T06 2/3 · T07 2/3 · T10 0/3 · T12 1/3.

## Reading

- **The gate is a real, measured improvement over DNA-v1:** false positives **halved**
  (100% → 58.3%) while recall stayed near-perfect (escaped 0% → 8.3%, one T02 slip). On
  every practical axis v2 dominates the currently-live v1.
- **It did NOT reach parity.** 58.3% FP is still **+50 pts** over baseline's 8.3% — far
  above noise. By bench-core-v1's win criterion ("lower escaped WITHOUT raising FP beyond
  noise") **DNA-v2 still does not win.** The gate is progress, not victory.
- **Where the gate worked:** T06 (3→1 FP) and T07 (3→1 FP) — the wiring/reality over-fire
  on pure-logic and already-covered features largely collapsed, as designed.
- **Two residual over-fire modes the gate does NOT cover:**
  1. **T10 (3/3 FP):** agents invent *overflow / NaN / Infinity "graceful error"*
     failure-mode tests on a pure duration formatter. This is the **failure-mode
     detector** over-firing — orthogonal to the wiring/reality gate.
  2. **T12 (2/3 FP):** speculative **conditional hedge** — "IF validation is later wired
     into a form, that's a boundary needing an E2E test" — injected into a feature the
     spec explicitly scoped as pure.
- **Recall preserved where it matters:** T08 (the un-cued wiring+fake-only anti-confound)
  stayed 3/3 caught, and T02 2/3. The gate did not blunt the genuine dark-zone catch.

## Decision
- DNA-v2 **committed to main** as a strict interim improvement over the live DNA-v1
  (halved FP, recall preserved). It is **not** the final state.
- **NOT yet promoted as "validated"** — it fails the precision-parity bar.

## Proposed v3 (next iteration — targets the two residual modes)
1. Extend the **pure** branch: "for a total pure function, do NOT invent
   degradation/overflow/NaN/error-injection failure-mode tests unless the spec implies
   them; test only the stated logic + its real input domain." (kills T10)
2. Forbid **speculative boundary hedges**: "do not add 'if this were wired into X…'
   boundary/E2E tests for a feature the spec scopes as pure; if wiring is genuinely
   in-scope the spec will say so." (kills T12)
Re-bench after v3; promote to "validated" only when FP returns toward baseline (≤ ~17%,
i.e. within ~1 task of baseline) AND escaped stays ≤ ~8%.

## Honest caveats
- N=3/cell, Haiku, tester-only; single judge model. Baseline/DNA-v1 reused from the
  same-session prior run (identical baseline arm). Deltas (50+ pts) are well above the
  ~8-pt/cell noise, so the "gate helps but doesn't fully fix" conclusion is safe to act on.
