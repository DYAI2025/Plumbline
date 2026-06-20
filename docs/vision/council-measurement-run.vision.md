# Product Vision: Council Measurement RUN — Slice 3b: RUN the measurement and PUBLISH the honest, refutable answer to "does the foreign-model council catch what Claude misses, WITHOUT raising cry-wolf?"

Feature-Slug: council-measurement-run
Slice: 3b of 4 — the MEASUREMENT RUN. (3a = the substrate, on main, consumed READ-ONLY; Slice 4 = the GUI.)
Status: user-confirmed (Ben 2026-06-20; confirmed together with the PRD at the Phase-0 gate; Canvas already user-confirmed. Phase 0 complete.)
Status note: FROZEN after a SINGLE spec-auditor remediation pass (Ben-approved, 2026-06-20) — measurement-integrity fixes propagated from the canvas/PRD (arm symmetry / symmetric flag protocol; Arm-A real transport via the new script; estimated-budget / MAX-CALLS reframe; minimum-survivors floor; n=2 rubric; one-preset pilot; honest pilot PURPOSE made load-bearing). Status remains user-confirmed; no re-audit. (Carried IDENTICALLY in §7 True-Line status.)
Owner: product-owner
Confirmed by user: yes (Ben 2026-06-20)

Linked Product Canvas (user-confirmed — Ben 2026-06-20, Phase-0.15 gate): docs/canvas/council-measurement-run.canvas.md
Linked PRD (draft, canvas-bound): docs/prd/council-measurement-run.prd.md (REQ-MR-001..011)
3a substrate Vision (same north star): docs/vision/council-diversity-measurement.vision.md
Method precedent (a published null/tradeoff result): metrics/SUMMARY-2026-05-30-dna-investigation.md
Traceability: docs/traceability.md (slice council-measurement-run)

> This Vision is bound to the user-confirmed Canvas and the draft PRD above and must stay
> consistent with them. It is the customer-value line — the *direction* — not a second PRD.
> Where the Canvas/PRD say HOW, this says WHO it is for, WHAT changes for them, WHEN they would
> use it, and WHAT would make it useless despite passing every test. **The 3a Vision built the
> ungameable INSTRUMENT; this Vision governs the RUN. The split is load-bearing and survives
> every rewrite: the deliverable of 3b is the honest MEASUREMENT, not a favorable RESULT.**

---

## 1. North Star (the confirmed customer value — the TRUE answer, not a favorable one)

The whole foreign-model-council effort — Slices 1+2, and the 3a substrate built to settle it —
rests on ONE unmeasured claim: that a foreign (non-Claude) preset council catches defects a
Claude-only review MISSES, **without raising the false-alarm (cry-wolf) rate.** 3a proved the
instrument works offline. **No measurement has been run.** Slice 3b is the run.

The north star is therefore **the honest, refutable ANSWER to "does the foreign council catch
what Claude misses without raising cry-wolf?"** — and the customer value is a **TRUE answer, not
a favorable one.** A measurement that can only confirm the framework's own premise is Goodharted
and worthless. **THE n=2 PAID PILOT IS NOT THAT ANSWER — and saying so is load-bearing.** The
pilot's PURPOSE is narrow and deliberate: **(a) prove the run-harness works end-to-end LIVE (a
real-boundary-smoke of the RUN MECHANISM) and (b) estimate cost + flakiness.** It is NOT a value
verdict on the council; at n=2 the only honest outcomes are `underpowered` and (at most)
`tradeoff-signal-to-investigate`. **Every value-claim path routes through the powered FOLLOW-ON
run** (corpus expansion + A/B/C presets), where the full demonstrated / refuted / tradeoff /
underpowered verdict and the honest write-up around it live, **whatever they show.** Being
*willing to refute the premise the rest of the foreign-council effort is built on, and to publish
that refutation as-is, IS the value of this effort.** The precedent is real and in-repo: the v0.10 DNA investigation
(`metrics/SUMMARY-2026-05-30-dna-investigation.md`) published a catch-vs-cry-wolf tradeoff (DNA
net-positive on Opus, a tradeoff on sub-Opus) and an explicit "do not claim X — measured: it
doesn't" rather than a flattering headline. That null/tradeoff write-up is exactly the shape
success takes here.

