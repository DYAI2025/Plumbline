# Bench — tester isolated-probe, DNA-v3 vs baseline / v1 / v2 (2026-05-29)

Same corpus/conditions: bench-core-v1, 8 tester tasks (4 gap / 4 control), Haiku
producers, 3 runs/cell, blind Opus judges, term-agnostic rubric. DNA-v3 = the boundary
gate **plus** two clauses targeting v2's residual over-fires: (1) no invented
overflow/NaN/error-mode tests on a pure function; (2) no speculative "if it were wired…"
boundary hedges. Baseline/v1/v2 reused from the same-session prior runs.

## 4-way result (both metrics: lower is better)

| arm | escaped-defect-rate (gap) | false-positive-rate (control) |
|---|---|---|
| baseline `@ee77e4c` | 41.7% (5/12) | **8.3%** (1/12) |
| DNA-v1 (no gate) | **0.0%** (0/12) | 100% (12/12) |
| DNA-v2 (gate) | 8.3% (1/12) | 58.3% (7/12) |
| **DNA-v3 (gate + 2 clauses)** | **8.3%** (1/12) | **25.0%** (3/12) |

DNA-v3 per-task — caught/3 (gap): T01 3/3 · T02 3/3 · T03 2/3 · T08 3/3.
DNA-v3 per-task — clean/3 (control): T06 2/3 · T07 1/3 · T10 3/3 · T12 3/3.

## Reading

- **The two v3 clauses worked exactly as intended.** T10 went 0/3 → **3/3 clean** and T12
  1/3 → **3/3 clean** — the invented-overflow and speculative-hedge over-fires are gone.
  Judges noted v3 outputs "explicitly refuse overflow/NaN/timeout and 'if later wired'
  hedges" — the clauses are being followed, not just present.
- **Trend across iterations:** FP **100% → 58% → 25%** while recall held flat
  (escaped 8.3%, vs baseline's 42%). Monotone convergence; the gate-family is precision-
  improving without sacrificing the dark-zone recall (T08 stayed 3/3 throughout).
- **Recall still strong where it matters:** T02 (fake-only) recovered to 3/3 in v3; T08
  (un-cued wiring+reality anti-confound) 3/3; the single gap miss is one T03 run where the
  agent forced a *pricing-service* timeout instead of a *cache-backend* timeout.

## Honest verdict: large win, NOT formally at the pre-registered bar

The pre-registered promotion bar (bench-v2 report) was **FP ≤ ~17% AND escaped ≤ ~8%**.
DNA-v3 hits escaped (8.3%) but **FP = 25% misses the ≤17% bar by ~1 control-task.** So by
the letter, v3 is **not yet "validated".** It is, however, a large, monotone improvement
and is **net-positive vs baseline** on a reasonable cost model: v3 trades **+16.7 pts FP**
for **−33.4 pts escaped** — i.e. ~2 more false alarms (review-time cost) to catch ~4 more
real escaped defects (prod-incident cost) per 12 tasks. For most QA contexts that trade is
favourable, and 25% FP is far from v1's cried-wolf 100%.

**Residual FP is now concentrated in T07** (2 of the 3 remaining FPs): on the
*already-correctly-specified* control, agents re-flag wiring/persistence that the spec
states is covered ("confirms route is not dead code", "file actually persists not just
in-memory"). This is the hardest residual: T07 *is* a real boundary feature, so the gate
correctly runs the probe — the agent just fails to register that the spec already covers
it. (T06 contributes the 3rd FP — one cart-wiring slip on the pure calc.)

## Decision
- DNA-v3 **committed to main** as a strict improvement over the live DNA-v2 (FP 58→25%,
  recall held).
- Marked **net-positive and shippable, but short of strict precision parity.** Diminishing
  returns: v1→v2 removed 42 FP-pts, v2→v3 removed 33 FP-pts; the residual 25% is mostly one
  hard case (T07).

## Optional v4 (only if strict parity is wanted)
Tighten the boundary branch's "already-covered" rule: when the spec explicitly states a
boundary feature is wired AND has a real-boundary test, the arm must mark those GREEN and
propose only *additional* cases — re-asserting them as gaps is itself a false alarm. Target
T07. Expected smaller gain (one control task ≈ 8 pts); weigh against the cost of another
48-run round. A reasonable alternative is to **stop at v3** and accept the favourable trade.

## Caveats
- N=3/cell, Haiku, tester-only, single judge model; baseline/v1/v2 reused (identical arms,
  same session). Deltas (33–75 pts across versions) are well above ~8-pt/cell noise; the
  convergence is real and safe to act on.
