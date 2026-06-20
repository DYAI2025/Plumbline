# EXP-008 (PENDING) · Powered council-measurement run — does the foreign council catch what Claude misses?

**ID:** EXP-008-PENDING · **Date:** 2026-06-20 (pilot run) · **Kind:** Experiment ·
**Status:** **PENDING — no value result yet.** The n=2 pilot below is complete and came back
`underpowered`; the powered run it informs is **pre-registered but not yet executed.**
Branch `agileteam/council-measurement-run`. Slice 3b. REQ-MR-005/007/010.

This is the open, central value hypothesis of the whole council line of work — and we are
explicit that it is **not answered.**

## The open hypothesis

**Does the foreign (non-Claude) council catch defects that a Claude-only review misses, without
raising cry-wolf?** Both anti-Goodhart metrics must move the right way for any "the council adds
value" claim. The capability to run the council live is proven (SMK-007); whether it *adds
value* is this experiment's question, and it is unanswered.

---

## Part A — the n=2 PILOT (complete, `underpowered`)

### What the pilot IS (binding honesty frame)

A **run-mechanism real-boundary-smoke** + a **cost/flakiness estimate** — **NOT a value
verdict.** At n=2 the cross-task variance is unestimable, so `demonstrated` and `refuted` are
**definitionally out of reach**; the only reachable pilot outcomes are `underpowered` and
`tradeoff-signal-to-investigate`. The value question is **not answered here.**

### Method (real captured live run)

`config/claude/metrics/council_measurement_run.py run --corpus
metrics/corpus/council-review-catch-v1 --preset A --claude-model anthropic/claude-haiku-4.5
--pre-registration metrics/pre-registration-council-measurement-run.json --max-calls 10 --live
--score`. Gated by `COUNCIL_INFERENCE_LIVE=1` + a user-named `--max-calls 10` ceiling. Key from
`~/.openclaw/.env`, header-only, never in trace.

- **Arm A** = Claude-only review on `anthropic/claude-haiku-4.5` (paid; cheapest current Claude,
  live-verified in the catalog before the run).
- **Arm B** = preset-A council on resolved **free** foreign models.
- Both arms prompted in the **same** structured-flag protocol, scored by the **same** parser
  (arm symmetry).

### Pre-registration (frozen before the scored run)

From [`metrics/pre-registration-council-measurement-run.json`](../../metrics/pre-registration-council-measurement-run.json),
`frozen_at: 2026-06-20T00:00:00Z`:
`n: 2`, `min_survivors: 2`, `mde: 0.5`, `noise_model: cross-task-variance`,
`corpus_id: council-review-catch-v1`, `corpus_hash: sha256:fb5f22df…fb92`. The rubric states
verbatim that at n=2 `demonstrated`/`refuted` are out of reach and only `underpowered` /
`tradeoff-signal-to-investigate` are selectable. The pass/fail line is judged against this file
and **never moved after seeing results.**

### Results (as captured)

| Field | Value |
|---|---|
| outcome | **`underpowered`** |
| survivors | **0 / min 2** |
| calls attempted | **4** (≤ the 10 ceiling) |
| attrition | T1-auth-token → `COUNCIL_RATE_LIMITED`; T2-pagination → `COUNCIL_RATE_LIMITED` (**100%**) |
| scored records | 0 (nothing survived → nothing emitted to the runs ledger) |
| secret leak-check | **0** |

Both corpus tasks were **paired-excluded** — an Arm-B free-model role hit
`COUNCIL_RATE_LIMITED`, so the subject was dropped from BOTH arms (flakiness is never scored as a
council miss). With 0 survivors below the pre-registered `min_survivors: 2`, the frozen-line
classifier returned `underpowered`. It was **not** laundered into a result in either direction.

### What the pilot proves / does NOT prove

