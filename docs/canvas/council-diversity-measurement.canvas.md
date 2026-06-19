# Product Canvas: Council Diversity Measurement — Slice 3a: build the measurement SUBSTRATE for "does foreign-model (non-Claude) cognition catch defects a Claude-only review MISSES, without raising the cry-wolf rate?"

Status: user-confirmed
Owner: requirements-analyst
Confirmed by user: yes (Ben 2026-06-19, re-confirmed after the BLOCKER re-scope; OQ-DM-7 = structured flag protocol + location-overlap)
Confirmation date: 2026-06-19
Confirmation note: This canvas was previously `user-confirmed` (Ben, 2026-06-19) for a Slice-3 that bundled SUBSTRATE + MEASUREMENT. The spec-auditor (Phase 0.5) found **4 BLOCKERs**: the measurement SUBSTRATE the design assumed does not exist, and the named corpus was wrong (read off the wrong file). Ben decided (2026-06-19): (1) BUILD A NEW review-catch corpus; (2) SPLIT this slice into **Slice 3a (substrate, this canvas)** and **Slice 3b (the measurement RUN, deferred)**. This was a material re-scope, so the re-scoped canvas was put to the user for explicit re-confirmation — and Ben RE-CONFIRMED it on 2026-06-19 ("Bestätigt — 3a bauen"), choosing OQ-DM-7 = structured flag protocol + location-overlap. Status is therefore `user-confirmed`. No agent self-confirmed it; the user re-confirmed it.
Canvas file: docs/canvas/council-diversity-measurement.canvas.md
Feature-Slug: council-diversity-measurement  (UNCHANGED — the branch `agileteam/council-diversity-measurement` and the PRIL Allowed-change-scope use it; the SCOPE is reframed, not the slug)
Slice: 3a of 4 — the MEASUREMENT SUBSTRATE. (3b = the deferred measurement RUN; Slice 4 = the GUI.)

> The Product Canvas is a **mandatory pre-build value-alignment artifact**. `/agileteam`
> may not finalize the PRD or enter development until this canvas is filled in, saved,
> linked to PRD/Vision/traceability, and **explicitly (re-)confirmed by the user**.
>
> Allowed `Status` values: `draft` | `user-confirmed` | `blocked`. This canvas is
> **`user-confirmed`** — the user re-confirmed the re-scope on 2026-06-19 (Ben,
> "Bestätigt — 3a bauen"). The six original
> `OPEN QUESTION`s (OQ-DM-1..6) about the MEASUREMENT were resolved by the user on
> 2026-06-19 and remain binding **for Slice 3b**; Slice 3a inherits them as the design
> constraints the substrate must SATISFY, and adds one genuinely-new open question of its
> own — the flag→seeded-defect MATCHING RULE (OQ-DM-7) — surfaced by the substrate work.

> **What changed and why (the spec-auditor remediation).** The previous Slice-3 canvas/PRD
> assumed it could measure foreign-vs-Claude review catch by REUSING `pipe-providedfake-v1`
> as "the catch + cry-wolf + recall corpus" and by running both arms through the existing
> `metrics/corpus/**` test-suite scorers. The audit disproved both premises against the
> real artifacts (verified 2026-06-19 by reading the files):
>
> 1. **BLOCKER-1 (wrong corpus).** `metrics/corpus/pipe-providedfake-v1/` contains ONE task
>    (`P1-login-audit`) and a single dark-zone mutator (`mutate_providedfake.py`, neuters
>    one real FileStore.append boundary). It has **no clean control, no recall control, no
>    cry-wolf oracle**. The "escaped-defect + false-positive control + reviewer-recall"
>    TRIPLE the canvas attributed to it is actually a property of **`pipe-core-v1`**
>    (`manifest.json`: primary `escaped_defect_rate`, secondary `pipeline_false_positive_rate`
>    on CTRL tasks + `reviewer_non_wiring_recall` on RDIFF tasks). The claim was read off the
>    wrong file. → A NEW corpus replaces it as PRIMARY.
> 2. **BLOCKER-2 (no variance / saturated single task).** A one-task corpus has two outcomes
>    (CAUGHT/ESCAPED) but **no across-task variance**, so 3b could not pin a noise threshold
>    or a minimum-detectable-effect (MDE) — exactly what OQ-DM-5's pre-registered pass/fail
>    line needs. → The new corpus MUST have real variance (≥2 distinct task outcomes).
> 3. **BLOCKER-3 (no substrate: scorer + Arm-A runner do not exist).** Both existing scorers
>    (`pipe-core-v1/score.py`, the mutators) score **test-suite RED/GREEN** — "did the arm's
>    own pytest suite catch the planted mutation". A `/concilium` review and a Claude-only
>    review produce **free-text findings, not a pytest suite**, so neither existing scorer
>    fits the foreign-vs-Claude REVIEW comparison. And `config/claude/lib/deepseek_review.py`
>    has only `run` / `preset` subcommands (the council = Arm B); there is **no Claude-only
>    Arm-A runner**, and the instrument libs are READ-ONLY (NGOAL-DM-001). → 3a must BUILD a
>    separate Arm-A runner + a NEW shared flag-set scorer.
> 4. **BLOCKER-4 (Vision self-contradiction).** The Vision header said `user-confirmed` while
>    its body (line ~210) said `draft`. → The WHOLE Vision was first reconciled to a single
>    consistent status, then re-confirmed by the user (Ben, 2026-06-19) — header and body now
>    consistently `user-confirmed`.

