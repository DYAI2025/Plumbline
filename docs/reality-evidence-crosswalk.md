# Reality Evidence-Class Crosswalk (canonical)

> **Single source of truth** for how the evidence-class vocabularies reconcile.
> Any routing/tiering lever that maps an `evidence_class` to `{boundary, logic}`
> (e.g. M7) MUST read this table — not re-derive its own mapping.

Plumbline carries **two** load-bearing evidence-class vocabularies. They are not
in conflict: one is a strict **coarsening** of the other.

1. **The 4-rung prose ladder** — in `config/claude/commands/agileteam.md`
   (the *Reality Ledger* evidence-class definition): `unit-fake →
   integration-fake → real-boundary-smoke → production-verified`. This is the
   human-facing ladder an agent reasons about during a run.

2. **The 10-value schema enum** — in
   `docs/templates/reality-ledger-evidence.schema.json`
   (`properties.evidence_class.enum`), each value ranked `0–5` in
   `config/claude/lib/plumbline_reality.py` `RANKS`. This is the machine vocabulary
   the PRIL `plumbline-reality-check` gate validates against.

The schema enum and `RANKS` are the **same set** (10 values); `RANKS` assigns each
its ordinal. The 4-rung ladder selects four of those values — the four whose ranks
are `1, 2, 3, 4` — as the named rungs an agent climbs.

## The canonical table

All 10 schema enum values, each with its `RANK` (from `plumbline_reality.RANKS`)
and its 4-rung-ladder equivalent. `—` marks the finer / back-compat / extreme
values that have **no** named prose rung.

| Schema enum value     | RANK | 4-rung ladder equivalent | Role |
|-----------------------|:----:|--------------------------|------|
| `fake-only`           | 0    | —                        | Below the ladder: no real evidence. Also in `FORBIDDEN_TOKENS` — rejected by the reality gate's token scan. |
| `unit-fake`           | 1    | **`unit-fake`** (rung 1) | Prose rung 1. |
| `unit-only`           | 1    | —                        | Back-compat alias at rank 1 (real unit evidence, no integration). |
| `integration-fake`    | 2    | **`integration-fake`** (rung 2) | Prose rung 2. |
| `integration`         | 2    | —                        | Back-compat alias at rank 2 (the gate's default `--min-evidence`). |
| `real-boundary-smoke` | 3    | **`real-boundary-smoke`** (rung 3) | Prose rung 3. |
| `browser-live`        | 3    | —                        | Back-compat alias at rank 3 (live boundary exercised through a browser). |
| `production-verified` | 4    | **`production-verified`** (rung 4) | Prose rung 4 — top of the ladder. |
| `production-observed` | 4    | —                        | Back-compat alias at rank 4 (observed in production). |
| `user-confirmed`      | 5    | —                        | Above the ladder: a human confirmed the behaviour. Highest rank. |

## Why the ladder is a strict COARSENING of the schema enum

A **strict coarsening**: every prose rung corresponds to **exactly one** schema
rank, and the rungs are **strictly monotonic** in rank — `unit-fake(1) <
integration-fake(2) < real-boundary-smoke(3) < production-verified(4)`. The schema
neither reorders nor splits those four ranks; it only:

- adds **finer / back-compat aliases at the same four ranks** —
  `unit-only`@1, `integration`@2, `browser-live`@3, `production-observed`@4
  (each shares a rank with its prose rung, so coarsening to the rung loses no
  ordering information); and
- adds **two values at the extremes the prose ladder does not name** —
  `fake-only`@0 (below the ladder; a forbidden non-reality token) and
  `user-confirmed`@5 (above the ladder; human sign-off).

So: collapsing the 10 schema values onto the 4 prose rungs (by rank, with
`fake-only` falling below rung 1 and `user-confirmed` rising above rung 4) is a
**well-defined, order-preserving, many-to-one map**. That is exactly what makes
the prose ladder a *coarsening* and never a contradiction of the schema enum.

## Invariants (guarded by `config/claude/tests/test_evidence_vocab.sh`)

1. The schema enum set and `plumbline_reality.RANKS` key set are **identical**.
2. The 4 prose-ladder rungs are all keys in `RANKS` with **strictly increasing**
   ranks (`1 < 2 < 3 < 4`).
3. This crosswalk doc **mentions all 10** schema enum values (it cannot silently
   drift from the enum).

If any of those break, `test_evidence_vocab.sh` fails closed — that is the signal
to reconcile this table, the schema, `RANKS`, and the prose ladder before any
routing lever keys off a desynced vocabulary.
