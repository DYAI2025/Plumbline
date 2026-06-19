# PRD: Council Measurement RUN — Slice 3b: RUN the foreign-model-council measurement on the 3a substrate and PUBLISH the honest result

Feature-Slug: council-measurement-run
Slice: 3b of 4 — the MEASUREMENT RUN. (3a = the substrate, on main, consumed READ-ONLY; Slice 4 = the GUI.)
Status: user-confirmed (Ben 2026-06-20; PRD + Vision confirmed together at the Phase-0 gate; Canvas already user-confirmed. Phase 0 complete.)
Status note: FROZEN after a SINGLE spec-auditor remediation pass (Ben-approved, 2026-06-20) — measurement-integrity fixes applied (arm symmetry / symmetric flag protocol replacing the deleted prose-parse; Arm-A real transport via the new script calling `run_inference` directly, resolving the REQ-MR-005 vs REQ-MR-009 contradiction; estimated-budget / MAX-CALLS reframe; minimum-survivors floor + OK-empty vs non-OK distinction; n=2 rubric; one-preset pilot). Status remains user-confirmed; no re-audit. (Carried IDENTICALLY in §7 DoR.)
Owner: requirements-analyst
Canvas (user-confirmed): docs/canvas/council-measurement-run.canvas.md (Status: user-confirmed, Ben 2026-06-20, Phase-0.15 gate)
Product Vision: docs/vision/council-measurement-run.vision.md (to be authored by product-owner after this PRD draft)
Traceability: docs/traceability.md (slice council-measurement-run; carries canvas-link: docs/canvas/council-measurement-run.canvas.md)
Prefix: REQ-MR-* (requirements), NFR-MR-* (non-functional), RISK-MR-* (risks), TRC-MR-* (traceability stub)

> This PRD is bound to the user-confirmed Product Canvas above and may not be read apart from
> it. Every REQ traces to a canvas value statement / RISK-3b-* / OQ-3b-* resolution / EVN-3b-*.
>
> **WHAT SLICE 3b IS.** Slice 3a (on main, user-confirmed) BUILT and offline-validated the
> SUBSTRATE — the frozen review-catch corpus `metrics/corpus/council-review-catch-v1/` (T1-auth
> = 1 seeded defect, T2-pagination = 2 seeded defects; clean controls; recall controls;
> deterministic file+line-overlap matcher), the Arm-A (Claude-only) runner
> `config/claude/metrics/arm_a_review_runner.py`, and the shared judge-free flag-set scorer
> `config/claude/metrics/council_review_scorer.py`. Slice 3b RUNS that instrument to produce the
> FIRST measurement of the value claim the whole foreign-model council effort (Slices 1+2) rests
> on — **"does a foreign (non-Claude) preset council catch defects a Claude-only review MISSES,
> WITHOUT raising the cry-wolf rate?"** — and the RESULT is the deliverable, whatever it is. For the
> n=2 PILOT the reachable outcomes are `underpowered` and (at most) `tradeoff-signal-to-investigate`;
> the full demonstrated/refuted/tradeoff/underpowered verdict belongs to the powered FOLLOW-ON run.
> **The pilot's PURPOSE is narrow: (a) a real-boundary-smoke of the RUN MECHANISM and (b) a
> cost/flakiness estimate — NOT a value verdict on the council.**
>
> **THE LOAD-BEARING HONESTY DISCIPLINE (binding — carried from the canvas, with the 2026-06-20
> remediation).**
> (1) Foreign-only Arm B enforced at RUN time; a foreign role with `code != OK` →
> PAIRED-EXCLUSION (drop the subject from BOTH arms), never Claude-substituted, never scored a
> miss; a `code == OK` role with 0 flags is a SCORED legitimate empty review; a MINIMUM-SURVIVORS
> floor forces `underpowered/unmeasurable`; attrition disclosed by difficulty. (2) Both metrics
> together, always — catch AND cry-wolf AND recall-control, with n/task-count/scope visible; a
> catch-only headline is RED. (3) Distinct model ids != uncorrelated cognition — the result is an
> OUTCOME DELTA on this corpus, never proven diversity. (4) Pre-registered pass/fail line FROZEN +
> timestamped before the first scored run; at n=2 `demonstrated`/`refuted` are definitionally out
> of reach; null/tradeoff/underpowered published as-is, never re-run-until-favourable; "underpowered"
> is a DISTINCT outcome from "refuted" and from "demonstrated". (5) ARM SYMMETRY: BOTH arms are
> prompted in the SAME structured flag protocol (appended to `--subject`) and parsed by the SAME
> `parse_flag_set` — a constrained-output, symmetric measurement of STRUCTURED-FLAG review (NOT
> free-form prose); a non-protocol output is a classified parse failure handled IDENTICALLY for both
> arms. (6) Budget = a MAX-CALLS ceiling (user-named cap ÷ per-call cap); there is NO aggregate-cost
> meter (the preset path discards `usage`); cost is an ESTIMATED upper bound with Arm-A actual usage
> where exposed; the PILOT runs ONE preset (A) vs Claude-only (A/B/C deferred). (7) Bench-isolation:
> eval inputs staged OUTSIDE the tree; ZERO live calls in `run_all.sh`; `git status` clean +
> `run_all.sh` green after every run; the deterministic primary scorer is re-runnable offline.
> (8) The 3a substrate + the read-only instrument are CONSUMED, not modified — Arm A's real boundary
> is reached by the NEW script calling `run_inference` directly, NOT by editing the frozen runner.

---

## 0. Provenance & verified premises (external-claim discipline)

All foreign-file / substrate-contract premises were OPENED and READ on 2026-06-20 BEFORE becoming
PRD premises (the gap rule). Classification per row: `belegt` = verified against the real artifact;
`ableitbar` = derivable from a verified artifact; `ungeprüft` = not yet read end-to-end (must be
closed in Phase 3 before becoming a run premise, never downgraded to a "documented risk").

