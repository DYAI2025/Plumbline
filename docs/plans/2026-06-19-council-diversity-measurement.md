# Implementation Plan — Council Diversity Measurement, Slice 3a (the measurement SUBSTRATE)

Date: 2026-06-19
Feature-Slug: council-diversity-measurement
Slice: 3a of 4 — the MEASUREMENT SUBSTRATE (3b = deferred measurement RUN; Slice 4 = GUI)
Branch: agileteam/council-diversity-measurement
Author: planner (Phase 1)
Source intake (binding): `docs/prd/council-diversity-measurement.prd.md` (REQ-DM-3a-001..010),
`docs/canvas/council-diversity-measurement.canvas.md` (Status `draft`, re-confirmation pending).

> This plan PLANS only. It writes no production code, makes no live call, and is NOT committed.
> The RED contract is being authored IN PARALLEL by the tester; **those tests are the contract** —
> where this plan and the committed tests disagree, the tests win and this plan is amended.
> 3a produces NO measurement number (NGOAL-DM-011). The instrument
> (`config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py`,
> `concilium/**`) is READ-ONLY (NGOAL-DM-001).

---

## 0. What 3a builds (three artifacts) and what it does NOT

Builds, all OFFLINE-verifiable at 0 credits:
1. **ART-3a-1** — a NEW frozen, council-independent review-catch corpus
   `metrics/corpus/council-review-catch-v1/` (seeded-defect diffs + clean controls + recall control;
   ≥2 distinct task outcomes; manifest with content hash + provenance).
2. **ART-3a-2** — `config/claude/metrics/arm_a_review_runner.py`, a SEPARATE Claude-only review runner
   that emits a structured reviewer flag-set over a corpus diff, offline via an injected transport.
3. **ART-3a-3** — `config/claude/metrics/council_review_scorer.py`, a deterministic
   location-overlap scorer that turns a flag-set + oracle into catch / cry-wolf / recall, and emits an
   `emit_run.py`-shaped metrics blob.
Plus a substrate README and the Phase-3 reality ledger.

Does NOT build (deferred to 3b / out of scope): any Arm-A-vs-Arm-B RUN; the paid pilot; the
pre-registered pass/fail eval; the `runs.jsonl` emission of real data; `process_health.py` analysis;
the honest write-up; the foreign-only RUN-TIME enforcement; the fallback cascade (BL-DM-001); the
secondary real-diff judge harness beyond a documented MISSING stub; ANY edit to the instrument.

---

## 1. Verified reuse points (read 2026-06-19 — `belegt` unless noted)