> **What Slice 3a IS — the SUBSTRATE, not the result.** Slice 3a delivers three buildable,
> OFFLINE-verifiable artifacts that make the 3b measurement POSSIBLE. It does NOT run the
> measurement, does NOT spend pilot budget, and does NOT produce a catch/cry-wolf number.
> The deliverable is the *instrument the measurement will use*, validated network-free.
> Slice 3b RUNS it.

> **What Slice 3a is NOT — the measurement RUN (all deferred to Slice 3b).** Arm-A-vs-Arm-B
> execution on the new corpus; the pre-registered pass/fail evaluation
> (demonstrated/refuted/tradeoff/underpowered); the PAID PILOT (OPEN-DM-A budget moves to
> 3b); the `runs.jsonl` emission + `process_health.py` analysis; the honest write-up. All
> of OQ-DM-1..6's *execution* consequences live in 3b.

> **THE LOAD-BEARING HONESTY DISCIPLINE (binding — carried verbatim, still the deliverable).**
> Slice 3a builds the instrument that 3b uses to measure the value the whole foreign-model
> effort is premised on, so the anti-Goodhart discipline is BUILT INTO the substrate, not
> bolted on in 3b:
>
> 1. **BOTH metrics, by construction.** The new corpus MUST carry BOTH a seeded-defect set
>    (for catch) AND clean controls (for cry-wolf/false-positive) AND a recall/no-narrowing
>    control — so 3b *cannot* report catch without cry-wolf because the substrate forces both.
> 2. **Scope is a first-class field.** The scorer's output schema carries `n`, task count,
>    and model scope so every downstream claim must show them.
> 3. **Distinct ids != uncorrelated cognition (RISK-B-007 / RISK-DS-004, reused verbatim).**
>    The substrate measures an OUTCOME DELTA on this corpus; it can never establish proven
>    cognitive diversity. The scorer schema reserves a field for the explicit non-claim.
> 4. **The corpus is authored INDEPENDENTLY of the council — the NGOAL-DM-003 Goodhart
>    tripwire is baked in.** Defects are seeded BEFORE and independent of any review (so they
>    are ungameable); the corpus is NEVER tuned to flatter the council; it is frozen +
>    version-stamped at author time.
> 5. **Underpowered is a DISTINCT outcome from refuted.** The corpus must have enough
>    variance for 3b to compute an MDE; a "no variance → unmeasurable" result may NOT be
>    laundered as a published null. (BLOCKER-2.)

> **Build ON the existing harness — do NOT reinvent (NGOAL-DM-002).** 3a reuses, unchanged:
> the deterministic-oracle corpus philosophy in `metrics/corpus/**` (frozen tasks +
> oracle + score; "report all metric families together; 0-escaped with no control data is
> NOT a pass"); `config/claude/metrics/emit_run.py` (the run-record schema 3b will emit
> into `metrics/runs.jsonl`); `process_health.py`; `rule_ledger.py`. Verified 2026-06-19:
> the harness + corpora (`bench-core-v1`, `pipe-core-v1`, `pipe-nonlocal-v1`,
> `pipe-providedfake-v1`, `challenge-token-oracle`) exist; `runs.jsonl` holds 2 records.

> **Benchmark/eval ISOLATION (binding).** Even though 3a does not RUN the live measurement,
> any offline validation of the substrate MUST stage inputs OUTSIDE the tree, keep
> builder/eval sub-agents TEXT-ONLY or sandboxed, and verify `git status` clean +
> `run_all.sh` green after every run. The new corpus is authored UNDER `metrics/corpus/`
> deliberately (it is a versioned artifact, not a throwaway eval input) — but no live
> council call ever runs inside `run_all.sh`.

---

## 1. Problem

What real problem should be solved?

Status: RESOLVED (re-scoped to the substrate gap; Ben 2026-06-19)

Answer:
The foreign-model-council effort (Slices 1+2) is premised on an UNMEASURED value claim — that
foreign (non-Claude) cognition catches defects a Claude-only review MISSES without raising the
cry-wolf rate. Slice 3 was supposed to measure it, but the spec-auditor found **the measurement
cannot even begin: the instrument it needs does not exist.** There is no review-catch corpus with
seeded defects + clean controls + a recall control (the named one, `pipe-providedfake-v1`, is a
single-task wired-in-prod mutator with none of those properties); there is no Claude-only Arm-A
runner (the on-`main` runner only runs the council = Arm B); and there is no scorer that consumes a
REVIEWER FLAG-SET (both arms emit free-text findings, not a pytest suite, so the existing
test-suite-RED/GREEN scorers do not fit). **The problem Slice 3a solves is building that missing
SUBSTRATE** — a frozen, council-independent review-catch corpus with real variance, an Arm-A
runner, and a single shared flag-set scorer — all offline-verifiable, so that Slice 3b can actually
run the honest, anti-Goodhart measurement. Without 3a, 3b is unbuildable; with a wrong substrate,
3b would produce a confabulated number.

---

## 2. Target user / customer

Who has this problem?

Status: RESOLVED (Ben 2026-06-19)

