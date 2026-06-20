# Product Canvas: Council Measurement RUN — Slice 3b: RUN the foreign-model-council measurement on the 3a substrate and PUBLISH the honest result ("does foreign cognition catch what Claude misses, WITHOUT raising cry-wolf?")

Status: user-confirmed
Status note: FROZEN after a SINGLE spec-auditor remediation pass (Ben-approved, 2026-06-20) — measurement-integrity fixes applied (arm symmetry / symmetric flag protocol; Arm-A real transport in the new run script; estimated-budget reframe; minimum-survivors floor; n=2 rubric; one-preset pilot). Status remains user-confirmed; no re-audit. (This note is carried IDENTICALLY in §"User confirmation" and the closing blockquote — the Slice-3a partial-flip lesson.)
Owner: requirements-analyst
Confirmed by user: yes (Ben, 2026-06-20, Phase-0.15 gate)
Canvas file: docs/canvas/council-measurement-run.canvas.md
Feature-Slug: council-measurement-run (branch `agileteam/council-measurement-run`; a SEPARATE slice from `council-diversity-measurement` (3a), which is on main and is consumed read-only)
Slice: 3b of 4 — the MEASUREMENT RUN. (3a = the substrate, on main, read-only here; Slice 4 = the GUI.)

> The Product Canvas is a **mandatory pre-build value-alignment artifact**. `/agileteam`
> may not finalize the PRD or enter development until this canvas is filled in, saved,
> linked to PRD/Vision/traceability, and **explicitly confirmed by the user**.
>
> Allowed `Status` values: `draft` | `user-confirmed` | `blocked`. This canvas is
> **`user-confirmed`** — the user (Ben) confirmed it at the Phase-0.15 gate on 2026-06-20,
> having decided OQ-3b-1..4 and acknowledged OQ-DM-8 (resolutions recorded in §"Open
> Questions" below). No agent self-confirmed. **Two run-time BLOCKERs survive canvas
> confirmation by user decision** (they are NOT product-critical canvas gaps — they are
> deliberate pre-run gates): the live run stays a BLOCKER until the user NAMES the
> token/$ budget cap immediately before it (OQ-3b-1), and the scored run stays a BLOCKER
> until the pre-registered pass/fail line is FROZEN + timestamped before the first scored
> run (OQ-3b-4). Canvas confirmation unblocks PRD finalization + planning + the
> OFFLINE-validatable build; it does NOT unblock any live/scored run.

> **What Slice 3b IS — the RUN + the HONEST WRITE-UP, whatever it shows.** Slice 3a (on
> main, `user-confirmed`) BUILT and offline-validated the SUBSTRATE: the frozen,
> council-independent corpus `metrics/corpus/council-review-catch-v1/` (2 seeded-defect
> tasks: T1-auth-token = 1 defect, T2-pagination = 2 defects; clean controls; recall
> controls; deterministic file+line-overlap matcher OQ-DM-7), the Arm-A (Claude-only)
> runner `config/claude/metrics/arm_a_review_runner.py`, and the shared judge-free
> flag-set scorer `config/claude/metrics/council_review_scorer.py`. Slice 3b RUNS that
> instrument to produce the FIRST measurement of the value claim the whole foreign-model
> effort (Slices 1+2) is premised on — **and the RESULT is the deliverable, whatever it
> is**: demonstrated, refuted, tradeoff, or underpowered. An honest write-up (a
> `docs/benchmarks/` or `metrics/` report) and the `runs.jsonl` records ARE the product.

> **THE LOAD-BEARING HONESTY DISCIPLINE (binding — carried verbatim from the 3a canvas /
> vision and the v0.10 DNA precedent). This is the value of the slice, including the
> honest possibility of REFUTING the premise the rest of the foreign-council effort rests
> on.**
>
> 1. **Foreign-only Arm B enforced at RUN time, with a survivors floor.** No `anthropic`/`claude-*`
>    model id may appear in any Arm-B (council) flag-set's `model_scope` — the scorer already exposes
>    a `foreign_only_ok` field for this; 3b asserts it true on every scored Arm-B record. A role/preset
>    whose `code != OK` (budget-exhausted / unresolvable / timeout) is a FLAKINESS event, never scored
>    a miss: it triggers **PAIRED-EXCLUSION** (drop the subject from BOTH arms) — never Claude-substituted.
>    DISTINCT from this: a role whose `code == OK` but whose review yields 0 flags is a LEGITIMATE EMPTY
>    REVIEW — a real potential miss, SCORED (not excluded). Attrition is DISCLOSED by task difficulty
>    (IMPORTANT-2). **MINIMUM-SURVIVORS FLOOR:** if fewer than the pre-registered minimum subjects
>    survive paired-exclusion, the outcome is FORCED to `underpowered/unmeasurable` and NEVER published
>    as a thin result.
> 2. **Both metrics together, always.** Every published claim carries `review_catch_rate`
>    AND `review_cry_wolf_rate` AND `review_recall_control`, with `n`, task count, and
>    model scope visible. A catch-only headline is RED.
> 3. **Distinct ids != uncorrelated cognition (RISK-B-007 / RISK-DM-003).** The result is
>    an OUTCOME DELTA on this corpus, never proven cognitive diversity; the write-up states
>    the non-claim explicitly (the scorer stamps a NON_CLAIM string already).
> 4. **Pre-registered pass/fail line FROZEN before the first scored run** (OQ-3b-4). A
>    null / negative / tradeoff result is a valid PUBLISHED outcome, recorded in
>    `runs.jsonl`, NEVER re-run-until-favourable. **"Underpowered → unmeasurable" is a
>    DISTINCT outcome from "refuted"** and may NOT be laundered as a published null.
> 5. **Bench-isolation.** Any eval inputs are staged OUTSIDE the repo tree; eval/builder
>    sub-agents are text-only or sandboxed; after every run `git status` is clean and
>    `run_all.sh` is green; the deterministic primary scorer is re-runnable offline.

---

## 1. Problem

What real problem should be solved?

Status: CONFIRMED (problem framing clear; the four OQ-3b decisions are RESOLVED by the user 2026-06-20 — see §"Open Questions")

Answer:
The foreign-model-council effort (Slices 1+2, plus the 3a substrate) is premised on an
UNMEASURED value claim: that a foreign (non-Claude) preset council catches defects a
Claude-only review MISSES, WITHOUT raising the cry-wolf (false-alarm) rate. Slice 3a built
the instrument to measure this and proved it works offline — but **no measurement has been
run, so the central justification for the whole foreign-council path is still asserted, not
evidenced.** The diversity gate (Slice 2 / OD-3) currently guards a council whose value is
unknown; Slice 4 (the GUI) would build on an unproven premise. Slice 3b solves this by
RUNNING the 3a instrument to produce the first real datapoint — and the problem is only
honestly solved if the run is willing to REFUTE the premise and publish that as-is. The
product-critical unknowns that must be closed before the run are the paid-pilot budget, the
power/variance framing, the arm composition, and the pre-registered pass/fail line
(OQ-3b-1..4).

---

## 2. Target user / customer

Who has this problem?

Status: CONFIRMED

Answer:
- **Plumbline maintainer / decision-owner (Ben).** Needs a defensible go/no-go datapoint —
  keep, extend (Slice 4 GUI), or retire the foreign-council path — carrying `n`, task count,
  model scope, AND catch + cry-wolf side by side, before paying for more council runs. The
  answer must be honest enough to act on even when it is unfavourable; that is the only kind
  worth a live pilot.
- **The framework's own integrity (the empirical instrument).** Slices 1+2 deferred the
  value claim ONLY because Slice 3 exists to settle it. If 3b is rigged, non-refutable, or
  re-run-until-favourable, every "Slice-3 measurement, not proven here" disclaimer upstream
  becomes a permanent dodge — the deferral was never honest. 3b is where that discipline is
  cashed out.
- **The reviewer / auditor and future readers of the write-up.** They benefit from a
  published result that states exactly what it does and does NOT establish (an outcome delta
  on THIS corpus, not proven cognitive diversity, not generality), so it cannot be misread.

---

## 3. Current workaround

How is the problem handled today?

Status: CONFIRMED (grounded against the repo, 2026-06-20)

Answer:
Today the value claim is UNMEASURED. The instrument exists and is offline-validated (3a, on
main): corpus, Arm-A runner, shared scorer — but `metrics/runs.jsonl` holds only 2 records
and none is a review-catch measurement. The methodological precedent is the 2026-05-30 DNA
investigation (`metrics/SUMMARY-2026-05-30-dna-investigation.md`): it reported catch AND
false-positive together, kept `n`/scope visible, and published a null/tradeoff result (DNA
net-positive on Opus, a catch-vs-cry-wolf tradeoff on sub-Opus) — but it measured a
DIFFERENT question (test-suite mutation-catch, not free-text review-catch) on a different
instrument. So the foreign-vs-Claude review-catch question has the instrument to measure it
but has never been run.

---

## 4. Value proposition

What concrete human/customer value will this create?

Status: CONFIRMED (the value is "a trustworthy answer, whatever it shows"; OQ-3b-1..4 RESOLVED 2026-06-20)

Answer:
- **A trustworthy, refutable answer to the core premise.** After 3b, the team has the first
  real catch-AND-cry-wolf datapoint on whether the foreign council earns its complexity and
  cost — on a council-independent, frozen corpus, with the foreign-only line enforced at run
  time, both metrics together, and scope visible. This unblocks the keep/extend/retire
  decision and Slice 4.
- **The honest write-up IS the product — including a refutation.** The deliverable is the
  RESULT (for the n=2 pilot: `underpowered` or, at most, `tradeoff-signal-to-investigate` — the
  powered FOLLOW-ON run can reach demonstrated/refuted/tradeoff) plus its ESTIMATED upper-bound cost
  (with Arm-A actual usage where exposed), published as-is. Being willing to refute the premise the
  rest of the foreign-council effort is built on, and publishing that refutation, IS the value of
  this slice.
- **The result is correctly classified at its TRUE evidence class.** The live paid pilot is
  `real-boundary-smoke` for that run; the broader/definitive claim stays RED(confidence)
  until a full powered run on an expanded corpus. 3b does NOT over-claim generality.
- **Reuse of the trusted spine.** Results are emitted via `emit_run.py` →
  `metrics/runs.jsonl` (review metrics under `--raw`, NOT `--metrics`, per the scorer's
  `emit-blob`), analyzed via `process_health.py` — no parallel harness.

---

## 5. Success signal

How will we know this is valuable?

Status: CONFIRMED (success = an honest published outcome; the exact pass/fail thresholds are OQ-3b-4, RESOLVED in PRINCIPLE 2026-06-20 — derive-from-corpus-variance via process_health.py — with the exact numbers FROZEN + timestamped in the pre-registration artifact before the first scored run, a run-time BLOCKER)

Answer:
Slice 3b is successful when a TRUSTWORTHY measurement has been RUN and PUBLISHED —
independent of whether the council "wins":
- **A pre-registered pass/fail line exists, timestamped BEFORE the first scored run**
  (demonstrated / refuted / tradeoff / underpowered thresholds + noise model / MDE; OQ-3b-4),
  and the published outcome is judged against it without moving the line.
- **Foreign-only integrity proven at run time, with the OK-empty vs non-OK distinction:** every
  scored Arm-B record has `foreign_only_ok = true` (no `anthropic`/`claude-*` id in `model_scope`);
  a foreign role with `code != OK` (budget-exhausted/timeout/unresolvable) is recorded unavailable and
  PAIRED-EXCLUDED from BOTH arms (flakiness, never a miss, never Claude-substituted); a foreign role
  with `code == OK` and 0 flags is a LEGITIMATE empty review (a real potential miss, SCORED). Attrition
  disclosed by task difficulty; the MINIMUM-SURVIVORS floor forces `underpowered/unmeasurable` if too
  few subjects survive.
- **Both metrics in every published claim:** `review_catch_rate` AND `review_cry_wolf_rate`
  AND `review_recall_control`, with `n`, task count, and model scope visible; a catch-only
  headline fails acceptance.
- **A result is recorded in `metrics/runs.jsonl`** via `emit_run.py` (review metrics under
  `--raw`; `corpus-id = council-review-catch-v1` top-level) and analyzable by
  `process_health.py`; the deterministic primary score is re-runnable offline and yields
  identical numbers on re-run (numeric equality).
- **The write-up exists** (`docs/benchmarks/` or `metrics/`) stating the outcome class, the
  pre-registered line it was judged against, the explicit non-claims (outcome-delta-only, not
  proven diversity, not generality), the attrition, and the cost (ESTIMATED upper bound + ACTUAL
  usage where exposed — see the budget bullet below).
- **The n=2 PILOT RUBRIC is honored.** At n=2 the cross-task variance is unestimable, so
  `demonstrated` and `refuted` are DEFINITIONALLY out of reach; the only honest pilot outcomes are
  `underpowered` and (at most) `tradeoff-signal-to-investigate`. A lucky 2/2-vs-0/2 split is NOT
  laundered as `demonstrated`. (The four-outcome rubric still governs the powered FOLLOW-ON run.)
- **Null / tradeoff / underpowered is published as-is**, never re-run-until-favourable;
  "underpowered → unmeasurable" is labeled DISTINCT from "refuted".
- **The pilot was budget-bounded by a MAX-CALLS ceiling** derived from the user-named cap. The
  instrument has only a PER-CALL token cap (`COUNCIL_MAX_TOKENS_PER_RUN`) and DISCARDS the
  response `usage` block on the preset path (EVN-3b-010 `belegt`), so there is NO aggregate-cap
  or actual-aggregate-cost meter. The aggregate budget is therefore a MAX-CALLS ceiling =
  user-named cap ÷ per-call cap (an a-priori upper bound); the live run REFUSES to start without
  the user-named cap. Cost is REPORTED as an ESTIMATED upper bound; ACTUAL usage is recorded only
  where the instrument exposes it — Arm A only, via the DIRECT `run_inference` return (which carries
  the `usage` block). Arm-B actual cost needs a disclosed usage-seam (OQ-DM-8), DEFERRED — not
  silently assumed.
- **The instrument stayed READ-ONLY:** `git diff` over the 3a substrate libs + corpus is
  empty (consumed, not modified); a 3b run-orchestration script is the only new code.
- **Isolation held:** ZERO live calls inside `run_all.sh`; `git status` clean +
  `run_all.sh` green after every run.

---

## 6. Core use case

What is the smallest meaningful use case?

Status: CONFIRMED (OQ-3b-1 budget + OQ-3b-2 power framing RESOLVED by the user 2026-06-20; OQ-3b-3 arm composition NARROWED to ONE preset for the pilot by user DECISION on the spec-auditor remediation 2026-06-20 — see §"Open Questions" OQ-3b-3)

Answer:
The confirmed pilot run (OQ-3b-2 + the remediation-decision OQ-3b-3): with a pre-registered
pass/fail line frozen and a user-named budget cap, run **Arm A (Claude-only) vs Arm B run
as preset A ONLY** (the foreign council; the read-only `deepseek_review.py preset` per-role
`positions` carry foreign `model` ids) over the SAME 2 corpus tasks with the SAME shared
scorer and the SAME pinned instrument snapshot; the Arm-A Claude tier is DISCLOSED. (A/B/C
across all three presets is DEFERRED to the powered full run — the pilot runs one preset to
cut cost and attrition.) Enforce foreign-only on every Arm-B record; PAIRED-EXCLUDE any
subject where an Arm-B role is unavailable and disclose the attrition by difficulty; emit
each arm's catch / cry-wolf / recall via the scorer's `emit-blob` into `runs.jsonl` (review
metrics under `--raw`); analyze with `process_health.py`; and PUBLISH an honest write-up of
the outcome class judged against the pre-registered line, with the ESTIMATED upper-bound
cost reported and ACTUAL usage recorded where the instrument exposes it.

The confirmed framing (OQ-3b-2): run this as a BOUNDED PAID PILOT on the current n=2 whose
PURPOSE is narrow and load-bearing — (a) prove the run-harness works end-to-end LIVE (a
real-boundary-smoke of the RUN MECHANISM) and (b) estimate cost + flakiness. **It is NOT a
value verdict on the council.** Every value-claim path routes through the powered full run
(corpus expansion + A/B/C presets), which is DEFERRED. The pilot is EXPLICITLY UNDERPOWERED;
at n=2 `demonstrated` and `refuted` are DEFINITIONALLY out of reach (see §5 / §8 RISK-3b-001)
— the only honest pilot outcomes are `underpowered` and (at most) `tradeoff-signal-to-investigate`.

**ARM SYMMETRY (the measurement-integrity core).** BOTH arms are prompted in the SAME
structured flag protocol and scored through the SAME parser. The orchestrator appends the
IDENTICAL structured-flag-protocol instruction — emit each finding as a `{file,line,description}`
object inside a single `{"flags": [...]}` JSON — to the `--subject` for BOTH Arm A AND Arm B's
council roles (Arm B via `deepseek_review.py preset --subject`, a confirmed pass-through to each
role's user message — EVN-3b-010 `belegt`). Each arm's raw model output is then parsed by the
SAME `arm_a_review_runner.parse_flag_set` into the `{file,line,description}` flag-set the scorer
consumes. The measurement is therefore of STRUCTURED-FLAG review for BOTH arms (constrained-output,
symmetric), NOT of free-form prose review — that fair scope is stated in the write-up. If a role's
output is not valid protocol JSON, `parse_flag_set` classifies it (`ARM_A_FLAG_PROTOCOL_MALFORMED`
→ EMPTY flag-set), handled IDENTICALLY for BOTH arms — never silently zeroing one arm only.
(The earlier "parse Arm-B free prose with parse_flag_set" requirement was DELETED: `parse_flag_set`
cannot parse free prose — it needs `{"flags":[...]}` JSON — so feeding it unconstrained council
prose yields an empty flag-set and structurally loses the council. The symmetric protocol fixes it.)

A run-orchestration script (`config/claude/metrics/council_measurement_run.py`) drives the
arms → scorer → emit_run loop; NO new instrument is built (the 3a corpus / runner / scorer
are reused, read-only). It calls `arm_a_review_runner` helpers (prompt + `parse_flag_set`)
for both arms' parsing, runs Arm A's real call by invoking `council_inference.run_inference(...)`
DIRECTLY (reaching the SAME `_real_transport` as Arm B — a symmetric real boundary; NOT by
editing the read-only `arm_a_review_runner.py`), and runs Arm B via `deepseek_review.py preset`.

---

## 7. Non-goals

What should explicitly not be built?

Status: CONFIRMED

Answer:
| ID | Excluded | Why |
|---|---|---|
| NGOAL-3b-001 | **Modifying the 3a substrate** — `metrics/corpus/council-review-catch-v1/**`, `config/claude/metrics/{arm_a_review_runner,council_review_scorer}.py` and the read-only instrument `config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py` + `concilium/**`. 3b CONSUMES them. | Measuring an instrument you simultaneously tune is Goodhart; the corpus's ungameability is its value. A genuinely-needed instrument seam is OQ-DM-8 (disclosed, user-authorized only). |
| NGOAL-3b-002 | **Building a new measurement instrument / a parallel metrics harness.** Reuse the 3a corpus/runner/scorer and `emit_run.py` / `process_health.py` / `rule_ledger.py`. | The instrument is 3a; 3b is the RUN. |
| NGOAL-3b-003 | **Tuning the corpus / dropping tasks to flatter an arm** (selecting cases the council happens to catch). The corpus is frozen + content-hashed. | NGOAL-DM-003 Goodhart tripwire carried verbatim; corpus ungameability is load-bearing. |
| NGOAL-3b-004 | **Headlining catch without cry-wolf** / "strictly better" on one metric. | Anti-Goodhart core (RISK-DM-001). Both metrics or it is RED. |
| NGOAL-3b-005 | **Claiming proven uncorrelated / cognitive diversity** from a distinct-model-id outcome delta. | RISK-B-007 / RISK-DM-003 carried verbatim. |
| NGOAL-3b-006 | **Suppressing / re-running-away a null/negative/tradeoff result**; treating "underpowered → unmeasurable" as a published null. | A confirm-only or re-run-until-favourable measurement is Goodharted; an unmeasurable result is NOT a null. |
| NGOAL-3b-007 | **Any Claude/anthropic model id in Arm B**; Claude-substituting a budget-exhausted foreign role; scoring a non-answer as a council miss. | Foreign-only integrity (RISK-DM-011); a contaminated Arm B makes the delta partly Claude-vs-Claude and uninterpretable; carries Slice-2's no-silent-Claude-fallback invariant. |
| NGOAL-3b-008 | **Any live council/eval call inside `run_all.sh` / the offline CI suite.** The live pilot is opt-in, gated (`COUNCIL_INFERENCE_LIVE=1` + `--live`), and isolated. | Cost + tree-pollution + CI-credit-spend guards. |
| NGOAL-3b-009 | **Claiming generality beyond the measured corpus**, or pooling the secondary real-defect-diff set (if run) into the primary number. | The primary is an outcome delta on n=2; generality stays RED(confidence) until a powered run. |
| NGOAL-3b-010 | **A full powered run + corpus expansion as part of THIS slice** (if OQ-3b-2 = pilot-first). | Recommended framing is pilot-then-expand; the powered run is a follow-on slice. |
| NGOAL-3b-011 | **The Slice-4 GUI; the model-resolution fallback cascade (BL-DM-001); auto credit purchase.** | Out of slice. |
| NGOAL-3b-012 | **Building the model-resolution FALLBACK CASCADE / introducing a Claude fallback into the measured council.** | The 3b measurement is FOREIGN-ONLY (OQ-DM-4); the cascade is a separate future slice (BL-DM-001). |

---

## 8. Risks / contradictions

What could make this wrong, useless, unsafe, misleading, too broad, or misaligned?

Status: CONFIRMED (RISK-3b-001..004 RESOLVED by the OQ-3b decisions 2026-06-20; the rest mitigated by the carried discipline. RISK-3b-002/003's run-time BLOCKER mitigations remain ARMED — they gate the live/scored run, by user decision, not the canvas.)

Answer:
| ID | Risk | Likelihood | Impact | Mitigation | Status |
|---|---|---:|---:|---|---|
| RISK-3b-001 | **Underpowered n=2 read as a verdict; a lucky 2/2-vs-0/2 split laundered as `demonstrated`.** A 2-task pilot estimates effect + cost; cross-task variance is unestimable at n=2. | high | high | OQ-3b-2 + the n=2 RUBRIC: at n=2 `demonstrated` and `refuted` are DEFINITIONALLY out of reach; the ONLY honest pilot outcomes are `underpowered` and (at most) `tradeoff-signal-to-investigate`; "underpowered → unmeasurable" is a DISTINCT published outcome (NOT a null, NOT refuted, NOT demonstrated). A 2/2-vs-0/2 split is explicitly guarded against being laundered as a win. The full four-outcome rubric governs only the powered FOLLOW-ON run; the powered run + corpus expansion is the follow-on. | RESOLVED 2026-06-20 (OQ-3b-2 = pilot-then-expand; n=2 rubric fixed; underpowered != refuted != demonstrated). |
| RISK-3b-002 | **Pilot budget unbounded / guessed; aggregate cost mis-claimed.** The instrument has only a PER-CALL cap and DISCARDS the `usage` block on the preset path, so there is no aggregate-cap or actual-aggregate-cost meter. | medium | high | OQ-3b-1: the token/$ cap is named by the USER at the PRE-RUN gate, NOT in the PRD, never guessed; the run REFUSES to start live without it. The aggregate budget is a MAX-CALLS ceiling = user-named cap ÷ per-call cap (an a-priori upper bound); cost is REPORTED as an ESTIMATED upper bound, with ACTUAL usage recorded only where exposed (Arm A via the DIRECT `run_inference` return). The live transport is gated (`COUNCIL_INFERENCE_LIVE=1` + `--live`), OFF by default. Arm-B actual cost needs the disclosed usage-seam OQ-DM-8 (deferred). | RESOLVED-IN-PRINCIPLE 2026-06-20 (OQ-3b-1 = user names the cap; aggregate = max-calls ceiling; cost = estimated upper bound). The run-time BLOCKER REMAINS ARMED by user decision: NO live call until the user names a token/$ cap immediately before the run. |
| RISK-3b-003 | **Pass/fail line written or moved AFTER seeing results.** A post-hoc line lets the council only "win". | medium | high | OQ-3b-4: the line + MDE + noise model are pre-registered and TIMESTAMPED before the first scored run; the noise model is derived from corpus variance via `process_health.py`; "demonstrated" = catch-rate up AND cry-wolf NOT worse; "refuted" = no catch delta outside noise; "tradeoff" = catch up but cry-wolf up; below-MDE = "underpowered" (DISTINCT from refuted). The published outcome is judged against the frozen line; clean controls give cry-wolf its own oracle. | RESOLVED-IN-PRINCIPLE 2026-06-20 (OQ-3b-4 = derive-from-variance; the four-outcome rubric is fixed). The run-time BLOCKER REMAINS ARMED: NO scored run until the exact line is frozen + timestamped. |
| RISK-3b-004 | **Arm composition multiplies cost / confounds the comparison.** Running all three presets (A/B/C) × Claude tier × live cost ≈ 3× Arm-B cost and 3× attrition surface. | medium | medium | OQ-3b-3 (remediation decision 2026-06-20): the PILOT runs ONE preset (A) vs Arm A Claude-only — A/B/C is DEFERRED to the powered full run. Same subjects/scorer, instrument snapshot pinned across arms; Arm-A Claude tier disclosed; cost is bounded by the OQ-3b-1 MAX-CALLS ceiling. One preset cuts pilot cost + attrition. | RESOLVED 2026-06-20 (OQ-3b-3 NARROWED to ONE preset (A) vs Claude-only for the pilot; A/B/C deferred; tier disclosed; snapshot pinned). |
| RISK-3b-005 | **Claude-contaminated Arm B** — a Claude id leaks into the council; the delta is partly Claude-vs-Claude and uninterpretable. | medium | high | The scorer's `foreign_only_ok` is asserted true on EVERY scored Arm-B record; a contaminated record is rejected, not scored. | MITIGATED-BY-SUBSTRATE (3a field), ENFORCED-3b. |
| RISK-3b-006 | **Free-tier / paid flakiness scored as signal** — a 402/429/timeout foreign role counted as a "council miss"; OR the inverse, a legitimate OK-but-empty review wrongly EXCLUDED as flakiness. | high | high | PAIRED-EXCLUSION on `code != OK` ONLY: a foreign role with a non-OK code drops the subject from BOTH arms (flakiness, recorded unavailable, not a miss). A role with `code == OK` and 0 flags is a LEGITIMATE empty review — SCORED as a real potential miss, never excluded. Attrition disclosed by task difficulty; the MINIMUM-SURVIVORS floor forces `underpowered/unmeasurable` below the pre-registered minimum. | BINDING. |
| RISK-3b-007 | **Catch-only headline** — catch reported without cry-wolf, manufacturing a "win" that is really a tradeoff. | medium | high | The scorer emits both families together by construction; every published claim carries both + scope; a catch-only headline is RED. | MITIGATED-BY-SUBSTRATE, ENFORCED-3b. |
| RISK-3b-008 | **Re-run-until-favourable** — an unfavourable run quietly dropped, a flattering one published. | medium | high | Every scored run is recorded in `runs.jsonl`; the published outcome is whatever the pre-registered line says on the recorded runs; no selective deletion. | BINDING. |
| RISK-3b-009 | **Eval pollutes the tree / spends CI credits.** | medium | high | Eval inputs staged OUTSIDE the tree; sub-agents text-only/sandboxed; `git status` clean + `run_all.sh` green after every run; no live call in `run_all.sh`; the deterministic primary is re-runnable. | BINDING. |
| RISK-3b-010 | **Stale-snapshot drift** of the measured instrument across arms. | medium | medium | The pinned instrument commit is recorded; the same snapshot is used for both arms. | BINDING. |
| RISK-3b-011 | **Distinct ids read as proven diversity.** | medium | high | RISK-B-007 carried verbatim; the scorer stamps the NON_CLAIM string; the write-up states outcome-delta-only. | BINDING. |
| RISK-3b-012 | **Over-claiming generality from n=2 / pooling the secondary real-diff set into the primary.** | medium | high | NGOAL-3b-009: the primary is an outcome delta on the named corpus; generality stays RED(confidence); any secondary set is reported separately, never pooled. | BINDING. |
| RISK-3b-013 | **@path / OSError / lax-flag-parser security regressions in the run harness** (carried 3a security notes). | low | medium | Confine any `@path` read to the work dir; surface OSError on the live write (no silent swallow); keep the flag parser STRICT (no inferred locations). | BINDING (carried from 3a). |

---

## 9. Evidence needed

What must be verified before implementation can be considered real?

Status: CONFIRMED (EVN-3b-001..003 are RESOLVED in principle by the OQ-3b decisions 2026-06-20; EVN-3b-001 (frozen line) + EVN-3b-002 (named budget) remain run-time GATES that must be produced before the scored/live run; the rest are run-time verifiable. EVN-3b-010's `deepseek_review.py preset` contract is now `belegt` — re-verified against the real artifact 2026-06-20 during the spec-auditor remediation: `preset --subject` threads the subject verbatim into each role, so the SAME structured-flag protocol is appended to `--subject` for BOTH arms and each OK role's protocol-JSON output is parsed by `parse_flag_set` — the orchestrator does NOT parse free prose, and `wrap_position` discards the `usage` block.)

Answer:
- **EVN-3b-001 — A pre-registered pass/fail line + MDE + noise model is committed and
  TIMESTAMPED before the first scored run** (OQ-3b-4), with the demonstrated / refuted /
  tradeoff / underpowered thresholds explicit and the underpowered case distinct from refuted.
- **EVN-3b-002 — A user-named pilot budget cap is recorded before the live run** (OQ-3b-1);
  the live transport is gated (`COUNCIL_INFERENCE_LIVE=1` + `--live`), OFF by default. The
  aggregate budget is a MAX-CALLS ceiling (user-named cap ÷ per-call cap) — the instrument has
  only a per-call cap and discards the preset-path `usage` (EVN-3b-010 `belegt`). Cost is reported
  as an ESTIMATED upper bound; ACTUAL usage is recorded where exposed (Arm A via the direct
  `run_inference` return). Arm-B actual cost is via the disclosed seam OQ-DM-8 (deferred).
- **EVN-3b-003 — Arm composition is fixed and disclosed** (OQ-3b-3): the PILOT is ONE Arm-B preset
  (A) vs Arm-A Claude-only (A/B/C deferred to the powered run); the Arm-A Claude tier is disclosed;
  the instrument snapshot commit is pinned and recorded across arms.
- **EVN-3b-004 — Foreign-only verified at run time:** every scored Arm-B record has
  `foreign_only_ok = true` (verified against the scorer's real output, not asserted); a
  non-answering foreign role is recorded unavailable + PAIRED-EXCLUDED, attrition disclosed by
  task difficulty.
- **EVN-3b-005 — Both metric families present in every record + every claim:**
  `review_catch_rate` / `review_cry_wolf_rate` / `review_recall_control`, with `n`, task count,
  model scope; verified against the scorer's actual `emit-blob` output and the
  `runs.jsonl` records.
- **EVN-3b-006 — Run-record output matches the REAL `emit_run.py` schema** (IMPORTANT-1):
  review metrics + `arm` + `model_scope` live under `--raw` (NOT `--metrics` — they are NOT in
  the closed `process_health.DIRECTIONS` allowlist; `emit_run` rejects a non-allowlisted
  `--metrics` key); `corpus_id = council-review-catch-v1` goes top-level via `--corpus-id`.
  Verified against `config/claude/metrics/emit_run.py` and the scorer's `emit-blob` subcommand.
- **EVN-3b-007 — Determinism of the primary score:** re-running the scorer over the same
  captured flag-sets yields IDENTICAL numbers (numeric equality, not substring); the corpus
  freeze-hash still equals `manifest.json` "hash".
- **EVN-3b-008 — Isolation proven:** eval inputs staged outside the tree; ZERO live calls
  inside `run_all.sh`; `git status` clean + `run_all.sh` green after every run; the 3a
  substrate files are byte-unchanged (`git diff` empty over them).
- **EVN-3b-009 — Reality Ledger** (`docs/reality/council-measurement-run.evidence.jsonl`,
  authored Phase 3 / Gate C) at the HONEST class per REQ: offline orchestration wiring exercised
  network-free = `integration-fake`; the LIVE PAID PILOT run = `real-boundary-smoke` for THAT
  run only; broader/definitive = RED(confidence) until a powered run. Never raise a class to
  clear a floor; avoid the FORBIDDEN_TOKENS (`fake-only`/`mock-only`/`placeholder`/`unverified`).
- **EVN-3b-010 — Foreign-instrument-contract claims verified against the real artifact** BEFORE
  they become run premises (classified `belegt | ableitbar | ungeprüft | nicht behaupten`).
  Verified 2026-06-20 (spec-auditor remediation, re-confirmed against the real files):
  - `deepseek_review.py preset --subject` threads the subject verbatim into each role's user
    message (`build_character_messages(slug, args.subject, ...)`), so the SAME structured-flag-protocol
    instruction is appendable to `--subject` for Arm B exactly as for Arm A — `belegt`.
  - `preset` returns `positions[].{role,character,model,code,position}`; `position` is the raw
    completion prose, and `wrap_position` DISCARDS the `usage` block (keeps only `completion`) — so
    the preset path exposes NO token usage — `belegt`. (This is why Arm-B actual cost needs OQ-DM-8.)
  - `arm_a_review_runner.parse_flag_set` parses ONLY a `{"flags":[...]}` JSON object (tolerant of a
    ` ```json ` fence); free prose yields `ARM_A_FLAG_PROTOCOL_MALFORMED` → an EMPTY flag-set — so it
    CANNOT parse unconstrained council prose, and BOTH arms must emit the structured protocol — `belegt`.
  - `council_inference.run_inference(...)` is directly callable with `messages` + `transport=_real_transport`,
    gated by `--live` AND `COUNCIL_INFERENCE_LIVE=1`, and its RETURN carries the reconciled `usage` block —
    so the new script reaches Arm A's real boundary WITHOUT editing the read-only `arm_a_review_runner.py`,
    and records Arm-A actual usage — `belegt`.
  - the `emit_run.py` record schema and the scorer's `emit-blob` output shape — `belegt` (per §0 of the PRD).
  Any contract later found `ungeprüft` stays an OPEN QUESTION/BLOCKER, never a "documented risk" premise.
- **EVN-3b-011 — The honest write-up exists** (`docs/benchmarks/` or `metrics/`) stating the
  outcome class (n=2 pilot: `underpowered` / `tradeoff-signal-to-investigate` only), the
  pre-registered line judged against, the explicit non-claims, the FAIR SCOPE (structured-flag review
  for BOTH arms, not free-form prose), the pilot PURPOSE (run-mechanism smoke + cost/flakiness
  estimate, NOT a value verdict), the attrition, and the ESTIMATED upper-bound cost (Arm-A actual
  usage where exposed).

---

## Allowed change scope

> Proposed by the requirements-analyst, grounded against the repo. Final OK given by the user
> at the Phase-0.15 / 0.6 gate. The 3a substrate (corpus + runner + scorer) and the read-only
> instrument (`config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py`,
> `concilium/**`) are **READ-ONLY** — CONSUMED, not modified. 3b adds only a run-orchestration
> script, the benchmark write-up, the 3b docs, the reality ledger, and appends to `runs.jsonl`.
> A genuinely-needed instrument seam is OQ-DM-8 (disclosed, user-authorized only), never
> pre-authorised here.

Machine-parseable scope (PRIL `plumbline-scope-check` / `plumbline_scope.py`): one
backtick-wrapped path per line so the runtime scope guard can parse it. (This intro line
intentionally does NOT start with `-`/`*`/`+` so the parser does not read it as a path.)

- `config/claude/metrics/council_measurement_run.py`
- `config/claude/tests/test_council_measurement_run.sh`
- `config/claude/tests/run_all.sh`
- `config/claude/tests/lib.sh`
- `metrics/runs.jsonl`
- `metrics/*`
- `docs/benchmarks/*`
- `docs/benchmarks/**`
- `docs/canvas/council-measurement-run.canvas.md`
- `docs/prd/council-measurement-run.prd.md`
- `docs/vision/council-measurement-run.vision.md`
- `docs/traceability.md`
- `docs/plans/2026-06-20-council-measurement-run.md`
- `docs/reality/council-measurement-run.evidence.jsonl`
- `backlog.md`
- `CLAUDE.md`

> Note: `council_measurement_run.py` (the run-orchestration script driving arms → scorer →
> emit_run) is the only new code module — its exact filename is a reversible implementation
> detail the planner may finalize, but it lives under `config/claude/metrics/` (NOT under the
> read-only `config/claude/lib/` instrument tree, and NOT a new instrument). If the planner
> chooses a different name, update this list at Phase 0.6 and re-run `plumbline-scope-check`.
> CONSUMED READ-ONLY (must NOT appear as modified): `metrics/corpus/council-review-catch-v1/**`,
> `config/claude/metrics/{arm_a_review_runner,council_review_scorer,emit_run,process_health,rule_ledger}.py`,
> `config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py`,
> `concilium/**`. (`metrics/*` is listed for `runs.jsonl` + the write-up; the corpus subtree
> is NOT in scope to modify.)

---

## 10. Traceability links

PRD: docs/prd/council-measurement-run.prd.md (to be authored after canvas confirmation; REQ-3b-* traced to this canvas)
Product Vision: docs/vision/council-measurement-run.vision.md (to be authored by product-owner after PRD draft; Phase 0 complete only when Canvas + PRD + Vision are all user-confirmed)
Traceability Matrix: docs/traceability.md (slice council-measurement-run; canvas-link: docs/canvas/council-measurement-run.canvas.md)
Related REQ IDs: REQ-3b-001.. (assigned by the PRD), tracing the deferred REQ-DM-3b-* from the 3a PRD §2b
Consumed substrate (READ-ONLY, on main): metrics/corpus/council-review-catch-v1/** ; config/claude/metrics/arm_a_review_runner.py ; config/claude/metrics/council_review_scorer.py
Consumed instrument (READ-ONLY): config/claude/lib/deepseek_review.py (Arm B = `preset`), council_presets.py, council_inference.py, council_backend.py
Reused harness: config/claude/metrics/{emit_run,process_health,rule_ledger}.py
Upstream 3a artifacts: docs/canvas/council-diversity-measurement.canvas.md ; docs/prd/council-diversity-measurement.prd.md (§2b deferred REQ-DM-3b-001.., OQ-DM-1..6 resolutions) ; docs/vision/council-diversity-measurement.vision.md
Method precedent (published null/tradeoff): metrics/SUMMARY-2026-05-30-dna-investigation.md
Backlog hand-off: backlog.md BL-DM-001 (model-resolution fallback cascade, separate slice); BL-DM-002 (this slice, the measurement RUN)
True-Line status: user-confirmed

---

## Open Questions (RESOLVED with the user at the Phase-0.15 gate — Ben, 2026-06-20)

All four product-critical OQs were closed WITH the user (not self-answered). Two run-time
BLOCKERs are RETAINED BY USER DECISION as pre-run gates (they are not unresolved canvas
gaps): the live run needs a user-named budget (OQ-3b-1) and the scored run needs a frozen,
timestamped pre-registered line (OQ-3b-4). OQ-DM-8 is resolved to read-only measurement,
with the Phase-3 contract read now done (EVN-3b-010 `belegt`).

| ID | Question | USER RESOLUTION (Ben, 2026-06-20) | Status |
|---|---|---|---|
| **OQ-3b-1** | **PAID PILOT BUDGET** (OPEN-DM-A). What is the token/$ cap for the pilot? | **Pilot budget is NAMED BY THE USER at the PRE-RUN gate — NOT in the PRD.** The canvas/PRD finalize WITHOUT a number; the live run REFUSES to start without it; the cap becomes a MAX-CALLS ceiling (cap ÷ per-call cap, an a-priori upper bound — there is NO aggregate-cost meter); cost is reported as an ESTIMATED upper bound with Arm-A actual usage where exposed. No live call until the user names the cap immediately before the run. | RESOLVED-IN-PRINCIPLE; **run-time BLOCKER RETAINED — no live call until the user names a token/$ cap immediately before the run.** |
| **OQ-3b-2** | **Thin variance (n=2 tasks).** Pilot on n=2 as an estimate, or expand the corpus first? | **Pilot on the current n=2 as an EXPLICITLY UNDERPOWERED effect+cost ESTIMATE**, then (follow-on) expand `council-review-catch-v1` + run a powered full run. **Underpowered != refuted** — it is a distinct published outcome, never laundered as a null. | RESOLVED. |
| **OQ-3b-3** | **Arm composition.** Which preset(s) in Arm B? Which Claude tier in Arm A? | **PILOT: ONE preset (A) vs Arm A Claude-only** (remediation decision 2026-06-20 — overrides the prior A+B+C answer FOR THE PILOT; A/B/C is DEFERRED to the powered full run, cutting pilot cost + attrition). Same subjects/scorer, instrument snapshot PINNED across arms; the Arm-A Claude tier is DISCLOSED. BOTH arms use the SAME structured flag protocol (appended to `--subject`) and the SAME `parse_flag_set`. | RESOLVED (NARROWED to one preset for the pilot; A/B/C → powered run). |
| **OQ-3b-4** | **The pre-registered pass/fail line + MDE.** | **Pre-registered pass/fail line FROZEN + timestamped before the first scored run.** Derive the noise model from corpus variance, computed by the orchestrator over the captured per-task scores (`process_health.py` reads `metrics`, not `raw`, where the review scores live — PRD §0 `belegt`). FOLLOW-ON (powered-run) rubric: "demonstrated" = catch-rate up AND cry-wolf NOT worse; "refuted" = no catch delta outside noise; "tradeoff" = catch up but cry-wolf up; below-MDE = "underpowered" (DISTINCT from refuted). PILOT (n=2) rubric: only `underpowered` / `tradeoff-signal-to-investigate` are reachable — `demonstrated`/`refuted` are definitionally out of reach (RISK-3b-001); plus a MINIMUM-SURVIVORS floor forcing `underpowered/unmeasurable`. | RESOLVED-IN-PRINCIPLE; **run-time BLOCKER RETAINED — no scored run until the exact line is frozen + timestamped.** |
| OQ-DM-8 (carried) | **Is any instrument SEAM needed for Arm B?** | **READ-ONLY measurement suffices for the pilot** against the existing `deepseek_review.py preset` per-role output. Phase-3 contract read DONE (EVN-3b-010 `belegt`): `preset --subject` threads the subject into each role, so the SAME structured-flag-protocol instruction is appended to `--subject` for Arm B; each role's OK `position` (the model's protocol JSON output) is parsed by `parse_flag_set` — the orchestrator does NOT parse free prose. **One disclosed seam is NOTED but DEFERRED:** the preset path discards the `usage` block, so Arm-B ACTUAL token cost would need a usage-exposing seam — USER-AUTHORIZED + DISCLOSED only, NOT taken in 3b (the pilot reports the estimated upper bound + Arm-A actual only). | RESOLVED — read-only suffices for the pilot; the usage seam is disclosed + deferred, never silently assumed. |

---

## User confirmation

Confirmed by user: yes
Confirmation date: 2026-06-20
Confirmation note: Confirmed by Ben at the Phase-0.15 gate. OQ-3b-1..4 decided and OQ-DM-8
acknowledged (resolutions recorded in §"Open Questions"). Confirmation unblocks PRD
finalization, planning, and the OFFLINE-validatable build. By the user's own decision it
does NOT unblock any live/scored run: OQ-3b-1 (user-named budget) and OQ-3b-4 (frozen,
timestamped pre-registered line) remain RETAINED run-time BLOCKERs for the live/scored run.
Status note (carried IDENTICALLY in the header + closing blockquote — Slice-3a partial-flip
lesson): this canvas was FROZEN after a SINGLE spec-auditor remediation pass (Ben-approved,
2026-06-20) — measurement-integrity fixes applied (arm symmetry / symmetric flag protocol;
Arm-A real transport in the new run script; estimated-budget reframe; minimum-survivors
floor; n=2 rubric; one-preset pilot). Status remains user-confirmed; no re-audit.

> This canvas is `user-confirmed` (Ben, 2026-06-20). It was confirmed at the Phase-0.15
> gate after the user decided OQ-3b-1..4 and acknowledged OQ-DM-8; no agent self-confirmed.
> Two run-time BLOCKERs are RETAINED BY USER DECISION and survive this confirmation:
> OQ-3b-1 (a user-named token/$ budget cap) gates the LIVE run, and OQ-3b-4 (a frozen +
> timestamped pre-registered pass/fail line) gates the SCORED run. Neither is an
> unresolved canvas gap — they are deliberate pre-run gates.
> Status note (carried IDENTICALLY in the header + §"User confirmation"): FROZEN after a
> SINGLE spec-auditor remediation pass (Ben-approved, 2026-06-20) — measurement-integrity
> fixes applied (arm symmetry / symmetric flag protocol; Arm-A real transport in the new
> run script; estimated-budget reframe; minimum-survivors floor; n=2 rubric; one-preset
> pilot). Status remains user-confirmed; no re-audit.

Confirmation phrase (uttered by the user when confirming):

```text
I confirm this Slice-3b Council Measurement RUN Product Canvas as the basis for AgileTeam planning.
```