| Reuse target | What it gives us | Constraint it imposes on the plan |
|---|---|---|
| `metrics/corpus/pipe-core-v1/{manifest.json,oracles/*.md,score.py,review-diffs/*.md,README.md}` | The corpus SHAPE to mirror: a `manifest.json` task index + per-task `oracles/<id>.md` + diff/scaffold dirs + a standalone `score.py` + `README.md`. RDIFF/CTRL show the clean-control + recall-control idiom. | ART-3a-1 mirrors this layout. Oracles are markdown for humans, but the matcher needs a MACHINE-readable oracle (see §4) — so the new corpus adds a JSON oracle field the matcher consumes, with the markdown as the human-readable companion. |
| `config/claude/metrics/emit_run.py` (read end-to-end) | The run-record contract. Top-level keys are FIXED: `run_id`, `metrics_schema_version`, `corpus_id`, `mode`, `baseline`, `process_branch`, `config_fingerprint`, `metrics`, `raw`, `gate_outcomes`, `active_rules`, `human_overrides`. `--metrics` is allowlist-validated; `--raw` is free-form. | The scorer's blob must split numeric→`metrics`, descriptive→`raw`. **Hard gate, see §1a.** |
| `config/claude/metrics/process_health.py` `DIRECTIONS` (read) | The CLOSED metric allowlist `emit_run.py` enforces: `first_pass, acceptance_first_try, mutation, coverage, dre, escaped_defect_rate, regression, unverified_claims, cycle_time, lead_time, dev_review_loops, human_override_rate, escalation_rate, cost_per_req, challenge_gate_tokens, root_cause_trigger_rate`. | `catch_rate`/`cry_wolf_rate`/`recall_control`/`n`/`task_count` are **NOT** in `DIRECTIONS` → `emit_run.py` REJECTS them as top-level `--metrics` keys. The scorer CANNOT silently pass them under `--metrics`. See §1a. |
| `config/claude/lib/deepseek_review.py` `_make_transport` + `_run_one` + `council_inference.run_inference` injected seam (read) | The injected-transport PATTERN: real transport armed only on `--live AND COUNCIL_INFERENCE_LIVE=1`; offline via `--inject-response`/`--inject-error`/`--inject-call-counter`; `on_transport_call` proves 0/1 calls; the runner computes its OWN `estimate_input_tokens` (never hand-fed). | ART-3a-2 REUSES this pattern by IMPORTING `council_inference.run_inference` (an import is not an edit) and replicating the live-gate idiom in its OWN `_make_transport`. It does NOT call `deepseek_review.preset`/`run` (that is the council = Arm B) and does NOT use `council_presets` (Arm A is Claude-only). |
| `config/claude/lib/council_inference.run_inference(env, *, model, messages, max_tokens, input_estimate, dry_run, build_only, inject_response, inject_error, inject_retry_after, transport=None, on_transport_call=None)` (signature read) | A stable, reusable, fail-closed inference entrypoint usable with ANY `model` string, including a Claude tier for Arm A. | ART-3a-2 passes a Claude model id explicitly; this is legitimate (Arm A IS Claude-only). No foreign resolver, no `council_presets`. |
| `docs/reality/openrouter-inference.evidence.jsonl` (read) | The reality-ledger record shape: one JSON object per line with `feature`, `requirement_id`, `evidence_class`, `evidence_ref`, `verified_by`, `note`. | REQ-DM-3a-010 ledger mirrors this exactly, all at `integration-fake` (§7). |
| `config/claude/tests/run_all.sh` (read) | The CI suite. New test module must be a standalone bash script `config/claude/tests/test_council_review_substrate.sh` registered as a new `stage` line; py_compile stage must list the two new `.py` modules. | The frontmatter validator globs `**/*.md` — see §8 tripwires for the corpus markdown + README. |

### 1a. The CLOSED-allowlist constraint (a real conflict with REQ-DM-3a-005 as literally worded — RESOLVE in build)

REQ-DM-3a-005 says `catch_rate`/`cry_wolf_rate`/`recall_control`/`n`/`task_count`/`cost` go "INSIDE the
`--metrics` … and/or `--raw` blob". But `emit_run.validate_metrics` fails closed on ANY key not in
`process_health.DIRECTIONS`, and NONE of those names are in it. The honest resolution (no instrument
edit, no laundering):

- **The scorer emits a single JSON object (its own artifact), NOT an `emit_run.py` invocation.** The
  scorer's job in 3a is to PRODUCE the blob; 3b decides how to feed `emit_run.py`. The 3a deliverable is
  a `scorer_output` JSON with two named sub-objects: `metrics` (the catch/cry-wolf/recall numbers) and
  `raw` (arm, model_scope, foreign-only assertion, pinned-instrument-commit, non-claim).
- **For the `emit_run.py` round-trip proof (REQ-DM-3a-005 acceptance):** the scorer's blob maps its
  catch number onto the EXISTING allowlisted `escaped_defect_rate` (`-1`, "lower better"; catch is the
  complement — `escaped = 1 - catch`, the same semantics `pipe-core-v1` already uses) so a real
  `emit_run.py --metrics` accepts it, and puts the cry-wolf/recall/n/task_count/arm/model_scope under
  `--raw` (free-form, un-allowlisted). The dry-run proof asserts `emit_run.py --dry-run` exits 0,
  `process_health.py` reads `metrics.escaped_defect_rate` without error, and `arm`/`model_scope`/
  `cry_wolf_rate` appear under `raw`, never top-level.
