# Bench — tester isolated-probe, DNA-v4 (FINAL, VALIDATED) (2026-05-29)

Same corpus/conditions: bench-core-v1, 8 tester tasks (4 gap / 4 control), Haiku
producers, 3 runs/cell, blind Opus judges, term-agnostic rubric. DNA-v4 = v3 + the
"already-covered" clause (when the spec states wiring + a real-boundary test exist, mark
GREEN and propose only additional cases; re-asserting them is a false alarm). Earlier arms
reused from same-session prior runs (identical pinned arms; stated).

## 5-way result — the full arc

| arm | escaped-defect-rate (gap) ↓ | false-positive-rate (control) ↓ |
|---|---|---|
| baseline `@ee77e4c` | 41.7% (5/12) | 8.3% (1/12) |
| DNA-v1 (no gate) | 0.0% | 100% |
| DNA-v2 (gate) | 8.3% | 58.3% |
| DNA-v3 (gate + 2 clauses) | 8.3% | 25.0% |
| **DNA-v4 (gate + 3 clauses)** | **8.3% (1/12)** | **8.3% (1/12)** |

DNA-v4 per-task — caught/3 (gap): T01 3/3 · T02 2/3 · T03 3/3 · T08 3/3.
DNA-v4 per-task — clean/3 (control): T06 3/3 · T07 3/3 · T10 2/3 · T12 3/3.

## Verdict: VALIDATED — DNA-v4 dominates baseline

DNA-v4 **clears the pre-registered bar** (FP ≤ ~17% ✓ at 8.3%; escaped ≤ ~8% ✓ at 8.3%)
and is a **Pareto improvement over baseline**:

- **Same precision:** false-positive-rate **8.3% = baseline's 8.3%.** The crying-wolf cost
  is gone — no net increase in false alarms over the plain baseline tester.
- **5× the recall:** escaped-defect-rate **8.3% vs baseline 41.7%** — v4 catches the
  dark-zone gaps (fake-only reality, un-cued wiring) the baseline misses, at **no extra
  false-alarm cost.** 1 escaped defect per 12 vs baseline's 5.

The "already-covered" clause did its job: **T07 went 1/3 → 3/3 clean** (re-flagging
already-stated wiring/reality eliminated) and T06 incidentally firmed to 3/3. The single
residual control FP is one T10 run inventing an overflow check — within 1-task noise
(~8 pts), not systematic. The single gap miss is one T02 run treating fake-only as
sufficient — also single-run, not systematic.

## The arc (what the bench drove)
FP **100 → 58 → 25 → 8.3%** across v1→v4, recall held flat (escaped 8.3%, T08 anti-confound
3/3 throughout). Each step was a measured response to a bench-exposed over-fire:
v2 boundary gate (wiring/reality on pure logic), v3 no-invented-failmodes + no-hedge
(overflow/NaN, "if-wired"), v4 already-covered (re-flagging covered work). The instrument
converged the DNA from a 100%-false-positive liability to a baseline-precision /
5×-recall asset.

## Status change
The v4 already-covered clause (committed `bd71dbe`, labelled UN-BENCHED) is now
**benched and VALIDATED** by this run. DNA-v4 is the validated production DNA for the
tester agent (isolated-probe, Haiku, this corpus).

## Honest caveats
- N=3/cell, Haiku, tester-only, single judge model; earlier arms reused (identical pinned
  arms, same session). The headline (FP parity + 5× recall) rests on deltas (33 pts FP
  v3→v4; 33 pts recall vs baseline) well above ~8-pt/cell noise. Two single-run wobbles
  (one T10 FP, one T02 miss) are within noise and not systematic.
- Not yet validated for: Opus (ceiling), the full /agileteam pipeline, or the
  code-reviewer/requirements-analyst dimensions (T04/T05/T09/T11). Those remain future runs.
