# Plumbline Experiment Register

> *The Plumbline knows only one direction — toward the truth.*
> We test our hypotheses transparently and learn from the results **without
> embellishment**. A null result, a tradeoff, an underpowered run, or a RED are
> first-class outcomes here. This register exists so every empirical claim Plumbline
> makes can be traced to a real source artifact — and so the ones we could NOT verify
> are marked, never invented.

This is the scientific log of every empirical run the Plumbline framework has executed.
It is the index, the methodology charter, and the honesty contract. The deliverables it
documents (the agent collection, the governance tooling) live elsewhere in the repo;
this is the *instrument's lab notebook*.

---

## Methodology charter (the honesty contract)

These rules are binding on every entry. They are the same anti-self-deception rules the
framework enforces on the code it builds — applied to the framework's own measurements.

1. **Transparent hypotheses.** Each experiment states what it expected to find *before*
   the numbers. We do not retrofit a hypothesis to a result.
2. **No sugar-coating — one direction.** The result is reported as captured. We do not
   round up, cherry-pick the flattering arm, or bury the disappointing one. The headline
   learning of this whole register is a result where *our cleverest idea did not work*
   (EXP-001) — and we shipped it anyway.
3. **RED is never downgraded.** A claim that touches a real boundary (I/O, a remote, an
   external API, UI) and was only tested with fakes is RED **regardless of green tests**.
   That RED stands until a real-boundary smoke lifts it, or the user explicitly
   reclassifies it at an acceptance gate. No silent laundering of the evidence ceiling.
4. **Both anti-Goodhart metrics, always together.** A catch-rate is half a ledger. A high
   catch-rate bought with a high false-positive ("cry-wolf") rate is *not* an improvement.
   We never headline catch-rate alone. "Strictly better" is a claim that needs **both**
   metrics to support it — and we have measured them moving in *opposite* directions.
5. **n and scope always visible.** Every entry carries its `n`, task count, model scope,
   and arms. A datapoint is labelled a datapoint, not a baseline.
6. **Pre-registration before scored runs.** A scored measurement is judged against a
   frozen, timestamped pre-registration authored *before* the run. The pass/fail line is
   never moved after seeing results.
7. **Underpowered ≠ refuted ≠ demonstrated.** At small `n`, `demonstrated` and `refuted`
   are definitionally out of reach. An underpowered pilot reports `underpowered` — it is
   not laundered into a value verdict in either direction.
8. **distinct-ids ≠ proven diversity.** Distinct model IDs in a council are an *outcome
   delta*, never proof of genuine cognitive diversity (RISK-B-007). We never let a
   distinct-count stand in for a diversity claim.
9. **Self-correction is logged, not hidden.** When the instrument caught its own bugs
   (a regex error, spec leaks, a hand-fed estimate, a dead real-path), we report the
   correction and re-run, in the open.

---

## Two kinds of entry — same honesty standard

The register holds two distinct kinds of run. Conflating them would itself be a form of
sugar-coating, so we separate them explicitly:

- **Experiments** — hypothesis-driven measurements with arms, a metric, and a verdict
  against a (pre-)registered expectation. They can *demonstrate*, *refute*, show a
  *tradeoff*, or come back *underpowered*. (EXP-001, EXP-002, EXP-008-PENDING.)
- **Real-boundary smokes** — capability proofs, not hypothesis tests. They answer "does
  this path actually cross the real boundary and behave, or is it fake/dead code?" Their
  verdict is `proven` / `RED(confidence)` per claim, *not* a catch-rate. A smoke that
  proves a capability says **nothing** about whether that capability adds *value* — the
  value question stays open until a powered experiment answers it. (SMK-003 … SMK-007.)

Both are held to the same evidence-class discipline and the same no-overclaim rule.

---

## Standard entry structure

Every entry file follows this skeleton, in this order:

**ID · Date · Kind** → **Hypothesis** → **Pre-registration (if any)** → **Method**
(arms / corpus / models / metrics / n) → **Results (as captured — both metrics)** →
**Honest interpretation** (including *what it does NOT show*) → **Limitations / confounds**
→ **What we learned** → **Evidence class** → **Source artifacts** (cited, read before
writing).

---

## Index