- **DECISION FLAGGED FOR THE TESTER/spec re-audit:** whether 3b also wants `cry_wolf_rate` as a
  first-class SPC-tracked metric (which would require an additive `DIRECTIONS` entry in
  `process_health.py` — that file IS in the Allowed change scope, NOT the read-only instrument). If the
  committed tests demand `cry_wolf_rate` under `metrics`, the build adds it to `DIRECTIONS` (direction
  `-1`) as a one-line additive change to `process_health.py` and `escaped_defect_rate` stays the catch
  carrier. **The tests decide; this plan defaults to the no-`DIRECTIONS`-change path (cry-wolf under
  `raw`)** to keep the surface minimal. Either way: never put a non-allowlisted key under `--metrics`.

---

## 2. Module / function decomposition

### ART-3a-1 — corpus `metrics/corpus/council-review-catch-v1/`
```
manifest.json                  corpus_id, version, content hash, task index, provenance, variance note
oracle.json                    machine-readable oracle: per-task list of seeded defects (the matcher input)
oracles/<task-id>.md           human-readable companion per task (mirrors pipe-core-v1 idiom)
diffs/<task-id>.md             the code diff under review (seeded-defect tasks AND clean controls)
README.md                      what the corpus IS / IS-NOT; how defects were seeded (independence proof)
freeze.py (or hash in manifest) recompute-and-compare the content hash (NFR-DM-3a-005)
```
- No Python logic is REQUIRED in the corpus beyond an optional `freeze.py` hash helper (keep the corpus
  declarative; the matcher lives in the scorer). `score.py` does NOT live in the corpus dir for 3a —
  the shared scorer is `council_review_scorer.py` (one scorer both arms feed, REQ-DM-3a-003). A thin
  `metrics/corpus/council-review-catch-v1/README.md` cross-links to it.

### ART-3a-2 — `config/claude/metrics/arm_a_review_runner.py`
- `load_diff(corpus_dir, task_id) -> str` — read `diffs/<task-id>.md`.
- `build_review_prompt(diff_text, protocol_spec) -> list[message]` — build the STRUCTURED flag-protocol
  prompt (system = the flag protocol instructions from §3; user = the diff). The runner computes its OWN
  `estimate_input_tokens(messages)` (never hand-fed — Slice-1 RISK-DS-005).
- `parse_flag_set(model_output) -> dict` — parse the model's structured output into the flag-set schema
  (§3). Tolerant of fenced JSON; classifies `flag-protocol-malformed` rather than fabricating flags.
- `_make_transport(args, env) -> Callable|None` — REPLICATES the deepseek live-gate idiom: real
  transport only on `--live AND COUNCIL_INFERENCE_LIVE=1`; else `None` (0 calls). Imports
  `council_inference._real_transport` lazily, same as the instrument.
- `run_arm_a(corpus_dir, task_id, *, model, env, transport, inject_response, inject_call_counter) ->
  flag_set` — wires diff → prompt → `run_inference` → `parse_flag_set` → flag-set with `arm`/`model_scope`.
- `main(argv)` CLI: `--corpus-dir --task-id --model --subject --json --dry-run --live
  --inject-response --inject-error --inject-call-counter`. Offline default makes ZERO network calls.
- **Model-scope disclosure (REQ-DM-3a-002):** the emitted flag-set ALWAYS carries `model_scope`
  (the Claude tier); a flag-set with empty/absent scope is the runner's own RED classification.

### ART-3a-3 — `config/claude/metrics/council_review_scorer.py`
- `load_oracle(corpus_dir) -> dict` — read `oracle.json` (the machine oracle).
- `overlaps(flag_loc, defect_loc) -> bool` — the deterministic location-overlap predicate (§4).
- `match_flags(flag_set, task_oracle) -> {matched_defects, unmatched_flags}` — apply the overlap rule
  + the type/tag check; deterministic, no judge.
- `score_task(flag_set, task_oracle) -> {caught, missed, cry_wolf_flags, recall_ok}`.
- `score_corpus(flag_sets, oracle) -> scorer_output` — aggregate per arm into catch / cry-wolf / recall
  + `n` + `task_count` + `model_scope` + foreign-only assertion + pinned-instrument-commit + non-claim.
