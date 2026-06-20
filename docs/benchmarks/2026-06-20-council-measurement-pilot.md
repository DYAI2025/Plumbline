# Council Measurement — n=2 Pilot (2026-06-20)

Slice 3b `council-measurement-run`. REQ-MR-005/007/010 · the deferred value-falsifier from Slices 1+2.
Branch `agileteam/council-measurement-run`. This is a **real captured live run** against OpenRouter,
not a fabricated snapshot. The API key was loaded at runtime from `~/.openclaw/.env`, used only in the
`Authorization` header, and is **never** in this trace (leak-check = 0). Gated by
`COUNCIL_INFERENCE_LIVE=1` + `--live` + a user-named `--max-calls 10` ceiling.

> **What this pilot IS (binding, user-confirmed honesty frame).** A **run-mechanism real-boundary-smoke**
> + a **cost/flakiness estimate** — NOT a value verdict. At n=2 the only reachable outcomes are
> `underpowered` / `tradeoff-signal-to-investigate`; `demonstrated`/`refuted` are definitionally out of
> reach. The value question ("does the foreign council catch what Claude misses without raising
> cry-wolf?") is **NOT answered here** — it needs the powered full run (corpus expansion + A/B/C presets).

## Command

```
# COUNCIL_INFERENCE_LIVE=1, key from ~/.openclaw/.env (never printed)
$ python3 config/claude/metrics/council_measurement_run.py run \
    --corpus metrics/corpus/council-review-catch-v1 --preset A \
    --claude-model anthropic/claude-haiku-4.5 \
    --pre-registration metrics/pre-registration-council-measurement-run.json \
    --max-calls 10 --live --score --json --out metrics/council-measurement-runs.jsonl
```
- **Arm A** = Claude-only review on `anthropic/claude-haiku-4.5` (paid; cheapest current Claude, live-verified in the catalog before the run).
- **Arm B** = preset A council (Visionaerin·Pruefer·Nutzeranwalt·Macherin) on resolved **free** foreign models.
- Both arms prompted in the **same** structured-flag protocol, scored by the **same** parser (arm symmetry).

## Captured result

| Field | Value |
|---|---|
| outcome | **`underpowered`** |
| survivors | **0 / min 2** |
| calls attempted | **4** (≤ the 10 ceiling) |
| attrition | T1-auth-token → `COUNCIL_RATE_LIMITED`; T2-pagination → `COUNCIL_RATE_LIMITED` (**100%**) |
| scored records | 0 (nothing survived → nothing emitted to the runs ledger — honest) |
| secret leak-check | **0** |

Both corpus tasks were **paired-excluded**: an Arm-B free-model role hit `COUNCIL_RATE_LIMITED`, so the
subject was dropped from BOTH arms (flakiness is never scored as a council miss). With 0 survivors below
the pre-registered `min_survivors: 2`, the frozen-line classifier returned **`underpowered`** — it was
**not** laundered into a result.

## What this proves (run mechanism) — and what it does NOT (value)

| Claim | Evidence class | Status |
|---|---|---|
| The measurement RUN crosses the real boundary live (both arms make real calls) and classifies per-arm outcomes instead of crashing/faking | **real-boundary-smoke** | proven (4 real calls; Arm-A Claude + Arm-B preset attempts) |
| The frozen pre-registration governs the verdict (rate-limit → paired-exclusion → attrition → `underpowered`, corpus_hash validated before scoring) | **real-boundary-smoke** | proven (outcome honestly `underpowered`, not laundered) |
| The MAX-CALLS budget ceiling holds + the key never leaks | verified | 4 ≤ 10; leak-check 0 |
| The foreign council catches more / is more diverse / higher quality than Claude | — | **NOT CLAIMED** — `underpowered`, 0 survivors; the value verdict needs the powered run |

## The actionable finding (cost + flakiness estimate — the pilot's real value)

- **Free-tier Arm-B is unusable for this measurement: 100% of subjects rate-limited.** A 4-role preset on
  free models could not complete a single task without a `429` on some role, so paired-exclusion removed
  every subject. **The powered full run MUST use PAID Arm-B models** (or heavy retry/backoff + a larger n
  to survive attrition). This is the key input the pilot was run to obtain.
- **Cost:** Arm A = 2 `claude-haiku-4.5` review calls on small diffs ≈ a few tenths of a cent (estimated
  upper bound; Arm-B = free, $0). The total live spend for this pilot was negligible.

## Honest ceiling (F3)

This is ONE underpowered pilot run. It establishes that the run mechanism works end-to-end at the real
boundary and that free-tier Arm-B is too flaky to measure on — nothing about the council's diversity/quality
value. Carried to the powered full run (deferred): paid Arm-B models, corpus expansion (n ≫ 2), presets
A/B/C, and the same frozen-line discipline. The 4-role-council-union vs 1-Claude flag-volume asymmetry
(Arm B unions up to 4 reviews vs Arm A's 1) did not come into play here (0 survivors) but **must be
disclosed as fair scope in the powered-run write-up**. Distinct foreign model ids would be an outcome
delta only, never proven cognitive diversity (RISK-B-007).
