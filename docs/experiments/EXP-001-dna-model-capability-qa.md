# EXP-001 · DNA vs. model capability in QA (mutation-oracle investigation)

**ID:** EXP-001 · **Date:** 2026-05-29 / 2026-05-30 · **Kind:** Experiment
(hypothesis-driven, mutation-oracle) · **Status:** complete.

This is the **methodological cornerstone** of the whole register: the run where our
cleverest idea — a QA-DNA prompt designed to make the test agent reach the real boundary —
turned out *not* to do what we hoped, and where catch-rate and cry-wolf-rate were first
seen moving in **opposite directions**. We give it the fullest treatment because every
later honesty rule in this repo descends from it.

## Hypothesis

The trigger was a real incident: the GBrain integration was a no-op (`client.add` did not
exist), tests were green, nobody noticed — *"tests green ≠ it works."* In response we built
the test agent a thinking discipline (reality-evidence classes, "is it wired in prod?",
real-boundary-over-fake). **Hypothesis:** this QA-DNA makes the agent's tests genuinely
better at catching the green-but-broken class — specifically the GBrain class where a
convenient fake already sits ready and testing the *real* thing is extra work.

## Method (falsification-resistant, no gut feeling)

Two agent versions — **old (no DNA)** vs **new (with DNA)** — get the *same* task and write
tests. Then a script **secretly sabotages the code** (mutation oracle) and counts: test red
= defect caught, test green = slipped through. Measured across **two model tiers** (Haiku =
floor, Opus = ceiling), **3 repetitions each**, coder-prompt **identical in both arms**, the
sabotaged "dark zone" never named in the spec.

Four instruments were sabotaged at four different layers:

| Instrument | What was sabotaged | Result |
|---|---|---|
| `bench-core-v1` | the test PLAN (pure thinking: which tests would you need?) | **DNA clearly better: 5× recall at equal precision** |
| `pipe-core-v1` | local logic in the built code | no difference (both arms catch it) |
| `pipe-nonlocal-v1` | wiring / real boundary (reality = the only test path) | no difference (both catch it) |
| `pipe-providedfake-v1` | real boundary, *with a fake already sitting there* (the GBrain shape) | **differential — but on the MODEL axis, not the DNA axis** |

The fourth instrument was the decisive one: it reproduces the actual GBrain case (a finished
fake + a starter test; testing the real thing is extra work).

## Results (as captured)

The provided-fake (GBrain-shaped) trap, escape counts (3 runs/cell):

|        | without DNA | with DNA |
|--------|-------------|----------|
| Haiku  | 3/3 slipped through | **3/3 slipped through** |
| Opus   | 0/3 (all caught) | 0/3 (all caught) |

**Addendum 2026-05-30 — Sonnet 4.6 measured (the missing middle):** 3 runs on the same P1
trap, tester-DNA forced via the explicit `model` parameter → **3/3 slipped through, like
Haiku.** So the boundary is **Opus vs. the rest**, not "Haiku vs. the rest." Sonnet is a
reasonable coding model and still misses this class silently.

The DNA's *measured* benefit is concentrated at the test-**planning** instrument
(`bench-core-v1`): **5× recall at equal precision**. At the actual *build* boundary it was
**precision-safe but result-neutral** — 0 regressions, 0 false alarms across all runs, but it
did not change which defects got caught.

## Honest interpretation — the one real finding

**Whether reality gets tested is decided by model strength, not by the prompt.**
- Opus reaches the real boundary on its own (even *without* the DNA) → always catches it.
- Haiku stays on the convenient fake (even *with* the DNA) → always sleeps through it.
- The DNA does **not** close this gap on the weak model. A stronger prompt cannot force a
  capability onto a weaker model.

**What it does NOT show:**
- It does **not** show the DNA is useless — at test-planning it is a 5× recall win (the
  thinking *is* the product there) and it is risk-free at build (0 regressions / 0 false
  alarms).
- It does **not** show the DNA closes the fake-boundary gap on weak models — measured: it
  does not. Claiming otherwise would be the exact overclaim this repo exists to prevent.
- The build-layer result is **n=3/cell** on selected traps — directional, not a baseline.

## Limitations / confounds

- Small `n` (3 per cell). Per-cell escape counts are integer-coarse (0/3 vs 3/3 is stark,
  but it is still three runs).
- The model tiers tested were Haiku / Sonnet / Opus only; the "Opus vs. the rest" line is
  drawn from these three, not a continuum.
- Mutation-oracle traps are curated; they exercise the GBrain *class*, not arbitrary code.
- This run measures catch on planted gaps. The cry-wolf side of the ledger for the full
  pipeline is measured separately in [EXP-002](EXP-002-full-pipeline-slice.md).

## Self-correction (logged, not hidden)

The instrument caught **its own** errors mid-investigation and they are documented in the
single-run reports rather than smoothed over: a regex bug in the sabotage script (a wrong
"slipped-through" verdict); four "leaks" where the spec/code/docstrings revealed the dark
zone themselves (de-leaked and re-run); and one run where the DNA file was accidentally
missing (discarded, cleanly repeated).

## What we learned (downstream consequences)

1. **DNA stays deployed** — free win at planning, no risk at build.
2. **The real lever against the GBrain defect class is raising the QA model tier** (run the
   tester on Opus), **not** strengthening the prompt.
3. **Do not claim** the DNA closes the fake-boundary gap on weak models — measured: it does
   not.
4. **Model-control finding:** per-agent `model:` frontmatter is **NOT applied** by this
   Claude Code version (verified from subagent logs, not self-report — a `retro-analyst`
   pinned `model: haiku` still logged `claude-opus-4-8`; only an explicit dispatch `model`
   parameter took effect, logging `claude-haiku-4-5`). All roles were reset to
   `model: inherit`; model control lives in the orchestrator. This is *why* the framework's
   model policy is "user decides, with a mandatory disclosure" rather than per-agent pins.
5. This run is the origin of the register's **anti-Goodhart law** (both metrics together)
   and the **no-overclaim** rule.

## Evidence class

Mutation-oracle measurement (falsification-resistant A/B), **n=3 per cell across 2–3 model
tiers**. The model-policy sub-finding is **logs-verified** (subagent `model` occurrences,
not self-report). Directional, internally coherent; not a statistically-powered baseline.

## Source artifacts (read before writing)

- [`metrics/SUMMARY-2026-05-30-dna-investigation.md`](../../metrics/SUMMARY-2026-05-30-dna-investigation.md)
  — the consolidated write-up (all numbers above traced here).
- Per-run reports: [`metrics/bench-2026-05-29-*.md`](../../metrics/) (e.g.
  `bench-2026-05-29-pipe-providedfake-arms.md`, `bench-2026-05-29-pipe-opus-ceiling.md`,
  `bench-2026-05-29-tester-probe*.md`).
- Corpora: `metrics/corpus/{bench-core-v1,pipe-core-v1,pipe-nonlocal-v1,pipe-providedfake-v1}/`.
- Model-policy mechanism: §"Modell-Policy" in the summary (subagent-log probes).
- Run ledger: [`metrics/runs.jsonl`](../../metrics/runs.jsonl) (the 2026-05-29 hive-backlog
  record).
</content>
