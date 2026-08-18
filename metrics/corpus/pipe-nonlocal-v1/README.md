# pipe-nonlocal-v1 — the non-local dark-zone oracle

## Why this exists

`pipe-core-v1` mutates **local logic** and runs the arm's tests. Across six
datapoints (T08, T02, T03, CTRL, Opus ceiling, T09/T09b at floor+ceiling) it
showed **0% differential** between baseline and DNA arms — because a capable
coder+tester catches local logic defects *by construction*: building the feature
means reading and exercising the very seam that gets mutated.

But the DNA's ("kritische semantische Glättung" + wired-in-prod check + evidence
-class reality ledger) actual target is **non-local**:

1. **Wiring gaps** — code correct in isolation, never wired into the composition
   root. ("Tests grün ≠ in Produktion erreichbar.")
2. **Fake tests** — the suite only exercises a fake/mock, never the real boundary
   production uses. ("Tests grün ≠ funktioniert.")

A local mutation oracle is *structurally unable* to probe these. This corpus does:
it injects a **non-local** defect that is **invisible to a unit/fake-only suite**
and **visible only to a suite wired through the real composition root / real
boundary**. So the escaped-defect-rate here measures whether the arm's tests reach
reality — the exact behaviour the DNA is supposed to change.

## The instrument

| Task | dark zone | mutation | escapes | catches |
|------|-----------|----------|---------|---------|
| N1-wiring-gap | handler not wired into `build_app()` | remove `register()` in composition root | unit-only test | integration test through `build_app()` |
| N2-fake-boundary | real persistence never tested | neuter `FileStore.append()` | fake-store-only test | real-boundary temp-file smoke test |

`FEATURE.md` for each task **never names the dark zone** — it does not tell the
tester to go through `build_app()` or to use the real `FileStore`. Choosing reality
is the arm's free decision; that decision is the variable under test. This is the
fix for the repeated "the spec/code telegraphed it" leak in T03/T09/T09b.

## Running it

Discrimination check (proves the oracle splits reality-reaching from unit-only):
```bash
# reference suites: unit/fake-only ESCAPE, integration/real-boundary CATCH
# (see manifest.json discrimination_validated)
```

Arm bench (per built increment):
```bash
PY=/home/dyai/clawd/hive-backlog/.venv/bin/python
python mutate_nonlocal.py N1 <built_dir>          # confirm applied:true
(cd <built_dir> && $PY -m pytest -q)              # RED=caught, GREEN=escaped
python mutate_nonlocal.py N1 <built_dir> --restore
```

## Status

- **2026-05-29:** instrument built and **discrimination validated** on reference
  suites (N1 + N2). Mutations apply deterministically (`applied:true`); reference
  suites green pre-mutation; the unit/fake suites escape and the integration/real
  suites catch.
- **Arm bench (baseline vs DNA, floor+ceiling): NOT yet run.** This is the first
  instrument expected to be *able* to show a pipeline-level differential, if one
  exists. Pending user go-ahead (it spawns a full /agileteam tester pass per arm).
