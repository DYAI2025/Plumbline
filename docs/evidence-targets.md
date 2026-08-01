# Evidence targets (`docs/evidence/<feature>.targets.json`)

The Reality Ledger classifies how *strong* a piece of evidence is
(`unit-fake → integration-fake → real-boundary-smoke → production-verified`). It said
nothing about **what the evidence touched**. That gap is a false-green generator.

Measured on 2026-07-30 against the pre-PLUM-13 gate, both cases exited **0**:

| ledger record | reality |
|---|---|
| `real-boundary-smoke` for a requirement about dataset `W32-default-seed` on `GET /api/v1/tree/read-through` | the linked test drove `W40-harness-seed` fixtures on a *different* route |
| `production-verified`, `evidence_ref: tests/does_not_exist_at_all.sh` | the referenced file does not exist at all |

The pilot hit the first one: a read-through test was green, the fixed defect was about
default seed IDs in a different dataset, and the high evidence class was recorded
anyway. Only a manual review of dataset, route and test phase surfaced the gap.

An evidence target closes it by making the binding **declared and provable**.

## Shape (schema 1)

```json
{
  "schema": 1,
  "feature": "my-feature",
  "targets": [
    {
      "requirement_id": "REQ-MF-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "seed ids resolve to the default catalog",
      "preconditions": [{"fixture": "seed-catalog", "state": "present"}],
      "min_evidence": "real-boundary-smoke",
      "proof_tokens": ["PROOF-REQ-MF-001-w32-readthrough"],
      "note": "human prose; never parsed as configuration"
    }
  ]
}
```

| field | required | meaning |
|---|---|---|
| `requirement_id` | **yes** | the REQ this target belongs to. Must be unique in the file. |
| `dataset` | **yes** | which data the evidence must have exercised. |
| `boundary` | **yes** | which route / system boundary. |
| `expected_result` | **yes** | what the criterion actually claims. |
| `preconditions` | no | list of `{"fixture": …, "state": "present"|"absent"}`. |
| `min_evidence` | no | a per-target floor that **outranks** a lower CLI `--min-evidence`. |
| `proof_tokens` | no | strings that must appear in the referenced artifact. Defaults to `[dataset]`. |
| `note` | no | human prose. Ignored by the gate. |

Unknown keys are refused, at both file and target level: in a gate configuration a
typo'd key must not read as "not configured".

## The matching ledger record

The record in `docs/reality/<feature>.evidence.jsonl` repeats the binding:

```json
{"feature": "my-feature", "requirement_id": "REQ-MF-001",
 "evidence_class": "real-boundary-smoke",
 "evidence_ref": "tests/test_read_through.sh::REQ-MF-001",
 "dataset": "W32-default-seed",
 "boundary": "GET /api/v1/tree/read-through",
 "expected_result": "seed ids resolve to the default catalog",
 "preconditions": [{"fixture": "seed-catalog", "state": "present"}],
 "verified_by": "…", "note": "…"}
```

`evidence_ref` follows the existing convention `<repo-relative-path>::<selector>
(free prose)`. The path part must resolve to a real file, and that file must contain
every proof token — that is the step that turns a self-declared binding into a
checked one.

## Classifications

| class | exit | when |
|---|---|---|
| `MISSING_BOUNDARY` | 2 | a declared target has no ledger record, or the record carries no `dataset`/`boundary`/`expected_result` — the boundary was never evidenced. |
| `EVIDENCE_MISMATCH` | 3 | evidence exists but proves the wrong thing (see below). |
| malformed | 4 | the targets file is present but broken (bad JSON, unknown key, missing required field, wrong feature, unknown `min_evidence`). |

`EVIDENCE_MISMATCH` covers: a `dataset`/`boundary`/`expected_result` that contradicts
the target · an unresolvable `evidence_ref` · a proof token absent from the referenced
artifact · differing preconditions · an unmet per-target floor · an `absent`-state
target with no resolvable present-state `control_ref`.

## Vacuous absence tests

A target whose precondition state is `absent` proves a negative, and it passes
trivially while the counter-set does not exist yet. Such a record must name a paired
present-state `control_ref`, and that control must resolve — otherwise the gate reports
`EVIDENCE_MISMATCH`. This is the "vakuumer Abwesenheitstest" the ticket names.

## Adoption

Targets are **opt-in per feature**: a feature with no targets file behaves exactly as
before, so the 84 existing ledger records across this repo keep passing untouched.
Declare targets for the *critical* criteria first — the ones where an I/O boundary,
a dataset identity or a route actually decides whether the requirement is met.

Run the gate the usual way; the target check happens before class ranking:

```bash
config/claude/bin/plumbline-reality-check --repo . --feature <slug> \
  --min-evidence integration
```

## Ceiling (what this does NOT prove)

The proof-token check shows the referenced artifact **mentions** the dataset/route; it
does not execute the test or observe which fixture the run really loaded. A determined
author can still satisfy it by adding the token to an unrelated test. What it removes
is the *accidental* mismatch — the pilot's actual failure — plus every unresolvable
reference. Treat it as a binding check, not as runtime instrumentation.