The north star is NOT "the council wins." Success = an honest, refutable, anti-Goodhart
measurement (both metrics together; n/scope visible; distinct-ids != cognition; a frozen
pre-registered line; no re-run-until-favourable; budget-gated), NOT "the council won."

---

## 2. Who benefits, and what changes for them

- **Ben / the Plumbline operator (the decision-owner).** Today he cannot say whether the
  foreign-model council earns its complexity and cost — the central justification is asserted,
  not measured, and Slice 2's diversity gate (OD-3) guards a council whose value is unknown.
  After 3b he holds a defensible **keep / extend (Slice 4 GUI) / retire** datapoint AND a cost
  go/no-go for the foreign council — carrying `n`, task count, model scope, AND catch-rate and
  cry-wolf side by side, on a council-independent frozen corpus, with the foreign-only line
  enforced at run time. Crucially, the answer is honest enough to act on **even when it is
  unfavourable** — the only kind worth paying a live pilot for.

- **The framework's own integrity (the empirical instrument).** This is the keystone slice.
  Slices 1+2 were allowed to defer the value claim **only because** Slice 3 exists to settle it.
  3b is where that deferral is cashed out. If the run is rigged, non-refutable, or
  re-run-until-favourable, then every "deferred to Slice 3 — not proven here" disclaimer upstream
  becomes a permanent dodge: the deferral was never honest. The beneficiary is Plumbline's
  central discipline — claims are *measured*, never asserted; RED is never downgraded.

- **The reviewer / auditor and future readers of the write-up.** They benefit from a published
  result that states exactly what it does and does NOT establish — an outcome delta on THIS
  corpus, NOT proven cognitive diversity, NOT generality — so it cannot be misread as proving
  more than it does. Refusing to over-claim is part of the delivered value, not a footnote.

## 3. When they would use it

When deciding whether the foreign-model council is worth running and paying for: before
committing to Slice 4 (the GUI) or to ongoing paid council runs, the operator consults the PILOT's
output — an `underpowered` / `tradeoff-signal-to-investigate` result judged against the
pre-registered line, plus its **ESTIMATED upper-bound cost (with Arm-A actual usage where the
instrument exposes it)** and its flakiness estimate — to decide whether to FUND the powered full
run. The pilot is run ONCE, on the frozen n=2 corpus, as an EXPLICITLY UNDERPOWERED run-mechanism
smoke + effect/cost estimate (ONE preset, A); the value verdict (demonstrated / refuted / tradeoff /
underpowered) comes from the powered full run (corpus expansion + A/B/C = the follow-on slice). The
deterministic primary scorer is re-runnable offline at zero credits; the live pilot is opt-in,
budget-bounded (a MAX-CALLS ceiling), and isolated outside the tree.

---

## 4. What "true to value" means here (True-Line discipline — the value-proof keystone)

Success is **a trustworthy measurement**, not "the council won" and not "tests green." This run
is true to value when ALL of the following hold:

- **Both anti-Goodhart metrics, always together.** Every published claim carries
  `review_catch_rate` AND `review_cry_wolf_rate` AND `review_recall_control`, side by side, with
  `n`, task count, and model scope visible. A catch-only headline ("the council halves escapes")
  without the cry-wolf number beside it is the single most dangerous miss and is RED. (The v0.10
  DNA slice found the two metrics can move in OPPOSITE directions — net-positive on Opus, a
  tradeoff on sub-Opus. "Strictly better" requires BOTH.)

- **The measurement is refutable by construction — and SYMMETRIC.** The pass/fail line is
  pre-registered, frozen, and TIMESTAMPED **before the first scored run** (REQ-MR-007; the noise
  model / MDE derived from the corpus cross-task variance, T1=1 / T2=2 defects). BOTH arms are
  prompted in the SAME structured flag protocol and scored through the SAME parser — a fair,
  constrained-output measurement of STRUCTURED-FLAG review, NOT a comparison where one arm is
  structured and the other is free prose (the asymmetry the remediation removed: feeding free
  council prose to a JSON-only parser would structurally lose the council). The powered-run rubric
  is four outcomes (**demonstrated** = catch up AND cry-wolf NOT worse; **refuted** = no catch delta
  outside the noise band; **tradeoff** = catch up but cry-wolf up; **underpowered** = below the MDE);
  at n=2 only `underpowered` / `tradeoff-signal-to-investigate` are reachable. A design that can only
  show the council winning is Goodharted and fails this Vision. **A null / negative / tradeoff result
  is a valid PUBLISHED outcome and is SUCCESS, not failure** — recorded in `metrics/runs.jsonl`,
  published as-is, never re-run-until-favourable.

