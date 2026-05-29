# Targeted Differential Canary — agileteam DNA vs. baseline (2026-05-29)

> **This is NOT the statistical drift-vs-precision bench.** That bench is
> precondition-blocked: no frozen corpus (`bench-core-v1` doesn't exist) and the
> baseline window is N=1 (`metrics/runs.jsonl` has one record). Per `agileteam-bench.md`
> ("if any precondition is unmet, STOP — do not fabricate a corpus or a baseline"), a
> statistical bench was not run. This is a single-task **falsification probe** of the
> causal claim: *does the new tester DNA catch the dark-zone failure class the baseline
> misses?* N=1 per cell. It can show a differential exists; it cannot estimate effect
> size or average-case behaviour.

## Setup
- **Arms:** baseline tester (`core/tester.md` @ `ee77e4c`) vs. new DNA (@ `fb0158a`).
  Only difference: the "Kritische semantische Glättung" 3-beat + Reality-Ledger
  discipline (+32 lines). Identical otherwise.
- **Models:** Opus 4.8 and Haiku 4.5 (to separate model strength from prompt effect).
- **Task (neutral, not hive-backlog):** REQ-N1 — "shipping an order sends a customer
  email; add a NotificationDispatcher and integrate it." A trap seeded with the exact
  failure class: built-but-not-wired-into-`build_app()`, and fake-only-never-real I/O.
- Same task text for all four cells; agents told only that `build_app()` is the
  production composition root.

## Rubric (the dark-zone catches the DNA targets)
- **W** — a test that drives `build_app()` to prove the dispatcher is actually *wired*.
- **G** — an explicit user-value **counter-thesis** ("green yet zero value").
- **R** — flags **fake-only as insufficient / RED** (green-against-fake ≠ real email sends).
- **E** — refuses to self-downgrade / call it done on fake evidence (escalation).

## Result

| Cell | W (wiring test) | G (counter-thesis) | R (reality-evidence flag) | E (no self-downgrade) |
|---|---|---|---|---|
| Opus · baseline | ✅ strong | ~ implicit | ❌ treated fake-E2E as sufficient | ❌ |
| Opus · new DNA | ✅ | ✅ explicit | ✅ "does not prove an email leaves the building" | ✅ "cannot self-downgrade" |
| Haiku · baseline | ✅ ("composition root critical") | ❌ | ❌ framed hermeticity as the *goal* | ❌ |
| Haiku · new DNA | ✅ | ✅ explicit | ✅ evidence-class alert, "post-deployment test" | ~ partial |

## Honest findings

1. **The wiring dimension (W) showed NO differential — all four caught it.** Even
   Haiku-baseline flagged "composition-root testing critical". So on the *specific*
   bug that sank the real sprint (wired-but-not-composed), a generic tester prompt +
   a capable model already cue the `build_app()` integration test. **Caveat / confound:**
   the task text explicitly named `build_app()` as the production composition root,
   which itself cues the wiring test — the real sprint never framed it that way. So
   this probe does **not** prove the DNA fixes the wiring blind spot.

2. **The measurable differential is R + G + E — the reality-evidence ledger and the
   structured counter-thesis.** Both baseline arms missed it (they treated "green
   against the fake EmailSender" as the objective — the exact blindness); both DNA arms
   caught it (Gegenthese + fake-only-is-RED + don't-call-it-done). Clean 2/2 split.

3. **Floor-raising (suggestive, not proven):** Haiku-new produced the same critical
   catches as Opus-new, while the baseline arms' quality tracked model strength
   (Opus-baseline richer than Haiku-baseline). The protocol made the critical checks
   **model-independent / non-optional** rather than emergent-when-the-model-is-sharp.
   This is the strongest argument for the DNA — and it is one run, not a measurement.

## Verdict
- **Signal: yes, but narrower than hoped.** The DNA demonstrably adds the
  reality-evidence catch (fake-only → RED, no self-downgrade) that the baseline misses
  at both capability levels. It did **not** demonstrate an advantage on wiring detection
  in this probe (confounded by task framing; all arms caught it).
- **Not a precision/drift result.** No corpus, N=1 per cell, one task, generous framing.
  Treat as a falsification probe that *passed* for the reality-evidence intervention and
  was *inconclusive* for the wiring intervention.

## What a real bench needs (to graduate CORE→FULL honestly)
1. A frozen `bench-core-v1` corpus of ~6–10 build tasks **seeded with the failure
   classes** (some with a wiring gap, some with fake-only reality gaps, some clean
   controls) — and *not* spoon-feeding "this is the composition root".
2. ≥3 runs per arm per task (stochasticity), baseline established from `main` first.
3. Primary metric = escaped-defect-rate on the seeded gaps (did the arm's plan/tests
   actually catch the planted gap), weighted over flow metrics (anti-Goodhart).
4. Pin one agent snapshot across arms; run weak + strong models to measure floor-raising.