- `foreign_only_ok(model_scope) -> bool` — returns False if any scope id matches `anthropic`/`claude-*`
  (REQ-DM-3a-003 / RISK-DM-011). For Arm A (Claude-only) this field is reported but NOT asserted-true;
  it is the Arm-B gate (3a builds the field, 3b enforces it).
- `to_emit_run_blob(scorer_output) -> {metrics, raw}` — the §1a mapping (catch → `escaped_defect_rate`
  complement under `metrics`; everything else under `raw`).
- `main(argv)` CLI: `--corpus-dir --flag-set <file ...> --json [--emit-run-blob]`. Pure-deterministic;
  no network, no transport.

---

## 3. The structured flag protocol + flag-set schema (OQ-DM-7 resolution = (a))

OQ-DM-7 is RESOLVED (Ben 2026-06-19) = **structured flag protocol + deterministic location-overlap**
for the primary; blind judge SECONDARY-only. So the primary is judge-free by construction.

The reviewer (either arm) is instructed to emit, per finding, a machine-parseable flag:
```json
{ "file": "<path>", "line_start": <int>, "line_end": <int>, "type": "<defect-type-tag>",
  "severity": "<blocking|nonblocking>", "summary": "<free text, NOT matched on>" }
```
- `type` is drawn from a small CLOSED vocabulary the corpus oracle also uses (e.g.
  `missing-error-handling`, `ordering`, `insecure-randomness`, `missing-ttl`, `secret-leak`,
  `injection`, `broken-access-control`, `unbounded-resource`, `no-audit-log`). The vocabulary lives in
  the corpus `manifest.json` so corpus and matcher share ONE source of truth.
- The `flag_set` artifact (ART-3a-2 output / ART-3a-3 input), per arm per corpus:
```json
{ "arm": "claude-only" | "council-A",
  "model_scope": ["<model id(s)>"],
  "instrument_commit": "<sha or 'n/a-for-arm-a'>",
  "tasks": { "<task-id>": { "flags": [ <flag>, ... ] }, ... } }
```
- `summary` free text is recorded for audit but is NEVER part of the deterministic match (so the match
  cannot drift on phrasing — RISK-DM-012).

---

## 4. Seeded-defect oracle format + deterministic location-overlap algorithm

### `oracle.json` (machine oracle — the matcher's only ground truth)
```json
{ "corpus_id": "council-review-catch-v1", "version": 1,
  "type_vocabulary": ["missing-error-handling", "ordering", ...],
  "tasks": {
    "<task-id>": {
      "kind": "seeded" | "clean-control" | "recall-control",
      "file": "<path the diff touches>",
      "defects": [
        { "id": "D1", "file": "...", "line_start": 12, "line_end": 14,
          "type": "ordering", "seeded_before_review": true }
      ],
      "clean_regions": [ { "file": "...", "line_start": 1, "line_end": 40 } ]
    }
  } }
```
- `seeded` tasks carry ≥1 `defects[]` entry. `clean-control` tasks carry `defects: []` (any flag on
  them is cry-wolf). `recall-control` carries known defects PLUS `clean_regions` to detect narrowing
  (a review that flags nothing / collapses scope fails recall). `seeded_before_review: true` is the
  provenance assertion the README backs.

### Location-overlap match rule (deterministic)
A flag F MATCHES a seeded defect D iff **all** hold:
1. **Same file:** `F.file == D.file` (exact, repo-relative).
2. **Line-range overlap:** the closed intervals `[F.line_start, F.line_end]` and
   `[D.line_start, D.line_end]` intersect, i.e. `F.line_start <= D.line_end AND D.line_start <=
   F.line_end`. (Closed intervals — touching endpoints count as overlap; documented explicitly.)
3. **Type agreement:** `F.type == D.type` (both from the CLOSED vocabulary). Type mismatch on an
   overlapping line is NOT a catch (prevents "flagged the right line for the wrong reason" inflation).

Scoring rules (per task, per arm), all deterministic:
- **catch** = a seeded defect D has ≥1 matching flag. Catch-rate = (caught defects) / (total seeded
  defects across `seeded`+`recall-control` tasks).