Answer:
- **Plumbline maintainer / decision-owner (Ben).** Needs the measurement to be POSSIBLE and
  TRUSTWORTHY before paying for a live pilot. A substrate that is wrong or gameable means the eventual
  go/no-go datapoint is worthless. 3a is the precondition for the answer Ben actually wants in 3b.
- **The reviewer / auditor (and future readers of the 3b write-up).** The substrate is where the
  anti-Goodhart guarantees physically live (seeded-before/independent defects, clean controls, a
  blind-or-deterministic matcher). If the corpus is gameable, no amount of careful 3b prose rescues it.
- **Slice 3b itself (the immediate downstream consumer).** 3b CANNOT start without 3a's corpus, runner,
  and scorer. 3a's success criterion is "3b has a correct, offline-validated instrument to run."

---

## 3. Current workaround

How is the problem handled today?

Status: CONFIRMED (grounded against the repo, 2026-06-19)

Answer:
Today there is NO review-catch substrate at all. The only related artifacts are: the test-suite
mutation-oracle corpora (`pipe-core-v1` etc.) which score "did the arm's own pytest suite catch a
planted mutation" — a DIFFERENT question from "did a free-text REVIEW flag a defect"; and the
2026-05-30 DNA investigation (`metrics/SUMMARY-2026-05-30-dna-investigation.md`), the methodological
precedent (catch AND false-positive reported together, `n`/scope visible, a published null/tradeoff)
— but it measured a different question and built a different instrument. So the foreign-vs-Claude
REVIEW-catch question has neither been measured NOR has the instrument to measure it. 3a builds that
instrument.

---

## 4. Value proposition

What concrete human/customer value will this create?

Status: RESOLVED — the value of 3a is a CORRECT, GAMEPROOF, OFFLINE-VALIDATED measurement instrument; the value of the *council* is 3b's OUTPUT (Ben 2026-06-19)

Answer:
- **A measurement that 3b can actually run, and trust.** After 3a, the team has a frozen,
  council-independent review-catch corpus (seeded defects + clean controls + recall control, with real
  variance), a Claude-only Arm-A runner, and a single shared flag-set scorer — each verified offline.
  3b can then produce a defensible, anti-Goodhart catch-AND-cry-wolf answer instead of an unbuildable
  or confabulated one.
- **The anti-Goodhart guarantees are STRUCTURAL, not editorial.** Because the corpus has clean controls
  baked in, 3b physically cannot report catch without cry-wolf. Because defects are seeded
  before/independent of any review, the corpus is ungameable. The honesty lives in the substrate.
- **Reuse of the trusted spine.** The scorer emits into the existing `emit_run.py` record shape (3b
  appends to `runs.jsonl`, `process_health.py` analyzes) — no parallel harness (NGOAL-DM-002).
- **3a does NOT assert the council adds value.** That is 3b's OUTPUT, unknown until it runs (OQ-DM-5/6).
  3a's value is exclusively the trustworthy instrument.

---

## 5. Success signal

How will we know this is valuable?

Status: RESOLVED — substrate-completeness criteria, all OFFLINE-verifiable (Ben 2026-06-19)

Answer:
Slice 3a is successful when the SUBSTRATE is complete and offline-validated — independent of any
measurement result (there is none in 3a):
- **A NEW review-catch corpus exists** under `metrics/corpus/<new>/`, frozen + version-stamped, with:
  (i) a set of code diffs each carrying a KNOWN seeded-defect oracle (defects seeded BEFORE/independent
  of any review → ungameable); (ii) clean controls (diffs/lines with NO seeded defect, for cry-wolf);
  (iii) a recall/no-narrowing control; and (iv) **real variance — ≥2 distinct task outcomes** (NOT a
  saturated single task), so 3b can pin a noise threshold + MDE (BLOCKER-2).
- **An Arm-A (Claude-only review) runner exists** as a SEPARATE entrypoint (NOT an edit to the read-only
  instrument; NGOAL-DM-001 / BLOCKER-3).
- **A single shared SCORER exists** that BOTH arms feed, consuming a REVIEWER FLAG-SET (not pytest
  RED/GREEN): catch = a review flags a real seeded defect; cry-wolf = a review flags where no defect was
  seeded (clean control); recall-control = guards against narrowing. Its output schema carries `n`, task
  count, model scope, and BOTH metric families together.
- **The flag→seeded-defect MATCHING RULE is specified and deterministic** (OQ-DM-7) — OR, if it cannot
  be made deterministic for some subset, that subset is explicitly an OPEN QUESTION raised to the user,
  never silently judged.
- **Everything is offline-validated:** the corpus mutator/oracle, the Arm-A runner (with a fake/injected
  transport, 0 credits), and the scorer all run network-free; `git status` clean + `run_all.sh` green
  afterward; ZERO live council calls.
- **The instrument stays READ-ONLY:** `git diff` over
  `config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py` and
  `concilium/**` is empty. Any genuinely-needed seam is a DISCLOSED OPEN QUESTION, never a silent edit.

---

## 6. Core use case

What is the smallest meaningful use case?

Status: RESOLVED (re-scoped to the substrate; Ben 2026-06-19)

