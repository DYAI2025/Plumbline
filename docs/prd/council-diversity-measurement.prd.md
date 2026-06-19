# PRD: Council Diversity Measurement — Slice 3a: the measurement SUBSTRATE (new review-catch corpus + Arm-A runner + shared flag-set scorer)

Feature-Slug: council-diversity-measurement
Slice: 3a of 4 — the MEASUREMENT SUBSTRATE (3b = the deferred measurement RUN; Slice 4 = the GUI)
Status: user-confirmed (Ben 2026-06-19, re-confirmed after the BLOCKER re-scope; OQ-DM-7 = structured flag protocol + location-overlap matching for the primary, blind judge secondary-only).
Owner: requirements-analyst
Canvas (re-scoped, user-confirmed): docs/canvas/council-diversity-measurement.canvas.md (Status: user-confirmed, Ben re-confirmed 2026-06-19)
Product Vision: docs/vision/council-diversity-measurement.vision.md (Status: user-confirmed — reconciled and re-confirmed)
Traceability: docs/traceability.md (slice council-diversity-measurement; carries canvas-link)
Prefix: REQ-DM-3a-* (3a substrate) and REQ-DM-3b-* (deferred measurement RUN)

> This PRD is bound to the re-scoped Product Canvas above and may not be read apart from it.
> Every REQ traces to a canvas value statement / RISK-DM-* / OQ-DM-* resolution.
>
> **WHY THIS RE-SCOPE (the spec-auditor remediation, 2026-06-19).** The previous Slice-3 PRD
> assumed the measurement could (a) reuse `pipe-providedfake-v1` as the catch+cry-wolf+recall
> corpus, (b) score both arms with the existing test-suite RED/GREEN scorers, and (c) get the
> Claude-only arm "for free". All three were disproved against the real artifacts:
> - **BLOCKER-1:** `pipe-providedfake-v1` is a SINGLE task (`P1-login-audit`) + one dark-zone
>   mutator with NO clean control, NO recall control, NO cry-wolf oracle. The triple belongs to
>   `pipe-core-v1` (`manifest.json`). The claim was read off the wrong file.
> - **BLOCKER-2:** a single-task corpus has no across-task variance → 3b cannot pin a noise
>   threshold or MDE (OQ-DM-5 needs both).
> - **BLOCKER-3:** the existing scorers score a pytest suite (RED/GREEN), but a review (council OR
>   Claude-only) produces FREE-TEXT findings, not a suite — no scorer fits; and
>   `deepseek_review.py` has only `run`/`preset` (the council = Arm B), so there is no Claude-only
>   Arm-A runner, and the instrument is read-only (NGOAL-DM-001).
> - **BLOCKER-4:** the Vision self-contradicted (header `user-confirmed`, body `draft`) — first
>   reconciled to a single consistent status, then re-confirmed by the user (Ben, 2026-06-19);
>   `user-confirmed` throughout.
>
> The remediation: **SPLIT.** Slice 3a (this PRD) builds the SUBSTRATE — a NEW review-catch
> corpus, an Arm-A runner, and a single shared flag-set scorer — all OFFLINE-verifiable. Slice 3b
> (deferred, backlog BL-DM-002) RUNS the measurement.
>
> **THE LOAD-BEARING HONESTY INVARIANT (binding).** The anti-Goodhart guarantees are STRUCTURAL in
> 3a: the corpus's clean controls force BOTH metrics; defects seeded before/independent of review
> make it ungameable; the deterministic matcher makes the primary catch judge-free. RED is never
> downgraded; missing tooling is marked MISSING. **Slice 3a produces NO measurement number** — that
> is 3b.
>
> **MEASUREMENT IS FOREIGN-ONLY (OQ-DM-4, a 3b execution invariant).** Arm B (the council) runs
> ONLY non-Claude foreign models. 3a's scorer schema carries the foreign-only assertion field; 3b
> enforces it at run time.

---

## 0. Provenance & verified premises (`belegt`)

All foreign-file premises were opened and read on 2026-06-19 BEFORE becoming PRD premises (gap rule /
external-claim discipline). Classification per row.