- **cry-wolf** = a flag on a `clean-control` task, OR a flag landing inside a `clean_regions` interval
  with NO overlapping seeded defect. Cry-wolf-rate = (cry-wolf flags) / (total flags on clean
  controls + clean regions). Reported TOGETHER with catch (REQ-DM-3a-003).
- **recall-control** = on `recall-control` tasks, did the review still surface the known defect(s)
  (guards against narrowing). Boolean per task → recall pass-rate.
- **Determinism (NFR-DM-3a-002):** scoring the SAME captured flag-sets twice yields byte-identical
  numbers; the test asserts EXACT numeric equality (not substring — real-boundary-evidence-hygiene
  learning).
- **Tie/ambiguity handling:** one flag may match at most ONE defect (first by `D.id` order) to avoid
  double-counting; a defect with multiple matching flags counts as one catch. Documented in the README.

### Corpus content (≥2 distinct task outcomes — BLOCKER-2 / variance)
Minimum viable primary corpus authored INDEPENDENTLY of the council (defects chosen from generic,
well-known defect classes, NOT from anything a council caught):
- ≥1 `seeded` diff (e.g. ordering/atomicity defect in a delete path — the RDIFF-A idiom, re-authored
  fresh, not copied) with its oracle.
- ≥1 `clean-control` diff (a correct, wired diff with NO seeded defect → cry-wolf oracle).
- ≥1 `recall-control` diff (known defect + clean regions → narrowing guard).
- Designed so ≥2 tasks can land on DISTINCT outcomes (one easily-caught, one subtle) → real
  across-task variance so 3b can pin a noise threshold + MDE. A saturated single-outcome corpus is
  rejected at acceptance.

---

## 5. Build order (RED → GREEN), offline seams

Strict TDD; no production code before a failing test. The tester owns the contract; the coder makes it
green. Each step is offline at 0 credits.

1. **Step 0 — Phase-3 contract read (REQ-DM-3a-007 / OQ-DM-8) FIRST.** Before any scorer premise about
   the council's per-role flag shape is used, open `deepseek_review.py preset`'s positions output
   end-to-end and classify the per-role shape `belegt`/`ableitbar`. The §0 `ungeprueft` row in the PRD
   MUST be reclassified here. **If `preset` does NOT expose a per-role flag-set in a scorable shape →
   raise OQ-DM-8 to the user (a one-file additive capture-only seam) — do NOT silently edit the
   instrument.** Default if unresolved: the scorer consumes Arm-B flag-sets in the SAME schema as Arm-A
   (the council runner output is adapted by a thin 3b-side translator, NOT an instrument edit). This
   step gates the scorer; record the classification in the ledger.
2. **Step 1 — corpus skeleton + `oracle.json` + manifest hash (RED: scorer/matcher tests reference it).**
   Author the seeded/clean/recall diffs + machine oracle + manifest with content hash. Validate the
   manifest scope/freeze. Acceptance: ≥1 each of seeded/clean/recall; ≥2 distinct outcomes possible;
   `freeze` hash recomputes (NFR-DM-3a-005); no clean control → REJECT.
3. **Step 2 — scorer (ART-3a-3), TDD against a SMALL FIXTURE flag-set.** Write failing tests first:
   (a) location-overlap match (exact-line, partial-overlap, touching-endpoint, type-mismatch-no-match);
   (b) catch+cry-wolf+recall emitted TOGETHER, missing cry-wolf field → RED;
   (c) determinism: same fixture twice → identical numbers (exact equality);
   (d) foreign-only assertion flips false on a `claude-*` scope;
   (e) `to_emit_run_blob` → `emit_run.py --dry-run` exits 0, `process_health.py` reads it,
   `arm`/`model_scope`/`cry_wolf_rate` under `raw` not top-level (REQ-DM-3a-005). Then implement.
   Offline seam: a tiny hand-written fixture flag-set JSON + a tiny fixture oracle staged in the test
   (NOT a live runner) so the scorer is tested in isolation.