| ID | Date | Kind | One-line honest outcome | Evidence class |
|---|---|---|---|---|
| [EXP-001](EXP-001-dna-model-capability-qa.md) | 2026-05-29/30 | Experiment | DNA helps test-*planning* (5× recall); at the *build* boundary it is precision-safe but result-neutral — and on sub-Opus it is a catch-vs-cry-wolf **tradeoff**, not a win. The real lever is model tier, not prompt. | mutation-oracle measurement (n=3/cell, 2–3 model tiers) |
| [EXP-002](EXP-002-full-pipeline-slice.md) | 2026-06-02 | Experiment | n=6 slice: on Opus the DNA is a clean win (same catch, ~4× less cry-wolf); on Haiku it **halves escapes but raises false positives** — "strictly better" is **false**. Underpowered, gap+control both run. | full-pipeline A/B, n=6/cell |
| [SMK-003](SMK-003-true-line-live-validation.md) | 2026-06-13 | Real-boundary smoke | Watcher blocks a planted value contradiction 3/3, cry-wolf 0/3 on controls — but `pause`s the borderline `subtle` arm 2/2 (over-pausing disclosed). Opus-only; not the full orchestration. | real-boundary-smoke (Watcher judgment, n=8) |
| [SMK-004](SMK-004-runtime-start-governance.md) | 2026-06-18 | Real-boundary smoke | The PreToolUse hook DENIES real planning/coding dispatches under VISION_MISSING (real-boundary-smoke); the command-gate halt stays honestly **integration-fake** (RED for live-model obedience). | real-boundary-smoke (hook) / integration-fake (command-gate) |
| [SMK-005](SMK-005-openrouter-council-backend-smoke.md) | 2026-06-18 | Real-boundary smoke | Live catalog reachability + normalized-base diversity gate proven against real OpenRouter (variant aliases collapse to 1). **Invocability and deep diversity stay RED(confidence)** — no paid probe run. | real-boundary-smoke (reachability) / RED (invocability) |
| [SMK-006](SMK-006-openrouter-inference-smoke.md) | 2026-06-19 | Real-boundary smoke | A real completion returned for **one** free model; the module's OWN heuristic drift measured (10 est. vs 18 real → +8). One model, one datapoint — broader invocability RED. Corrects an earlier hand-fed-estimate capture. | real-boundary-smoke (one model) / RED (general) |
| [SMK-007](SMK-007-deepseek-foreign-council-smoke.md) | 2026-06-19 | Real-boundary smoke | A foreign (non-Claude) model ran a `/concilium` character live and returned a real in-character position; 4 distinct free families resolved. 1/4 roles invocable (rest rate-limited/unavailable). Value LIFT **NOT CLAIMED**. | real-boundary-smoke (capability) / NOT-CLAIMED (value) |
| [EXP-008-PENDING](EXP-008-PENDING-powered-council-measurement.md) | 2026-06-20 (pilot) | Experiment (pilot → PENDING) | n=2 pilot came back **`underpowered`**, 0/2 survivors, **100% free-tier Arm-B attrition**. NOT a value verdict. The powered run (paid Arm-B, n≫2, presets A/B/C) is **pre-registered but not yet run**. | underpowered pilot (real-boundary-smoke of mechanism only) |
| [EXP-009](EXP-009-free-diversity-probe.md) | 2026-06-20 | Experiment (best-effort, underpowered) | No-budget free-only reframe (NOT vs Claude). One run, 0 attrition: free council showed **no catch advantage** (both 100% on a **saturated** n=2 corpus → no headroom) and **added cry-wolf** (+0.25) — a directional hint of "more reviewers → more noise", leaning *against* the council. `underpowered`, not a verdict. | underpowered (real-boundary-smoke of mechanism on free models) |

**Outcome legend:** Experiments can be `demonstrated` / `refuted` / `tradeoff` /
`underpowered`. Smokes are `proven` / `RED(confidence)` / `NOT-CLAIMED` per claim. Nothing
in this table is rounded up.

---

## What this register deliberately does NOT claim

- It does **not** claim the framework's DNA makes weak models reach the real test
  boundary. We measured the opposite (EXP-001).
- It does **not** claim the foreign council catches more or is more diverse than
  Claude-only. That experiment is `PENDING` (EXP-008-PENDING) and the only run so far was
  underpowered.
- It does **not** claim any OpenRouter completion path is broadly invocable. We proved one
  model, once (SMK-006/007); the general claim is RED.
- It does **not** claim the live `/agileteam` orchestrator obeys its own start-gate at
  runtime. Only the harness hook is proven; the command-gate is integration-fake (SMK-004).

---

## Source-of-truth artifacts (the raw evidence behind this register)

- Mutation-oracle write-up: [`metrics/SUMMARY-2026-05-30-dna-investigation.md`](../../metrics/SUMMARY-2026-05-30-dna-investigation.md)
  and the per-run reports [`metrics/bench-2026-05-29-*.md`](../../metrics/).
- Run ledger: [`metrics/runs.jsonl`](../../metrics/runs.jsonl).
- Benchmark write-ups: [`docs/benchmarks/`](../benchmarks/).
- Pre-registration: [`metrics/pre-registration-council-measurement-run.json`](../../metrics/pre-registration-council-measurement-run.json).
- Reality ledgers (per-feature evidence class): [`docs/reality/`](../reality/).
</content>