Answer:
The smallest meaningful substrate: author a frozen review-catch corpus of a handful of code diffs —
some carrying a seeded defect with a known oracle, some clean controls with no seeded defect, plus a
recall-control case — with ≥2 distinct task outcomes for variance; build a Claude-only Arm-A runner as
a separate entrypoint that produces a flag-set over a given diff (offline via an injected transport);
build a single shared scorer that takes a flag-set + the corpus oracle and computes catch / cry-wolf /
recall per arm using a deterministic flag→seeded-defect matching rule; and prove all three run offline,
network-free, leaving the tree clean. No live call, no pilot budget, no measurement number — that is
all Slice 3b.

The three buildable artifacts (each offline-verifiable):
- **ART-3a-1 — NEW frozen, council-INDEPENDENT review-catch corpus.** Seeded-defect diffs (oracle
  seeded BEFORE/independent of review → ungameable) + clean controls (cry-wolf) + recall control; real
  variance (≥2 distinct task outcomes); frozen + version-stamped; NGOAL-DM-003 tripwire baked in.
- **ART-3a-2 — Arm-A (Claude-only) runner.** A SEPARATE runner/entrypoint (the on-`main`
  `deepseek_review.py` only has `run`/`preset` = the council/Arm B; instrument is read-only). Produces a
  reviewer flag-set over a corpus diff. Offline via injected transport (0 credits). Any instrument seam
  truly needed = DISCLOSED OPEN QUESTION (OQ-DM-8), never a silent edit.
- **ART-3a-3 — Single shared SCORER (both arms feed it).** Consumes a REVIEWER FLAG-SET, not test-suite
  RED/GREEN. catch = flags a real seeded defect; cry-wolf = flags on a clean control; recall-control =
  no-narrowing guard. Output schema carries `n`, task count, model scope, and BOTH metric families.
  The HARD part — the flag→seeded-defect MATCHING RULE — is OQ-DM-7.

---

## 7. Non-goals

What should explicitly not be built?

Status: CONFIRMED (re-scoped: measurement-RUN non-goals + the new substrate non-goals; Ben 2026-06-19)