| Premise | Source (read 2026-06-20) | Class |
|---|---|---|
| `deepseek_review.py preset --subject <S>` threads `S` VERBATIM into each role's user message (`_cmd_preset` → `build_character_messages(slug, args.subject, ...)`), so the orchestrator can append the IDENTICAL structured-flag-protocol instruction to `--subject` for Arm B exactly as Arm A embeds it. `preset` returns `{"code", "positions": [{"role","character","model","code","position"}], "diversity": ...}`; each role's `model` is the foreign id; each role's `position` is the RAW model completion (or `None` on a non-OK code). | `config/claude/lib/deepseek_review.py` `_cmd_preset` (474–537), `build_character_messages` (237–246), `wrap_position` (252–264), `p_pre --subject` (355) | **belegt** — closes the 3a `ungeprüft` (EVN-DM-008 / OQ-DM-8). Drives REQ-MR-002 (SYMMETRIC flag protocol: both arms prompted in the same protocol via `--subject`, both parsed by the SAME `parse_flag_set`). |
| `wrap_position` DISCARDS the response `usage` block — it keeps ONLY `completion` as the position — so the `preset` path exposes NO per-role token usage. `council_inference.run_inference(...)` is callable DIRECTLY with `messages` + `transport=_real_transport`, gated by `--live` AND `COUNCIL_INFERENCE_LIVE=1`, and its RETURN carries the reconciled `usage` block. | `deepseek_review.py` `wrap_position` (260–264); `council_inference.py` `run_inference` (288–373), `_classify_response` (215–218), `_make_transport`/gate (365–375, 436–440) | **belegt** — drives REQ-MR-005 (budget = MAX-CALLS ceiling, NO aggregate-cost meter; Arm-A actual usage via the direct `run_inference` return; Arm-B actual cost needs the deferred OQ-DM-8 seam) and the Arm-A-transport-in-new-script resolution of the REQ-MR-005 vs REQ-MR-009 contradiction. |
| `deepseek_review.py preset` arms the real transport ONLY when `--live` AND `COUNCIL_INFERENCE_LIVE=1` (delegates to `council_inference._real_transport`); offline via `--inject-response`/`--inject-catalog`/`--inject-call-counter` (0 credits, 0 network). | `deepseek_review.py` `_make_transport` (365–375), `_parser` (353–361) | belegt — drives REQ-MR-005 (live gate) + REQ-MR-008 (offline harness). |
| The `preset` resolver NEVER substitutes a Claude model on an unresolvable role: a role classifies `model-unresolvable`/`catalog-unreachable`/`unknown-character-slug` with `position: None` and a non-OK `code`. | `deepseek_review.py` (47–50, 499–504), `council_presets` (per 3a `belegt`) | belegt — drives REQ-MR-004 (PAIRED-EXCLUSION; a non-OK Arm-B role is unavailable, not a miss). |
| `council_review_scorer.py score` consumes a flag-set `{arm, model_scope, task, flags:[{file,line\|line_start/line_end, description}]}` + the corpus oracle and returns BOTH metric families plus `foreign_only_ok` (true iff a non-`claude-only` arm carries NO `anthropic`/`claude` id in `model_scope`). | `council_review_scorer.py` `score_flag_set` (174–262), `_cmd_score` (294–306) | belegt — drives REQ-MR-003 (scoring) + REQ-MR-004 (foreign-only). |
| `council_review_scorer.py emit-blob` routes the review metrics + `arm` + `model_scope` under `raw` (NOT `metrics`) and leaves `metrics` empty; flags `--catch/--cry-wolf/--recall/--n/--task-count/--arm/--model-scope`. | `council_review_scorer.py` `build_emit_blob` (268–288), `_cmd_emit_blob`/`_parser` (309–361) | belegt — drives REQ-MR-006 (emission schema). |
| `arm_a_review_runner.py` exposes REUSABLE pure helpers — `build_messages` / `build_review_prompt` (the structured-flag-protocol prompt) and `parse_flag_set` (parses ONLY `{"flags":[...]}` JSON, tolerant of a ` ```json ` fence; free prose → `ARM_A_FLAG_PROTOCOL_MALFORMED` → EMPTY flag-set, never a fabricated flag). Its `_cmd_review` live path still classifies `ARM_A_NEEDS_INJECTION` and fires 0 calls — it has NO real transport. | `arm_a_review_runner.py` `build_messages` (99–104), `build_review_prompt` (75–96), `parse_flag_set` (110–153), `_cmd_review` (214–252) | belegt — drives REQ-MR-002 (the SAME `parse_flag_set` for both arms; it cannot parse free prose, so both arms MUST be prompted in the structured protocol) and REQ-MR-005 (3b reaches Arm-A's real boundary NOT by editing this read-only file but by the new `council_measurement_run.py` calling `council_inference.run_inference(...)` directly with Arm-A's `build_messages` — resolving the REQ-MR-005 vs REQ-MR-009 contradiction; the dead 3a Arm-A live path stays untouched, mirroring the openrouter-inference injectable-seam lesson). |
| `emit_run.py` rejects any `--metrics` key not in the closed `process_health.DIRECTIONS` allowlist; `corpus_id` is top-level via `--corpus-id`; `--raw` is free-form (recorded, never scored). Top-level record keys are fixed (no `arm`/`model_scope`/`catch_rate`). `--tokens-total`+`--reqs-accepted` compute the allowlisted `cost_per_req`. | `emit_run.py` `validate_metrics` (262–271), `apply_cost` (274–303), `main` (337–388) | belegt — drives REQ-MR-006 (raw, not metrics) + REQ-MR-005 (cost via the allowlisted `cost_per_req`). |
| `process_health.py` SPC reads each metric as `r["metrics"][<name>]` ONLY — it does NOT read `raw`. So review catch/cry-wolf (which live under `raw`) are NOT directly SPC'd; the cross-task variance / MDE for the pre-registered line must be computed by the orchestrator over the captured per-task scores (or the allowlisted `cost_per_req` is the only directly-SPC'd metric). | `process_health.py` `spc_for_metric` (80–110), `load_runs`/`baseline_values` (42–58) | **belegt** — drives REQ-MR-007 (the noise model / MDE is derived from the captured per-task catch/cry-wolf scores; do NOT claim `process_health.py` SPCs the review metrics directly). |
| The corpus `council-review-catch-v1` is content-hashed: `council_review_scorer.py freeze-hash` recomputes the hash over `oracle.json` + `diffs/`, comparable to `manifest.json` "hash". T1 = 1 defect, T2 = 2 defects (cross-task variance for the MDE). | `council_review_scorer.py` `compute_corpus_hash` (324–340); corpus `manifest.json`/`oracle.json` | belegt — drives REQ-MR-007 (variance source) + REQ-MR-009 (freeze-hash check). |

> Any premise that is later found `ungeprüft` MUST be opened and reclassified in Phase 3 BEFORE it
> becomes a run premise (the external-claim discipline). It may NOT be downgraded to a "documented
> risk" and forwarded as a working premise. The most expensive miss this prevents: a disproven
> external method contract surviving to the judgment gate.

---

## 1. Goal & non-goals (pointer)

**Goal.** RUN the 3a instrument as a BOUNDED PAID PILOT (Arm A Claude-only vs Arm B = preset A
ONLY; OQ-3b-2 + OQ-3b-3 as narrowed by the 2026-06-20 remediation decision; A/B/C deferred to the
powered run) on the frozen n=2 corpus, with BOTH arms prompted in the SAME structured flag protocol
and scored through the SAME parser + shared judge-free scorer, emit per-arm results into
`metrics/runs.jsonl`, and PUBLISH an honest write-up of the outcome class — judged against a
pre-registered, frozen, timestamped pass/fail line — with the ESTIMATED upper-bound cost reported
and ACTUAL usage recorded where the instrument exposes it (Arm A only). **The pilot's PURPOSE is
narrow and load-bearing: (a) prove the run-harness works end-to-end LIVE (a real-boundary-smoke of
the RUN MECHANISM) and (b) estimate cost + flakiness — it is NOT a value verdict on the council.**
Every value-claim path routes through the powered full run (deferred). The deliverable is the honest
result, whatever it shows.

**Non-goals.** Carried verbatim from canvas §7 (NGOAL-3b-001..012): no modifying the 3a substrate
or the read-only instrument; no new instrument / parallel harness; no corpus tuning or task
dropping; no catch-only / single-metric headline; no claiming proven cognitive diversity; no
suppressing or re-running-away a null/tradeoff/underpowered result; no Claude id in Arm B and no
Claude-substitution of a budget-exhausted foreign role; no live call in `run_all.sh`; no claiming
generality beyond the measured corpus; no full powered run + corpus expansion in THIS slice
(follow-on); no Slice-4 GUI; no model-resolution fallback cascade (BL-DM-001).

---

## 2. Run flow (the orchestration this PRD specifies)

The NEW run-orchestration script (proposed path `config/claude/metrics/council_measurement_run.py`
— the canvas-scoped, scope-validated name; the task-proposed alias `run_measurement.py` is a
reversible implementation detail the planner may pick, but it would require a Phase-0.6 canvas
scope update + `plumbline-scope-check` re-run). It is the ONLY new code module; it lives under
`config/claude/metrics/`, NOT under the read-only `config/claude/lib/` instrument tree, and it
builds NO new instrument.

Per corpus task (T1-auth, T2-pagination). BOTH arms are prompted in the SAME structured flag
protocol (each finding as `{file,line,description}` inside one `{"flags":[...]}` JSON) and parsed
by the SAME `arm_a_review_runner.parse_flag_set` — a SYMMETRIC, constrained-output measurement:

1. **Arm A** — build the structured-flag-protocol messages (`arm_a_review_runner.build_messages`),
   parse the model output with `arm_a_review_runner.parse_flag_set` → an Arm-A flag-set. Offline:
   inject the response and parse it. Live (3b): the new `council_measurement_run.py` calls
   `council_inference.run_inference(...)` DIRECTLY with those Arm-A messages + `transport=_real_transport`
   (reaching the SAME real boundary as Arm B, gated by `--live` + `COUNCIL_INFERENCE_LIVE=1`), and
   parses the returned `completion` with the same `parse_flag_set`. It does NOT edit the read-only
   `arm_a_review_runner.py` (REQ-MR-009). (REQ-MR-005)
2. **Arm B (preset A only for the pilot; A/B/C deferred)** — invoke `deepseek_review.py preset
   --preset A --subject <S>` where `S` carries the IDENTICAL structured-flag-protocol instruction
   appended to the review subject (EVN-3b-010 `belegt`: `--subject` threads verbatim into each role).
   For each role whose `code == OK`, parse its `position` (the model's protocol JSON output) with the
   SAME `parse_flag_set`; assemble the preset's flag-set with `arm="council-A"` and
   `model_scope=[the resolved foreign model ids]`. (NOT "parse free prose": `parse_flag_set` cannot
   parse unconstrained prose — that incoherent step was DELETED. REQ-MR-002.)
3. **Score** — feed each arm's flag-set to `council_review_scorer.py` (`score` / `score_flag_set`)
   → catch / cry-wolf / recall + `foreign_only_ok`, deterministically. (REQ-MR-003)
4. **Foreign-only + attrition + survivors gate** — assert `foreign_only_ok=true` on every scored
   Arm-B record. A role whose `code != OK` (budget-exhausted/timeout/unresolvable) is FLAKINESS:
   PAIRED-EXCLUDE that subject from BOTH arms, record attrition by difficulty. A role whose
   `code == OK` with 0 parsed flags is a LEGITIMATE empty review — SCORED (a real potential miss),
   NOT excluded. If fewer than the pre-registered MINIMUM SURVIVORS remain, force the outcome to
   `underpowered/unmeasurable`. (REQ-MR-004)
5. **Emit** — for each surviving arm×task record, build the `emit-blob` `{metrics, raw}` pair and
   call `emit_run.py --raw <blob.raw> --corpus-id council-review-catch-v1` (review metrics under
   `raw`). Cost: there is NO aggregate-cost meter (the preset path discards `usage`); the allowlisted
   `cost_per_req` (via `--tokens-total`/`--reqs-accepted`) is populated ONLY for Arm A from the direct
   `run_inference` `usage` return; Arm-B cost is the ESTIMATED upper bound. (REQ-MR-006)
6. **Analyze** — run `process_health.py` over `runs.jsonl`; compute the cross-task variance / MDE
   for the pre-registered line from the captured per-task catch/cry-wolf scores (NOT from
   `process_health`'s metric SPC, which reads `metrics`, not `raw`). (REQ-MR-007)
7. **Classify + publish** — judge the aggregate against the FROZEN pre-registered line. At n=2 only
   `underpowered` / `tradeoff-signal-to-investigate` are reachable (`demonstrated`/`refuted` are
   definitionally out of reach — REQ-MR-007); write the honest report with the estimated upper-bound
   cost + Arm-A actual usage. (REQ-MR-007, REQ-MR-010)

---

## 3. Functional requirements (REQ-MR-*)

Each REQ is atomic, testable, and Given/When/Then. "OFFLINE" = injected Arm-A/Arm-B responses +
injected catalog, 0 credits, 0 network.

### REQ-MR-001 — Run orchestration over the corpus (both arms, per task)
Traces: canvas §6, value-prop bullet 4, EVN-3b-006.
The orchestrator runs, per corpus task, Arm A (Claude-only) and Arm B (preset A ONLY for the pilot;
A/B/C deferred), with BOTH arms prompted in the SAME structured flag protocol and parsed by the SAME
`parse_flag_set`, scores each via `council_review_scorer.py`, and emits one run record per surviving
arm×task via `emit_run.py`.
- **Given** the frozen corpus `council-review-catch-v1` and an OFFLINE config (injected responses
  for both arms, injected catalog),
- **When** the orchestrator runs end-to-end,
- **Then** it produces, for each task and each arm (A = `claude-only`, B = `council-A`), exactly
  one scored record carrying `arm`, `model_scope`, `task`, `review_catch_rate`,
  `review_cry_wolf_rate`, `review_recall_control`, `n`, `task_count`, and `foreign_only_ok`; and it
  exits non-zero on any orchestration error (fail-closed), never emitting a partial/fabricated
  record. (The powered FOLLOW-ON run adds `council-B`/`council-C`; the pilot runs one preset.)

### REQ-MR-002 — SYMMETRIC structured flag protocol for BOTH arms (verified contract)
Traces: §0 (`belegt` preset `--subject` + `parse_flag_set` contract), OQ-DM-8 resolution, canvas §6
ARM SYMMETRY block. **This REQ was rewritten in the 2026-06-20 remediation: the prior "parse Arm-B
free prose with `parse_flag_set`" requirement is DELETED as incoherent — `parse_flag_set` parses
ONLY a `{"flags":[...]}` JSON object (free prose → `ARM_A_FLAG_PROTOCOL_MALFORMED` → EMPTY flag-set),
so feeding it unconstrained council prose would structurally lose the council (empty flag-set). There
is no unvalidated prose→flag parser; the fix is symmetry.**
The orchestrator appends the IDENTICAL structured-flag-protocol instruction (emit each finding as a
`{file,line,description}` object inside one `{"flags":[...]}` JSON) to the review `--subject` for BOTH
Arm A (already structured) AND Arm B's council roles (via `deepseek_review.py preset --subject`,
`belegt`: `--subject` threads verbatim into each role's user message). Each arm's raw model output is
then parsed by the SAME `arm_a_review_runner.parse_flag_set`. The measurement is therefore of
STRUCTURED-FLAG review for BOTH arms (constrained-output, symmetric), NOT free-form prose review — that
fair scope is stated in the write-up (REQ-MR-010). A non-protocol output is a CLASSIFIED parse failure
handled IDENTICALLY for both arms (never silently zeroing one arm only).
- **Given** an Arm-B role whose `code == OK` and whose output is well-formed protocol JSON,
- **When** the orchestrator parses it with the SAME `parse_flag_set` it uses for Arm A,
- **Then** the Arm-B flag-set contains exactly the locatable `{file,line,description}` flags;
- **And given** a `code == OK` role whose output is non-protocol JSON, **Then** `parse_flag_set`
  classifies it `ARM_A_FLAG_PROTOCOL_MALFORMED` → an EMPTY flag-set — the SAME classification path Arm
  A's non-protocol output takes (symmetric), never a fabricated flag;
- **And given** a role with a non-OK `code` / `position: None`, **Then** it is treated as UNAVAILABLE
  (REQ-MR-004 PAIRED-EXCLUSION), DISTINCT from a `code == OK` empty review (a scored real miss).

### REQ-MR-003 — Judge-free scoring via the shared scorer (deterministic)
Traces: canvas §5, EVN-3b-007, NFR-MR-002.
Both arms are scored ONLY through the read-only `council_review_scorer.py`; the orchestrator adds
no scoring logic of its own.
- **Given** a captured flag-set for an arm×task,
- **When** it is scored,
- **Then** the result carries BOTH metric families together (catch AND cry-wolf AND recall) and is
  numerically IDENTICAL on re-run over the same captured flag-set (numeric equality, not substring);
- **And** the corpus freeze-hash (`council_review_scorer.py freeze-hash`) still equals
  `manifest.json` "hash" (the corpus was consumed, not mutated).

### REQ-MR-004 — Foreign-only enforcement + PAIRED-EXCLUSION at run time
Traces: canvas §1.1 / §7 NGOAL-3b-007 / RISK-3b-005 / RISK-3b-006, EVN-3b-004.
Every scored Arm-B record asserts `foreign_only_ok=true` (no `anthropic`/`claude` id in
`model_scope`). The attrition rule turns on the role `code`, and a MINIMUM-SURVIVORS floor guards
against a thin published result:
- a role whose **`code != OK`** (budget-exhausted/unresolvable/timeout) is FLAKINESS → PAIRED-EXCLUSION:
  drop that SUBJECT from BOTH arms; record it UNAVAILABLE (never a council miss, never Claude-substituted);
- a role whose **`code == OK`** with 0 parsed flags is a LEGITIMATE EMPTY REVIEW → SCORED (a real
  potential miss), NEVER excluded;
- attrition is disclosed by task difficulty; if fewer than the pre-registered MINIMUM SURVIVORS remain
  after paired-exclusion, the outcome is FORCED to `underpowered/unmeasurable` (REQ-MR-007), never
  published as a thin result.
- **Given** an Arm-B record whose `model_scope` carries a Claude/anthropic id,
- **When** the orchestrator validates it,
- **Then** the record is REJECTED (not scored as a council result) and the run fails closed for
  that subject;
- **And given** an Arm-B role that returns a non-OK `code` (budget-exhausted/timeout/unresolvable),
- **Then** the orchestrator PAIRED-EXCLUDES the subject from BOTH arms, records it unavailable with
  the task difficulty, and NEVER scores it as a council miss and NEVER substitutes a Claude model;
- **And given** an Arm-B role with `code == OK` and 0 flags, **Then** the subject is SCORED (a
  legitimate empty review / real potential miss), NOT excluded;
- **And given** fewer than the pre-registered minimum survivors, **Then** the outcome is forced to
  `underpowered/unmeasurable`.

### REQ-MR-005 — Live gate + budget BLOCKER + Arm-A real transport in the NEW script
Traces: canvas OQ-3b-1 (BLOCKER), RISK-3b-002, EVN-3b-002, NGOAL-3b-008, NFR-MR-003; §0 (`belegt`
`run_inference` direct-call + `usage` return + dead 3a Arm-A path).
**Arm-A transport resolution (resolves the prior REQ-MR-005 vs REQ-MR-009 contradiction).** REQ-MR-009
freezes `arm_a_review_runner.py` read-only, so 3b does NOT edit it to add Arm-A's real transport.
Instead the NEW `config/claude/metrics/council_measurement_run.py` reaches Arm A's real boundary by
calling `council_inference.run_inference(...)` DIRECTLY with Arm-A's structured-protocol `messages`
(from `arm_a_review_runner.build_messages`) and `transport=council_inference._real_transport` — the
SAME `_real_transport` Arm B reaches via `deepseek_review.py preset` (a SYMMETRIC real boundary). The
3a Arm-A live path stays dead and untouched (mirroring the openrouter-inference injectable-seam lesson:
a paired, gated real entrypoint, not an edit to the frozen runner).
**Live gate.** Real calls happen ONLY when the live gate is ON (`--live` AND `COUNCIL_INFERENCE_LIVE=1`)
AND a user-named pilot budget cap (token or $) is supplied at invocation. The budget value is NOT in
the PRD; it is NAMED BY THE USER at the pre-run gate.
**Budget = MAX-CALLS ceiling (NOT an aggregate-cost meter).** The instrument enforces ONLY a PER-CALL
token cap (`COUNCIL_MAX_TOKENS_PER_RUN`) and DISCARDS the `usage` block on the preset path (§0
`belegt`), so there is NO aggregate-spend meter to "halt at an aggregate cap". The aggregate budget is
therefore a MAX-CALLS CEILING = user-named cap ÷ per-call cap (an a-priori UPPER BOUND); the run makes
at most that many calls. Cost is REPORTED as an ESTIMATED upper bound; ACTUAL usage is recorded ONLY
where exposed — Arm A via the direct `run_inference` `usage` return — while Arm-B actual cost needs the
disclosed usage-seam OQ-DM-8 (deferred, not silently assumed).
- **Given** a live invocation with NO budget cap supplied,
- **When** the orchestrator starts,
- **Then** it REFUSES to start the live run (fail-closed, non-zero exit) — no live call is made;
- **And given** a live invocation WITH a user-named cap,
- **Then** real calls proceed up to the derived MAX-CALLS ceiling, the ESTIMATED upper-bound cost is
  reported, and Arm-A ACTUAL usage is recorded from the `run_inference` return;
- **And given** the default (no gate), **Then** ZERO transport calls fire (the call counter reads 0)
  and the run uses the offline injected path. A test asserts the gate is OFF by default (0 calls) and
  that the Arm-A live path is REACHABLE only when armed.

### REQ-MR-006 — Emission matches the REAL emit_run schema (raw, not metrics)
Traces: canvas value-prop bullet 4 / EVN-3b-006, §0 (`belegt` emit_run + scorer emit-blob).
Per surviving arm×task, the orchestrator builds the scorer's `emit-blob` `{metrics, raw}` pair and
calls `emit_run.py` with the review metrics + `arm` + `model_scope` under `--raw` (NEVER `--metrics`
— they are not in `process_health.DIRECTIONS`; `emit_run` rejects a non-allowlisted `--metrics`
key), and `corpus_id = council-review-catch-v1` top-level via `--corpus-id`. Any cost metric is the
allowlisted `cost_per_req` only (via `--tokens-total`/`--reqs-accepted`), populated ONLY for Arm A
from the direct `run_inference` `usage` return; Arm-B cost is the ESTIMATED upper bound (no `usage`
on the preset path — §0 `belegt`), never a fabricated actual.
- **Given** a scored arm×task result,
- **When** it is emitted,
- **Then** `runs.jsonl` gains one record whose `corpus_id="council-review-catch-v1"` (top-level),
  whose `raw` carries `review_catch_rate`/`review_cry_wolf_rate`/`review_recall_control`/`n`/
  `task_count`/`arm`/`model_scope`, and whose `metrics` contains NO non-allowlisted key; and
  `emit_run.py` exits 0 (it would exit 2 on a non-allowlisted `--metrics` key — proving the routing).

### REQ-MR-007 — Pre-registered pass/fail line FROZEN before the first scored run
Traces: canvas OQ-3b-4 (BLOCKER), RISK-3b-001/003, EVN-3b-001, success-signal bullets 1+6.
A pre-registration ARTIFACT (proposed `metrics/pre-registration-council-measurement-run.json`) is
authored and TIMESTAMPED before the first scored run. It records: the noise model (derived from the
corpus cross-task variance T1=1 / T2=2 defects, computed by the orchestrator over captured per-task
catch/cry-wolf scores — NOT from `process_health`'s metric SPC, which reads `metrics`, not `raw`), the
MDE, the MINIMUM-SURVIVORS floor, and the outcome rubric.
**Powered FOLLOW-ON rubric (four outcomes):** **demonstrated** = catch-rate up AND cry-wolf NOT worse;
**refuted** = no catch delta outside the noise band; **tradeoff** = catch up but cry-wolf up;
**underpowered** = the observed delta is below the MDE (DISTINCT from refuted).
**PILOT (n=2) rubric — definitionally narrower (remediation 2026-06-20):** at n=2 the cross-task
variance is UNESTIMABLE, so **`demonstrated` and `refuted` are DEFINITIONALLY OUT OF REACH.** The ONLY
honest pilot outcomes are **`underpowered`** and (at most) **`tradeoff-signal-to-investigate`**. A lucky
2/2-vs-0/2 split MUST NOT be laundered as `demonstrated`. The MINIMUM-SURVIVORS floor (REQ-MR-004) also
forces `underpowered/unmeasurable` below the pre-registered minimum. The published outcome is judged
against the FROZEN line, never against a line moved after seeing results.
- **Given** an attempt to score a run while no frozen, timestamped pre-registration artifact exists,
- **When** the orchestrator reaches the scored-run step,
- **Then** it REFUSES to score (fail-closed, non-zero exit);
- **And given** a frozen artifact with a timestamp earlier than the first scored record,
- **Then** the run proceeds and the report classifies the outcome strictly by the artifact's rubric,
  with "underpowered" emitted as a DISTINCT class (never relabeled "refuted" or "demonstrated", never
  laundered as a null);
- **And given** an n=2 pilot run, **Then** the classifier emits ONLY `underpowered` or
  `tradeoff-signal-to-investigate` — `demonstrated`/`refuted` are unreachable at n=2 by construction.

### REQ-MR-008 — Offline-validatable harness (run logic tested before any live spend)
Traces: canvas §1.5 / §5, EVN-3b-008, NGOAL-3b-008, NFR-MR-002.
The full orchestration + scoring + emission path is exercisable OFFLINE with injected Arm-A and
Arm-B responses + an injected catalog (0 credits, 0 network), so the RUN LOGIC is proven before any
live spend; the live run is the only real-boundary part. Bench-isolation: inputs staged OUTSIDE the
repo tree; after every run `git status` is clean and `run_all.sh` is green; NO live call inside
`run_all.sh`.
- **Given** an OFFLINE invocation (injected responses + catalog, no live gate),
- **When** the orchestrator runs the full per-task arm→scorer→emit loop to a temp `runs.jsonl`
  staged outside the tree,
- **Then** it completes with 0 transport calls (counter == 0), produces the expected scored records
  deterministically, and leaves the repo tree byte-unchanged (the 3a substrate `git diff` is empty);
- **And** the offline path is covered by `config/claude/tests/test_council_measurement_run.sh`, which
  runs inside `run_all.sh` and makes ZERO live calls.

### REQ-MR-009 — Substrate + corpus stay READ-ONLY (consumed, not modified)
Traces: canvas §7 NGOAL-3b-001/002, success-signal bullet 8, EVN-3b-008.
3b adds ONLY the run-orchestration script, its test, the benchmark write-up, the 3b docs, the
reality ledger, the pre-registration artifact, and appends to `runs.jsonl`. The 3a substrate
(corpus, Arm-A runner, scorer) and the read-only instrument
(`config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py`,
`concilium/**`) are CONSUMED, not edited.
- **Given** the completed 3b build,
- **When** `git diff` is taken over the substrate + instrument paths,
- **Then** it is EMPTY (byte-unchanged); and the corpus freeze-hash still equals `manifest.json`
  "hash".

### REQ-MR-010 — The deliverable is the honest write-up at its TRUE evidence class
Traces: canvas §4 value-prop / §5 success-signal, EVN-3b-009/011, NGOAL-3b-006/009.
The deliverable is a `docs/benchmarks/` report stating: the outcome class, the pre-registered line
it was judged against, the explicit non-claims (outcome-delta-only on this corpus, NOT proven
diversity, NOT generality), the FAIR SCOPE (this measures STRUCTURED-FLAG review for BOTH arms —
constrained-output, symmetric — NOT free-form prose review), the attrition by difficulty, BOTH metric
families with n/task-count/scope, the pinned instrument snapshot commit, the pilot PURPOSE (a
real-boundary-smoke of the RUN MECHANISM + a cost/flakiness estimate, NOT a value verdict), and the
cost as an ESTIMATED upper bound with Arm-A ACTUAL usage where exposed. The live pilot is classified
`real-boundary-smoke` for THAT run only; the broader/definitive claim stays RED(confidence) until a
powered run. A null/tradeoff/underpowered result is published as-is.
- **Given** a completed scored n=2 pilot run (any outcome),
- **When** the report is written,
- **Then** it carries both metrics + n + scope + the FAIR (structured-flag) scope statement + the
  pilot-purpose statement + the n=2 classification (`underpowered`/`tradeoff-signal-to-investigate`
  only) + the non-claims + the estimated upper-bound cost (Arm-A actual where exposed), and it does
  NOT headline catch alone, does NOT claim generality or proven diversity, does NOT claim free-form
  prose review was measured, and does NOT relabel an underpowered result as a null, as refuted, or as
  demonstrated.

### REQ-MR-011 — Carry the 3a security notes N1/N2/N3 into the harness
Traces: canvas RISK-3b-013, EVN-3b (security carry), NFR-MR-001.
The run harness carries the 3a security notes: **N1** confine any `@path` read to the work dir (no
path traversal / arbitrary-file read); **N2** surface OSError on the live `runs.jsonl` write (no
silent swallow that hides a failed/partial emission); **N3** keep the flag/argument parser STRICT
(no inferred file locations, no lax positional inference).
- **Given** an `@path` outside the designated work dir, **When** the harness resolves it, **Then**
  it is refused (confined), not read;
- **And given** the live `runs.jsonl` write fails (OSError), **When** the harness writes,
  **Then** the error is surfaced (non-zero exit / explicit error), never silently swallowed;
- **And given** a malformed/ambiguous flag, **When** parsed, **Then** the strict parser rejects it
  rather than inferring a location.

---

## 4. Non-functional requirements (NFR-MR-*)

| ID | NFR | Acceptance |
|---|---|---|
| NFR-MR-001 | **No secret in output.** No API key appears in any emitted record, log line, report, or the disclosed prompt; a real key lives header-only inside the real transport. | `grep` over all 3b outputs (records/report/logs) finds no key material; `plumbline-redact` is clean on the report. |
| NFR-MR-002 | **Determinism of scoring.** The primary score is judge-free and re-runnable: identical numbers on re-run over the same captured flag-sets (numeric equality). | A test scores a fixed flag-set twice and asserts numeric equality of all three metric families. |
| NFR-MR-003 | **Cost-bound / fail-closed.** The live run refuses to start without a user-named budget cap; the aggregate budget is a MAX-CALLS ceiling (cap ÷ per-call cap) — there is NO aggregate-cost meter; cost is reported as an ESTIMATED upper bound with Arm-A actual usage where exposed; the live gate is OFF by default (0 calls). | REQ-MR-005 GWTs; a test asserts the gate is OFF by default and that a missing cap refuses the live run. |
| NFR-MR-004 | **Isolation.** ZERO live calls inside `run_all.sh`; eval inputs staged outside the tree; `git status` clean + `run_all.sh` green after every run; the deterministic primary is re-runnable offline. | `run_all.sh` green with the new test; `git status` clean; the new test makes 0 live calls. |
| NFR-MR-005 | **Reality Ledger at the TRUE class.** `docs/reality/council-measurement-run.evidence.jsonl` authored Phase 3 (Gate C) with one record per load-bearing REQ at its honest class: offline orchestration wiring = `integration-fake`; the LIVE pilot run = `real-boundary-smoke` for THAT run only; broader/definitive = RED(confidence). No class raised to clear a floor; FORBIDDEN_TOKENS (`fake-only`/`mock-only`/`placeholder`/`unverified`) avoided. | `plumbline-reality-check --min-evidence integration` passes against the ledger; the live-pilot record is `real-boundary-smoke`, no higher. |

---

## 5. Risks (RISK-MR-* → canvas RISK-3b-*)

| ID | Risk (links canvas) | Mitigation (REQ) |
|---|---|---|
| RISK-MR-001 | Underpowered n=2 read as a verdict (canvas RISK-3b-001). | REQ-MR-007: pre-registered MDE; "underpowered" is a DISTINCT published outcome; powered run is the follow-on. |
| RISK-MR-002 | Pilot budget unbounded/guessed; aggregate cost mis-claimed (no aggregate meter; preset path discards `usage`) (RISK-3b-002, RISK-3b-004). | REQ-MR-005 + NFR-MR-003: user-named cap at the pre-run gate; refuse-without-cap; aggregate = MAX-CALLS ceiling; cost = estimated upper bound + Arm-A actual where exposed; one preset (A) for the pilot cuts cost. |
| RISK-MR-003 | Pass/fail line written/moved after results (RISK-3b-003). | REQ-MR-007: frozen, timestamped pre-registration artifact; outcome judged against the frozen line. |
| RISK-MR-004 | Claude-contaminated Arm B (RISK-3b-005). | REQ-MR-004: `foreign_only_ok=true` asserted per scored Arm-B record; contaminated record rejected. |
| RISK-MR-005 | Free-tier/paid flakiness scored as signal, OR a legitimate OK-empty review wrongly excluded (RISK-3b-006). | REQ-MR-004: PAIRED-EXCLUSION on `code != OK` only (flakiness, never a miss); a `code == OK` empty review is SCORED (real potential miss); attrition disclosed; minimum-survivors floor. |
| RISK-MR-006 | Catch-only headline (RISK-3b-007). | REQ-MR-003 + REQ-MR-010: scorer emits both families by construction; report carries both + scope. |
| RISK-MR-007 | Re-run-until-favourable (RISK-3b-008). | REQ-MR-007 + REQ-MR-010: every scored run recorded; outcome is whatever the frozen line says; null/tradeoff/underpowered published as-is. |
| RISK-MR-008 | Eval pollutes the tree / spends CI credits (RISK-3b-009). | NFR-MR-004 + REQ-MR-008: inputs outside the tree; 0 live calls in `run_all.sh`; clean `git status`; green suite. |
| RISK-MR-009 | Distinct ids read as proven diversity (RISK-3b-011). | REQ-MR-010: report states outcome-delta-only; scorer stamps the NON_CLAIM string. |
| RISK-MR-010 | Over-claiming generality from n=2 (RISK-3b-012). | REQ-MR-010: primary is an outcome delta on the named corpus; generality stays RED(confidence). |
| RISK-MR-011 | @path / OSError / lax-parser regressions in the harness (RISK-3b-013). | REQ-MR-011 (N1/N2/N3). |
| RISK-MR-012 | Arm-A live path dead (3a `belegt` finding): a real-boundary smoke is impossible if the Arm-A transport stays unimplemented (wired-in-prod, one level down). | REQ-MR-005: the NEW `council_measurement_run.py` reaches Arm A's real boundary by calling `council_inference.run_inference(...)` DIRECTLY (NOT by editing the read-only `arm_a_review_runner.py` — resolving the REQ-MR-005 vs REQ-MR-009 contradiction); + a test asserting the gate is OFF by default and the live path reachable only when armed; the live pilot is the smoke. |

---

## 6. Traceability stub (TRC-MR-*)

canvas-link: docs/canvas/council-measurement-run.canvas.md (Status: user-confirmed, Ben 2026-06-20)
The full REQ-ID ↔ acceptance-test ↔ impl-task ↔ pass-evidence matrix is maintained by
context-keeper in `docs/traceability.md` (slice council-measurement-run). Stub:

| TRC-ID | REQ | Acceptance test (planned) | Impl task (planned) | Evidence class |
|---|---|---|---|---|
| TRC-MR-001 | REQ-MR-001 | `test_council_measurement_run.sh::offline_full_loop` | orchestrator per-task arm loop | integration-fake |
| TRC-MR-002 | REQ-MR-002 | `::symmetric_protocol_both_arms` (well-formed + non-protocol, both arms via the SAME `parse_flag_set`) | symmetric protocol appended to `--subject`; shared parser | integration-fake |
| TRC-MR-003 | REQ-MR-003 | `::scoring_deterministic` + `::corpus_freeze_hash` | scorer invocation (read-only) | integration-fake |
| TRC-MR-004 | REQ-MR-004 | `::foreign_only_rejects_claude` + `::paired_exclusion` | foreign-only + attrition gate | integration-fake |
| TRC-MR-005 | REQ-MR-005 | `::live_gate_off_by_default` + `::refuse_without_budget` + `::arm_a_reachable_when_armed` | Arm-A real transport via direct `run_inference` in the new script (no edit to the read-only runner) + MAX-CALLS ceiling | real-boundary-smoke (live); integration-fake (gate-off) |
| TRC-MR-006 | REQ-MR-006 | `::emit_routes_under_raw` (emit_run exit 0) | emit-blob → emit_run wiring | integration-fake |
| TRC-MR-007 | REQ-MR-007 | `::refuse_score_without_frozen_line` | pre-registration artifact + classifier | integration-fake |
| TRC-MR-008 | REQ-MR-008 | `::offline_zero_calls` + `run_all.sh` green | offline harness + isolation | integration-fake |
| TRC-MR-009 | REQ-MR-009 | `::substrate_git_diff_empty` | (verification only) | integration-fake |
| TRC-MR-010 | REQ-MR-010 | (report review at Gate C/D) | benchmark write-up | real-boundary-smoke (pilot) / RED (definitive) |
| TRC-MR-011 | REQ-MR-011 | `::path_confined` + `::oserror_surfaced` + `::strict_parser` | security carry N1/N2/N3 | integration-fake |

---

## 7. Definition of Ready / open items at PRD draft

- Canvas: **user-confirmed** (Ben, 2026-06-20). ✓
- All four product-critical OQs (OQ-3b-1..4) + OQ-DM-8: **RESOLVED** with the user; the
  `deepseek_review.py preset` contract is now `belegt`. ✓
- **Retained run-time BLOCKERs (by user decision, NOT unresolved canvas gaps):** OQ-3b-1
  (user-named budget cap) gates the LIVE run; OQ-3b-4 (frozen, timestamped pre-registered line)
  gates the SCORED run. Neither blocks PRD finalization, planning, or the OFFLINE build; both must
  be satisfied immediately before the live/scored run.
- Product Vision: docs/vision/council-measurement-run.vision.md (user-confirmed, Ben 2026-06-20). **Phase 0 complete — Canvas + PRD + Vision all user-confirmed.**
- Status note (carried IDENTICALLY in the PRD header): this PRD was FROZEN after a SINGLE
  spec-auditor remediation pass (Ben-approved, 2026-06-20) — measurement-integrity fixes applied
  (arm symmetry / symmetric flag protocol replacing the deleted prose-parse; Arm-A real transport via
  the new script calling `run_inference` directly, resolving the REQ-MR-005 vs REQ-MR-009 contradiction;
  estimated-budget / MAX-CALLS reframe; minimum-survivors floor + OK-empty vs non-OK distinction; n=2
  rubric; one-preset pilot). Status remains user-confirmed; no re-audit.

Handoff to product-owner (Vision gate): PRD path `docs/prd/council-measurement-run.prd.md`; REQ-IDs
REQ-MR-001..011; acceptance criteria as above; non-goals NGOAL-3b-001..012; retained run-time
BLOCKERs (budget, frozen line); customer = Plumbline maintainer (Ben) + the framework's empirical
integrity; success metric = an honest, refutable, pre-registered published outcome (catch AND
cry-wolf AND recall, with n/scope), NOT a council "win".