| Claim | Evidence class | Status |
|---|---|---|
| The measurement RUN crosses the real boundary live (both arms real-call) and classifies per-arm outcomes instead of crashing/faking | **real-boundary-smoke** | proven (4 real calls) |
| The frozen pre-registration governs the verdict (rate-limit → paired-exclusion → attrition → `underpowered`, corpus_hash validated before scoring) | **real-boundary-smoke** | proven (honestly `underpowered`) |
| MAX-CALLS ceiling holds + key never leaks | verified | 4 ≤ 10; leak-check 0 |
| The foreign council catches more / is more diverse / higher quality than Claude | — | **NOT CLAIMED** — `underpowered`, 0 survivors |

### The pilot's real value (cost + flakiness estimate)

- **Free-tier Arm-B is unusable for this measurement: 100% of subjects rate-limited.** A 4-role
  preset on free models could not complete a single task without a `429` on some role, so
  paired-exclusion removed every subject. **The powered run MUST use PAID Arm-B models** (or
  heavy retry/backoff + a larger n to survive attrition). This is the key input the pilot was run
  to obtain.
- **Cost:** Arm A = 2 `claude-haiku-4.5` review calls on small diffs ≈ a few tenths of a cent
  (estimated upper bound); Arm B = free, $0. Total live spend negligible.

---

## Part B — the PENDING powered run (pre-registered, NOT yet run)

**Status: no results yet.** The pilot established only that the mechanism works end-to-end and
that free-tier Arm-B is too flaky to measure on. Nothing about the council's value.

### Why the pilot was underpowered (and the powered run is needed)

- n=2 with `min_survivors: 2` and **100% free-tier attrition** → 0 survivors → `underpowered`
  by construction. Cross-task variance is unestimable at n=2, so a value verdict was
  definitionally unreachable.

### Prerequisites the powered run MUST satisfy

1. **Paid Arm-B models** (or aggressive retry/backoff + larger n) so subjects survive attrition.
2. **Corpus n ≫ 2** (`council-review-catch-v1` expanded) so cross-task variance is estimable.
3. **Presets A / B / C** run, not just preset A.

### Pre-registered rubric it will follow

- The powered run carries the **full four-outcome rubric** (`demonstrated` / `refuted` /
  `tradeoff-signal-to-investigate` / `underpowered`) — explicitly **not** selectable at n=2.
- **Both** anti-Goodhart metrics required for any "adds value" claim (catch *and* cry-wolf).
- **Fair-scope disclosure (must be in the powered write-up):** the 4-role-council-union vs
  1-Claude flag-volume asymmetry — Arm B unions up to 4 reviews vs Arm A's 1 — did not come into
  play in the pilot (0 survivors) but **must be disclosed as fair scope** in the powered run.
- Distinct foreign model ids are an **outcome delta only, never proven cognitive diversity**
  (RISK-B-007).
- Same frozen-line discipline: a new pre-registration, frozen and timestamped before the scored
  run; the pass/fail line never moved after results.

## Evidence class

Pilot: `underpowered` — real-boundary-smoke of the **run mechanism only**, no value evidence.
Powered run: **PENDING / not yet executed.**

## Source artifacts (read before writing)

- [`docs/benchmarks/2026-06-20-council-measurement-pilot.md`](../benchmarks/2026-06-20-council-measurement-pilot.md)
  — the captured-result table, attrition, and honest ceiling traced here.
- Pre-registration: [`metrics/pre-registration-council-measurement-run.json`](../../metrics/pre-registration-council-measurement-run.json)
  (all pre-reg fields traced verbatim).
- Reality ledgers: [`docs/reality/council-measurement-run.evidence.jsonl`](../reality/council-measurement-run.evidence.jsonl),
  [`docs/reality/council-diversity-measurement.evidence.jsonl`](../reality/council-diversity-measurement.evidence.jsonl).
- Harness under test: `config/claude/metrics/council_measurement_run.py`;
  corpus `metrics/corpus/council-review-catch-v1`.
</content>
