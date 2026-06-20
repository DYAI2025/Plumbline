# Implementation Plan — Slice 3b: Council Measurement RUN orchestrator (`council_measurement_run.py`)

Status: planning (Phase 1 of /agileteam). Author: planner. Date: 2026-06-20.
Branch: `agileteam/council-measurement-run` (branched from `main`, per the OD-3 build-hygiene rule).
Bound to: `docs/prd/council-measurement-run.prd.md` (REQ-MR-001..011, NFR-MR-001..005),
`docs/canvas/council-measurement-run.canvas.md` (user-confirmed, Ben 2026-06-20).

> This plan covers the build of the ONLY new code module
> (`config/claude/metrics/council_measurement_run.py`) + its test + the docs/artifacts in scope.
> **The tester is writing the RED contract (`config/claude/tests/test_council_measurement_run.sh`)
> in parallel; those tests ARE the contract. Where this plan conflicts with a landed test, the
> test wins** — the planner must re-read the test at Gate-start and adjust the decomposition, not
> the other way round. The plan deliberately leaves CLI flag spellings and JSON field names as
> "proposed" so they can be reconciled to the test.

---

## 0. What is being built (and what is NOT)

**Built (in scope, per the canvas `Allowed change scope` list):**
- `config/claude/metrics/council_measurement_run.py` — the orchestration script (only new code module).
- `config/claude/tests/test_council_measurement_run.sh` — owned by the parallel tester; this plan
  references it but does not author it.
- one line registering the new test in `config/claude/tests/run_all.sh` (after the existing
  `test_arm_a_review_runner.sh` line, ~line 115).
- `metrics/pre-registration-council-measurement-run.json` — the frozen, timestamped pre-registration
  artifact (BLOCKER for the scored run; authored at the pre-run gate, NOT in the offline build —
  but the LOADER + n=2 rubric live in the module and are offline-tested with a fixture artifact).
- `docs/benchmarks/<date>-council-measurement-run-pilot.md` — the honest write-up (LIVE-only content;
  the offline build produces the skeleton + the structural assertions the test checks).
- `docs/reality/council-measurement-run.evidence.jsonl` — the PRIL reality ledger (Phase 3 / Gate C).
- append-only to `metrics/runs.jsonl` (LIVE pilot only; offline runs stage to a temp `--out` OUTSIDE
  the tree).
- `docs/traceability.md`, `backlog.md`, `CLAUDE.md` — maintained by context-keeper / learning-loop.

**NOT built (NGOAL-3b-001..012, REQ-MR-009):** no edit to the 3a substrate
(`arm_a_review_runner.py`, `council_review_scorer.py`, corpus) or the read-only instrument
(`config/claude/lib/{deepseek_review,council_presets,council_inference,council_backend}.py`,
`concilium/**`); no new instrument / parallel harness; no corpus tuning; no Slice-4 GUI; no A/B/C
presets (pilot runs preset A only); no model-resolution fallback cascade.

**Verified substrate contracts (read 2026-06-20, drive the reuse map below — all `belegt`):**
- `arm_a_review_runner.build_messages(diff_text, model_scope)` → `[system, user]`;
  `parse_flag_set(text) -> (flags, status)` parses ONLY `{"flags":[...]}` JSON (fence-tolerant),
  non-protocol → `([], CODE_FLAG_PROTOCOL_MALFORMED)`, empty → `([], CODE_NEEDS_INJECTION)`.
- `council_review_scorer.score_flag_set(flag_set, oracle)` → both metric families +
  `foreign_only_ok`; `build_emit_blob(...) -> {"metrics":{}, "raw":{...}}`;
  `load_corpus(dir)`, `compute_corpus_hash(dir)`.
- `council_inference.run_inference(env, *, model, messages, max_tokens, input_estimate, dry_run,
  build_only, inject_response, inject_error, inject_retry_after, transport=None,
  on_transport_call=None)` — `transport=None` + `inject_response=<text>` is the offline path (one
  classified result, `on_transport_call` fires once); `transport=council_inference._real_transport`
  + a real `OPENROUTER_API_KEY` is the live path; OK result carries `completion` + `usage`.
  `_real_transport` is gated by the caller (live only when `--live` AND `COUNCIL_INFERENCE_LIVE=1`).