| Premise | Source (read 2026-06-19) | Class |
|---|---|---|
| `metrics/corpus/pipe-providedfake-v1/` contains ONLY `mutate_providedfake.py` (a single dark-zone mutator that neuters one real `FileStore.append` boundary) + one task `tasks/P1-login-audit/`. It has NO clean control, NO recall control, NO cry-wolf oracle, NO `score.py`, NO `manifest.json`. | `metrics/corpus/pipe-providedfake-v1/` (listed); `mutate_providedfake.py` (read) | belegt — **BLOCKER-1 confirmed: the canvas's catch+cry-wolf+recall claim was misattributed.** |
| The catch+cry-wolf+recall TRIPLE belongs to `pipe-core-v1`: `manifest.json` → primary `escaped_defect_rate`, secondary `pipeline_false_positive_rate` (CTRL tasks) + `reviewer_non_wiring_recall` (RDIFF tasks); `score.py` aggregates gap/control/rdiff. | `metrics/corpus/pipe-core-v1/manifest.json`, `score.py` (read) | belegt |
| BOTH existing scorers score TEST-SUITE RED/GREEN ("did the arm's own pytest suite catch the planted mutation"), NOT a reviewer flag-set. A free-text review produces neither a suite nor a RED/GREEN — so neither scorer fits the foreign-vs-Claude REVIEW comparison. | `pipe-core-v1/score.py`; `pipe-providedfake-v1/mutate_providedfake.py` (read) | belegt — **BLOCKER-3 confirmed: a new flag-set scorer is required.** |
| `deepseek_review.py` exposes ONLY two subcommands: `run` (ONE body OR ONE character) and `preset` (resolve + run a named preset, default A = the council = Arm B). There is NO Claude-only review subcommand. The real transport is armed only when `--live` AND `COUNCIL_INFERENCE_LIVE=1`; offline via `--inject-response`/`--inject-catalog`/`--inject-call-counter` (0 credits). | `config/claude/lib/deepseek_review.py` (`_parser`, lines 339–361; `_make_transport`) | belegt — **BLOCKER-3 confirmed: Arm-A is a SEPARATE runner; instrument read-only.** |
| `council_presets.resolve_preset` returns per-role models + a diversity gate; an unresolvable role classifies `model-unresolvable`/`catalog-unreachable`/`unknown-character-slug` and **NEVER substitutes a Claude model** (no anthropic/claude literal in the resolver). | `config/claude/lib/council_presets.py` (lines 17–18, 58–93, 234–293) | belegt |
| `emit_run.py` builds a run record whose TOP-LEVEL keys are exactly: `run_id`, `metrics_schema_version`, `corpus_id`, `mode`, `baseline`, `process_branch`, `config_fingerprint`, `metrics`, `raw`, `gate_outcomes`, `active_rules`, `human_overrides`. There is NO top-level `arm`/`model_scope`/`cost`/`catch_rate`. `process_health.py` reads each metric as `r["metrics"][<name>]`. Flags: `--metrics`/`--metrics-file`, `--raw`, `--corpus-id`, `--mode {core,full}`, `--gate-outcomes`, `--tokens-total`, `--reqs-accepted`, `--active-rules`, `--baseline`. | `config/claude/metrics/emit_run.py` (lines 306–331, 356–370); `process_health.py` (lines 53–124, 214) | belegt — **IMPORTANT-1 confirmed: arm/model_scope/cost/catch_rate/cry_wolf_rate/recall_control/n/task_count MUST live INSIDE `metrics`/`raw`, NOT top-level.** |
| The on-`main` per-role flag/position SHAPE that the scorer will consume (what `deepseek_review.py preset` returns per role) | `config/claude/lib/deepseek_review.py` | **ungeprüft** — the parser/transport are read, but the exact scorable per-role flag shape is NOT yet read end-to-end. MUST be opened + reclassified in Phase 3 before it becomes a scorer premise (EVN-DM-008). Drives OQ-DM-8. |

> Any `ungeprüft` premise MUST be opened and reclassified `belegt | ableitbar | nicht behaupten` in
> Phase 3 before it becomes a scorer/measurement premise (EVN-DM-008). It may NOT be downgraded to a
> "documented risk" and forwarded as a working premise.

---

## 1. Goal & non-goals (pointer)

Goal (Slice 3a): build the honest, anti-Goodhart MEASUREMENT SUBSTRATE that makes the 3b
foreign-vs-Claude review-catch measurement POSSIBLE and ungameable — a NEW frozen, council-independent
review-catch corpus (seeded defects + clean controls + recall control, with real variance), a
Claude-only Arm-A runner (separate entrypoint), and a single shared flag-set scorer both arms feed —
all OFFLINE-verifiable. 3a produces NO measurement number.

