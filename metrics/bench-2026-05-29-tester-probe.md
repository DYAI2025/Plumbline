# Bench — tester isolated-probe, bench-core-v1 (2026-05-29)

**Mode:** isolated probe (per-agent A/B). **Agent:** tester. **Model:** Haiku 4.5.
**Arms:** baseline `core/tester.md @ee77e4c` vs DNA `@HEAD` (only diff: the
"Kritische semantische Glättung" + Reality-Ledger discipline). **Runs:** 3/cell.
**Tasks:** the 8 tester-targetable, non-file-dependent corpus tasks (4 gap + 4 control).
**Judging:** 8 independent **Opus** judges, blind to arm (outputs anonymized o1–o6 via a
fixed arm-mixed scramble), term-agnostic rubric. 48 producer runs + 48 judged verdicts.

## Headline

| Metric | baseline | DNA | delta | noise (~1 cell) |
|---|---|---|---|---|
| **escaped-defect-rate** (gap) ↓ | 41.7% (5/12) | **0.0%** (0/12) | **−41.7 pts** | ±8 pts |
| **false-positive-rate** (control) ↓ | 8.3% (1/12) | **100%** (12/12) | **+91.7 pts** | ±8 pts |

Both deltas are far above noise → **both are real signals.**

## Per-task (caught/clean out of 3 runs per arm)

| Task | class | baseline | DNA | read |
|---|---|---|---|---|
| T01 rate-limit wiring (de-cued) | gap | 3/3 ✅ | 3/3 ✅ | no differential — both catch it unprompted |
| T02 fake-only webhook reality | gap | 1/3 | 3/3 ✅ | **DNA catches**, baseline mostly misses |
| T03 cache failure-mode (named) | gap | 3/3 ✅ | 3/3 ✅ | no differential — requirement names the fallback |
| **T08 wiring+fake-only UNANNOUNCED** | gap | **0/3** | **3/3** ✅ | **the key result** — baseline fully blind, DNA fully catches |
| T06 pure-logic discount | control | 3/3 clean | **0/3** | DNA invents wiring/reality gaps |
| T07 already-wired CSV export | control | 3/3 clean | **0/3** | DNA re-flags already-covered wiring/reality |
| T10 pure formatter | control | 2/3 clean | **0/3** | DNA invents failure-mode/reality tests |
| T12 pure validation | control | 3/3 clean | **0/3** | DNA invents "never wired into form" gap |

## Honest verdict: the DNA, as written, does NOT win — it is net-negative on precision

Per bench-core-v1's own win criterion — *"lowers escaped-defect-rate WITHOUT raising
false-positive-rate beyond noise"* — the DNA **fails it**. It is a **high-recall,
low-precision** instrument: it trades a 41.7-pt recall gain for a 91.7-pt precision loss.

- **Where the DNA genuinely wins (recall):** exactly the dark-zone classes that sank the
  real sprint — **T08** (un-cued wiring + fake-only: baseline 0/3 → DNA 3/3) and **T02**
  (fake-only reality: 1/3 → 3/3). On the *anti-confound* task the baseline is fully blind
  and the DNA fully sighted. That is the real, valuable effect, and the controls prove it
  isn't just the corpus cueing it.
- **Where the DNA breaks (precision):** it cries wolf on **every control (12/12)**. The
  mandatory Gegenthese ("if you cannot construct a counter-thesis you have not understood
  the value — do not skip") **forces the agent to manufacture a wiring/reality concern even
  for a pure function** (duration formatter, discount calc, validation) and to re-flag
  already-covered features. Root cause is identifiable in the prompt text.

## What the bench proved about itself
A naive gaps-only bench would have reported "DNA: 41.7% → 0% escaped — ship it!" The
**controls are what revealed the 100% false-positive cost.** The anti-Goodhart design
worked: it caught a regression the earlier canary (no controls) structurally could not.

## Proposed fix (NEXT iteration — human-gated, not auto-applied)
Add a **boundary gate (beat 0)** to the kritische semantische Glättung, BEFORE the
Gegenthese: *"Does this feature actually cross a real boundary — I/O, remote, external API,
UI, or cross-component wiring? If NO → it is pure logic: skip the reality/wiring probe and
test the logic. Only run the Gegenthese/Reality-Ledger when a real boundary exists."*
Hypothesis: collapses T06/T10/T12 false positives (pure logic → gate skips) and T07
(already-covered → acknowledge), while preserving the T02/T08 catches (real boundaries →
gate fires). Re-bench after the fix; promote only if escaped-defect-rate stays low AND
false-positive-rate drops back toward baseline.

## Caveats (honest power)
- N=3/cell, Haiku only, tester-only (T04/T05/T09/T11 not in this probe). Opus ceiling and
  full-pipeline not run. Single judge model (Opus) per task — no judge-agreement check.
- The result is strong enough (deltas ≫ noise, consistent across 3 runs and 4 tasks/side)
  to act on: **do not promote the DNA as-is; fix the over-fire first.**
