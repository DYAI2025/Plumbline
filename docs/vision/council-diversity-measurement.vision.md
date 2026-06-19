# Product Vision: Council Diversity Measurement — Slice 3a: the SUBSTRATE for the honest, refutable answer to "does foreign-model cognition catch what Claude misses, without raising cry-wolf?"

Feature-Slug: council-diversity-measurement
Slice: 3a of 4 — the MEASUREMENT SUBSTRATE (3b = the deferred measurement RUN; Slice 4 = the GUI)
Status: user-confirmed (Ben 2026-06-19, re-confirmed together with the re-scoped Canvas + PRD after the BLOCKER re-scope).
Owner: product-owner
Confirmed by user: yes (Ben 2026-06-19)

Linked Product Canvas (re-scoped, draft — re-confirmation pending): docs/canvas/council-diversity-measurement.canvas.md
Linked PRD (re-scoped to Slice 3a, draft, canvas-bound): docs/prd/council-diversity-measurement.prd.md (REQ-DM-3a-001..010 + deferred REQ-DM-3b-*)
Traceability: docs/traceability.md (slice council-diversity-measurement)
Carried-falsifier provenance: docs/canvas/deepseek-review-agent.canvas.md (NGOAL-DS-003 / NGOAL-DS-011); docs/vision/deepseek-review-agent.vision.md §5
Method precedent: metrics/SUMMARY-2026-05-30-dna-investigation.md (a published null/tradeoff result)

> **RE-SCOPE NOTE (the spec-auditor remediation, 2026-06-19).** The spec-auditor found 4 BLOCKERs:
> (1) the named corpus `pipe-providedfake-v1` is a single-task wired-in-prod mutator with NO clean
> control / recall control / cry-wolf oracle — the catch+cry-wolf+recall triple belongs to
> `pipe-core-v1`; the claim was read off the wrong file; (2) a single-task corpus has no variance, so
> no noise threshold / MDE could be pinned; (3) there is no review-flag-set scorer and no Claude-only
> Arm-A runner (the instrument has only `run`/`preset` = the council, and is read-only); (4) THIS
> Vision self-contradicted (header `user-confirmed`, body `draft`). Ben decided: BUILD a new
> review-catch corpus; SPLIT into Slice 3a (the SUBSTRATE — new corpus + Arm-A runner + shared
> flag-set scorer, all offline-verifiable) and Slice 3b (the measurement RUN, deferred). BLOCKER-4 is
> fixed here: the WHOLE Vision is now consistently `draft`, re-confirmation pending.

> This Vision is bound to the re-scoped Canvas and the re-scoped PRD above and must stay consistent
> with them. It is the customer-value line — the *direction* — not a second PRD. Where the
> Canvas/PRD say HOW, this says WHO it is for, WHAT changes for them, and WHAT would make it
> useless despite passing tests. The honesty split below is load-bearing and survives every
> rewrite: **the deliverable of Slice 3a is the honest, ungameable measurement INSTRUMENT (not a
> result); the deliverable of Slice 3b is the honest MEASUREMENT, not a favorable RESULT.**

---

## 1. North Star (the confirmed customer value — knowing the TRUTH about the diversity lift)

The whole foreign-model-council premise — Slices 1+2's reason to exist — rests on ONE unmeasured
claim: that running `/concilium` bodies on diverse, foreign (non-Claude) models catches defects a
Claude-only review MISSES, **without raising the false-alarm (cry-wolf) rate**. Slices 1+2
deliberately stated that as a GOAL and never as evidence, and carried it forward as an explicit
deferred falsifier. Slice 3 is the instrument that finally answers it — but the spec-auditor showed
the instrument did not yet exist, so Slice 3 is now split: **Slice 3a BUILDS the measurement
substrate; Slice 3b RUNS it.** This Vision governs Slice 3a; it stays bound to the same north star
because a wrong or gameable substrate makes the eventual answer worthless.

