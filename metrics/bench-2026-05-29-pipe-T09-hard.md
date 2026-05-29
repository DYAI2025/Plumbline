# Pipe-core-v1 — Hard Task: Money-Transfer Atomicity (T09 + T09b), Floor+Ceiling

Date: 2026-05-29
Arms: baseline = agents @ee77e4c (v3, pre-DNA) · dna = @HEAD (v4 "kritische semantische Glättung")
Tiers: floor = Haiku 4.5 · ceiling = Opus 4.8 · 3 runs each → **24 built increments**
Oracle: deterministic mutation (`mutate.py T09`) → reset `_credit_or_rollback` to naive
`dst.credit(amount)` (removes atomicity), then run the arm's OWN tests.
RED = caught, GREEN = escaped.

## Why this task
Prior pipeline datapoints (T08, T02, T03, CTRL) showed **0% build-level differential**.
Hypothesis: those tasks were too easy / their dark zone too visible. This task targets
**partial-failure atomicity** — transfer debits the source, then the destination credit
can raise (`AccountFrozen`), leaving money vanished unless the source debit is rolled back.
Two framings of the same dark zone:

- **T09 (named-in-spec):** FEATURE.md explicitly requires rollback/atomicity.
- **T09b (unnamed-in-spec):** FEATURE.md says only "implement transfer"; the rollback
  requirement is *not* stated. This is the genuine dark-zone probe.

## Results

| Variant | Tier | Arm | escaped / built | escaped-rate |
|---|---|---|---|---|
| T09 (named)   | Haiku | baseline | 0/3 | 0% |
| T09 (named)   | Haiku | dna      | 0/3 | 0% |
| T09 (named)   | Opus  | baseline | 0/3 | 0% |
| T09 (named)   | Opus  | dna      | 0/3 | 0% |
| T09b (unnamed)| Haiku | baseline | 0/3 | 0% |
| T09b (unnamed)| Haiku | dna      | 0/3 | 0% |
| T09b (unnamed)| Opus  | baseline | 0/3 | 0% |
| T09b (unnamed)| Opus  | dna      | 0/3 | 0% |

**No differential. Both variants, both arms, both tiers: 0% escaped.**
Oracle mutation `applied=True` in all 24 runs (verified — not a false-negative like the
earlier T03 regex bug). Every arm wrote ≥2 rollback/conservation tests (T09b counts:
baseline 2–5, dna 2–4 per run), all of which go red under the mutation.

## Why T09b still didn't hide the dark zone (the real finding)

The spec was neutral, but the **code telegraphed the failure mode**:
- the hook is literally named `_credit_or_rollback`
- `Account.credit()` raises `AccountFrozen` (visible in `src/bank.py`)

Two Opus-baseline agents stated the hook name signaled the intended fix. Every arm read
the code, saw `credit()` can throw, and wrote a conservation test — regardless of arm.

This is the **third leak** of the same kind:
1. T03 — dark zone named in the spec.
2. T09 — dark zone named in the spec.
3. T09b — dark zone named in the *code* (hook name + visible exception).

The pattern is not "the task wasn't hard enough." It is **methodological**:

> A deterministic mutation oracle needs a **fixed, named seam** to mutate reproducibly.
> A fixed, named seam *is* a signpost a diligent tester reads. So this harness can only
> measure **locally-visible logic defects** — and a capable coder+tester (either arm)
> catches those by construction, because building the feature means reading that seam.

## Consolidated verdict (unchanged, now with floor+ceiling on the hard task)

The DNA-v4 ("kritische semantische Glättung") value is **confined to test-PLAN
derivation**, where it was validated independently (FP parity 8.3% with 5× recall vs
baseline's 41.7% escaped on the bench-core-v1 probe). That value lives in catching
**non-local reality gaps** — "is it wired into the composition root?", "is this test a
fake?", "is this claim about a foreign file verified?" — which are exactly the gaps the
full pipeline already closes by construction (the coder wires it; the tester writes real
tests against real boundaries).

At **built-increment / full-pipeline level**, across T08, T02, T03, CTRL, the Opus
ceiling, and now the hard atomicity task T09/T09b at both floor and ceiling, the DNA is
**precision-safe but outcome-neutral**: it never raised false positives (CTRL 0% both
arms) and never changed escaped-defect rate (always 0% both arms).

**The mutation-oracle methodology is structurally unable to exhibit the DNA's value**,
because that value is about non-local/composition/fake-test gaps, while a reproducible
mutation oracle can only probe locally-visible logic — which both arms already catch.
Building a "harder" local task (T09c with fully-neutral naming) would not change this:
to keep the oracle deterministic the seam must stay fixed and visible, which re-leaks.

### Recommendation
- Keep DNA-v4 deployed: it is a free precision-positive at the test-PLAN stage and
  introduced zero regressions anywhere measured.
- Do NOT claim a full-pipeline escaped-defect improvement — there is no evidence for one,
  and six datapoints across two tiers say it is neutral there.
- To measure the DNA's real value at pipeline level would require a **non-local dark-zone
  oracle** (e.g. inject a composition-root wiring gap or a fake-passing test and check
  whether the arm's suite catches it) — not a local-logic mutation. That is the next
  instrument to build if pipeline-level proof is wanted; flagged, not silently skipped.