- **"Underpowered" is NEVER laundered.** The n=2 pilot estimates effect + cost; it cannot deliver
  a definitive demonstrated/refuted call — at n=2 those are DEFINITIONALLY out of reach. A lucky
  2/2-vs-0/2 split MUST NOT be sold as `demonstrated`. "Underpowered → unmeasurable" is a
  **DISTINCT** published outcome — it is NOT a null, it is NOT "refuted", and it is NOT
  "demonstrated." Selling an underpowered pilot as a refutation (or as a win) is a False-Line
  violation and is RED.

- **Foreign-only integrity holds at run time — non-negotiable, with the OK-empty distinction.**
  Every scored Arm-B record asserts `foreign_only_ok = true` (no `anthropic`/`claude` id in
  `model_scope`). A foreign role with `code != OK` (budget-exhausted / unresolvable / timeout)
  triggers **PAIRED-EXCLUSION** (drop the SUBJECT from BOTH arms), is recorded UNAVAILABLE (never
  scored as a council miss, never Claude-substituted); a foreign role with `code == OK` and 0 flags
  is a LEGITIMATE empty review and is SCORED (a real potential miss, never excluded). Attrition is
  DISCLOSED by task difficulty; a MINIMUM-SURVIVORS floor forces `underpowered/unmeasurable` if too
  few subjects survive. A Claude-contaminated Arm B makes the delta partly Claude-vs-Claude and the
  whole result **uninterpretable** — the difference between a measurement and a fiction.

- **Distinct model ids are NOT read as proven cognition.** The result is an OUTCOME DELTA on THIS
  corpus — NOT proven uncorrelated *cognitive* diversity, NOT generality. The write-up says so
  explicitly (the scorer stamps the NON_CLAIM string).

- **The budget is user-gated; cost is honestly bounded; the instrument is consumed read-only;
  isolation holds.** The live pilot REFUSES to start without a token/$ cap NAMED BY THE USER at the
  pre-run gate. The instrument has only a PER-CALL cap and DISCARDS the preset-path `usage` block, so
  there is NO aggregate-cost meter: the aggregate budget is a MAX-CALLS ceiling (cap ÷ per-call cap, an
  a-priori upper bound) and cost is reported as an ESTIMATED upper bound, with ACTUAL usage recorded
  only where exposed (Arm A via the direct `run_inference` return; Arm-B actual cost needs the disclosed
  usage-seam OQ-DM-8, deferred). The 3a substrate (corpus + Arm-A runner + scorer) and the read-only
  instrument are CONSUMED, byte-unchanged — Arm A's real boundary is reached by the NEW run script
  calling `run_inference` directly, never by editing the frozen runner. ZERO live calls run inside
  `run_all.sh`; `git status` is clean and the suite green after every run; the deterministic primary
  score is re-runnable offline.

## Reality-Ledger Gegenthese (the value-killer to hold against this slice at the final gate)

*Could 3b be fully green — orchestrator passing, suite green, a record in `runs.jsonl` — yet
deliver ZERO truth?* The classic shapes to hunt for, each RED and (per the escalation-asymmetry
rule) NOT downgradable to a "known limitation" by any agent — only the user can:

- **A rigged corpus** — tasks tuned/dropped to flatter an arm. Green, but it can only confirm.
- **A non-refutable line** — a pass/fail rule written or moved AFTER seeing results. Green, but
  Goodharted; the council can only "win."
- **A re-run-until-favourable result** — the unfavourable run quietly dropped, a flattering one
  published. Green, but a lie.
- **A catch-only headline** — catch reported without cry-wolf beside it, manufacturing a "win"
  that is really a tradeoff. Green, but the most dangerous miss.
- **A Claude-contaminated Arm B** — a Claude id leaking into the council, so the delta is partly
  Claude-vs-Claude. Green, but uninterpretable.
- **Flakiness scored as signal** — a foreign role that 402/429/times-out counted as a "council
  miss" instead of paired-excluded and recorded unavailable. Green, but measuring the free tier,
  not cognition.
- **Underpowered sold as refuted (or as demonstrated)** — an n=2 below-MDE pilot relabeled into a
  definitive verdict. Green, but a false definitive — the laundering this slice exists to prevent.
