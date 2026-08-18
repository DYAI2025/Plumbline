---
description: Empirically measure an agent/prompt/process change instead of asserting it works — build a task corpus, run a deterministic mutation oracle (sabotage the code, see which tests catch it), and write an honest report including negative results. Use to compare two agent variants (e.g. baseline vs. a DNA/prompt change) or two models on a dark-zone behaviour.
---

You are running **bench-oracle** — Plumbline's instrument for turning *"this change
should help"* into a falsifiable, measured claim. It is the method behind
`metrics/corpus/` and `metrics/SUMMARY-2026-05-30-dna-investigation.md`; read those for
worked examples before starting.

## Core idea (deterministic, no vibes)
Give two arms the same task, let each produce code + tests, then **secretly sabotage the
code with a known mutation** and run each arm's *own* tests:
- test goes **RED** → the defect was **caught**
- test stays **GREEN** → the defect **escaped**

Escaped-defect-rate per arm is the metric. A mutation that no arm catches (or that every
arm catches by construction) measures nothing — design the dark zone so it is genuinely
escape-able.

## Steps
1. **Name the claim and the dark zone.** What behaviour is the change supposed to
   improve, and what specific defect class would a *worse* agent miss? (e.g. "tests reach
   the real boundary, not a provided fake".)
2. **Define the arms.** Pin them exactly: e.g. `baseline` = agent @<sha>, `dna` = @HEAD;
   or `model: sonnet` vs `model: opus`. Hold everything else identical (same task text,
   same coder prompt). The arm must be the *only* variable.
3. **Build a small corpus** under `metrics/corpus/<name>/`: a `FEATURE.md` that does NOT
   name the dark zone (a leak invalidates the test — see Guardrails), scaffold `src/`,
   and a deterministic mutator script. Add ≥1 **reference suite that escapes** and ≥1
   **that catches**, and prove the mutator splits them — this validates the instrument
   before any arm runs.
4. **Run the arms** (e.g. Haiku floor + Opus ceiling, 3× each). Dispatch real subagents;
   keep each in its own dir. Note: per-agent `model:` frontmatter is NOT honoured by the
   runtime — force a model via the explicit dispatch `model` parameter.
5. **Run the oracle** across every built dir: apply mutation (confirm `applied: true`),
   run `pytest -q`, restore, tally RED/GREEN per arm per tier.
6. **Write the honest report** to `metrics/bench-<date>-<name>.md`: the tally, the
   verdict, AND every limitation — leaks found, confounds, instrument bugs. A null or
   negative result is a valid, publishable result.

## Guardrails (each one cost a real bug here)
- **Leak check is mandatory.** If the spec, a method name, or a docstring telegraphs the
  dark zone, every arm "catches" it and the differential vanishes. De-leak and re-run.
  (Happened 4×: T03/T09/T09b spec-or-code names; N1/N2 docstrings.)
- **Verify the mutator actually applied.** A regex that silently no-matches produces a
  false "escaped". Always emit and check an `applied` flag. (Real bug: T03.)
- **Validate discrimination first.** Reference suites must show escape-vs-catch *before*
  spending tokens on arms — otherwise you cannot trust a null result.
- **The corpus is sacred — never fabricate.** If a precondition is missing (no baseline,
  no real boundary available), STOP and report it; do not invent data or a baseline.
- **Confounds are findings, not embarrassments.** If you discover the run was tainted
  (e.g. a missing DNA file, a stale snapshot), discard it, say so in the report, re-run.
- **State the reach honestly.** One corpus + one task + 3 runs can *refute* a claim but
  rarely *establishes* a general one. Say which you did.

The output that matters most is the one that says *"we expected X, measured not-X."*
That is the whole point.
