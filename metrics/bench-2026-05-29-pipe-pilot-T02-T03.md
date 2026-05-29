# pipe-core-v1 PILOT 2 — T02 + T03, Haiku, both arms × 3 runs (2026-05-29)

Second pilot (Option 2): the two remaining build dark-zones where the "build forces the
test" effect from the T08 pilot might NOT hold — T02 (webhook fake-only) and T03 (overdraft
failure-mode guard). Both arms (tester pinned `@ee77e4c` baseline vs `@HEAD` DNA-v4),
Haiku, 3 runs/arm, build TDD → deterministic mutation oracle on the built increment.

## Result

| task | mutation | baseline escaped | dna escaped |
|---|---|---|---|
| T02-webhook | drop the webhook recording (POST silently lost) | 0/3 (3/3 caught) | 0/3 (3/3 caught) |
| T03-overdraft-guard | stub `_check_overdraft` → pass (guard removed) | 0/3 (3/3 caught) | 0/3 (3/3 caught) |

**No differential on either task.** Every built increment, both arms, has a test that
exercises the dark-zone behaviour: T02 asserts the POST fires on `mark_paid` (so dropping
it → red); T03 asserts an overdraft raises `InsufficientFunds` (so stubbing the guard →
red). All 12 mutations caught.

## Combined build-task picture (T08 + T02 + T03, N=3/arm each)
| task (dark zone) | baseline escaped | dna escaped |
|---|---|---|
| T08 wiring+fake-only | 0% | 0% |
| T02 fake-only reality | 0% | 0% |
| T03 failure-mode guard | 0% | 0% |

**Across all three build dark-zones the build-level escaped-defect-rate is 0% for BOTH
arms — no differential anywhere.** The "build forces the guarding test" effect is general,
not specific to T08: writing the obvious acceptance test for a feature inherently exercises
its dark-zone behaviour, so the DNA's test-PLAN advantage (validated in bench-core-v1) is
**fully absorbed once the pipeline actually builds + tests the feature.**

## Harness hardening (a bug the pilot caught)
The first T03 oracle run silently mis-fired: the stub regex anchored on `):` but the
scaffold signature ends `-> None:`, so it matched nothing (`n=0`) and produced a FALSE
"escaped" (green). The applied-count flag + an effectiveness probe (does an overdraft still
raise after mutation?) caught it; the corrected mutation (match to the def's final colon)
made all 6 go red. Committed a hardened `mutate.py` so the runner can't silently no-match —
it reports `applied` and warns that a green result without an applied mutation is a false
escape. (The instrument catching its own measurement bug is the whole point.)

## Honest conclusion (build level)
On Haiku, across the three build dark-zones, the DNA produces **no measurable
built-increment escaped-defect improvement** — the value is confined to test-PLAN
derivation (where it IS validated: FP parity + 5× recall). This is consistent and now
threefold-replicated. Remaining unrun pieces of pipe-core-v1: the CTRL pure-logic
false-positive task and the RDIFF reviewer dimension (the latter already separately found:
no narrowing). On current evidence a full multi-task run is unlikely to surface a
build-level differential; the honest summary is: **DNA helps plans, not builds, on these
tasks/this model.**

## Caveats
- N=3/cell, Haiku, tester-pinned arms (the dominant DNA variable for build; reviewer/PO not
  separately run here). Opus ceiling unrun. Three small, naturally-guarded features — a
  larger/messier feature where the obvious test does NOT cover the dark zone could still
  show a differential, but none of the corpus's three did.
