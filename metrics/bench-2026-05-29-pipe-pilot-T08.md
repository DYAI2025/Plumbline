# pipe-core-v1 PILOT — T08, Haiku, both arms × 3 runs (2026-05-29)

First real execution of the `pipe-core-v1` harness, scoped to ONE task (T08) as a pilot:
validate the harness mechanics end-to-end and get a first built-increment data point.

## Setup
- Task: `T08-account-deletion` (gap-build; dark zone = wiring + fake-only).
- Arms: tester pinned `@ee77e4c` (baseline, no gate) vs `@HEAD` (DNA-v4, gate+3).
- Model: Haiku. Runs: 3/arm. Per run: a build agent (under the arm's tester DNA) derived
  + wrote tests and implemented TDD to green, then the **deterministic mutation oracle**
  un-wired `store.delete_all` from `delete_account` and ran the arm's own tests.

## Result

| arm | builds green | mutation → red (caught) | escaped-defect-rate |
|---|---|---|---|
| baseline | 3/3 | 3/3 | **0.0%** |
| dna (v4) | 3/3 | 3/3 | **0.0%** |

**No differential.** All six built increments guard the wiring: every build agent (both
arms) wrote a `delete_account`-driving acceptance test (through `build_service()` or
direct) that the un-wiring mutation breaks. The oracle worked flawlessly — all 6 went red,
deterministically, no judging needed.

## Reading
- **Harness validated:** scaffolds build, agents reach green, the mutation oracle
  classifies caught/escaped deterministically (6/6 red). The instrument works as designed.
- **T08 built-increment differential = none**, at N=3/arm — replicating and strengthening
  the earlier N=1 T08 datapoint. The DNA's T08 advantage seen in the *test-plan* probe
  (bench-core-v1: baseline 0/3 caught) does NOT carry to the *built increment*: the obvious
  acceptance test for "delete account → files gone" inherently exercises the wiring, so
  both arms guard it. "Articulating the wiring concern in a plan" ≠ "the built increment
  needs the DNA to guard it" — for this small, naturally-guarded feature they diverge.

## Implication for the full run
On naturally-guarded build tasks like T08, expect little build-level escaped-defect
differential (the build forces the guarding test). A full `pipe-core-v1` run is still worth
it to test the OTHER dimensions where a differential might live:
- T02/T03 — do less-obvious dark zones (a webhook side-effect; a failure-mode guard)
  reproduce the same "build forces the test" effect, or does the DNA help there?
- CTRL — does the DNA's pipeline cry wolf on pure logic (false-positive cost)?
- RDIFF-A/B/C — the reviewer dimension (already separately found: no narrowing).
But temper expectations: the pilot suggests the DNA's value is concentrated at test-PLAN
derivation, and may be largely absorbed once the pipeline actually builds + tests a feature.

## Honest status
- **Validated:** the harness; T08 built-increment escaped-defect-rate = 0% both arms (no
  differential).
- **Cost note:** this pilot was 6 build pipelines + oracle (~1M tokens). The full run
  (7 tasks × 2 arms × 3 runs + reviews + judges) is several × this. Given the pilot's null
  on T08, decide deliberately whether the full run's expected information justifies it.