Non-goals: carried from canvas §7 (NGOAL-DM-001..012). Load-bearing for 3a:
- do NOT modify the instrument (`config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py`) or `concilium/**` — read-only; the Arm-A runner is a SEPARATE entrypoint; a genuine seam is OQ-DM-8, not pre-authorised (NGOAL-DM-001);
- do NOT build a parallel metrics harness — the scorer emits into the existing `emit_run.py` record shape (NGOAL-DM-002);
- do NOT tune the corpus to flatter the council; defects are seeded before/independent of review (NGOAL-DM-003);
- do NOT build a corpus without clean controls (NGOAL-DM-004);
- do NOT use `pipe-providedfake-v1` (or any existing corpus) as the catch+cry-wolf+recall PRIMARY (NGOAL-DM-012 / BLOCKER-1);
- do NOT RUN the measurement, spend pilot budget, or emit a catch/cry-wolf number — that is Slice 3b (NGOAL-DM-011);
- NO live call inside `run_all.sh` (NGOAL-DM-007); do NOT build the fallback cascade (NGOAL-DM-010 → backlog BL-DM-001).

---

## 2. Requirements — Slice 3a substrate (REQ-DM-3a-*)

Each REQ has Given/When/Then acceptance criteria. "The instrument" = the on-`main` read-only council
runner `config/claude/lib/deepseek_review.py` (+ `council_presets.py` etc.).

### REQ-DM-3a-001 — NEW frozen, council-independent review-catch corpus with real variance
A NEW corpus under `metrics/corpus/council-review-catch-v1/` (name finalizable by the planner;
update the canvas scope if changed). It is a set of code diffs, each either (a) carrying a KNOWN
seeded-defect oracle (the defect seeded BEFORE and independent of any review → ungameable) or (b) a
CLEAN CONTROL with NO seeded defect (the cry-wolf oracle), plus (c) at least one RECALL/no-narrowing
control. It is FROZEN + version-stamped (corpus id + content hash) and authored INDEPENDENTLY of the
council (NGOAL-DM-003). It has REAL VARIANCE: ≥2 distinct task outcomes (not a saturated single task)
so 3b can pin a noise threshold + MDE. (OQ-DM-1; BLOCKER-1/2; RISK-DM-002/005/006.)

- **Given** the new corpus directory,
  **When** it is authored,
  **Then** it contains ≥1 seeded-defect diff WITH its oracle, ≥1 clean-control diff (no seeded defect),
  AND ≥1 recall/no-narrowing control; a manifest records corpus id + content hash + a per-diff oracle
  index; and a corpus with NO clean control fails acceptance (NGOAL-DM-004).
- **Given** the seeded-defect diffs,
  **When** their provenance is recorded,
  **Then** the manifest documents that each defect was seeded BEFORE/independent of any review (not
  selected because a model caught it), and the corpus is NEVER re-selected/tuned per result (NGOAL-DM-003).
- **Given** the corpus,
  **When** its variance is assessed,
  **Then** it admits ≥2 distinct task outcomes (so an across-task noise threshold + MDE are computable
  in 3b); a single-task / saturated corpus is REJECTED (BLOCKER-2). "Underpowered → unmeasurable" is
  documented (for 3b) as a DISTINCT outcome from "refuted" — never laundered as a published null.

### REQ-DM-3a-002 — Arm-A (Claude-only) review runner as a SEPARATE entrypoint
A Claude-only review runner exists as a SEPARATE module/entrypoint (e.g.
`config/claude/metrics/arm_a_review_runner.py`), NOT an edit to the read-only instrument. It produces a
REVIEWER FLAG-SET over a given corpus diff, and runs OFFLINE via an injected/fake transport (0 credits).
(BLOCKER-3; NGOAL-DM-001.)

- **Given** the Arm-A runner and a corpus diff,
  **When** it is invoked offline with an injected response,
  **Then** it emits a structured reviewer flag-set (the same flag schema the scorer consumes — REQ-DM-3a-003)
  and makes ZERO network calls; the four instrument files + `concilium/**` are byte-unchanged (`git diff`
  empty over those paths).
- **Given** the runner,
  **When** its Claude tier/model-scope is recorded,
  **Then** the disclosed Arm-A model scope is present in the flag-set output (for 3b's "scope visible"
  requirement); an Arm-A flag-set with undisclosed scope is RED.

### REQ-DM-3a-003 — Single shared flag-set SCORER both arms feed
A single shared scorer (e.g. `config/claude/metrics/council_review_scorer.py`) consumes a REVIEWER
FLAG-SET (NOT test-suite RED/GREEN) from EITHER arm + the corpus oracle, and computes per arm: catch
(a review flags a real seeded defect), cry-wolf (a review flags where no defect was seeded — a clean
control), and recall-control (no-narrowing guard). Its output schema carries `n`, task count, model
scope, BOTH metric families together, the pinned-instrument-commit field, the foreign-only assertion
field, and an explicit non-claim field. (BLOCKER-3; OQ-DM-2; RISK-DM-001/008.)