4. **Step 3 — Arm-A runner (ART-3a-2), TDD via injected transport (0 credits).** Failing tests first:
   (a) `--inject-response '<structured flags>'` → a valid flag-set; ZERO network
   (`--inject-call-counter` reads 0 with no `--live`); (b) malformed model output → classified
   `flag-protocol-malformed`, no fabricated flags; (c) `model_scope` always present; (d) the four
   instrument files + `concilium/**` byte-unchanged (`git diff` empty) — NFR-DM-3a-003; (e) the runner
   computes its OWN estimate (assert it is NOT a hand-fed constant). Then implement.
5. **Step 4 — end-to-end offline wiring proof.** `arm_a_review_runner --inject-response ...` →
   flag-set file → `council_review_scorer` → scorer_output with both metric families; assert the
   `emit_run.py --dry-run` round-trip. ZERO live calls; `git status` clean after (REQ-DM-3a-006).
6. **Step 5 — substrate README (REQ-DM-3a-009)** stating IS/IS-NOT, the matching rule, the entrypoints,
   and marking the SECONDARY real-diff judge set MISSING (deferred; not assembled in 3a).
7. **Step 6 — reality ledger (REQ-DM-3a-010)** at `integration-fake` (§7).
8. **Step 7 — register the new test module in `run_all.sh`** (new stage + py_compile entries); run the
   full suite green.

Offline seams summary: (i) the Arm-A runner's `--inject-response`/`--inject-call-counter` (transport
never armed without `--live AND COUNCIL_INFERENCE_LIVE=1`); (ii) a small fixture corpus + fixture
flag-set staged inside the scorer tests so the deterministic matcher is provable without any runner.

---

## 6. Instrument-read-only integrity (NGOAL-DM-001 / NFR-DM-3a-003 / REQ-DM-3a-008)

- NO step in this plan edits `config/claude/lib/{deepseek_review,council_presets,council_inference,
  council_backend}.py` or `concilium/**`. ART-3a-2 IMPORTS `council_inference.run_inference` /
  `_real_transport` (an import is not a modification); it does not call `deepseek_review` or
  `council_presets` at all.
- The only library-tree files this plan touches are NEW modules under `config/claude/metrics/`
  (`arm_a_review_runner.py`, `council_review_scorer.py`) — outside the read-only `config/claude/lib/`
  instrument tree, and inside the Allowed change scope.
- `process_health.py` MAY receive a one-line additive `DIRECTIONS` entry ONLY if the committed tests
  require `cry_wolf_rate` under `metrics` (§1a) — it is in scope and is NOT an instrument file. Default
  plan: leave it untouched.
- A genuinely-needed council-capture seam is OQ-DM-8: surfaced at Step 0, presented to the user as an
  exact one-file additive change, and NOT applied without authorization. Until then `git diff` over the
  four instrument files + `concilium/**` stays empty — a build step asserts this.

---

## 7. Reality ledger (REQ-DM-3a-010) — all `integration-fake`