Answer:
| ID | Excluded | Why |
|---|---|---|
| NGOAL-DM-001 | **Modifying the instrument under measurement** — `config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py` and `concilium/**` are READ-ONLY. The Arm-A runner is a SEPARATE entrypoint, NOT an edit to these. EXCEPTION: a genuinely-needed measurement seam (e.g. capturing a council's per-role flag-set) is a DISCLOSED OPEN QUESTION (OQ-DM-8), never silently added. | Measuring an instrument you simultaneously tune is Goodhart. BLOCKER-3. |
| NGOAL-DM-002 | **Building a parallel metrics harness.** Reuse `emit_run.py` / `process_health.py` / `rule_ledger.py` / the `metrics/corpus/**` oracle philosophy; the scorer emits into the existing run-record shape. | Avoid a one-off measurement off the trusted spine. |
| NGOAL-DM-003 | **Tuning the corpus/diffs to flatter the council** (seeding defects foreign models happen to catch; dropping cases they miss). Defects are seeded BEFORE/independent of any review; the corpus is frozen. | The "don't hand-feed the instrument" rule applies to the substrate. The corpus's ungameability IS the deliverable. |
| NGOAL-DM-004 | **Headlining catch without cry-wolf** / "strictly better" on one metric — and, for the substrate: building a corpus with NO clean controls. | Anti-Goodhart core (RISK-DM-001). The substrate must force BOTH metrics. |
| NGOAL-DM-005 | **Claiming proven uncorrelated / cognitive diversity** from a distinct-model-id outcome delta. | RISK-B-007 / RISK-DS-004 reused verbatim. |
| NGOAL-DM-006 (3b) | **Suppressing or re-running-away a null/negative/tradeoff result** — and treating "underpowered → unmeasurable" as a published null. | A confirm-only measurement is Goodharted; an unmeasurable result is NOT a null (BLOCKER-2). |
| NGOAL-DM-007 | **Any live council/eval call inside `run_all.sh` / the offline suite.** 3a validates everything network-free; live runs are 3b, opt-in, gated, isolated. | Cost + tree-pollution + CI-credit-spend guards. |
| NGOAL-DM-008 | The Slice-4 GUI; generalising the claim beyond the corpus; auto credit purchase. | Out of slice. |
| NGOAL-DM-009 | **Editing `concilium/**` body/character prompts** (the source of truth the instrument loads). | Carried read-only invariant (NGOAL-DS-008/009). |
| NGOAL-DM-010 | **Building the model-resolution FALLBACK CASCADE.** Out of Slice-3 scope entirely. | Per OQ-DM-4 (Ben, 2026-06-19): the MEASUREMENT (3b) is FOREIGN-ONLY. The cascade is a SEPARATE future slice (backlog BL-DM-001), distinct from Slice-2's FORBIDDEN *silent* Claude fallback. |
| **NGOAL-DM-011 (new, 3a)** | **Running the measurement / spending pilot budget / emitting a catch-cry-wolf number in Slice 3a.** 3a builds + offline-validates the substrate ONLY. The Arm-A-vs-Arm-B RUN, the pre-registered pass/fail evaluation, the PAID pilot (OPEN-DM-A), the `runs.jsonl` emission, `process_health.py` analysis, and the honest write-up are ALL Slice 3b. | The split (BLOCKER-2/3 remediation): build the instrument before running it. Like Slice-2 deferred its measurement to Slice-3. |
| **NGOAL-DM-012 (new, 3a)** | **Using `pipe-providedfake-v1` (or any existing corpus) as the catch+cry-wolf+recall PRIMARY.** That property was misattributed (BLOCKER-1); `pipe-providedfake-v1` is a single-task wired-in-prod mutator with no controls. The NEW corpus (ART-3a-1) is the PRIMARY. | BLOCKER-1: the claim was read off the wrong file (the triple is `pipe-core-v1`'s). |

---

## 8. Risks / contradictions

What could make this wrong, useless, unsafe, misleading, too broad, or misaligned?

Status: RESOLVED for 3a-relevant risks; 3b-only risks carried forward and tagged (Ben 2026-06-19)

Answer:
| ID | Risk | Likelihood | Impact | Mitigation | Status |
|---|---|---:|---:|---|---|
| RISK-DM-001 (3b) | **Catch-only headline** — reporting catch without cry-wolf. | medium | high | The SUBSTRATE forces both: the corpus has clean controls; the scorer schema emits both families together. A catch-only headline is structurally hard to produce and is RED in 3b. | MITIGATED-BY-SUBSTRATE (3a builds the forcing function). |
| RISK-DM-002 | **Goodharted measurement** — corpus derived FROM / tuned to flatter the council. | medium | high | 3a: defects seeded BEFORE/independent of any review; corpus frozen + version-stamped; NGOAL-DM-003 tripwire baked in; deterministic oracle for the primary. | RESOLVED-IN-3a-DESIGN (ungameability is the deliverable). |
| RISK-DM-003 (3b) | **Distinct ids read as proven diversity.** | medium | high | RISK-B-007 reused verbatim; the scorer schema reserves an explicit non-claim field; 3b write-up states outcome-delta-only. | BINDING (carried to 3b). |
| RISK-DM-004 (3b) | **Free-tier flakiness confound** — a non-answering foreign role scored as a miss. | high | high | The scorer's per-role classification + "missing position ≠ miss" rule is part of ART-3a-3's schema; 3b handles the live attrition. | DESIGNED-IN-3a (schema), EXECUTED-3b. |
| RISK-DM-005 (3b) | **Underpowered n × cost.** | high | medium | 3a: the corpus MUST carry ≥2 distinct task outcomes / real variance so 3b can compute an MDE; "underpowered → unmeasurable" is a DISTINCT outcome from "refuted" and may NOT be published as a null. | RESOLVED-IN-3a-DESIGN (BLOCKER-2). |
| RISK-DM-006 (3b) | **Confirm-only design.** | medium | high | 3a: clean controls + recall control are mandatory corpus components (cry-wolf has its own oracle); 3b pre-registers the refutation line. | RESOLVED-IN-3a-DESIGN. |
| RISK-DM-007 | **Eval pollutes the tree / spends CI credits.** | medium | high | 3a offline-validation stages inputs outside the tree; sub-agents TEXT-ONLY/sandboxed; `git status` clean + `run_all.sh` green after every run; no live call in `run_all.sh`. The new corpus IS a tracked artifact (deliberate), authored cleanly. | BINDING. |
| RISK-DM-008 | **Scorer asymmetry / Claude-judges-Claude.** | medium | medium | ART-3a-3 is a SINGLE shared scorer both arms feed; the primary matching rule is deterministic (judge-free); a blind judge is used ONLY where determinism is impossible (the secondary real-diff set), with arm identity blinded. | RESOLVED-IN-3a-DESIGN (OQ-DM-7). |
| RISK-DM-009 | **Instrument-seam scope creep.** | low | high | NGOAL-DM-001: any seam in the instrument files is a DISCLOSED OPEN QUESTION (OQ-DM-8), never silently added; the Arm-A runner is a SEPARATE entrypoint. | BINDING (governance). |
| RISK-DM-010 (3b) | **Stale-snapshot drift** of the measured instrument. | medium | medium | The scorer schema records the pinned instrument commit; 3b pins it across arms. | DESIGNED-IN-3a (field), ENFORCED-3b. |
| RISK-DM-011 (3b) | **Silent-Claude contamination of Arm B.** | medium | high | The scorer asserts NO `anthropic`/`claude-*` id in any Arm-B flag-set's model scope; 3b enforces foreign-only at run time. | DESIGNED-IN-3a (assertion), ENFORCED-3b. |
| **RISK-DM-012 (new, 3a)** | **The flag→seeded-defect MATCHING RULE is not deterministic / is gameable.** If "does this free-text flag MATCH this seeded defect" is fuzzy, the catch number is judge-dependent and the whole substrate is soft. | high | high | OQ-DM-7: spec a STRUCTURED flag protocol (reviewer must emit defect-location/type tags the matcher checks deterministically), OR a blind deterministic matcher, OR a blind judge for the SECONDARY real-diff set only. If no deterministic rule is achievable for a subset, RAISE it to the user as an OPEN QUESTION — do not silently judge. | RESOLVED (OQ-DM-7 = (a) structured flag protocol + location-overlap; deterministic primary; Ben 2026-06-19). |
| **RISK-DM-013 (new, 3a)** | **Re-importing the wrong-corpus error** — a downstream doc again names `pipe-providedfake-v1` as the catch+cry-wolf+recall corpus. | low | high | The NEW corpus (ART-3a-1) is the PRIMARY everywhere; NGOAL-DM-012 forbids the old attribution; the misattribution provenance is recorded so it is not re-derived. | RESOLVED (BLOCKER-1 corrected). |

---

## 9. Evidence needed

What must be verified before implementation can be considered real?

Status: RESOLVED — substrate evidence (all OFFLINE); Ben 2026-06-19

Answer:
- **EVN-DM-001 — NEW review-catch corpus exists** under `metrics/corpus/<new>/`, frozen + version-stamped,
  with seeded-defect diffs (oracle seeded before/independent of review), clean controls (cry-wolf oracle),
  a recall/no-narrowing control, and ≥2 distinct task outcomes (real variance — BLOCKER-2). (ART-3a-1.)
- **EVN-DM-002 — Arm-A (Claude-only) runner exists** as a SEPARATE entrypoint that produces a reviewer
  flag-set over a corpus diff, runnable OFFLINE via an injected transport (0 credits); the instrument
  files are byte-unchanged. (ART-3a-2; BLOCKER-3.)
- **EVN-DM-003 — Single shared SCORER exists** consuming a REVIEWER FLAG-SET (not pytest RED/GREEN),
  computing catch / cry-wolf / recall per arm, with an output schema carrying `n`, task count, model
  scope, the pinned-instrument-commit field, the foreign-only assertion field, BOTH metric families
  together, and an explicit non-claim field. (ART-3a-3; BLOCKER-3.)
- **EVN-DM-004 — The flag→seeded-defect MATCHING RULE is specified and deterministic for the primary**
  (structured flag protocol or blind deterministic matcher); any subset that cannot be made deterministic
  is an OPEN QUESTION raised to the user (OQ-DM-7), never silently judged. Re-running the matcher on the
  same captured flag-sets yields identical numbers.
- **EVN-DM-005 — The scorer's run-record output matches the REAL `emit_run.py` schema** (IMPORTANT-1):
  `arm`, `model_scope`, `cost`, `catch_rate`, `cry_wolf_rate`, `recall_control`, `n`, `task_count` live
  INSIDE the `--metrics` (numeric, SPC-tracked by `process_health.py` via `metrics.<name>`) or `--raw`
  (free-form, e.g. `model_scope`) blob — NOT as top-level record fields. Verified against
  `config/claude/metrics/emit_run.py` (top-level keys are `run_id`/`corpus_id`/`mode`/`baseline`/
  `process_branch`/`config_fingerprint`/`metrics`/`raw`/`gate_outcomes`/`active_rules`/`human_overrides`).
- **EVN-DM-006 — Offline isolation proven:** corpus mutator/oracle, Arm-A runner, and scorer all run
  network-free; `git status` clean and `run_all.sh` green afterward; ZERO live calls; new corpus authored
  cleanly under `metrics/corpus/<new>/` (a deliberate tracked artifact).
- **EVN-DM-007 — Reality Ledger** (`docs/reality/council-diversity-measurement.evidence.jsonl`, authored
  Phase 3 / Gate C) at the HONEST class per REQ: the offline corpus/runner/scorer wiring exercised
  network-free = `integration-fake` (3a crosses NO real boundary, so NO `real-boundary-smoke` record is
  honest in 3a — that class belongs to 3b's live run). Never raise a class to clear a floor; avoid the
  FORBIDDEN_TOKENS (`fake-only`/`mock-only`/`placeholder`/`unverified`).
- **EVN-DM-008 — Foreign-instrument-contract claims verified against the real artifact** BEFORE they
  become substrate premises (classified `belegt | ableitbar | ungeprüft | nicht behaupten`): what
  `deepseek_review.py preset` returns as a per-role position/flag shape the scorer consumes; the
  `emit_run.py` record schema; the new corpus's own oracle field shape. An unverifiable contract stays an
  OPEN QUESTION/BLOCKER, never a "documented risk" forwarded as a working premise.

---

## Allowed change scope

> Proposed by the requirements-analyst, grounded against the repo. Final OK given by the user at the
> Phase-0.15 / 0.6 re-scope gate (Ben re-confirmed 2026-06-19). The instrument under measurement
> (`config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py`) and
> `concilium/**` are **read-only** — measured, not modified. The Arm-A runner is a SEPARATE entrypoint,
> NOT an edit to those files. A genuinely-needed measurement seam in them is an OPEN QUESTION to the user
> (NGOAL-DM-001 / OQ-DM-8), not pre-authorised here.

Machine-parseable scope (PRIL `plumbline-scope-check` / `plumbline_scope.py`): one
backtick-wrapped path per line so the runtime scope guard can parse it. (This intro line
intentionally does NOT start with `-`/`*`/`+` so the parser does not read it as a path.)

- `metrics/corpus/council-review-catch-v1/*`
- `metrics/corpus/council-review-catch-v1/**`
- `config/claude/metrics/arm_a_review_runner.py`
- `config/claude/metrics/council_review_scorer.py`
- `config/claude/metrics/emit_run.py`
- `config/claude/metrics/process_health.py`
- `config/claude/metrics/rule_ledger.py`
- `config/claude/tests/test_arm_a_review_runner.sh`
- `config/claude/tests/test_council_review_scorer.sh`
- `config/claude/tests/run_all.sh`
- `config/claude/tests/lib.sh`
- `metrics/runs.jsonl`
- `metrics/*`
- `docs/benchmarks/*`
- `docs/canvas/council-diversity-measurement.canvas.md`
- `docs/prd/council-diversity-measurement.prd.md`
- `docs/vision/council-diversity-measurement.vision.md`
- `docs/traceability.md`
- `docs/plans/2026-06-19-council-diversity-measurement.md`
- `docs/reality/council-diversity-measurement.evidence.jsonl`
- `backlog.md`
- `CLAUDE.md`

> Note on the new artifact paths: `metrics/corpus/council-review-catch-v1/` is the NEW corpus dir
> (ART-3a-1); `arm_a_review_runner.py` (ART-3a-2) and `council_review_scorer.py` (ART-3a-3) are the new
> SEPARATE modules — exact filenames are a reversible implementation detail the planner may finalize, but
> they live under `config/claude/metrics/` (not under the read-only `config/claude/lib/` instrument tree).
> If the planner chooses different names, update this scope list at Phase 0.6 and re-run
> `plumbline-scope-check` before build.

---

## 10. Traceability links

PRD: docs/prd/council-diversity-measurement.prd.md (re-scoped to Slice 3a; REQ-DM-3a-* traced to this canvas — canvas Status `user-confirmed`, PRD finalization unblocked by Ben's 2026-06-19 re-confirmation)
Product Vision: docs/vision/council-diversity-measurement.vision.md (`user-confirmed`; reconciled and re-confirmed; Phase 0 complete — Canvas, PRD, and Vision all re-confirmed together 2026-06-19)
Traceability Matrix: docs/traceability.md (slice council-diversity-measurement; canvas-link: docs/canvas/council-diversity-measurement.canvas.md)
Related REQ IDs: REQ-DM-3a-001..REQ-DM-3a-010 (3a substrate) + deferred REQ-DM-3b-* (the measurement RUN), assigned by the PRD
Carried-falsifier provenance: docs/canvas/deepseek-review-agent.canvas.md (NGOAL-DS-003 / NGOAL-DS-011), docs/vision/deepseek-review-agent.vision.md §5
Measured instrument (read-only): config/claude/lib/deepseek_review.py, council_presets.py, council_inference.py, council_backend.py
Reused harness: config/claude/metrics/{emit_run,process_health,rule_ledger}.py; metrics/corpus/**; metrics/SUMMARY-2026-05-30-dna-investigation.md (method precedent)
Backlog hand-off: backlog.md BL-DM-001 (model-resolution fallback cascade — separate slice, NGOAL-DM-010)
True-Line status: canvas RE-CONFIRMED (Status `user-confirmed`, Ben re-confirmed the re-scope 2026-06-19); Phase 0 complete — the re-scoped canvas, PRD, and Vision are all user-confirmed

---

## Open Questions

The six MEASUREMENT open questions were RESOLVED by the user on 2026-06-19 and remain BINDING for
Slice 3b (carried below for provenance). Slice 3a inherits them as design constraints the substrate
must SATISFY, and surfaces TWO genuinely-new substrate open questions (OQ-DM-7, OQ-DM-8).

### NEW Slice-3a open questions (require user input)

| ID | Question | Status |
|---|---|---|
| **OQ-DM-7** | **The flag→seeded-defect MATCHING RULE.** When does a free-text reviewer flag "match" a seeded defect? Options: (a) a STRUCTURED flag protocol — the reviewer must emit a machine-parseable defect tag (location + type) the matcher checks deterministically; (b) a blind DETERMINISTIC matcher over free text (e.g. line-range + keyword oracle); (c) a blind JUDGE, used ONLY for the SECONDARY real-diff set where determinism is impossible. The PRIMARY corpus subset MUST be deterministic (so catch is judge-free). **Which protocol does the user want for the primary, and is a blind judge acceptable for the secondary real-diff subset only?** | **RESOLVED (Ben 2026-06-19) = (a) STRUCTURED flag protocol + deterministic location-overlap matching for the primary (judge-free); a blind judge is acceptable for the SECONDARY real-diff subset only.** |
| **OQ-DM-8** | **Is any instrument SEAM needed for Arm B?** The scorer consumes a per-role flag-set. If the on-`main` `deepseek_review.py preset` does NOT already expose a council's per-role positions/flags in a scorable shape (to be verified against the real file in Phase 3 per EVN-DM-008), a seam in the read-only instrument may be needed. **Per NGOAL-DM-001 this is a DISCLOSED OPEN QUESTION to the user, never a silent edit.** Default: measure read-only; if a seam is required, the user decides whether to authorize it (a one-file, additive, capture-only seam) or keep the instrument byte-unchanged and adapt the scorer to the existing output. | **OPEN — pending the Phase-3 contract read; surfaced now, not silently resolved.** |

### Slice-3b MEASUREMENT open questions — RESOLVED 2026-06-19 (binding for 3b)

| ID | Question | RESOLUTION (Ben, 2026-06-19 — binding for 3b) |
|---|---|---|
| OQ-DM-1 | Corpus / ground-truth source. | **NEW review-catch corpus PRIMARY (ART-3a-1) + small real-defect-diff SECONDARY** (blind-judged, reported separately, NOT pooled). (REVISED from the original "`pipe-providedfake-v1` primary" — BLOCKER-1: that corpus lacks the controls; the new corpus replaces it.) |
| OQ-DM-2 | "Catch" definition / scorer. | **Deterministic matcher PRIMARY (judge-free) + blind judge only where deterministic is impossible** (secondary real-diff set). Clean controls give cry-wolf its own oracle. (3a builds the scorer; OQ-DM-7 settles the matching rule.) |
| OQ-DM-3 | Comparison design. | **Compare MULTIPLE presets (A, B, C) vs. Claude-only** on the SAME subjects / SAME scorer; instrument snapshot pinned across arms. (3b runs it; 3a's scorer schema carries the arm + pinned-commit fields.) |
| OQ-DM-4 | Power vs flakiness + cost. | **MEASUREMENT IS FOREIGN-ONLY** (no Claude in Arm B; budget-exhausted role EXCLUDED/retried + attrition disclosed, never Claude-substituted). PAID pilot first (bounded budget, exact number named by the user before the live run → **OPEN-DM-A, moved to 3b**); ≥3 runs/arm/task. |
| OQ-DM-5 | Pass/fail line. | **Pre-registered BEFORE the runs:** demonstrated / refuted / tradeoff; noise threshold pinned from the corpus's run variance (which is why the corpus MUST have variance — BLOCKER-2). 3b pre-registers it; 3a guarantees the variance. |
| OQ-DM-6 | Honesty of a NULL result. | **A null/negative/tradeoff result is a valid PUBLISHED outcome** — and "underpowered → unmeasurable" is a DISTINCT outcome that may NOT be laundered as a published null (BLOCKER-2). |

---

## Backlog hand-off (Slice-3-adjacent, OUT of scope)

| ID | Hand-off | Why it is a separate slice |
|---|---|---|
| BL-DM-001 | **Model-resolution FALLBACK CASCADE** — prefer reasoning-capable models → paid large-context (125k+) moderate-price models within budget → disclosed Claude-with-character-skills as the budget-exhausted last resort. | A SEPARATE future product/resolver slice (NGOAL-DM-010), a DISCLOSED intentional fallback (distinct from Slice-2's FORBIDDEN *silent* Claude fallback). The 3b MEASUREMENT is FOREIGN-ONLY (OQ-DM-4); building the cascade inside it would contaminate the comparison. |
| **BL-DM-002 (the deferred Slice 3b)** | **The measurement RUN:** Arm-A vs Arm-B execution on the new corpus; the pre-registered pass/fail evaluation (demonstrated / refuted / tradeoff / **underpowered**); the PAID pilot (OPEN-DM-A budget); the `runs.jsonl` emission + `process_health.py` analysis; the honest write-up; the PAIRED-EXCLUSION attrition rule (drop a subject from BOTH arms if any Arm-B role is unavailable) + attrition reported by task difficulty (IMPORTANT-2). | 3a builds + offline-validates the substrate; 3b RUNS it. Mirrors how Slice-2 deferred its measurement to Slice-3. The substrate (this slice) is the precondition. |

---

## User confirmation

Confirmed by user: YES — re-confirmed (Ben, 2026-06-19, "Bestätigt — 3a bauen")
Confirmation date: 2026-06-19
Confirmation note:
This canvas was previously confirmed by Ben (2026-06-19) for a Slice-3 that bundled SUBSTRATE +
MEASUREMENT. The spec-auditor found 4 BLOCKERs (the substrate does not exist; the named corpus was
wrong). Ben decided (2026-06-19): BUILD a new review-catch corpus; SPLIT into Slice 3a (substrate,
this canvas) and Slice 3b (the measurement RUN, deferred to BL-DM-002). This was a material re-scope,
so the re-scoped canvas was put back to the user — and Ben RE-CONFIRMED it on 2026-06-19, choosing
OQ-DM-7 = structured flag protocol + location-overlap. Status is `user-confirmed`. No agent
self-confirmed it; the user re-confirmed it.

What the user re-confirmed:
- The SPLIT: 3a delivers the substrate (new corpus + Arm-A runner + shared flag-set scorer), all
  offline-verifiable; 3b runs the measurement (deferred).
- The NEW corpus design (ART-3a-1): seeded defects (seeded before/independent of review) + clean
  controls (cry-wolf) + recall control, ≥2 distinct task outcomes (real variance), frozen +
  version-stamped, council-independent (NGOAL-DM-003 tripwire).
- OQ-DM-7 (the flag→seeded-defect MATCHING RULE) — the one genuinely-new product-critical decision the
  user must make: which deterministic protocol for the primary, and whether a blind judge is acceptable
  for the secondary real-diff subset only.
- OQ-DM-8 (instrument-seam) stays a DISCLOSED OPEN QUESTION pending the Phase-3 contract read.

Anti-Goodhart discipline remains BINDING (both metrics together; n/task-count/model-scope visible;
distinct ids != uncorrelated cognition per RISK-B-007; corpus independent of the council and frozen;
the measurement refutable; underpowered ≠ refuted). The instrument files stay READ-ONLY unless a
genuine seam is user-authorized (OQ-DM-8), never silently edited.

Confirmation phrase (SATISFIED — Ben re-confirmed 2026-06-19, "Bestätigt — 3a bauen"):

```text
I confirm this re-scoped Slice-3a Product Canvas as the basis for AgileTeam planning.
```
