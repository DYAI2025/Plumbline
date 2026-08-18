# Investigation — does the v4 code-reviewer "wired-in-prod" check NARROW review? (2026-05-29)

## Why
The T08 pipeline data point (N=1/arm) showed baseline reviewer BLOCK (caught
error-handling/ordering/audit) vs v4 reviewer SHIP (its wired-in-prod check passed →
declared done). Hypothesis: the DNA's wired-in-prod bullet narrows the reviewer, crowding
out broader scrutiny. N=1 with high-variance review output could equally be noise — so:
a controlled replication.

## Design (falsifiable)
- Arms: code-reviewer `@ee77e4c` (baseline) vs `@HEAD` (v4 — adds the docstring-lie +
  wired-in-prod bullets, nothing else).
- 3 diffs, each **correctly wired** (the wired-in-prod check PASSES — no wiring gap to
  find), each carrying **3 planted NON-wiring defects** (the dimension narrowing would
  hurt):
  - A: account-deletion file cleanup — D1 no error-handling/transaction, D2 DB-before-
    cleanup ordering, D3 no audit log.
  - B: password reset — D1 non-crypto RNG token, D2 no token expiry, D3 token returned to
    caller (account takeover).
  - C: CSV order export — D1 CSV/formula injection, D2 broken access control (exports all
    users' orders), D3 unbounded/DoS.
- 3 diffs × 2 arms × 3 runs = 18 reviews (Haiku), blind-judged (Opus) against the hidden
  planted-defect lists. Metric: **non-wiring defect recall** + block-rate per arm.
- Narrowing predicts v4 catches FEWER non-wiring defects and/or ships more. Null predicts
  no difference.

## Result

| arm | non-wiring defect recall | block-rate |
|---|---|---|
| baseline | 23/27 = 85.2% | 8/9 |
| v4 (DNA) | 22/27 = 81.5% | 8/9 |

Per-diff defect recall (caught of 9 each): A baseline 6 / v4 5 · B 9 / 9 · C 8 / 8.

## Verdict: narrowing NOT supported — the N=1 was noise

- The arms are **statistically indistinguishable**: 23 vs 22 of 27 (a **1-defect** gap,
  ≈4 pts, within ~1-item noise) and an **identical 8/9 block-rate**. On the security-heavy
  diffs B and C the arms are equal (9/9, 8/8) and block 100%.
- The T08 "v4 SHIP / baseline BLOCK" did **not** replicate. The only place v4 dipped was
  one diff-A run catching 1 instead of 2 — and diff A is exactly the borderline case
  (audit/ordering, not hard security) where BOTH arms show SHIP/BLOCK variance (baseline
  itself shipped one diff-A run). The earlier single point was stochastic, not a real
  narrowing effect.
- Shared blind spot (not a DNA difference): D3-audit on diff A was caught by neither arm
  in any run — a gap in both reviewers, orthogonal to the DNA.

## What this means
The feared regression from the pipeline data point **does not hold up under replication**.
The v4 code-reviewer's wired-in-prod check does **not** crowd out broader review: on
correctly-wired diffs laden with security/robustness defects it catches the same
non-wiring issues as baseline and blocks at the same rate. This both clears the DNA of the
narrowing charge AND re-demonstrates the core discipline — a single data point (the T08
SHIP) must never be trusted; the controlled N=9/arm refutes it.

## Caveats
- N=3 runs/diff/arm (9/arm total); Haiku reviewers, Opus blind judge; 3 diffs. Enough to
  rule out a LARGE narrowing effect (none seen); a subtle <1-defect effect can't be
  resolved at this N and isn't worth chasing. Does not isolate which v4 bullet (docstring
  vs wired-in-prod) — moot, since no harmful effect was found.