The north star is therefore **not "the council wins."** It is **knowing the TRUTH about the
diversity lift** — and Slice 3a's contribution to that north star is **building a measurement
instrument honest and refutable BY CONSTRUCTION**, so that whatever Slice 3b later says can be
acted on, including when it says the foreign council adds nothing, or trades catch for cry-wolf. In
3a the anti-Goodhart guarantees become STRUCTURAL: the corpus's clean controls force both metrics,
and defects seeded before/independent of any review make the corpus ungameable.

The customer value is an **HONEST answer, not a favorable one.** A measurement that can only
confirm the framework's own premise is Goodharted and worthless. Being *willing to refute the
premise the rest of the foreign-council effort is built on* — and publishing that refutation as-is
— IS the value of this slice. The precedent is real and in-repo: the v0.10 DNA investigation
(`metrics/SUMMARY-2026-05-30-dna-investigation.md`) published a catch-vs-cry-wolf tradeoff finding
rather than a flattering headline, and that null/tradeoff write-up is exactly the shape success
takes here.

---

## 2. Who benefits, and what changes for them

- **Ben / the Plumbline operator (the decision-owner).** Today they cannot say whether the
  foreign-model council earns its complexity and cost — the central justification is asserted, not
  measured, and the diversity gate (Slice 2's OD-3) guards a council whose value is unknown. After
  Slice 3 they get a defensible go/no-go datapoint — keep, extend (Slice 4 GUI), or retire the
  foreign-council path — carrying `n=`, task count, model scope, AND both catch-rate and cry-wolf
  side by side, on a corpus whose oracle is derived independently of the council. Crucially, the
  answer is honest enough to act on **even when it is unfavourable** — which is the only kind of
  answer worth paying a live pilot for.

- **Slice 3b itself (the immediate downstream consumer).** 3b CANNOT start without 3a's corpus,
  Arm-A runner, and shared scorer. 3a's success criterion is precisely "3b has a correct,
  offline-validated instrument to run." A substrate that is wrong or gameable means 3b would produce
  an unbuildable result or a confabulated number — which is exactly the failure the spec-auditor's 4
  BLOCKERs caught before any token was spent.

- **The framework's own integrity (the empirical instrument).** This slice (3a+3b together) is the
  keystone that keeps the foreign-council claims honest. Slices 1+2 are allowed to defer the value
  claim *only because* Slice 3 exists to settle it. If the substrate is rigged or the measurement is
  non-refutable or re-run-until-favourable, then every "Slice-3 measurement, not proven here"
  disclaimer upstream becomes a permanent dodge — the deferral was never honest. The beneficiary here
  is Plumbline's central discipline: claims are *measured*, never asserted, and RED is never
  downgraded. 3a is where that discipline is physically built into the corpus and scorer.

- **The reviewer / auditor and future readers of the write-up.** They benefit from a published
  result that states exactly what it does and does NOT establish — an outcome delta on THIS corpus,
  NOT proven cognitive diversity, NOT generality — so the result cannot be misread as proving more
  than it does (the exact failure RISK-DM-001/003 guard). Refusing to over-claim is part of the
  delivered value, not a footnote.

## 3. When they would use it

When deciding whether the foreign-model council is worth running and paying for: before committing
to Slice 4 (the GUI) or to ongoing paid council runs, the operator consults the measurement's
published outcome (demonstrated / refuted / tradeoff / underpowered, per the pre-registered line) plus
its actual recorded cost. **In Slice 3a, the operator's use is upstream:** they confirm the substrate
is correct and ungameable (and decide OQ-DM-7, the flag→seeded-defect matching rule) BEFORE any paid
run is authorized. The deterministic primary scorer is re-runnable offline at zero credits; the live
pilot is a Slice-3b concern — an opt-in, budget-bounded, isolated run done once to estimate effect +
real cost before any scale decision.

---

## 4. What "true to value" means here (True-Line discipline — this is the integrity keystone)

Success is **a trustworthy measurement**, not "the council won" and not "tests green." Concretely,
this slice is true to value when ALL of the following hold:

- **Both anti-Goodhart metrics, always together.** Every claim carries catch-rate AND cry-wolf
  (false-positive) rate, side by side — never catch alone. "Strictly better" requires BOTH to
  hold. A catch-only headline ("the council halves escapes") without the cry-wolf number beside it
  is the single most dangerous miss (RISK-DM-001) and is RED. (The v0.10 DNA slice found the two
  metrics can move in OPPOSITE directions — net-positive on Opus, a tradeoff on sub-Opus.)

- **The measurement is refutable by construction.** The pass/fail line is pre-registered and frozen
  BEFORE any scored run (demonstrated / refuted / tradeoff, noise threshold pinned from corpus
  variance — REQ-DM-006). Clean control items give cry-wolf its own oracle. A design that can only
  show the council winning is Goodharted by construction (RISK-DM-006) and fails this Vision.

- **The corpus is independent of the council.** The oracle is a NEW review-catch corpus
  (`metrics/corpus/council-review-catch-v1`, ART-3a-1) — seeded-defect diffs (defects seeded
  before/independent of any review → ungameable) + clean controls (cry-wolf oracle) + a recall
  control, with real variance — frozen and version-stamped, derived INDEPENDENTLY of the council and
  never tuned per result. (The previously-named `pipe-providedfake-v1` was the wrong corpus —
  BLOCKER-1: it is a single-task wired-in-prod mutator with no controls; the catch+cry-wolf+recall
  triple belongs to `pipe-core-v1`.) Measuring an instrument you simultaneously tune (or hand-feeding
  the tasks the council happens to catch) is Goodhart — the Slice-1 "don't hand-feed the instrument"
  rule applies to the SUBSTRATE itself (RISK-DM-002), and building the corpus's ungameability IS
  Slice 3a's central deliverable.

- **Distinct model ids are NOT read as proven cognition.** An outcome delta over distinct model
  bases establishes an outcome delta on THIS corpus — NOT proven uncorrelated *cognitive*
  diversity, NOT generality (RISK-B-007 / RISK-DM-003 carried verbatim). The write-up must say so
  explicitly.

- **Foreign-only integrity holds the line.** Arm B contains NO Claude/anthropic model id. A
  Claude-contaminated Arm B would make the foreign-vs-Claude delta partly Claude-vs-Claude and the
  whole result **uninterpretable** — and would silently violate Slice-2's tested
  no-silent-Claude-fallback invariant. A budget-exhausted/unresolvable foreign role is
  excluded/retried and the attrition DISCLOSED, never Claude-substituted and never scored as a
  "council miss" (RISK-DM-004/011, REQ-DM-004). This is non-negotiable: it is the difference between
  a measurement and a fiction.

- **A null / negative / tradeoff result is SUCCESS, not failure.** The deliverable is the honest
  measurement + write-up, whatever it shows. A result showing no lift, or a catch-vs-cry-wolf
  tradeoff, is recorded in `metrics/runs.jsonl` and published as-is — never re-run-until-favourable,
  never downgraded (OQ-DM-6, REQ-DM-007). The v0.10 DNA published-null-result is the precedent.

## Reality-Ledger Gegenthese (the value-killer to hold against this slice at the final gate)

*Could this slice be fully green yet deliver zero TRUTH?* The classic shapes to hunt for:

- **A rigged corpus** — the oracle derived from, or tuned to flatter, the council. Green, but it can
  only confirm. Zero truth.
- **A non-refutable line** — a pass/fail rule written or moved AFTER seeing results, or with no
  clean controls / cry-wolf oracle, so the council can only "win." Green, but Goodharted.
- **A re-run-until-favourable result** — the unfavourable run quietly dropped, a flattering one
  published. Green, but a lie.
- **A catch-only headline** — catch reported without cry-wolf beside it, manufacturing a "win" that
  is really a tradeoff. Green, but the most dangerous miss.
- **A Claude-contaminated Arm B** — a Claude id leaking into the council, so the measured delta is
  partly Claude-vs-Claude. Green, but uninterpretable.
- **A flakiness confound scored as signal** — a foreign role that 402/429/times-out counted as a
  "council miss" instead of recorded unavailable. Green, but measuring the free tier, not cognition.

Any such shape is RED and, per the escalation-asymmetry rule, may NOT be downgraded to a "known
limitation" by any agent — only the user can. A measurement that can only confirm delivers zero
customer value here no matter how green it is.

---

## 5. Explicit non-claims (what this slice does NOT prove)

Stating the north star as a question while refusing to pre-judge its answer is itself the value.
This slice does **NOT** assert, and the write-up must not be read as proving:

- **That the council adds value.** This Vision does NOT claim the foreign council wins. The
  pre-registered pass/fail line (OQ-DM-5) is the binding decision rule the measurement RESOLVES; the
  value of the council is the measurement's OUTPUT, unknown until it runs, and a valid published
  outcome whatever it is (OQ-DM-6).
- **Proven uncorrelated / cognitive diversity** from a distinct-model-id outcome delta
  (RISK-B-007 / RISK-DM-003). N distinct foreign ids still do not prove uncorrelated cognition.
- **Generality beyond the measured corpus.** The primary number (in 3b) is an outcome delta on the
  NEW `council-review-catch-v1` corpus, not a general claim; the secondary real-defect-diff set is a
  separately reported reality signal, NOT pooled into the primary number (REQ-DM-3a-001/003/004).
- **Any live capability inside CI.** `run_all.sh` / the offline suite make ZERO live council calls.
  The live pilot is opt-in, budget-bounded, isolated outside the tree (REQ-DM-008/009).

---

## 6. Success signals (VCHK customer-value checks — what QA must verify as VALUE, not just function)

These are the value checks QA must prove; they trace to the canvas success signals (§5) and the PRD
REQ acceptance. Each is a check that the *measurement is trustworthy*, independent of whether the
council "wins". **Scope split:** VCHK-DM-3a-1..4 are SUBSTRATE checks QA verifies in Slice 3a
(offline); VCHK-DM-3b-* (the run-time checks: foreign-only enforcement, refutable pre-registered line,
null-publishable, isolation + cost honesty, headline-both-metrics) are deferred to Slice 3b and listed
afterward for traceability. A 3a substrate is "true to value" when the 3b checks are MADE POSSIBLE by
construction (clean controls, deterministic matcher, schema fields), even though they only EXECUTE in 3b.

### Slice 3a substrate checks (QA verifies these OFFLINE in 3a)

- **VCHK-DM-3a-1 — The substrate FORCES both metrics.** The new corpus carries clean controls and the
  shared scorer's output schema emits catch-rate AND cry-wolf-rate AND a recall/no-narrowing control
  together; a corpus with no clean control, or a scorer output missing the cry-wolf field, fails
  acceptance. (REQ-DM-3a-001/003; RISK-DM-001.)
- **VCHK-DM-3a-2 — Corpus independent + real variance.** The primary corpus is the NEW frozen,
  version-stamped, council-independent `council-review-catch-v1` (defects seeded before/independent of
  review; never tuned per result), with ≥2 distinct task outcomes so 3b can pin a noise threshold + MDE;
  a single-task/saturated corpus is REJECTED. (REQ-DM-3a-001; RISK-DM-002/005/006; BLOCKER-1/2.)
- **VCHK-DM-3a-3 — Deterministic primary matcher + scorer determinism.** The flag→seeded-defect matching
  rule is deterministic for the primary (OQ-DM-7); re-running the scorer over the same captured flag-sets
  yields identical numbers (numeric equality, not substring). A blind judge appears ONLY on the secondary
  real-diff set, arm identity blinded. (REQ-DM-3a-004; RISK-DM-008/012; NFR-DM-3a-002.)
- **VCHK-DM-3a-4 — Schema correct + instrument read-only + isolated.** The scorer's run-record output
  places `arm`/`model_scope`/`cost`/`catch_rate`/`cry_wolf_rate`/`recall_control`/`n`/`task_count` INSIDE
  the `metrics`/`raw` blob (NOT top-level — IMPORTANT-1), `process_health.py` reads them; the four
  instrument files + `concilium/**` are byte-unchanged (any seam = disclosed OQ-DM-8); 3a validation makes
  ZERO live calls and leaves `git status` clean + `run_all.sh` green. (REQ-DM-3a-005/006/008; RISK-DM-007/009.)

### Slice 3b run-time checks (deferred — listed for traceability, EXECUTED in 3b)

- **VCHK-DM-3b-1 — Both metrics in every published claim;** catch-only headline fails. (REQ-DM-3b-007; RISK-DM-001.)
- **VCHK-DM-3b-2 — Scope visible on every claim** (`n=`, task count, model scope; small `n` labeled; MDE honest). (REQ-DM-3b-007; RISK-DM-004/005.)
- **VCHK-DM-3b-3 — Foreign-only integrity proven at run time;** non-answering role unavailable/disclosed, never Claude-filled, never scored a miss; PAIRED-EXCLUSION attrition by task difficulty (IMPORTANT-2). (REQ-DM-3b-002/006; RISK-DM-011.)
- **VCHK-DM-3b-4 — Refutable + null-publishable;** pass/fail line timestamped BEFORE the first scored run; underpowered ≠ refuted; no re-run-to-favour. (REQ-DM-3b-003/004; RISK-DM-006; BLOCKER-2.)
- **VCHK-DM-3b-5 — Isolation + cost honesty;** live pilot halts at the user-named budget (OPEN-DM-A); actual cost recorded. (REQ-DM-3b-005; RISK-DM-007.)

---

## 7. Traceability links

Product Canvas: docs/canvas/council-diversity-measurement.canvas.md (re-scoped, draft — re-confirmation pending, Ben 2026-06-19)
PRD: docs/prd/council-diversity-measurement.prd.md (re-scoped to Slice 3a; REQ-DM-3a-001..010 + deferred REQ-DM-3b-*; draft, canvas-bound)
Traceability Matrix: docs/traceability.md (slice council-diversity-measurement)
Reality Ledger (authored Phase 3 / Gate C): docs/reality/council-diversity-measurement.evidence.jsonl
Method precedent (published null/tradeoff result): metrics/SUMMARY-2026-05-30-dna-investigation.md
Carried-falsifier provenance: docs/canvas/deepseek-review-agent.canvas.md (NGOAL-DS-003 / NGOAL-DS-011); docs/vision/deepseek-review-agent.vision.md §5
Measured instrument (read-only): config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py
New substrate artifacts (Slice 3a): metrics/corpus/council-review-catch-v1/** (ART-3a-1); config/claude/metrics/arm_a_review_runner.py (ART-3a-2); config/claude/metrics/council_review_scorer.py (ART-3a-3)
Reused harness: config/claude/metrics/{emit_run,process_health,rule_ledger}.py; metrics/corpus/**
The one genuinely-new 3a open item: OQ-DM-7 (the flag→seeded-defect matching rule for the primary) — a user decision, a BLOCKER until decided. Plus OQ-DM-8 (instrument seam, disclosed; default read-only).
Deferred to Slice 3b (backlog BL-DM-002): the measurement RUN, the pre-registered pass/fail evaluation, the PAID pilot (OPEN-DM-A budget, named by the user immediately before the paid pilot — never guessed), the runs.jsonl emission + process_health analysis, and the honest write-up.

True-Line status: draft — Vision NOT self-confirmed (this is the SINGLE consistent status throughout
this document; the prior header/body contradiction was BLOCKER-4, now fixed). Phase 0 completes only
when the re-scoped Canvas, the PRD, AND this Vision are all user-confirmed together at the next gate,
using the confirmation phrase:

```text
I confirm this re-scoped Slice-3a Product Vision as the basis for AgileTeam planning.
```