- **An ASYMMETRIC measurement** — one arm prompted in the structured flag protocol while the other's
  free prose is fed to a JSON-only parser (yielding an empty flag-set). Green, but the council
  structurally loses to a parsing artifact, not to cognition — the integrity bug the 2026-06-20
  remediation removed (both arms now use the SAME protocol + SAME parser).
- **A fabricated "actual cost"** — an aggregate-cost figure reported as measured when the instrument
  discards the preset-path `usage` and has only a per-call cap. Green, but false precision — cost is
  an ESTIMATED upper bound (Arm-A actual only where the instrument exposes it).
- **A dead Arm-A live path** — an "it ran live" claim while Arm A's real transport is unreachable
  (the wired-in-prod risk below). Green, but the smoke never crossed the boundary.

A measurement matching any shape delivers zero customer value here no matter how green it is. The
specific wired-in-prod risk for THIS slice (carried from the openrouter-inference lesson, PRD
RISK-MR-012): the 3a Arm-A live transport is currently DEAD — a real-boundary smoke is impossible
until 3b adds the gated real entrypoint, so an "it ran live" claim with the Arm-A path still
unwired would be exactly the "exists in tests, never composed in prod" failure this repo exists to
prevent.

---

## 5. Explicit non-claims (what this slice does NOT prove)

Stating the north star as a question while refusing to pre-judge its answer is itself the value.
This slice does **NOT** assert, and the write-up must not be read as proving:

- **That the council adds value.** This Vision does NOT claim the foreign council wins. The
  council's value is the measurement's OUTPUT, unknown until it runs, and a valid published outcome
  whatever it is.
- **A definitive verdict from n=2.** The pilot is an EXPLICITLY UNDERPOWERED effect+cost estimate;
  the powered run + corpus expansion is the follow-on slice (NGOAL-3b-010).
- **Proven uncorrelated / cognitive diversity** from a distinct-model-id outcome delta. N distinct
  foreign ids do not prove uncorrelated cognition.
- **Generality beyond the measured corpus.** The primary number is an outcome delta on
  `council-review-catch-v1`; generality stays RED(confidence) until a powered run; any secondary
  real-defect-diff set is reported separately, never pooled into the primary.
- **Any live capability inside CI.** `run_all.sh` / the offline suite make ZERO live council calls.
  The live pilot is opt-in (`COUNCIL_INFERENCE_LIVE=1` + `--live`), budget-bounded, isolated.

---

## 6. Success signals (VCHK customer-value checks — what QA must verify as VALUE, not just function)

These trace to the canvas success signals (§5) and the PRD REQ acceptance. Each verifies that the
*measurement is trustworthy*, independent of whether the council "wins". (These execute in 3b the
deferred VCHK-DM-3b-* checks the 3a Vision §6 listed for traceability.)

- **VCHK-MR-1 — Both metrics in every published claim;** catch-only headline fails acceptance.
  Scope (`n`, task count, model scope) visible on every claim. (REQ-MR-003/006/010; RISK-MR-006.)
- **VCHK-MR-2 — Refutable + symmetric + null-publishable;** BOTH arms use the SAME structured flag
  protocol and the SAME parser (fair, constrained-output measurement, not structured-vs-prose); the
  pass/fail line + MDE + minimum-survivors floor + rubric is frozen and TIMESTAMPED before the first
  scored run; the run REFUSES to score without it; the outcome is judged against the frozen line and
  null/tradeoff/underpowered is published as-is, never re-run-to-favour. (REQ-MR-002/007;
  RISK-MR-003/007.)
- **VCHK-MR-3 — "Underpowered" stays DISTINCT** from "refuted" and from "demonstrated" in the
  record and the write-up; never laundered into a definitive verdict. (REQ-MR-007/010; RISK-MR-001.)
- **VCHK-MR-4 — Foreign-only integrity proven at run time, with the OK-empty distinction;** every
  scored Arm-B record has `foreign_only_ok = true`; a `code != OK` role is PAIRED-EXCLUDED, recorded
  unavailable, never Claude-filled, never scored a miss; a `code == OK` role with 0 flags is a SCORED
  legitimate empty review; a minimum-survivors floor forces `underpowered/unmeasurable`; attrition
  disclosed by task difficulty. (REQ-MR-004; RISK-MR-004/005.)