- `deepseek_review.py preset --preset A --subject <S>` returns
  `{"code", "positions":[{"role","character","model","code","position"}], "diversity":...}`;
  `--subject` threads VERBATIM into each role's user message; `position` is the raw completion (or
  `None` on non-OK `code`); `wrap_position` DISCARDS `usage` (no per-role token cost on this path).
  **Offline caveat (load-bearing — drives the Arm-B seam decision below):** `preset`'s ONLY offline
  seams are a SINGLE `--inject-response` (reused for EVERY role) + `--inject-catalog` +
  `--inject-call-counter`. There is NO per-role injected-response map on the CLI.
- `emit_run.py`: `--raw <json>` free-form (recorded, NOT scored); `--metrics` rejects any key not in
  `process_health.DIRECTIONS` (exit 2); `cost_per_req` computed from `--tokens-total`/`--reqs-accepted`
  only; `--corpus-id` top-level; `--out <path>` redirects the append target (used to stage offline
  runs OUTSIDE the tree); `--dry-run` prints without writing.
- `process_health.py` SPC reads `r["metrics"][name]` ONLY — NEVER `raw`. So review catch/cry-wolf
  (under `raw`) are NOT SPC'd; the orchestrator computes MDE/noise over the captured per-task scores.
- corpus `council-review-catch-v1`: T1-auth-token = 1 defect, T2-pagination = 2 defects; each task has
  `oracle` / `clean_controls` / `recall_control`; diffs under `diffs/`. (The cross-task variance source.)

---

## 1. Module / function decomposition (`council_measurement_run.py`)

A single CLI script under `config/claude/metrics/` (NOT `config/claude/lib/`). It IMPORTS the three
3a/instrument modules and ORCHESTRATES — it adds NO scoring logic of its own (REQ-MR-003). Because
`config/claude/lib/` is not a package, the script adds the lib dir to `sys.path` at import time
(mirroring how `deepseek_review.py` does `from council_inference import _real_transport`).

Proposed function surface (names are stable handles for the test; reconcile spellings with the
landed RED test):

**A. Subject + protocol (REQ-MR-002 — symmetric flag protocol).**
- `STRUCTURED_FLAG_PROTOCOL` — the EXACT protocol-instruction string appended to `--subject` for BOTH
  arms. It must match the `{"flags":[{file,line,description}]}` shape `parse_flag_set` accepts. Reuse
  the wording from `arm_a_review_runner.build_review_prompt` (do NOT re-derive a divergent protocol)
  so both arms are prompted identically.
- `build_arm_a_messages(diff_text, model_scope)` → delegates to `arm_a_review_runner.build_messages`
  (Arm A already embeds the protocol via `build_review_prompt`).
- `build_arm_b_subject(diff_text)` → the review subject for Arm B = the diff under review + the
  IDENTICAL `STRUCTURED_FLAG_PROTOCOL` appended (the thing passed to `preset --subject`).
  **Symmetry contract:** the protocol text in A's prompt and in B's subject is byte-identical.

**B. Arm runners (injectable seams — REQ-MR-008 / REQ-MR-005).**
- `run_arm_a(task, *, model_scope, env, live, transport=None, inject_response=None,
  on_call=None) -> ArmResult`
  - Offline: call `council_inference.run_inference(env, model=..., messages=build_arm_a_messages(...),
    ..., inject_response=inject_response, transport=None, on_transport_call=on_call)`; parse the
    returned `completion` (or the injected text) with `parse_flag_set`.
  - Live: same call with `transport=council_inference._real_transport` and the live model id; capture
    the returned `usage` block (Arm-A ACTUAL usage — REQ-MR-005/006).
  - Returns `{arm:"claude-only", model_scope, task, code, flags, usage|None}`.