- **Given** a flag-set from either arm + the corpus oracle,
  **When** the scorer runs,
  **Then** it emits catch-rate, cry-wolf-rate, AND recall-control TOGETHER, plus `n`, task count, and
  model scope; a scorer output missing the cry-wolf field is RED (the substrate forces both — RISK-DM-001).
- **Given** the SAME flag-set scored twice,
  **When** the deterministic primary matching rule (REQ-DM-3a-004) is applied,
  **Then** the two scorer runs yield IDENTICAL numbers (numeric equality, not substring — NFR-DM-3a-002).
- **Given** an Arm-B (council) flag-set whose model scope contains an `anthropic`/`claude-*` id,
  **When** the scorer validates foreign-only integrity,
  **Then** the scorer FLAGS it (the assertion field is false) so 3b can reject it — never silently scores
  it as a valid council result (RISK-DM-011; the enforcement RUN is 3b).

### REQ-DM-3a-004 — Deterministic flag→seeded-defect MATCHING RULE for the primary (OQ-DM-7)
The flag→seeded-defect matching rule is specified and DETERMINISTIC for the PRIMARY corpus: a flag
"matches" a seeded defect by a machine-checkable rule (a STRUCTURED flag protocol — defect
location/type tags — OR a blind deterministic matcher over free text). A blind JUDGE is allowed ONLY
for the SECONDARY real-diff set where determinism is impossible, with arm identity BLINDED. If a
deterministic rule cannot be achieved for the primary, that is an OPEN QUESTION raised to the user
(OQ-DM-7), never silently judged. (OQ-DM-2/7; RISK-DM-012; the genuinely-new 3a question.)

- **Given** the primary corpus + flag-sets,
  **When** catch and cry-wolf are scored,
  **Then** the matching is fully deterministic (no judge) and reproducible (NFR-DM-3a-002); the matching
  rule is documented (which protocol; how a match is decided).
- **Given** a secondary real-diff requiring a judge,
  **When** the judge scores a flag-set,
  **Then** arm identity is blinded (no "Claude"/"council"/house-term leak), the SAME scorer scores both
  arms, and the blinding procedure is recorded; a judge that can see arm identity is RED.
- **Given** OQ-DM-7 is unresolved by the user for the primary,
  **When** the substrate is built,
  **Then** the primary matching rule is a BLOCKER (not a downgrade) until the user decides; the planner
  must not pick a fuzzy rule and proceed.

### REQ-DM-3a-005 — Scorer run-record output matches the REAL `emit_run.py` schema (IMPORTANT-1)
The scorer's run-record output (which 3b will pass to `emit_run.py`) places `arm`, `model_scope`,
`cost`, `catch_rate`, `cry_wolf_rate`, `recall_control`, `n`, `task_count` INSIDE the `--metrics`
(numeric, SPC-tracked via `process_health.py`'s `metrics.<name>`) and/or `--raw` (free-form, e.g.
`model_scope`, `arm` label) blob — NOT as top-level record fields. (Verified against `emit_run.py`:
top-level keys are `run_id`/`corpus_id`/`mode`/`baseline`/`process_branch`/`config_fingerprint`/
`metrics`/`raw`/`gate_outcomes`/`active_rules`/`human_overrides`.) (NGOAL-DM-002; EVN-DM-005.)

- **Given** the scorer output handed to `emit_run.py`,
  **When** a run record is assembled (a 3a offline dry-run / fixture is sufficient — no live data),
  **Then** the numeric metrics (`catch_rate`, `cry_wolf_rate`, `recall_control`, `n`, `task_count`,
  `cost`) appear under `metrics`, the descriptive scope (`arm`, `model_scope`) appears under `metrics`/`raw`,
  NONE of them appear as top-level record keys, and `process_health.py` reads them via `metrics.<name>`
  without error; an output that puts `catch_rate`/`arm`/`model_scope` at the top level is RED.

### REQ-DM-3a-006 — Offline isolation: inputs staged outside the tree; git clean + run_all green
All 3a offline validation (corpus mutator/oracle, Arm-A runner, scorer) runs network-free; transient
eval inputs are staged OUTSIDE the repo (`/tmp/…`); builder/eval sub-agents are TEXT-ONLY or sandboxed;
after EVERY run `git status` is clean (the new corpus under `metrics/corpus/<new>/` is the only
INTENDED tracked addition) and `run_all.sh` is green; ZERO live council/network calls. (RISK-DM-007;
NGOAL-DM-007; bench-isolation learning.)