- **VCHK-MR-5 — Distinct-ids != cognition stated explicitly;** the write-up claims outcome-delta-
  only on this corpus, NOT proven diversity, NOT generality. (REQ-MR-010; RISK-MR-009/010.)
- **VCHK-MR-6 — Budget + isolation + cost honesty;** the live pilot refuses without a user-named
  cap; the aggregate budget is a MAX-CALLS ceiling (there is NO aggregate-cost meter); cost is an
  ESTIMATED upper bound with Arm-A actual usage where exposed; the live gate is OFF by default
  (0 calls) and Arm-A's real path is reachable only when armed (via the new script's direct
  `run_inference`, not an edit to the frozen runner); ZERO live calls in `run_all.sh`; `git status`
  clean + suite green after every run; the 3a substrate `git diff` is empty (consumed, not modified).
  (REQ-MR-005/008/009; NFR-MR-003/004; RISK-MR-008.)
- **VCHK-MR-7 — Deliverable is the honest write-up at its TRUE evidence class;** the live pilot is
  `real-boundary-smoke` of the RUN MECHANISM for THAT run only (a cost/flakiness estimate, NOT a value
  verdict), broader/definitive stays RED(confidence) until the powered run; the report carries the
  n=2 outcome class (`underpowered` / `tradeoff-signal-to-investigate`), the pre-registered line
  judged against, the FAIR (structured-flag) scope, the non-claims, the attrition, and the ESTIMATED
  upper-bound cost (Arm-A actual where exposed). (REQ-MR-010; NFR-MR-005.)

---

## 7. Traceability links

Product Canvas: docs/canvas/council-measurement-run.canvas.md (Status: user-confirmed, Ben 2026-06-20)
PRD: docs/prd/council-measurement-run.prd.md (draft; REQ-MR-001..011; canvas-bound)
Traceability Matrix: docs/traceability.md (slice council-measurement-run)
Reality Ledger (authored Phase 3 / Gate C): docs/reality/council-measurement-run.evidence.jsonl
3a substrate Vision (same north star): docs/vision/council-diversity-measurement.vision.md
3a substrate Canvas / PRD: docs/canvas/council-diversity-measurement.canvas.md ; docs/prd/council-diversity-measurement.prd.md (§2b deferred REQ-DM-3b-*)
Method precedent (published null/tradeoff result): metrics/SUMMARY-2026-05-30-dna-investigation.md
Consumed substrate (READ-ONLY, on main): metrics/corpus/council-review-catch-v1/** ; config/claude/metrics/{arm_a_review_runner,council_review_scorer}.py
Consumed instrument (READ-ONLY): config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py
Reused harness: config/claude/metrics/{emit_run,process_health,rule_ledger}.py
Backlog hand-off: backlog.md BL-DM-002 (this slice); BL-DM-001 (model-resolution fallback cascade, separate slice); powered run + corpus expansion = follow-on (NGOAL-3b-010).

Retained run-time BLOCKERs (by user decision at canvas confirmation, NOT unresolved Vision gaps):
the LIVE run needs a user-named token/$ budget cap (OQ-3b-1); the SCORED run needs a frozen,
timestamped pre-registered pass/fail line (OQ-3b-4). Neither blocks this Vision's confirmation,
the PRD, planning, or the OFFLINE build; both must be satisfied immediately before the live/scored run.

True-Line status: **user-confirmed (Ben 2026-06-20).** This Vision was authored by the
product-owner from the user-confirmed Canvas; the user confirmed the PRD AND this Vision together
at the Phase-0 gate, so Canvas + PRD + Vision are all user-confirmed and Phase 0 is complete. The user confirmed
the PRD and this Vision TOGETHER at the next gate; the product-owner does not self-confirm.
Status note (carried IDENTICALLY in the header above): this Vision was FROZEN after a SINGLE
spec-auditor remediation pass (Ben-approved, 2026-06-20) — measurement-integrity fixes propagated
from the canvas/PRD (arm symmetry / symmetric flag protocol; Arm-A real transport via the new script
calling `run_inference` directly; estimated-budget / MAX-CALLS reframe; minimum-survivors floor;
n=2 rubric; one-preset pilot; honest pilot PURPOSE made load-bearing). Status remains user-confirmed;
no re-audit. The confirmation phrase, to be UTTERED BY THE USER at that gate:

```text
I confirm this Slice-3b Council Measurement RUN Product Vision as the basis for AgileTeam planning.
```