- `run_arm_b(task, *, preset="A", env, live, arm_b_fn=None, inject_catalog=None,
  inject_role_responses=None, on_call=None) -> ArmResult`
  - **The Arm-B seam is a CALLABLE injected at the orchestrator level**, NOT `deepseek_review`'s
    single `--inject-response` (which cannot give DISTINCT per-role outputs). Default `arm_b_fn`
    shells/imports `deepseek_review._cmd_preset` with `--subject build_arm_b_subject(...)` +
    `--inject-catalog`. The offline test supplies `arm_b_fn` (or `inject_role_responses`) returning a
    canned `preset` result dict (`positions:[...]`) — 0 network. This keeps the measured contract
    (`preset` shape) while allowing per-role offline fixtures.
  - For each `position` with `code == OK`: `parse_flag_set(position["position"])` → flags. UNION the
    per-role flags into ONE Arm-B flag-set for the subject (council = all roles' findings together);
    `model_scope = [position["model"] for OK roles]`.
  - Returns `{arm:"council-A", model_scope, task, code (overall), positions, flags, usage:None}`
    (no usage on the preset path — REQ-MR-005).

**C. Scoring (REQ-MR-003 — read-only scorer).**
- `score_arm(arm_result, oracle) -> dict` → builds the scorer's flag-set
  `{arm, model_scope, task, flags}` and calls `council_review_scorer.score_flag_set`. No local math.
- `assert_foreign_only(scored)` → on a council arm, require `scored["foreign_only_ok"] is True`;
  else REJECT the record + fail closed for that subject (REQ-MR-004).

**D. Paired-exclusion + survivors (REQ-MR-004).**
- `classify_subject(arm_a_result, arm_b_result) -> ("scored" | "excluded", reason, difficulty)`
  - If ANY Arm-B role has `code != OK` (budget-exhausted/timeout/unresolvable) → `excluded`
    (flakiness): PAIRED-EXCLUDE the subject from BOTH arms; record UNAVAILABLE + task difficulty;
    NEVER score it a miss, NEVER Claude-substitute.
  - A `code == OK` Arm-B role with 0 flags is NOT exclusion — it is a SCORED legitimate empty review.
  - (Arm-A `code != OK` is also a paired-exclusion of that subject — symmetric instrument failure.)
- `enforce_survivors_floor(n_survivors, floor) -> outcome|None` → if `n_survivors < floor`, force the
  run outcome to `underpowered/unmeasurable` (REQ-MR-007); the floor value comes from the
  pre-registration artifact.

**E. Pre-registration + classification (REQ-MR-007).**
- `load_preregistration(path) -> PreReg` — STRICT load (REQ-MR-011 N3); fields: frozen-timestamp,
  noise model, MDE, minimum-survivors floor, rubric. Confine `@path`-style inputs to the work dir
  (N1).
- `assert_frozen_before_first_score(prereg, first_score_time)` → REFUSE to score (fail-closed,
  non-zero) if no artifact exists OR its timestamp is not earlier than the first scored record
  (REQ-MR-007).
- `compute_noise_and_mde(per_task_scores) -> {noise, mde}` — over the CAPTURED per-task catch/cry-wolf
  scores (T1 1-defect vs T2 2-defect cross-task variance), NOT via `process_health` (which reads
  `metrics`, not `raw`).
- `classify_outcome(prereg, aggregate, n, survivors) -> outcome` — **n=2 PILOT rubric: emit ONLY
  `underpowered` or `tradeoff-signal-to-investigate`; `demonstrated`/`refuted` are unreachable by
  construction** (a 2/2-vs-0/2 split must NOT be laundered as `demonstrated`). The full four-outcome
  rubric is recorded for the deferred powered run but not selectable at n=2.

**F. Emission (REQ-MR-006).**
- `emit_arm_record(scored, *, env, out_path, usage=None) -> int`
  - Build `council_review_scorer.build_emit_blob(catch=..., cry_wolf=..., recall=..., n=..., 
    task_count=1, arm=..., model_scope=...)` → `{metrics:{}, raw:{...}}`.
  - Call `emit_run.py` (via `subprocess` or `emit_run.main([...])`) with `--raw <blob.raw>`
    `--corpus-id council-review-catch-v1` `--out <out_path>`; for Arm A ONLY, add
    `--tokens-total <usage.completion_tokens> --reqs-accepted <survivors>` so the allowlisted
    `cost_per_req` is populated from ACTUAL usage. Arm B emits NO `cost_per_req` (estimated upper
    bound only). Assert `emit_run` exit 0 (a non-allowlisted `--metrics` key would exit 2 — the
    routing proof). Surface OSError on the write (N2).

**G. Budget gate (REQ-MR-005 / NFR-MR-003).**
- `resolve_max_calls(cap, per_call_cap) -> int` → `cap // per_call_cap` (MAX-CALLS ceiling; an
  a-priori upper bound — there is NO aggregate-cost meter; `usage` is discarded on the preset path).
- `refuse_live_without_cap(args)` → if `--live` AND `COUNCIL_INFERENCE_LIVE=1` but NO user-named cap
  → fail-closed non-zero, NO live call made (REQ-MR-005). The cap value is NOT in any artifact; it is
  named by the user at the pre-run gate.
- The live gate is OFF by default: a test asserts 0 transport calls by default (via the injected
  `on_call` counter), and that the Arm-A live path is REACHABLE only when armed.

**H. CLI + main (REQ-MR-001).**
- `--corpus <dir>` `--preset A` `--out <runs.jsonl>` `--preregistration <path>`
  `--inject-catalog <json>` `--inject-arm-a-response <text|@path>` `--inject-arm-b <fixture>`
  `--inject-call-counter <path>` `--live` `--budget-cap <int>` `--per-call-cap <int>`
  `--model-scope-a <id>` (proposed; reconcile to the test). `main` runs the per-task loop:
  for each task → run_arm_a + run_arm_b → classify_subject → (scored) score both → assert foreign-only
  → emit both → collect per-task scores; then survivors-floor + classify_outcome. Exits non-zero on
  ANY orchestration error (fail-closed; never a partial/fabricated record — REQ-MR-001).

**I. Security carry (REQ-MR-011).**
- N1: any `@path` (the inject-response file form) is `realpath`-confined to the work dir before read
  (refuse traversal) — mirror `deepseek_review._character_exists`'s `commonpath` guard.
- N2: the live `runs.jsonl` write surfaces OSError (non-zero exit / explicit error), never swallowed.
- N3: STRICT argparse — no inferred file locations, no lax positional inference; malformed flag → reject.

---

## 2. Reuse map (exact call sites — REQ-MR-009 keeps these byte-unchanged)

| Need | Reused symbol (read-only) | Call site in `council_measurement_run.py` |
|---|---|---|
| Arm-A messages (protocol-embedded) | `arm_a_review_runner.build_messages` / `build_review_prompt` | `build_arm_a_messages` |
| Both arms' output → flags | `arm_a_review_runner.parse_flag_set` | `run_arm_a`, `run_arm_b` (per OK role) |
| Arm-A REAL boundary + usage | `council_inference.run_inference` (+ `_real_transport` when armed) | `run_arm_a` |
| Arm-B council roles | `deepseek_review` `preset` (`--subject`, returns `positions[]`) | `run_arm_b` default `arm_b_fn` |
| Scoring (both families + foreign-only) | `council_review_scorer.score_flag_set` | `score_arm` |
| Emit-blob `{metrics,raw}` | `council_review_scorer.build_emit_blob` | `emit_arm_record` |
| Corpus load + tasks/oracle | `council_review_scorer.load_corpus` | `main` |
| Corpus freeze-hash check | `council_review_scorer.compute_corpus_hash` vs `manifest.json` hash | `main` (REQ-MR-003 verify) |
| Append run record | `emit_run.py` (`--raw`, `--corpus-id`, `--out`, `--tokens-total`/`--reqs-accepted`) | `emit_arm_record` |
| Analysis (cost SPC only) | `process_health.py` (reads `metrics`, not `raw`) | post-run analysis step |

**The Arm-A-transport-in-new-script approach (resolves REQ-MR-005 vs REQ-MR-009):** Arm A's real
boundary is reached by `council_measurement_run.py` calling `run_inference(..., transport=_real_transport)`
DIRECTLY — NOT by editing the frozen `arm_a_review_runner.py` (whose own live `_cmd_review` path stays
dead and untouched). This mirrors the openrouter-inference injectable-seam lesson: a paired, gated real
entrypoint, not an edit to the frozen runner. The instrument stays byte-unchanged (REQ-MR-009 git-diff-empty).

---

## 3. Build order (RED → GREEN, TDD; no production code before a failing test)

The tester owns the RED contract; the planner/coder build to GREEN test-by-test. Order chosen so each
step has a falsifying test and the offline path is fully green before ANY live concern.

1. **Skeleton + import wiring (REQ-MR-009).** Create the module with `sys.path` wiring + a `main` that
   loads the corpus and verifies `compute_corpus_hash == manifest hash`, exits 0. Test:
   `::offline_full_loop` (initially RED), `::substrate_git_diff_empty`, `::corpus_freeze_hash`.
2. **Symmetric protocol (REQ-MR-002).** `STRUCTURED_FLAG_PROTOCOL` + `build_arm_a_messages` +
   `build_arm_b_subject`; assert the protocol text is byte-identical across arms. Test:
   `::symmetric_protocol_both_arms` (well-formed protocol JSON → parsed flags for BOTH; non-protocol
   JSON → empty flag-set via the SAME `parse_flag_set`, both arms).
3. **Arm-A offline (REQ-MR-005 offline half / REQ-MR-008).** `run_arm_a` with `transport=None` +
   `inject_response`; parse via `parse_flag_set`; counter == 0. Test: `::offline_zero_calls` (Arm-A leg).
4. **Arm-B offline (REQ-MR-002/004).** `run_arm_b` with the injected `arm_b_fn`/role-responses +
   `inject_catalog`; union per-role OK flags; `model_scope` = OK foreign ids; counter == 0.
5. **Scoring + foreign-only (REQ-MR-003/004).** `score_arm` via `score_flag_set`;
   `assert_foreign_only`. Tests: `::scoring_deterministic` (numeric equality on re-run),
   `::foreign_only_rejects_claude` (a Claude id in Arm-B `model_scope` → rejected, fail-closed).
6. **Paired-exclusion + survivors (REQ-MR-004).** `classify_subject` + `enforce_survivors_floor`.
   Test: `::paired_exclusion` (non-OK role → subject dropped from BOTH arms, recorded unavailable,
   NOT a miss; a `code==OK`+0-flags role → SCORED, not excluded; below floor → `underpowered`).
7. **Pre-registration + classify (REQ-MR-007).** `load_preregistration` (STRICT) +
   `assert_frozen_before_first_score` + `classify_outcome` (n=2 → only `underpowered` /
   `tradeoff-signal-to-investigate`). Tests: `::refuse_score_without_frozen_line`,
   n=2-rubric assertion. (Offline test uses a FIXTURE pre-registration artifact staged in `/tmp`.)
8. **Emission (REQ-MR-006).** `emit_arm_record` → `emit_run.py --raw ... --out <tmp>`; review metrics
   under `raw`, `cost_per_req` for Arm A only. Test: `::emit_routes_under_raw` (emit_run exit 0;
   `runs.jsonl` record has `corpus_id` top-level + review keys under `raw`; no non-allowlisted
   `metrics` key).
9. **Budget gate (REQ-MR-005 / NFR-MR-003).** `refuse_live_without_cap` + `resolve_max_calls` +
   the default-off gate. Tests: `::live_gate_off_by_default` (0 calls), `::refuse_without_budget`
   (live + no cap → non-zero, no call), `::arm_a_reachable_when_armed` (the live path is reachable
   only when `--live` AND `COUNCIL_INFERENCE_LIVE=1` — proven via a STUB transport in the test, not a
   real call, so the offline suite stays 0-network).
10. **Security carry (REQ-MR-011).** N1 `@path` confinement, N2 OSError surface, N3 strict parser.
    Tests: `::path_confined`, `::oserror_surfaced`, `::strict_parser`.
11. **Register the test in `run_all.sh`** + ensure `git status` clean and full suite green
    (NFR-MR-004). The offline test makes ZERO live calls and stages all I/O to `/tmp`.

After every step: `bash config/claude/tests/run_all.sh` green + `git status` clean over the substrate
(the bench-isolation tripwire — a stray file in `metrics/corpus/**` or a duplicate `name:` reddens the
frontmatter scan).

---

## 4. The offline seams (how 0 network is guaranteed — REQ-MR-008 / NFR-MR-004)

- **Arm A:** `run_inference(transport=None, inject_response=<canned protocol JSON>)` — the no-transport
  branch returns a classified result with ZERO `urlopen`; `on_transport_call` counter stays 0.
- **Arm B:** an injected `arm_b_fn` (or `inject_role_responses` map) at the ORCHESTRATOR level returns
  a canned `preset`-shaped dict (`positions:[{role,model,code:"COUNCIL_OK",position:<protocol JSON>}]`)
  — chosen over `deepseek_review`'s single `--inject-response` because that seam reuses ONE response
  for EVERY role and cannot produce distinct per-role council outputs. `--inject-catalog` keeps the
  resolver offline if the default `arm_b_fn` (the real `preset`) is used with canned responses.
- **Catalog:** `--inject-catalog <json>` threads to `preset`'s `--inject-catalog` (0-network resolver).
- **Call counter:** `--inject-call-counter <path>` (and the in-process `on_call` hook) proves
  counter == 0 on every offline test.
- **Staging:** the offline test writes `runs.jsonl` via `emit_run.py --out /tmp/<...>` and stages the
  pre-registration fixture in `/tmp` — NEVER in the tracked tree (RISK-3b-009 / the bench-isolation
  lesson). The 3a substrate `git diff` must be empty after the run (REQ-MR-009).

---

## 5. Validation commands

```bash
# Frontmatter validator + full CI suite (must be green after every step):
bash config/claude/tests/run_all.sh

# The new module's test in isolation (owned by the tester):
bash config/claude/tests/test_council_measurement_run.sh

# Substrate untouched (REQ-MR-009 — must print nothing):
git diff --stat -- \
  metrics/corpus/council-review-catch-v1 \
  config/claude/metrics/arm_a_review_runner.py \
  config/claude/metrics/council_review_scorer.py \
  config/claude/lib/deepseek_review.py \
  config/claude/lib/council_presets.py \
  config/claude/lib/council_inference.py \
  config/claude/lib/council_backend.py \
  concilium

# Corpus freeze-hash still matches the manifest (REQ-MR-003):
python3 config/claude/metrics/council_review_scorer.py freeze-hash \
  --corpus metrics/corpus/council-review-catch-v1
# compare to manifest.json "hash": sha256:fb5f22df28706b2bae8af3f0187a64201c3e0070d9188be9f0bf0c5356b6fb92

# Offline end-to-end to a TEMP runs.jsonl OUTSIDE the tree (0 network):
python3 config/claude/metrics/council_measurement_run.py \
  --corpus metrics/corpus/council-review-catch-v1 --preset A \
  --preregistration /tmp/prereg.fixture.json \
  --inject-catalog '<offline catalog json>' \
  --inject-arm-a-response '<protocol json>' --inject-arm-b '<fixture>' \
  --inject-call-counter /tmp/calls.txt --out /tmp/runs.jsonl
test "$(cat /tmp/calls.txt)" = "0"     # 0 transport calls

# PRIL gates (Gate C / Phase 3):
config/claude/bin/plumbline-scope-check --repo . --feature council-measurement-run \
  --changed-files <list>
config/claude/bin/plumbline-reality-check --min-evidence integration   # offline ledger floor
config/claude/bin/plumbline-redact   # clean on the write-up (NFR-MR-001)

# Cost SPC (the ONLY directly-SPC'd metric — review metrics live under raw):
python3 config/claude/metrics/process_health.py
```

---

## 6. The LIVE-only part (deferred — NOT run in this build)

Everything above is OFFLINE and lands in this slice. The following is the paid pilot, gated by the
two RETAINED run-time BLOCKERs (canvas §"Open Questions" OQ-3b-1 + OQ-3b-4). It is NOT executed during
the build; the build only proves the mechanism is reachable when armed.

1. **Freeze the pre-registration artifact** `metrics/pre-registration-council-measurement-run.json`
   with the n=2 rubric, noise model, MDE, minimum-survivors floor, and a real timestamp — BEFORE the
   first scored run (REQ-MR-007 BLOCKER). This is the only artifact that gates the SCORED run.
2. **User names the budget cap** at the pre-run gate (OQ-3b-1 BLOCKER). The cap is NOT in any artifact;
   the run REFUSES to start live without it. `resolve_max_calls(cap, per_call_cap)` derives the
   MAX-CALLS ceiling.
3. **Arm the live gate:** `--live` AND `COUNCIL_INFERENCE_LIVE=1` AND a real `OPENROUTER_API_KEY` in
   the env (header-only, never logged — NFR-MR-001). Run preset A vs Claude-only over T1+T2.
4. **Score against the FROZEN line; publish as-is.** Emit per-arm records to `metrics/runs.jsonl`;
   classify the outcome (`underpowered` / `tradeoff-signal-to-investigate` ONLY at n=2); write
   `docs/benchmarks/<date>-council-measurement-run-pilot.md` with BOTH metric families + n + scope +
   the FAIR (structured-flag, not free-prose) scope statement + the pilot-purpose statement
   (run-mechanism smoke + cost/flakiness estimate, NOT a value verdict) + the ESTIMATED upper-bound
   cost with Arm-A ACTUAL usage where exposed + the explicit non-claims (outcome-delta-only, not
   proven diversity, not generality). Never headline catch alone; never relabel underpowered.
5. **Reality ledger:** the LIVE pilot record in `docs/reality/council-measurement-run.evidence.jsonl`
   is `real-boundary-smoke` for THAT run only; offline wiring is `integration-fake`; broader/definitive
   stays RED(confidence). Never raise a class to clear a floor; avoid the FORBIDDEN_TOKENS.
6. **Isolation after the live run:** `git status` clean (records appended only to `runs.jsonl` +
   the write-up), `run_all.sh` green, ZERO live calls inside `run_all.sh`.

---

## 7. Risks specific to this build

- **The parallel RED contract may name flags/fields differently.** Mitigation: re-read
  `test_council_measurement_run.sh` at the start of Gate C and reconcile the CLI/JSON spellings BEFORE
  coding; the test wins.
- **Arm-B per-role offline fidelity.** Because `preset`'s CLI offline seam is a single response, the
  orchestrator-level `arm_b_fn`/`inject_role_responses` seam is REQUIRED to exercise distinct per-role
  council outputs. Confirm the tester's fixture shape matches the `positions[]` contract; do NOT route
  the council through a degenerate single-response path that structurally collapses the council.
- **`emit_run` invocation mode.** `subprocess` vs `emit_run.main([...])` — pick whichever the test
  asserts; `main([...])` keeps it in-process and avoids a Python-path subprocess surprise, but
  `subprocess` is closer to the documented contract. Default: in-process `main` with `--out` to /tmp,
  fall back to subprocess if the test shells out.
- **Bench-isolation tripwire.** A stray file under `metrics/corpus/**` or a duplicate `name:` in any
  `**/*.md` reddens `run_all.sh` twice. All offline I/O stages to `/tmp`; verify `git status` clean.

---

## 8. Traceability (plan → REQ → test → evidence)

| REQ | Plan section | Acceptance test (planned) | Evidence class |
|---|---|---|---|
| REQ-MR-001 | §1.H, §3.1 | `::offline_full_loop` | integration-fake |
| REQ-MR-002 | §1.A, §3.2 | `::symmetric_protocol_both_arms` | integration-fake |
| REQ-MR-003 | §1.C, §3.5 | `::scoring_deterministic` + `::corpus_freeze_hash` | integration-fake |
| REQ-MR-004 | §1.C/D, §3.5/6 | `::foreign_only_rejects_claude` + `::paired_exclusion` | integration-fake |
| REQ-MR-005 | §1.B/G, §2, §3.3/9 | `::live_gate_off_by_default` + `::refuse_without_budget` + `::arm_a_reachable_when_armed` | real-boundary-smoke (live) / integration-fake (gate-off) |
| REQ-MR-006 | §1.F, §3.8 | `::emit_routes_under_raw` | integration-fake |
| REQ-MR-007 | §1.E, §3.7 | `::refuse_score_without_frozen_line` + n=2 rubric | integration-fake |
| REQ-MR-008 | §4, §3.* | `::offline_zero_calls` + `run_all.sh` green | integration-fake |
| REQ-MR-009 | §0, §2 | `::substrate_git_diff_empty` | integration-fake |
| REQ-MR-010 | §6.4 | report review (Gate C/D) | real-boundary-smoke (pilot) / RED (definitive) |
| REQ-MR-011 | §1.I, §3.10 | `::path_confined` + `::oserror_surfaced` + `::strict_parser` | integration-fake |