- **Given** any 3a validation run,
  **When** it executes,
  **Then** it makes ZERO network calls, no eval sub-agent writes outside the Allowed change scope, and
  immediately after, `git status --porcelain` shows only intended paths AND
  `bash config/claude/tests/run_all.sh` is green.
- **Given** `run_all.sh` / the offline suite,
  **When** it runs in CI or locally,
  **Then** it makes ZERO live council/network calls.

### REQ-DM-3a-007 — Foreign-instrument-contract claims verified against the real artifact before use
Any premise about what the instrument returns (per-role flag/position shape the scorer consumes), the
new corpus's oracle field shape, and the `emit_run.py` record schema, is read from the real file and
classified `belegt | ableitbar | ungeprüft | nicht behaupten` BEFORE it becomes a scorer premise. An
unverifiable contract stays an OPEN QUESTION/BLOCKER — never downgraded to a "documented risk" and
forwarded. (EVN-DM-008; OQ-DM-8; gap rule.)

- **Given** a scorer that consumes the instrument's per-role output or the corpus oracle,
  **When** that field's shape is used as a premise,
  **Then** the real file was opened, the field is classified `belegt`/`ableitbar`, and the classification
  is recorded; an `ungeprüft` field BLOCKS the scorer until verified (this resolves the §0 `ungeprüft`
  row and feeds OQ-DM-8).

### REQ-DM-3a-008 — Instrument-seam decision is a DISCLOSED OPEN QUESTION, never a silent edit (OQ-DM-8)
If the Phase-3 contract read (REQ-DM-3a-007) shows the on-`main` `deepseek_review.py preset` does NOT
already expose a council's per-role flag-set in a scorable shape, any seam in the read-only instrument
is RAISED to the user as OQ-DM-8 (a one-file, additive, capture-only seam) — never silently added.
Default: measure read-only and adapt the scorer to the existing output. (NGOAL-DM-001; RISK-DM-009.)

- **Given** the contract read reveals a missing scorable shape,
  **When** the build needs a seam,
  **Then** the seam is presented to the user as OQ-DM-8 with the exact one-file additive change, and the
  build does NOT proceed with an instrument edit until the user authorizes it; `git diff` over the
  instrument files stays empty otherwise.

### REQ-DM-3a-009 — The deliverable is the offline-validated substrate at its true evidence class
The deliverable is the NEW corpus + Arm-A runner + shared scorer + the matching-rule spec, each
OFFLINE-verified, with a short substrate README (under the corpus dir or `docs/benchmarks/`) that
states what the substrate IS (the instrument 3b will run) and is NOT (a measurement number). MISSING
tooling is marked MISSING (e.g. if the secondary real-diff set is not assembled in 3a, say so). RED is
never downgraded. (EVN-DM-001/002/003; NGOAL-DM-011.)

- **Given** the substrate,
  **When** it is documented,
  **Then** the README states the corpus design (seeded/clean/recall, variance), the Arm-A runner and
  scorer entrypoints, the matching rule, and explicitly that NO measurement is run in 3a (that is 3b /
  BL-DM-002); any gap (e.g. secondary set deferred) is marked MISSING, not silently dropped.

### REQ-DM-3a-010 — Reality Ledger authored Phase 3 at the honest (integration-fake) class
`docs/reality/council-diversity-measurement.evidence.jsonl` is authored in Phase 3 (Gate C) with one
record per load-bearing 3a REQ at its TRUE class. Because 3a crosses NO real boundary (everything is
offline / injected transport), the honest class is `integration-fake` — there is NO honest
`real-boundary-smoke` record in 3a (that class belongs to 3b's live run). The class is NEVER raised to
clear a floor. (EVN-DM-007; CLAUDE.md PRIL ledger rule.)

- **Given** the ledger,
  **When** it is authored,
  **Then** each load-bearing 3a REQ has a record at `integration-fake` (offline corpus/runner/scorer
  wiring exercised network-free), the text avoids the FORBIDDEN_TOKENS
  (`fake-only`/`mock-only`/`placeholder`/`unverified`), and `plumbline-reality-check` passes WITHOUT
  raising any record's class. (Note: the default `integration` floor is satisfied by `integration-fake`;
  do NOT invent a `real-boundary-smoke` record to clear a higher floor — 3a has no real boundary.)

