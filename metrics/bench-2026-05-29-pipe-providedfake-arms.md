# Provided-fake oracle — Arm Bench (pipe-providedfake-v1), Floor+Ceiling

Date: 2026-05-29
Arms: baseline = tester DNA @ee77e4c (0 reality terms) · dna = @HEAD (4 reality terms)
Tiers: floor = Haiku 4.5 · ceiling = Opus 4.8 · 3 runs each
Task: P1-login-audit → **12 built increments**
Oracle: `mutate_providedfake.py P1` — neuter the real `FileStore.append()`, run the
arm's OWN suite. RED=caught, GREEN=escaped.

## The design (mirrors the real GBrain incident)
Unlike pipe-nonlocal-v1 (where the reality path was the *only* test path), this
scaffold makes **mocking the path of least resistance**:
- a ready-made `InMemoryStore` fake is **provided** in `tests/fakes.py`;
- a **starter passing test** (`tests/test_service.py`) already uses it;
- reaching the real boundary requires deliberate extra work (`build_service(tmpfile)`
  + read the file back).
FEATURE.md only says "implement `record_login`" — the dark zone (does the suite
prove the *real* persistence path?) is never named. Instrument validated: fake-only
reference suite ESCAPES, real-boundary reference suite CATCHES.

## Result — first task to produce a differential, but along the TIER axis

| | baseline | dna |
|---|---|---|
| **Haiku** | **3/3 escaped** | **3/3 escaped** |
| **Opus**  | **0/3 escaped** | **0/3 escaped** |

(Oracle `applied:true` all 12; per-run verified.)

- **Haiku escapes 100% in BOTH arms.** It extends the provided fake pattern and never
  touches the real boundary; the neutered `FileStore.append` is invisible to its suite.
- **Opus catches 100% in BOTH arms.** It adds a `build_service`/real-`FileStore`
  persistence test (disk round-trip, fresh-instance re-read) and catches the break.

## What this proves

1. **The dark zone is genuinely escape-able** — this is the first corpus where an arm
   (Haiku) actually misses the defect. The instrument is not rigged toward catching.
2. **DNA-v4 does NOT close the gap.** Haiku-dna escaped exactly as much as Haiku-baseline
   (3/3 = 3/3). The reality discipline (evidence-class ledger, prefer real-boundary-smoke,
   wired-in-prod check) did not make the weaker model write a real-boundary test. Reading
   the Haiku-dna reports: they wrote only fake-based tests, no boundary reasoning surfaced.
3. **Capability closes it, not the DNA.** Opus reaches the real boundary by default in
   both arms; its reports show the Beat-0 boundary reasoning even in the *baseline* arm
   (it does this unprompted). The DNA's value is absorbed by a capable base model and is
   not transferable to a weaker one on this dark zone.

### Corroboration from the discarded first run
The first P1 run was confounded — I had deleted `/tmp/nl-dna/` in a prior cleanup, so all
12 agents ran DNA-less (Opus agents flagged "DNA MISSING"; Haiku silently proceeded). That
run showed the SAME pattern: Opus (no DNA) wrote production tests, Haiku (no DNA) wrote only
fake tests. Consistent with a tier effect that is independent of the DNA. (Discarded for
the headline numbers; re-run clean above.)

## Consolidated verdict across THREE oracles

| oracle | mutates | differential? |
|---|---|---|
| pipe-core-v1 | local logic | none (both arms catch) |
| pipe-nonlocal-v1 | non-local reality, reality=only path | none (both arms catch) |
| pipe-providedfake-v1 | non-local reality, fake=easy path | **tier differential** (Opus catches, Haiku escapes); **arm-neutral** |

**Final, triangulated conclusion:** DNA-v4 is precision-safe and outcome-neutral on the
ARM axis at build/pipeline level across every oracle, including the one specifically
engineered (mirroring the real GBrain incident) to be escape-able. The behaviour the DNA
encodes — reaching the real boundary instead of the fake — is governed by **model
capability**, not by the DNA prompt: Opus already does it; Haiku does not do it even with
the DNA. The DNA's demonstrated value remains confined to **test-PLAN derivation**
(bench-core-v1: 5× recall at parity precision), where the reasoning is the deliverable.

### Recommendations
- Keep DNA-v4 deployed (zero regressions; free precision-positive at plan stage).
- For the real GBrain-style dark zone, the effective lever is **model tier for the QA
  step** (run the tester on Opus), NOT a stronger prompt on a weaker model.
- Do not claim the DNA closes the fake-boundary gap on weaker models — measured: it does not.