`docs/reality/council-diversity-measurement.evidence.jsonl`, authored Phase 3 / Gate C, one record per
load-bearing 3a REQ, mirroring the `openrouter-inference.evidence.jsonl` shape. Every record is
`integration-fake` (3a crosses NO real boundary — everything is offline/injected). There is NO honest
`real-boundary-smoke` record in 3a (that class belongs to 3b's live run). The class is NEVER raised to
clear a floor; run `plumbline-reality-check --min-evidence integration` (the default floor is satisfied
BY `integration-fake`). Ledger text avoids the FORBIDDEN_TOKENS
(`fake-only`/`mock-only`/`placeholder`/`unverified`); use "offline, injected transport, 0 credits".
Records: REQ-DM-3a-001 (corpus controls+variance), -002 (Arm-A offline flag-set), -003 (shared scorer
both families), -004 (deterministic overlap reproducible), -005 (emit_run blob round-trip), -006
(offline isolation), -007 (contract read classified), -010 (ledger itself). REQ-DM-3a-008/009 are
governance/doc REQs evidenced by README + the empty-instrument-diff assertion.

---

## 8. Validation commands + `run_all.sh` integration

```bash
# Scope check (re-run after finalizing module/corpus names — names match the canvas scope list)
config/claude/bin/plumbline-scope-check --repo . --feature council-diversity-measurement \
  --changed-files <space-separated changed paths>

# The new standalone test module (RED first, GREEN after build)
bash config/claude/tests/test_council_review_substrate.sh

# Full CI suite (must be green; new stage + py_compile entries added)
bash config/claude/tests/run_all.sh

# Reality floor (default integration floor; satisfied by integration-fake)
config/claude/bin/plumbline-reality-check --min-evidence integration

# Corpus freeze re-derivation (NFR-DM-3a-005)
python3 metrics/corpus/council-review-catch-v1/freeze.py --check   # or recompute hash vs manifest

# Offline isolation proof (REQ-DM-3a-006) — after every run
git status --porcelain    # only intended paths
git diff --stat config/claude/lib/deepseek_review.py config/claude/lib/council_presets.py \
  config/claude/lib/council_inference.py config/claude/lib/council_backend.py concilium/   # MUST be empty
```

### `run_all.sh` tripwires (binding — from prior incidents)
- **Corpus markdown + README must NOT carry `---` frontmatter** (the frontmatter validator globs
  `**/*.md`). Start every new `.md` (`README.md`, `diffs/*.md`, `oracles/*.md`) with a plain `#`
  heading and NO `---` block, OR ensure any present frontmatter has unique `name:` + `description:`.
  Safest: NO frontmatter on corpus/diff/oracle markdown.
- The `diffs/*.md` review-diff files are DATA (mirroring `pipe-core-v1/review-diffs/`), not agents —
  keep them frontmatter-free so they neither fail the parser nor collide on `name:`.
- Do NOT quote any `mcp__<family>__` literal in the new docs (`test_dependencies_doc.sh`); refer in
  prose only.
- Add the two new modules to the `py_compile` stage and a new `stage "..."` line for the test module.

---

## 9. Risks this plan must keep honest

- **Closed-allowlist laundering (§1a):** the catch number maps onto `escaped_defect_rate` (existing,
  correct semantics) — do NOT invent a new top-level metric key to dodge the allowlist; if `metrics`
  promotion of cry-wolf is required, it is an explicit additive `DIRECTIONS` line, disclosed.
- **Goodhart (NGOAL-DM-003):** defects seeded from generic defect classes BEFORE/independent of any
  review; corpus frozen + hashed; provenance recorded in README. Never tune to the council.
- **Matching-rule softness (RISK-DM-012):** the overlap rule is the §4 closed-form predicate (file +
  interval intersection + closed-vocabulary type) — no judge on the primary; exact-equality determinism
  test.
- **Wrong-corpus re-import (RISK-DM-013):** the NEW `council-review-catch-v1` is the PRIMARY everywhere;
  `pipe-providedfake-v1` is never named as the catch+cry-wolf+recall corpus.
- **Instrument creep (RISK-DM-009):** §6 — empty-diff assertion as a test; seam only via OQ-DM-8.

---

## 10. Explicitly DEFERRED to Slice 3b (NOT built here)

- The Arm-A-vs-Arm-B measurement RUN on the new corpus (same scorer, instrument snapshot pinned).
- The PAID pilot under a bounded budget (OPEN-DM-A — user-named immediately before the live run).
- The pre-registered pass/fail evaluation: demonstrated / refuted / tradeoff / **underpowered**
  (underpowered is DISTINCT from refuted — BLOCKER-2).
- Foreign-only enforcement at RUN time (3a builds the assertion FIELD; 3b rejects on it).
- The `runs.jsonl` emission of REAL data + `process_health.py` SPC analysis + the honest write-up
  headlining BOTH metrics with scope + non-claims.
- The PAIRED-EXCLUSION attrition rule (drop a subject from BOTH arms if any Arm-B role unavailable;
  attrition reported by task difficulty).
- The SECONDARY real-diff blind-judge harness (marked MISSING in the 3a README; assembled in 3b if
  pursued). The fallback cascade (BL-DM-001) — separate future slice.
```