---

## 2b. Deferred to Slice 3b (REQ-DM-3b-*, NOT built in 3a — recorded for traceability)

These are the measurement-RUN requirements, deferred to Slice 3b (backlog BL-DM-002). Recorded here
so the split is explicit and the carried OQ resolutions are not lost. They are NOT in 3a's scope.

- **REQ-DM-3b-001 — Experiment RUN:** Arm A (Claude-only) vs Arm B (presets A/B/C, FOREIGN) on the
  SAME frozen subjects (the 3a corpus) with the SAME scorer; instrument snapshot PINNED across arms.
- **REQ-DM-3b-002 — Foreign-only enforcement at run time:** assert NO `anthropic`/`claude-*` id in any
  Arm-B run (reject if present); a non-answering foreign role recorded UNAVAILABLE, excluded/retried,
  attrition DISCLOSED, never Claude-substituted, never scored a miss (OQ-DM-4; RISK-DM-004/011).
- **REQ-DM-3b-003 — Pre-registered pass/fail line, frozen BEFORE the runs:** demonstrated / refuted /
  tradeoff / **underpowered** (BLOCKER-2: underpowered is distinct from refuted); noise threshold pinned
  from the 3a corpus's run variance (OQ-DM-5; RISK-DM-006).
- **REQ-DM-3b-004 — Null/negative/tradeoff is a valid PUBLISHED outcome;** never re-run-until-favourable
  (OQ-DM-6; NGOAL-DM-006).
- **REQ-DM-3b-005 — PAID pilot first under a bounded budget (OPEN-DM-A, user-named before the live run);**
  per-call cap reused; actual cost recorded (OQ-DM-4; RISK-DM-005).
- **REQ-DM-3b-006 — PAIRED-EXCLUSION attrition rule (IMPORTANT-2):** drop a subject from BOTH arms if any
  Arm-B role is unavailable; report attrition BY TASK DIFFICULTY — bounds survivorship bias, not just
  disclosure.
- **REQ-DM-3b-007 — Emit the run via `emit_run.py` into `runs.jsonl`** (metrics inside the blob per
  REQ-DM-3a-005), analyze via `process_health.py`, publish the honest write-up headlining BOTH metrics
  with scope + non-claims (RISK-DM-001/003; NGOAL-DM-005).

---

## 3. Data model (substrate artifacts + the run-record contract — corrected per IMPORTANT-1)

**The NEW corpus (ART-3a-1)** — `metrics/corpus/council-review-catch-v1/`:
- `manifest.json`: `corpus_id`, `version`, content `hash`, per-diff oracle index, provenance note
  (defects seeded before/independent of review), variance note (≥2 distinct task outcomes).
- seeded-defect diffs + their oracles (the defect location/type the matcher checks).
- clean-control diffs (no seeded defect → cry-wolf oracle).
- ≥1 recall/no-narrowing control.

**The reviewer FLAG-SET (the scorer's input contract, ART-3a-2 output / ART-3a-3 input)** — per arm,
per diff:
- `arm` (label, e.g. `claude-only`, `council-A`), `model_scope` (Arm-A Claude tier; Arm-B per-role
  resolved foreign model ids + per-role availability), and a list of flags, each with the
  machine-checkable fields the matching rule (REQ-DM-3a-004) needs (e.g. defect location/type tag).

**The scorer run-record output (ART-3a-3 → `emit_run.py`)** — CORRECTED to the REAL schema. The
record's TOP-LEVEL keys are fixed by `emit_run.py`: `run_id`, `metrics_schema_version`, `corpus_id`,
`mode`, `baseline`, `process_branch`, `config_fingerprint`, `metrics`, `raw`, `gate_outcomes`,
`active_rules`, `human_overrides`. Therefore:
- **INSIDE `metrics` (numeric, SPC-tracked by `process_health.py` via `metrics.<name>`):**
  `catch_rate`, `cry_wolf_rate`, `recall_control`, `n`, `task_count`, `cost` (tokens/credits — 3b).
- **INSIDE `raw` (free-form diagnostic):** `arm` (label), `model_scope` (Arm-A tier; Arm-B per-role
  ids + availability classification answered/402/429/timeout/`model-unresolvable`), the
  foreign-only-assertion result, the pinned-instrument-commit, and the explicit non-claim string.
- `corpus_id` (top-level): the frozen new corpus id + version.
- `config_fingerprint` (top-level, populated by `emit_run.py`): pins the install snapshot; 3b additionally
  records the measured-instrument commit inside `raw` (per RISK-DM-010).
- `gate_outcomes` (top-level): in 3b, the pre-registered pass/fail evaluation (demonstrated/refuted/
  tradeoff/underpowered).

> This is the correction of the previous PRD's §3, which listed `arm`/`model_scope`/`cost`/`catch_rate`/
> `cry_wolf_rate`/`recall_control`/`n`/`task_count` as bare TOP-LEVEL record fields. `emit_run.py` does
> not accept those as top-level keys and `process_health.py` reads metrics ONLY at `metrics.<name>`, so
> they must live inside `metrics`/`raw`. (IMPORTANT-1, verified against the real files 2026-06-19.)

The secondary real-defect-diff set (if assembled in 3a; otherwise marked MISSING) is recorded as a
SEPARATE record/section, never merged into the primary metrics.

---

## 4. NFRs (Slice 3a)

| ID | NFR | Acceptance |
|---|---|---|
| NFR-DM-3a-001 | **No secret in output.** No API key / credential appears in any corpus file, runner/scorer output, or log. | `plumbline-redact` / grep over outputs finds no secret; offline suite has no live key. |
| NFR-DM-3a-002 | **Determinism of the primary scorer.** The deterministic flag→seeded-defect matching reproduces identical numbers on a re-run over the same captured flag-sets + frozen corpus. | Two scorer runs over the same captured flag-sets match exactly (numeric equality, not substring). |
| NFR-DM-3a-003 | **No instrument mutation.** The four instrument files + `concilium/**` are byte-unchanged by 3a (unless a user-approved OQ-DM-8 seam exists). | `git diff` over those paths is empty (or limited to a user-approved capture-only seam). |
| NFR-DM-3a-004 | **Isolation / no live call.** 3a validation + `run_all.sh` make ZERO live council/network calls. | CI green with no network; `git status` clean after every run. |
| NFR-DM-3a-005 | **Corpus frozen + reproducible.** The corpus manifest carries a content hash; re-deriving the hash matches. | Hash recomputation matches the manifest. |

---

## 5. Risks (link canvas — Goodhart/honesty risks dominate; 3a builds the structural mitigations)

Carried from canvas §8 (RISK-DM-001..013). For 3a the dominant, BINDING risks:
- **RISK-DM-002** Goodharted measurement → REQ-DM-3a-001 (defects seeded before/independent of review; frozen).
- **RISK-DM-005 / BLOCKER-2** underpowered / no variance → REQ-DM-3a-001 (≥2 distinct task outcomes; underpowered ≠ refuted).
- **RISK-DM-006** confirm-only design → REQ-DM-3a-001 (clean controls + recall control mandatory).
- **RISK-DM-008** scorer asymmetry → REQ-DM-3a-003/004 (single shared scorer; deterministic primary; blind judge only on secondary).
- **RISK-DM-012 (new)** non-deterministic / gameable matching rule → REQ-DM-3a-004 / OQ-DM-7 (primary must be deterministic or it's a BLOCKER).
- **RISK-DM-013 (new)** re-importing the wrong-corpus error → NGOAL-DM-012 (new corpus is PRIMARY; old attribution forbidden).
- **RISK-DM-007** eval pollutes the tree → REQ-DM-3a-006.
- **RISK-DM-009** instrument-seam scope creep → REQ-DM-3a-008 / OQ-DM-8.
- **RISK-DM-001 (3b)** catch-only headline → structurally pre-empted by the substrate (clean controls; scorer emits both families) — REQ-DM-3a-003.

---

## 6. Open items (for the user / spec-auditor — NOT guessed)

- **OQ-DM-7 (the genuinely-new 3a product-critical decision):** the flag→seeded-defect MATCHING RULE for
  the primary corpus. The user must choose a deterministic protocol (structured flag protocol OR blind
  deterministic matcher) for the primary, and decide whether a blind judge is acceptable for the
  SECONDARY real-diff subset only. If no deterministic rule is achievable for the primary, this is a
  BLOCKER, not a downgrade. (REQ-DM-3a-004; RISK-DM-012.)
- **OQ-DM-8 (instrument-seam, disclosed):** whether a one-file, additive, capture-only seam in the
  read-only instrument is needed to expose a council's per-role flag-set in a scorable shape. Surfaced
  now; settled after the Phase-3 contract read (REQ-DM-3a-007). Default: measure read-only and adapt the
  scorer. Never a silent edit (NGOAL-DM-001).
- **OPEN-DM-A (moved to Slice 3b):** the exact PILOT TOKEN BUDGET. A paid pilot is approved in principle;
  the bounded number is named by the user immediately before the live pilot. This is NOT a 3a item —
  3a runs nothing live.

---

## 7. Traceability stub (TRC-DM-3a-*) — canvas-linked

canvas-link: docs/canvas/council-diversity-measurement.canvas.md (Status: user-confirmed, Ben re-confirmed 2026-06-19)

| TRC-ID | REQ-ID | canvas-value-claim / success-signal | canvas-risk-status | acceptance-test (Phase 0.5+) | impl-task (planner) | pass-evidence (Phase 3) |
|---|---|---|---|---|---|---|
| TRC-DM-3a-001 | REQ-DM-3a-001 | new council-independent corpus; seeded+clean+recall; real variance | aligned (BLOCKER-1/2; RISK-DM-002/005/006) | corpus has clean control + ≥2 distinct outcomes; manifest hash + provenance | TBD | TBD |
| TRC-DM-3a-002 | REQ-DM-3a-002 | Arm-A runner as separate entrypoint; offline | aligned (BLOCKER-3) | runner emits flag-set offline; instrument byte-unchanged | TBD | TBD |
| TRC-DM-3a-003 | REQ-DM-3a-003 | single shared flag-set scorer; both metrics together | aligned (RISK-DM-001/008/011) | scorer emits catch+cry-wolf+recall; missing cry-wolf = RED | TBD | TBD |
| TRC-DM-3a-004 | REQ-DM-3a-004 | deterministic primary matching rule; blind judge secondary only | aligned (RISK-DM-012; OQ-DM-7) | primary matching deterministic + reproducible; judge blinded | TBD | TBD |
| TRC-DM-3a-005 | REQ-DM-3a-005 | run-record matches real emit_run schema | aligned (IMPORTANT-1) | metrics inside metrics/raw blob, not top-level; process_health reads them | TBD | TBD |
| TRC-DM-3a-006 | REQ-DM-3a-006 | offline isolation; git clean + run_all green | aligned (RISK-DM-007) | zero live calls; clean tree after run | TBD | TBD |
| TRC-DM-3a-007 | REQ-DM-3a-007 | foreign-contract premises verified before use | aligned (EVN-DM-008) | per-role shape classified belegt/ableitbar before scorer uses it | TBD | TBD |
| TRC-DM-3a-008 | REQ-DM-3a-008 | instrument seam = disclosed OQ, never silent | aligned (RISK-DM-009; OQ-DM-8) | seam raised to user; instrument diff empty otherwise | TBD | TBD |
| TRC-DM-3a-009 | REQ-DM-3a-009 | substrate documented; no measurement in 3a | aligned (NGOAL-DM-011) | README states IS/IS-NOT; gaps marked MISSING | TBD | TBD |
| TRC-DM-3a-010 | REQ-DM-3a-010 | Reality Ledger at honest (integration-fake) class | aligned | ledger at integration-fake; no invented real-boundary record; reality-check passes | TBD | TBD |

> Full True-Line fields (canvas-problem, canvas-target-user, vision-link, value-check-id,
> true-line-status) are populated in `docs/traceability.md` by context-keeper after the Vision is
> re-confirmed. canvas-risk-status above is the intake value.

---

## 8. Definition of Ready (Phase 0 gate)

- [x] Re-scoped Product Canvas filled, saved, linked, and **user-RE-confirmed** (Ben, 2026-06-19, "Bestätigt — 3a bauen").
- [x] OQ-DM-7 decided = (a) structured flag protocol + deterministic location-overlap for the primary; blind judge secondary-only (Ben 2026-06-19).
- [x] OQ-DM-8 (instrument seam) surfaced as a DISCLOSED open question (settled after the Phase-3 contract read; default read-only).
- [x] OPEN-DM-A (pilot budget) moved to Slice 3b (3a runs nothing live).
- [x] REQ-DM-3a-001..010 are atomic, testable, contradiction-free; each traced to canvas + risk; the deferred REQ-DM-3b-* recorded.
- [x] §3 data model corrected to the REAL `emit_run.py` schema (IMPORTANT-1).
- [x] Allowed change scope is machine-parseable; re-run `plumbline-scope-check` after the planner finalizes module/corpus names.
- [x] spec-auditor (Phase 0.5) re-audit of the re-scoped intake (4 BLOCKERs raised and remediated).
- [x] Product Vision reconciled and **user-re-confirmed** (Phase 0 complete — the Canvas, this PRD, AND the Vision were all re-confirmed together by Ben, 2026-06-19).
