#!/usr/bin/env bash
set -u
#
# Phase-1 BLACK-BOX acceptance contract for Slice 3b — the MEASUREMENT-RUN
# ORCHESTRATOR:  config/claude/metrics/council_measurement_run.py  (absent now -> RED).
#
# Written BEFORE any implementation exists (TDD RED). These tests ARE the contract:
# the coder builds the orchestrator to satisfy EXACTLY this file. RED NOW because the
# module config/claude/metrics/council_measurement_run.py is absent.
#
# DERIVED INDEPENDENTLY from the FROZEN, user-confirmed spec (Ben 2026-06-20):
#   docs/prd/council-measurement-run.prd.md      (REQ-MR-001..011, NFR-MR-001..005, §0 belegt)
#   docs/canvas/council-measurement-run.canvas.md (ARM SYMMETRY core; honesty discipline)
# Consumed substrate (READ-ONLY, contracts re-read 2026-06-20 against the real files):
#   config/claude/metrics/{arm_a_review_runner,council_review_scorer,emit_run,process_health}.py
#   config/claude/lib/{deepseek_review,council_inference,council_presets,council_backend}.py
#   metrics/corpus/council-review-catch-v1/   (T1-auth-token = 1 defect, T2-pagination = 2)
#
# OFFLINE ONLY: 0 credits, 0 network. The live gate (--live + COUNCIL_INFERENCE_LIVE=1)
# is NEVER armed here; the live PAID PILOT is the only real-boundary part (the spec's
# real-boundary-smoke for THAT run, RED(confidence) until run by the user — NOT a gap
# this offline suite asserts). This suite proves the RUN LOGIC + the gate-OFF default +
# the seam-reachable-when-armed wiring (wired-in-prod, one level down) — never spends.
#
# Eval-free assertion style mirrored from test_council_review_scorer.sh + lib.sh:
# assert_json_eq (payload to a temp file, NEVER eval'd) / assert_contains /
# assert_not_contains. No apostrophes/single-quotes inside any $(...)-wrapped heredoc
# body (the macOS bash-3.2 lesson). Exact-value assertions for every numeric/signed
# contract field; no substring matches on numbers (the openrouter-inference lesson).
#
# ===========================================================================
# SEAM / CONTRACT THE CODER MUST IMPLEMENT (derived independently from the spec)
# ===========================================================================
# A NEW deterministic Python module + CLI at config/claude/metrics/council_measurement_run.py.
# It is the ONLY new code module; it lives under config/claude/metrics/ (NOT under the
# read-only config/claude/lib/ instrument tree) and builds NO new instrument — it CONSUMES
# arm_a_review_runner / council_review_scorer / deepseek_review / council_inference / emit_run.
#
# The `run` flow (tests own the exact contract):
#   python3 config/claude/metrics/council_measurement_run.py run \
#       --corpus metrics/corpus/council-review-catch-v1 \
#       --preset A --claude-model <id> \
#       --pre-registration <file.json> --max-calls <N> [--live] --json \
#       --out <runs.jsonl-outside-the-tree> \
#       --inject-arm-a  <json|@file>     # per-task Arm-A raw model output (offline seam)
#       --inject-arm-b  <json|@file>     # per-task per-role Arm-B positions (offline seam)
#       --inject-call-counter <file>     # transport-invocation count (proves 0 calls offline)
#
# Offline-injection shapes (the contract the coder implements — keyed by corpus task id):
#   --inject-arm-a : {"<task-id>": "<raw model output text>", ...}
#                    each value is the RAW model completion (protocol JSON or not), parsed by
#                    the SAME arm_a_review_runner.parse_flag_set.
#   --inject-arm-b : {"<task-id>": [ {"role": "...", "model": "<foreign-id>", "code": "<CODE>",
#                                     "position": "<raw completion or null>"}, ... ], ...}
#                    mirrors deepseek_review.py preset positions[]: each role carries a foreign
#                    `model`, a `code` (COUNCIL_INFERENCE_OK == OK), and a `position` (raw
#                    completion; OK roles parsed by the SAME parse_flag_set).
#
# The `run --json` result object (top-level) carries at least:
#   {"outcome": "<underpowered|tradeoff-signal-to-investigate|...>",
#    "records": [ {"arm": "<claude-only|council-A>", "task": "<id>",
#                  "review_catch_rate":.., "review_cry_wolf_rate":.., "review_recall_control":..,
#                  "n":.., "task_count":.., "foreign_only_ok":.., "model_scope":.. }, ... ],
#    "attrition": [ {"task": "<id>", "reason": "<code>", "difficulty": <int|str> }, ... ],
#    "survivors": <int>, "min_survivors": <int>, "calls_attempted": <int>,
#    "arm_a_subject_protocol": "<str>", "arm_b_subject_protocol": "<str>"}
# (The orchestrator also has a `protocol-instruction` helper subcommand emitting the IDENTICAL
#  structured-flag-protocol string appended to --subject for BOTH arms — see ARM SYMMETRY.)
#
# CONTRACT DECISIONS surfaced for the planner/coder are listed at the foot of this file.
# ===========================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

RUNNER="config/claude/metrics/council_measurement_run.py"
SCORER="config/claude/metrics/council_review_scorer.py"
ARMA="config/claude/metrics/arm_a_review_runner.py"
DEEPSEEK="config/claude/lib/deepseek_review.py"
PRESETS="config/claude/lib/council_presets.py"
INFER="config/claude/lib/council_inference.py"
BACKEND="config/claude/lib/council_backend.py"
PH="config/claude/metrics/process_health.py"
CORPUS="metrics/corpus/council-review-catch-v1"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Run the orchestrator HERMETICALLY: no real key, live gate OFF (no COUNCIL_INFERENCE_LIVE),
# offline injected paths only. env -i scrubs the ambient env so a stray key can never leak in.
mr() { env -i PATH="$PATH" python3 "$RUNNER" "$@" 2>&1; }

# A well-formed structured-flag-protocol output catching T1-auth-token's seeded defect.
# (T1 oracle = 1 defect; the coder's corpus seeds it — we only need a locatable flag that the
#  scorer's file+line-overlap matcher accepts. The fidelity of the line is the scorer's job,
#  proven in test_council_review_scorer.sh; here we assert the SAME parser/scorer are USED.)
PROTO_OK='{"flags": [{"file": "auth.py", "line": 12, "description": "seeded defect"}]}'
PROTO_EMPTY='{"flags": []}'
PROTO_MALFORMED='this is free prose, not protocol JSON at all'

printf 'Council MEASUREMENT-RUN orchestrator — Slice 3b Phase-1 contract (RED until built)\n'

# ===========================================================================
# 0. ARTIFACT PRESENCE — drives the RED state before implementation.
# ===========================================================================
assert_file "REQ-MR-001 orchestrator module exists" "$RUNNER"

# ===========================================================================
# 1. ARM SYMMETRY (THE CORE — REQ-MR-002)
#    These: "both arms get reviewed." Gegenthese: the orchestrator could append the
#    structured-flag protocol to Arm A only (already structured) and feed Arm B free
#    prose to parse_flag_set -> Arm B structurally empties to 0 flags every time and the
#    council always "loses" — a green-shaped run that measures NOTHING (the deleted-prose
#    incoherence the remediation killed). Schaerfung: assert (a) the IDENTICAL protocol
#    instruction is appended to --subject for BOTH arms, (b) the SAME parse_flag_set turns
#    a given protocol-JSON into the SAME flags regardless of arm, and (c) a non-protocol
#    output yields the SAME classified empty parse for BOTH arms (never zeroing only Arm B).
# ===========================================================================
# (a) The orchestrator exposes the protocol instruction it appends to --subject; BOTH arms
#     carry the byte-identical instruction (symmetry is a property of the SAME string).
SYM="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
        --inject-arm-a "{}" --inject-arm-b "{}" \
        --inject-call-counter "$WORK/c_sym" --json 2>&1)"
assert_json_eq "REQ-MR-002 result exposes the Arm-A subject protocol instruction" \
  "$SYM" 'isinstance(d.get("arm_a_subject_protocol"), str) and len(d["arm_a_subject_protocol"])>0' True
assert_json_eq "REQ-MR-002 result exposes the Arm-B subject protocol instruction" \
  "$SYM" 'isinstance(d.get("arm_b_subject_protocol"), str) and len(d["arm_b_subject_protocol"])>0' True
assert_json_eq "REQ-MR-002 ARM SYMMETRY: the appended protocol instruction is BYTE-IDENTICAL for both arms" \
  "$SYM" 'd.get("arm_a_subject_protocol")==d.get("arm_b_subject_protocol")' True
# The protocol instruction must actually demand the {"flags":[...]} shape parse_flag_set needs
# (else "symmetric" but unparseable by the shared parser).
assert_contains "REQ-MR-002 protocol instruction demands the flags JSON envelope parse_flag_set requires" \
  "$SYM" "flags"

# (b) The SAME parse_flag_set yields the SAME flags for a given protocol-JSON regardless of arm.
#     Driven through the orchestrator's own parsing helper so we test the CODE PATH, not a copy.
PARSE_SAME="$(env -i PATH="$PATH" python3 - "$REPO_DIR" "$PROTO_OK" <<'PY' 2>&1
import importlib.util, json, sys, pathlib
repo, proto = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "council_measurement_run",
    pathlib.Path(repo) / "config/claude/metrics/council_measurement_run.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
# The orchestrator MUST parse BOTH arms with arm_a_review_runner.parse_flag_set. It exposes a
# single parsing entrypoint used for both arms; we call it tagged as each arm and compare.
fa, ca = m.parse_arm_output(proto, arm="claude-only")
fb, cb = m.parse_arm_output(proto, arm="council-A")
print(json.dumps({"flags_equal": fa==fb, "code_equal": ca==cb,
                  "n_flags": len(fa), "code": ca}, sort_keys=True))
PY
)"
assert_json_eq "REQ-MR-002 same protocol JSON -> SAME flags for both arms (shared parse_flag_set)" \
  "$PARSE_SAME" 'd["flags_equal"] is True and d["code_equal"] is True' True
assert_json_eq "REQ-MR-002 a single well-formed flag parses to exactly 1 flag (exact, not substring)" \
  "$PARSE_SAME" 'd["n_flags"]==1' True

# (c) A non-protocol (free-prose) output -> the SAME classified parse failure -> EMPTY flag-set
#     for BOTH arms (never a fabricated flag, never zeroing only Arm B).
PARSE_BAD="$(env -i PATH="$PATH" python3 - "$REPO_DIR" "$PROTO_MALFORMED" <<'PY' 2>&1
import importlib.util, json, sys, pathlib
repo, proto = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "council_measurement_run",
    pathlib.Path(repo) / "config/claude/metrics/council_measurement_run.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
fa, ca = m.parse_arm_output(proto, arm="claude-only")
fb, cb = m.parse_arm_output(proto, arm="council-A")
print(json.dumps({"a_empty": fa==[], "b_empty": fb==[], "code_equal": ca==cb,
                  "code": ca}, sort_keys=True))
PY
)"
assert_json_eq "REQ-MR-002 non-protocol output -> EMPTY flag-set for Arm A (no fabricated flag)" \
  "$PARSE_BAD" 'd["a_empty"] is True' True
assert_json_eq "REQ-MR-002 non-protocol output -> EMPTY flag-set for Arm B (symmetric, not zeroed-only-B)" \
  "$PARSE_BAD" 'd["b_empty"] is True' True
assert_json_eq "REQ-MR-002 non-protocol output -> the SAME classified parse code for both arms" \
  "$PARSE_BAD" 'd["code_equal"] is True' True
assert_contains "REQ-MR-002 malformed output classifies to the SAME ARM_A_FLAG_PROTOCOL_MALFORMED code (shared classifier)" \
  "$PARSE_BAD" "ARM_A_FLAG_PROTOCOL_MALFORMED"

# ===========================================================================
# 2. PAIRED-EXCLUSION + OK-empty-vs-non-OK + SURVIVORS FLOOR (REQ-MR-004)
#    These: "the council is scored." Gegenthese: a 402/timeout (code != OK) foreign role
#    silently scored as a council MISS makes flakiness look like signal; OR a legitimate
#    code==OK empty review wrongly EXCLUDED hides a real miss; OR a thin survivor count
#    published as a result. Schaerfung: drive injected Arm-B positions and assert (a) a
#    role with code != OK PAIRED-EXCLUDES the subject from BOTH arms (attrition, NOT a
#    scored council miss), (b) a code==OK role with 0 flags is SCORED (a real miss, not
#    excluded), (c) survivors < min -> outcome == the EXACT string "underpowered".
# ===========================================================================
# (a) An Arm-B role with code != OK on T1 -> T1 paired-excluded from BOTH arms; recorded
#     as attrition; NOT present as a scored record for either arm.
INJ_A_BOTH="{\"T1-auth-token\": $(printf '%s' "$PROTO_OK" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))'), \"T2-pagination\": $(printf '%s' "$PROTO_OK" | python3 -c 'import json,sys;print(json.dumps(sys.stdin.read()))')}"
# Arm B: T1 has a non-OK role (budget-exhausted) -> excluded; T2 all-OK with flags -> scored.
INJ_B_EXCL="$(env -i PATH="$PATH" python3 - "$PROTO_OK" <<'PY' 2>&1
import json, sys
proto = sys.argv[1]
out = {
  "T1-auth-token": [
    {"role": "Pruefer", "model": "openai/gpt-4o", "code": "COUNCIL_INSUFFICIENT_CREDIT", "position": None}
  ],
  "T2-pagination": [
    {"role": "Pruefer", "model": "openai/gpt-4o", "code": "COUNCIL_INFERENCE_OK", "position": proto}
  ],
}
print(json.dumps(out))
PY
)"
EXCL="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
         --inject-arm-a "$INJ_A_BOTH" --inject-arm-b "$INJ_B_EXCL" \
         --inject-call-counter "$WORK/c_excl" --json 2>&1)"
assert_json_eq "REQ-MR-004 non-OK Arm-B role -> T1 recorded as attrition" \
  "$EXCL" 'any(a.get("task")=="T1-auth-token" for a in d.get("attrition",[]))' True
assert_json_eq "REQ-MR-004 PAIRED-EXCLUSION: T1 produces NO scored record for EITHER arm" \
  "$EXCL" 'not any(r.get("task")=="T1-auth-token" for r in d.get("records",[]))' True
assert_json_eq "REQ-MR-004 a non-OK role is NEVER scored as a council miss (no council-A record for the excluded task)" \
  "$EXCL" 'not any(r.get("task")=="T1-auth-token" and r.get("arm")=="council-A" for r in d.get("records",[]))' True
assert_json_eq "REQ-MR-004 attrition carries the task difficulty (disclosed by difficulty)" \
  "$EXCL" 'all(("difficulty" in a) for a in d.get("attrition",[]) if a.get("task")=="T1-auth-token")' True

# (b) A code==OK role with 0 flags is a LEGITIMATE empty review -> SCORED (a real miss),
#     NOT excluded. T2 all-OK-empty must yield a scored council-A record with catch 0.0.
INJ_B_OKEMPTY="$(env -i PATH="$PATH" python3 - "$PROTO_EMPTY" <<'PY' 2>&1
import json, sys
empty = sys.argv[1]
out = {
  "T1-auth-token": [
    {"role": "Pruefer", "model": "openai/gpt-4o", "code": "COUNCIL_INFERENCE_OK", "position": empty}
  ],
  "T2-pagination": [
    {"role": "Pruefer", "model": "openai/gpt-4o", "code": "COUNCIL_INFERENCE_OK", "position": empty}
  ],
}
print(json.dumps(out))
PY
)"
OKEMPTY="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
            --inject-arm-a "$INJ_A_BOTH" --inject-arm-b "$INJ_B_OKEMPTY" \
            --inject-call-counter "$WORK/c_ok" --json 2>&1)"
assert_json_eq "REQ-MR-004 code==OK empty review is SCORED, NOT excluded (T1 NOT in attrition)" \
  "$OKEMPTY" 'not any(a.get("task")=="T1-auth-token" for a in d.get("attrition",[]))' True
assert_json_eq "REQ-MR-004 code==OK empty review -> a scored council-A record exists for T1" \
  "$OKEMPTY" 'any(r.get("task")=="T1-auth-token" and r.get("arm")=="council-A" for r in d.get("records",[]))' True
assert_json_eq "REQ-MR-004 code==OK empty review -> council-A catch rate is exactly 0.0 (a real miss, numeric)" \
  "$OKEMPTY" '[r["review_catch_rate"] for r in d["records"] if r.get("task")=="T1-auth-token" and r.get("arm")=="council-A"][0]==0.0' True

# (c) Survivors < the pre-registered minimum -> outcome forced to the EXACT string "underpowered".
#     Both tasks paired-excluded -> 0 survivors -> below any positive min.
INJ_B_ALLEXCL="$(env -i PATH="$PATH" python3 - <<'PY' 2>&1
import json
role = {"role": "Pruefer", "model": "openai/gpt-4o", "code": "COUNCIL_TIMEOUT", "position": None}
print(json.dumps({"T1-auth-token": [role], "T2-pagination": [role]}))
PY
)"
cat > "$WORK/prereg_min2.json" <<'JSON'
{"frozen_at": "2026-06-20T00:00:00Z", "n": 2, "min_survivors": 2,
 "mde": 0.5, "noise_model": "cross-task-variance",
 "rubric": "pilot-n2: only underpowered or tradeoff-signal-to-investigate"}
JSON
UNDER="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
          --pre-registration "$WORK/prereg_min2.json" \
          --inject-arm-a "$INJ_A_BOTH" --inject-arm-b "$INJ_B_ALLEXCL" \
          --inject-call-counter "$WORK/c_under" --json 2>&1)"
assert_json_eq "REQ-MR-004 survivors < min -> outcome is the EXACT string underpowered" \
  "$UNDER" 'd.get("outcome")=="underpowered"' True
assert_json_eq "REQ-MR-004 all-excluded -> survivors count is exactly 0 (numeric)" \
  "$UNDER" 'd.get("survivors")==0' True

# ===========================================================================
# 3. BUDGET = MAX-CALLS CEILING (REQ-MR-005 / NFR-MR-003)
#    These: "the live run is budgeted." Gegenthese: a live run with no cap is unbounded
#    spend, OR a run that quietly proceeds past N real calls. Schaerfung: (a) --live with
#    NO --max-calls REFUSES to start (non-zero exit, classified, 0 calls); (b) the offline
#    injected path makes 0 real calls regardless. (The 'no more than N real calls' ceiling
#    is exercised only on the live path, which is the env-gated real-boundary smoke, NOT
#    asserted here — this offline suite proves refuse-without-cap + 0-calls-offline.)
# ===========================================================================
# (a) --live without --max-calls must refuse (non-zero) and fire 0 calls. The live env gate
#     is deliberately NOT set, so even if refuse logic regressed, no real call could happen.
mr run --corpus "$CORPUS" --preset A --claude-model test-tier --live \
   --inject-arm-a "$INJ_A_BOTH" --inject-arm-b "$INJ_B_OKEMPTY" \
   --inject-call-counter "$WORK/c_nocap" --json >/dev/null 2>&1
RC_NOCAP=$?
assert "REQ-MR-005 --live with NO --max-calls REFUSES to start (non-zero exit, fail-closed)" "[ $RC_NOCAP -ne 0 ]"
assert "REQ-MR-005 refuse-without-cap fires 0 transport calls (counter 0 or unwritten)" \
  "[ ! -s \"$WORK/c_nocap\" ] || [ \"\$(cat \"$WORK/c_nocap\")\" = \"0\" ]"

# (b) The offline injected path makes 0 real calls (the counter, when written, is 0).
assert "REQ-MR-005 offline injected run writes a call counter of exactly 0" \
  "[ \"\$(cat \"$WORK/c_ok\" 2>/dev/null)\" = \"0\" ]"
assert_json_eq "REQ-MR-005 offline run reports calls_attempted == 0 (numeric)" \
  "$OKEMPTY" 'd.get("calls_attempted")==0' True

# (c) MAX-CALLS CEILING ENFORCEMENT (REQ-MR-005 / NFR-MR-003 — falsifying the unenforced cap).
#    These: "--max-calls is read." Gegenthese: --max-calls is read for PRESENCE only and never
#    enforced as a ceiling, so a --live run whose worst-case call count exceeds the cap proceeds
#    anyway -- unbounded spend past the budget the human pre-committed. Schaerfung: a --live run
#    whose worst-case call count (~ 2 + roles x tasks; >= 10 on the n=2 / preset-A corpus)
#    EXCEEDS --max-calls MUST FAIL CLOSED up-front (non-zero exit, classified) and attempt 0
#    calls -- the cap is checked BEFORE any dispatch, never after the budget is blown.
#    OFFLINE-shaped: the live env gate is NOT armed and offline injects are supplied, so even if
#    the ceiling check regressed, 0 real calls can happen (the counter proves it).
mr run --corpus "$CORPUS" --preset A --claude-model test-tier --live --max-calls 1 \
   --inject-arm-a "$INJ_A_BOTH" --inject-arm-b "$INJ_B_OKEMPTY" \
   --inject-call-counter "$WORK/c_ceiling" --json >/dev/null 2>&1
RC_CEILING=$?
assert "REQ-MR-005 --live whose worst-case call count EXCEEDS --max-calls REFUSES up-front (non-zero exit, fail-closed)" \
  "[ $RC_CEILING -ne 0 ]"
assert "REQ-MR-005 over-ceiling refusal attempts 0 transport calls (counter 0 or unwritten)" \
  "[ ! -s \"$WORK/c_ceiling\" ] || [ \"\$(cat \"$WORK/c_ceiling\")\" = \"0\" ]"
# A cap that comfortably covers the worst case must NOT trip the ceiling refusal (offline
# injects keep it 0-call regardless) -- proving the refusal is the ceiling, not --live itself.
mr run --corpus "$CORPUS" --preset A --claude-model test-tier --live --max-calls 1000 \
   --inject-arm-a "$INJ_A_BOTH" --inject-arm-b "$INJ_B_OKEMPTY" \
   --inject-call-counter "$WORK/c_roomy" --json >/dev/null 2>&1
RC_ROOMY=$?
assert "REQ-MR-005 a --max-calls cap above the worst case does NOT trip the ceiling refusal" \
  "[ $RC_ROOMY -eq 0 ]"
assert "REQ-MR-005 the roomy-cap run still fires 0 real calls (offline injects; counter 0)" \
  "[ \"\$(cat \"$WORK/c_roomy\" 2>/dev/null)\" = \"0\" ]"

# ===========================================================================
# 4. LIVE GATE OFF BY DEFAULT (REQ-MR-005 / RISK-MR-012 / NFR-MR-003)
#    These: "real calls only when armed." Gegenthese: a default run that silently reaches
#    the network is the credit-spend / wired-in-prod-one-level-down failure. Schaerfung:
#    without --live AND without COUNCIL_INFERENCE_LIVE=1, the run makes 0 network calls
#    (counter == 0) and a test asserts the gate is OFF by default. (Reachability-when-armed
#    is proven structurally below in section 8: the module reaches Arm A's real boundary by
#    calling council_inference.run_inference DIRECTLY, NOT by editing the read-only runner.)
# ===========================================================================
assert "REQ-MR-005 default (no --live, no env) -> call counter is exactly 0" \
  "[ \"\$(cat \"$WORK/c_sym\" 2>/dev/null)\" = \"0\" ]"
# Belt-and-braces: even with the env set but --live absent, default-off holds and 0 calls fire.
ENVON="$(env -i PATH="$PATH" COUNCIL_INFERENCE_LIVE=1 python3 "$RUNNER" run \
          --corpus "$CORPUS" --preset A --claude-model test-tier \
          --inject-arm-a "$INJ_A_BOTH" --inject-arm-b "$INJ_B_OKEMPTY" \
          --inject-call-counter "$WORK/c_envon" --json 2>&1)"
assert "REQ-MR-005 env COUNCIL_INFERENCE_LIVE=1 alone (no --live flag) -> still 0 calls" \
  "[ \"\$(cat \"$WORK/c_envon\" 2>/dev/null)\" = \"0\" ]"
assert_json_eq "REQ-MR-005 env-only (no --live) run still reports calls_attempted == 0" \
  "$ENVON" 'd.get("calls_attempted")==0' True

# ===========================================================================
# 5. n=2 PILOT RUBRIC (REQ-MR-007)
#    These: "the run classifies an outcome." Gegenthese: a lucky 2/2-vs-0/2 split laundered
#    as `demonstrated`, or below-MDE relabeled `refuted` — exactly the over-claim the
#    pre-registration discipline forbids; at n=2 cross-task variance is unestimable.
#    Schaerfung: given the frozen pre-registration, assert `demonstrated` and `refuted` are
#    NOT reachable for n=2; a council-2/2 vs claude-0/2 injected split does NOT classify as
#    `demonstrated` (only underpowered / tradeoff-signal-to-investigate are reachable).
# ===========================================================================
# Council catches both tasks (protocol-OK flags), Claude catches neither (empty) -> the
# tempting "2/2 vs 0/2 = demonstrated" trap. The classifier must NOT emit demonstrated/refuted.
cat > "$WORK/prereg_pilot.json" <<'JSON'
{"frozen_at": "2026-06-20T00:00:00Z", "n": 2, "min_survivors": 2,
 "mde": 0.5, "noise_model": "cross-task-variance",
 "rubric": "pilot-n2"}
JSON
INJ_A_EMPTY="$(env -i PATH="$PATH" python3 - "$PROTO_EMPTY" <<'PY' 2>&1
import json, sys
e = sys.argv[1]
print(json.dumps({"T1-auth-token": e, "T2-pagination": e}))
PY
)"
INJ_B_BOTHOK="$(env -i PATH="$PATH" python3 - "$PROTO_OK" <<'PY' 2>&1
import json, sys
p = sys.argv[1]
role = {"role": "Pruefer", "model": "openai/gpt-4o", "code": "COUNCIL_INFERENCE_OK", "position": p}
print(json.dumps({"T1-auth-token": [role], "T2-pagination": [role]}))
PY
)"
SPLIT="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
          --pre-registration "$WORK/prereg_pilot.json" \
          --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_BOTHOK" \
          --inject-call-counter "$WORK/c_split" --json 2>&1)"
assert_json_eq "REQ-MR-007 a 2/2-vs-0/2 split does NOT classify as demonstrated (n=2, laundering guarded)" \
  "$SPLIT" 'd.get("outcome")!="demonstrated"' True
assert_json_eq "REQ-MR-007 n=2 outcome is NEVER refuted (definitionally out of reach)" \
  "$SPLIT" 'd.get("outcome")!="refuted"' True
assert_json_eq "REQ-MR-007 n=2 outcome is one of the reachable pilot classes only" \
  "$SPLIT" 'd.get("outcome") in ("underpowered","tradeoff-signal-to-investigate")' True
# Scoring without a frozen pre-registration must REFUSE (fail-closed, non-zero).
mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
   --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_BOTHOK" \
   --score --inject-call-counter "$WORK/c_noprereg" --json >/dev/null 2>&1
RC_NOPREREG=$?
assert "REQ-MR-007 scoring with NO frozen pre-registration REFUSES (fail-closed, non-zero)" "[ $RC_NOPREREG -ne 0 ]"

# ---------------------------------------------------------------------------
# 5b. MDE / CATCH-DELTA RUBRIC (REQ-MR-007 — falsifying the unimplemented MDE check)
#    These: "survivors >= min => tradeoff." Gegenthese: the frozen pre-registration defines
#    `underpowered` as survivors-below-min OR the observed catch delta BELOW the MDE
#    (noise_model: cross-task-variance). The current classifier checks ONLY survivors, so a
#    survivors->=min run whose two arms produce the SAME catch (delta 0, i.e. BELOW any
#    positive MDE) is laundered as `tradeoff-signal-to-investigate` -- a real-signal claim on
#    pure noise. Schaerfung: a survivors-2 run with IDENTICAL flag-sets (catch delta == 0)
#    MUST classify `underpowered`, NOT `tradeoff-signal-to-investigate`; a catch delta ABOVE
#    the MDE with cry-wolf UP stays `tradeoff-signal-to-investigate`; demonstrated/refuted
#    remain unreachable at n=2. The MDE is read from the ARTIFACT (never hardcoded).
# ---------------------------------------------------------------------------
# The mde value comes from the FROZEN pre-registration artifact (cross-task-variance noise).
PREREG_ARTIFACT="metrics/pre-registration-council-measurement-run.json"
MDE_VALUE="$(env -i PATH="$PATH" python3 - "$PREREG_ARTIFACT" <<'PY' 2>&1
import json, sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["mde"])
PY
)"
assert "REQ-MR-007 the frozen artifact carries a positive numeric MDE (read, not hardcoded)" \
  "env -i PATH=\"$PATH\" python3 -c \"import sys; v=float(sys.argv[1]); sys.exit(0 if v>0 else 1)\" \"$MDE_VALUE\""
# Build a pre-registration that carries the EXACT mde read from the artifact.
env -i PATH="$PATH" MDE="$MDE_VALUE" python3 - "$WORK/prereg_mde.json" <<'PY' 2>&1
import json, os, sys
prereg = {"frozen_at": "2026-06-20T00:00:00Z", "n": 2, "min_survivors": 2,
          "mde": float(os.environ["MDE"]), "noise_model": "cross-task-variance",
          "rubric": "pilot-n2"}
json.dump(prereg, open(sys.argv[1], "w", encoding="utf-8"))
PY

# (a) FALSIFYING: survivors==2 (>= min) but Arm-A and Arm-B produce IDENTICAL flag-sets ->
#     catch delta == 0 (BELOW the positive MDE) -> outcome MUST be "underpowered".
#     (Current code checks only survivors -> emits "tradeoff-signal-to-investigate" -> RED now.)
INJ_A_IDENT="$(env -i PATH="$PATH" python3 - "$PROTO_OK" <<'PY' 2>&1
import json, sys
p = sys.argv[1]
print(json.dumps({"T1-auth-token": p, "T2-pagination": p}))
PY
)"
INJ_B_IDENT="$(env -i PATH="$PATH" python3 - "$PROTO_OK" <<'PY' 2>&1
import json, sys
p = sys.argv[1]
role = {"role": "Pruefer", "model": "openai/gpt-4o", "code": "COUNCIL_INFERENCE_OK", "position": p}
print(json.dumps({"T1-auth-token": [role], "T2-pagination": [role]}))
PY
)"
MDE_ZERO="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
             --pre-registration "$WORK/prereg_mde.json" \
             --inject-arm-a "$INJ_A_IDENT" --inject-arm-b "$INJ_B_IDENT" \
             --inject-call-counter "$WORK/c_mde0" --json 2>&1)"
assert_json_eq "REQ-MR-007 identical flag-sets -> survivors >= min holds (numeric, isolates the MDE check)" \
  "$MDE_ZERO" 'd.get("survivors")==2 and d.get("survivors")>=d.get("min_survivors")' True
assert_json_eq "REQ-MR-007 MDE: a catch delta of 0 (below MDE) with survivors >= min -> outcome underpowered" \
  "$MDE_ZERO" 'd.get("outcome")=="underpowered"' True
assert_json_eq "REQ-MR-007 MDE: a below-MDE delta is NEVER laundered as tradeoff-signal-to-investigate" \
  "$MDE_ZERO" 'd.get("outcome")!="tradeoff-signal-to-investigate"' True

# (b) Catch delta ABOVE the MDE (council catches both seeded defects -> 1.0; claude catches
#     none -> 0.0; delta 1.0 > MDE) WITH cry-wolf UP for claude (false flags at clean
#     controls) -> stays "tradeoff-signal-to-investigate" (a real catch-vs-cry-wolf trade).
INJ_B_CATCH="$(env -i PATH="$PATH" python3 - <<'PY' 2>&1
import json
t1 = json.dumps({"flags": [{"file": "auth/token.py", "line": 17, "description": "timing side channel"}]})
t2 = json.dumps({"flags": [{"file": "api/list.py", "line": 25, "description": "resource exhaustion"},
                           {"file": "api/list.py", "line": 36, "description": "unhandled exception"}]})
r1 = {"role": "Pruefer", "model": "openai/gpt-4o", "code": "COUNCIL_INFERENCE_OK", "position": t1}
r2 = {"role": "Pruefer", "model": "openai/gpt-4o", "code": "COUNCIL_INFERENCE_OK", "position": t2}
print(json.dumps({"T1-auth-token": [r1], "T2-pagination": [r2]}))
PY
)"
INJ_A_CRYWOLF="$(env -i PATH="$PATH" python3 - <<'PY' 2>&1
import json
t1 = json.dumps({"flags": [{"file": "auth/token.py", "line": 20, "description": "false flag at clean control"}]})
t2 = json.dumps({"flags": [{"file": "api/list.py", "line": 40, "description": "false flag at clean control"}]})
print(json.dumps({"T1-auth-token": t1, "T2-pagination": t2}))
PY
)"
MDE_ABOVE="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
              --pre-registration "$WORK/prereg_mde.json" \
              --inject-arm-a "$INJ_A_CRYWOLF" --inject-arm-b "$INJ_B_CATCH" \
              --inject-call-counter "$WORK/c_mdeabove" --json 2>&1)"
assert_json_eq "REQ-MR-007 MDE: scenario actually exercises an above-MDE catch delta (council 1.0 vs claude 0.0)" \
  "$MDE_ABOVE" 'sorted(r["review_catch_rate"] for r in d["records"] if r.get("arm")=="council-A")==[1.0,1.0] and sorted(r["review_catch_rate"] for r in d["records"] if r.get("arm")=="claude-only")==[0.0,0.0]' True
assert_json_eq "REQ-MR-007 MDE: cry-wolf is UP for claude-only (false flags at clean controls)" \
  "$MDE_ABOVE" 'all(r["review_cry_wolf_rate"]>0.0 for r in d["records"] if r.get("arm")=="claude-only")' True
assert_json_eq "REQ-MR-007 MDE: an above-MDE delta with cry-wolf up -> tradeoff-signal-to-investigate" \
  "$MDE_ABOVE" 'd.get("outcome")=="tradeoff-signal-to-investigate"' True
assert_json_eq "REQ-MR-007 MDE: demonstrated/refuted remain unreachable at n=2 even above the MDE" \
  "$MDE_ABOVE" 'd.get("outcome") not in ("demonstrated","refuted")' True

# ===========================================================================
# 6. emit_run ROUND-TRIP via the REAL emit_run.py (REQ-MR-006)
#    These: "results are emitted." Gegenthese: review metrics at the TOP LEVEL -> emit_run
#    rejects non-allowlisted --metrics keys and process_health reads only metrics.<name>,
#    so a wrong shape silently breaks the pipeline. Schaerfung: per-arm results route
#    through the REAL emit_run.py --raw; review metrics land under record.raw, NONE top-level,
#    corpus_id top-level; both metric families + n/scope/arm present together; process_health
#    reads the runs.jsonl without crashing.
# ===========================================================================
RUNS_OUT="$WORK/runs.jsonl"   # staged OUTSIDE the repo tree (bench isolation)
mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
   --pre-registration "$WORK/prereg_pilot.json" \
   --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_BOTHOK" \
   --out "$RUNS_OUT" --inject-call-counter "$WORK/c_emit" --json >/dev/null 2>&1
assert "REQ-MR-006 the orchestrator wrote runs.jsonl outside the tree (emit_run round-trip)" "[ -s \"$RUNS_OUT\" ]"
# Inspect the emitted records via the REAL emit_run schema (record.raw vs top-level).
EMITCHK="$(env -i PATH="$PATH" python3 - "$RUNS_OUT" <<'PY' 2>&1
import json, sys
recs = [json.loads(l) for l in open(sys.argv[1]) if l.strip()]
def has_raw(r, k): return k in r.get("raw", {})
out = {
  "n_records": len(recs),
  "all_corpus_top": all(r.get("corpus_id")=="council-review-catch-v1" for r in recs),
  "catch_in_raw": all(has_raw(r,"review_catch_rate") for r in recs),
  "crywolf_in_raw": all(has_raw(r,"review_cry_wolf_rate") for r in recs),
  "recall_in_raw": all(has_raw(r,"review_recall_control") for r in recs),
  "n_in_raw": all(has_raw(r,"n") for r in recs),
  "arm_in_raw": all(has_raw(r,"arm") for r in recs),
  "scope_in_raw": all(has_raw(r,"model_scope") for r in recs),
  "none_top_level": all(("review_catch_rate" not in r and "arm" not in r and "model_scope" not in r) for r in recs),
  "metrics_no_review_key": all(all(k not in r.get("metrics",{}) for k in ("review_catch_rate","review_cry_wolf_rate","review_recall_control")) for r in recs),
}
print(json.dumps(out, sort_keys=True))
PY
)"
assert_json_eq "REQ-MR-006 at least 2 surviving records emitted (>= 2 arms x >= 1 surviving task)" \
  "$EMITCHK" 'd["n_records"]>=2' True
assert_json_eq "REQ-MR-006 every record carries corpus_id top-level == council-review-catch-v1" \
  "$EMITCHK" 'd["all_corpus_top"] is True' True
assert_json_eq "REQ-MR-006 review_catch_rate lands under record.raw" "$EMITCHK" 'd["catch_in_raw"] is True' True
assert_json_eq "REQ-MR-006 BOTH metric families present together under raw (cry-wolf + recall)" \
  "$EMITCHK" 'd["crywolf_in_raw"] is True and d["recall_in_raw"] is True' True
assert_json_eq "REQ-MR-006 n + arm + model_scope all present under raw (scope visible)" \
  "$EMITCHK" 'd["n_in_raw"] is True and d["arm_in_raw"] is True and d["scope_in_raw"] is True' True
assert_json_eq "REQ-MR-006 NONE of review_catch_rate/arm/model_scope appear top-level" \
  "$EMITCHK" 'd["none_top_level"] is True' True
assert_json_eq "REQ-MR-006 no review key smuggled into the allowlisted metrics block" \
  "$EMITCHK" 'd["metrics_no_review_key"] is True' True
# process_health reads the assembled runs.jsonl without crashing.
assert "REQ-MR-006 process_health reads the emitted runs.jsonl without crashing" \
  "env -i PATH=\"$PATH\" python3 \"$PH\" --runs \"$RUNS_OUT\" --out \"$WORK/ph.md\" >/dev/null 2>&1"

# ===========================================================================
# 7. FOREIGN-ONLY AT RUN TIME (REQ-MR-004 / RISK-MR-004)
#    These: "Arm B is the foreign council." Gegenthese: a Claude/anthropic id leaks into
#    Arm B and the delta becomes partly Claude-vs-Claude, uninterpretable. Schaerfung:
#    an Arm-B role carrying an anthropic/claude id -> the subject is REJECTED (not scored
#    as a council result); the result records arm identity. Reuses the scorer's
#    foreign_only_ok contract (a council record must carry foreign_only_ok == false here).
# ===========================================================================
INJ_B_CLAUDE="$(env -i PATH="$PATH" python3 - "$PROTO_OK" <<'PY' 2>&1
import json, sys
p = sys.argv[1]
role = {"role": "Pruefer", "model": "anthropic/claude-3-opus", "code": "COUNCIL_INFERENCE_OK", "position": p}
print(json.dumps({"T1-auth-token": [role], "T2-pagination": [role]}))
PY
)"
mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
   --pre-registration "$WORK/prereg_pilot.json" \
   --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_CLAUDE" \
   --out "$WORK/runs_claude.jsonl" --inject-call-counter "$WORK/c_claude" --json >/dev/null 2>&1
RC_CLAUDE=$?
assert "REQ-MR-004 Claude-contaminated Arm B -> run fails closed for that subject (non-zero exit)" "[ $RC_CLAUDE -ne 0 ]"
# Whatever it emits, NO contaminated council record may be written as a valid (foreign_only_ok true) result.
CLAUDECHK="$(env -i PATH="$PATH" python3 - "$WORK/runs_claude.jsonl" <<'PY' 2>&1
import json, os, sys
path = sys.argv[1]
recs = [json.loads(l) for l in open(path)] if os.path.isfile(path) else []
council = [r for r in recs if r.get("raw",{}).get("arm")=="council-A"]
# A council record that slipped through MUST be flagged foreign_only_ok == False (rejected),
# never true. (If the run refused before emitting, the list is empty -> also acceptable.)
ok = all(r.get("raw",{}).get("foreign_only_ok") is False for r in council)
print(json.dumps({"council_records": len(council), "all_flagged_false": ok}, sort_keys=True))
PY
)"
assert_json_eq "REQ-MR-004 no contaminated council record is emitted as a valid (foreign_only_ok true) result" \
  "$CLAUDECHK" 'd["council_records"]==0 or d["all_flagged_false"] is True' True

# ===========================================================================
# 8. INSTRUMENT READ-ONLY + Arm-A real boundary via DIRECT run_inference (REQ-MR-009 / REQ-MR-005)
#    These: "3b consumes the instrument." Gegenthese: the orchestrator edits the read-only
#    runner/scorer/instrument (Goodhart: measuring an instrument you tune), OR it reaches
#    Arm A's real boundary by editing the frozen arm_a_review_runner.py instead of calling
#    run_inference directly (the resolved REQ-MR-005-vs-009 contradiction). Schaerfung:
#    (a) the four read-only files are BYTE-UNCHANGED after a run; (b) the corpus freeze-hash
#    still equals manifest.json hash; (c) the orchestrator's OWN source calls
#    council_inference.run_inference (the symmetric Arm-A real boundary) and does NOT import-
#    and-mutate the read-only runner.
# ===========================================================================
# (a) Byte-unchanged read-only files after the runs above (git diff empty over them).
assert "REQ-MR-009 arm_a_review_runner.py is byte-unchanged after the run (git diff empty)" \
  "git diff --quiet -- \"$ARMA\""
assert "REQ-MR-009 council_review_scorer.py is byte-unchanged after the run" \
  "git diff --quiet -- \"$SCORER\""
assert "REQ-MR-009 council_inference.py is byte-unchanged after the run" \
  "git diff --quiet -- \"$INFER\""
assert "REQ-MR-009 council_presets.py is byte-unchanged after the run" \
  "git diff --quiet -- \"$PRESETS\""
assert "REQ-MR-009 council_backend.py is byte-unchanged after the run" \
  "git diff --quiet -- \"$BACKEND\""
assert "REQ-MR-009 deepseek_review.py is byte-unchanged after the run" \
  "git diff --quiet -- \"$DEEPSEEK\""
assert "REQ-MR-009 the consumed corpus is byte-unchanged after the run" \
  "git diff --quiet -- \"$CORPUS\""
# (b) Corpus freeze-hash still equals the manifest hash (corpus consumed, not mutated).
FREEZE="$(env -i PATH="$PATH" python3 "$SCORER" freeze-hash --corpus "$CORPUS" 2>&1)"
MANHASH="$(python3 -c 'import json;print(json.load(open("metrics/corpus/council-review-catch-v1/manifest.json"))["hash"])')"
assert_eq "REQ-MR-003 corpus freeze-hash equals manifest hash (consumed, not mutated)" "$MANHASH" "$FREEZE"
# (c) The orchestrator reaches Arm A's real boundary by calling run_inference DIRECTLY,
#     and does NOT add a transport of its OWN. The real invariant (NOT "the literal
#     _real_transport never appears"): the module DEFINES no transport and imports no http
#     -- i.e. NO `def _real_transport`, NO `import urllib`, NO `urlopen(`. A PLAIN reference
#     `council_inference._real_transport` (CONSUMING the read-only instrument's gated
#     transport for Arm A's live boundary, REQ-MR-005) IS allowed -- forbidding the bare
#     reference only forces a getattr obfuscation (test-gaming), it proves nothing.
assert "REQ-MR-005 orchestrator source calls council_inference.run_inference directly (Arm-A real boundary)" \
  "grep -nE 'run_inference' \"$RUNNER\""
# Real-invariant check (AST/source, eval-free, file by path): the module must DEFINE no
# transport and IMPORT no http; consuming the instrument's _real_transport by plain
# reference is permitted. Fails closed on a parse error.
# shellcheck disable=SC2034  # DEFCHK is consumed inside the assert condition strings below
DEFCHK="$(env -i PATH="$PATH" python3 - "$RUNNER" <<'PY' 2>&1
import ast, sys
src = open(sys.argv[1], encoding="utf-8").read()
tree = ast.parse(src)
defines_transport = any(
    isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == "_real_transport"
    for n in ast.walk(tree))
imports_http = False
for n in ast.walk(tree):
    if isinstance(n, ast.Import):
        if any(a.name.split(".")[0] in ("urllib", "http", "requests") for a in n.names):
            imports_http = True
    elif isinstance(n, ast.ImportFrom):
        root = (n.module or "").split(".")[0]
        if root in ("urllib", "http", "requests"):
            imports_http = True
# urlopen( as a CALL anywhere (own-transport tell), via the unparsed source token stream.
calls_urlopen = any(
    isinstance(n, ast.Call) and (
        (isinstance(n.func, ast.Name) and n.func.id == "urlopen") or
        (isinstance(n.func, ast.Attribute) and n.func.attr == "urlopen"))
    for n in ast.walk(tree))
print("DEF" if defines_transport else "nodef")
print("IMP" if imports_http else "noimp")
print("URL" if calls_urlopen else "nourl")
PY
)"
assert "REQ-MR-005 orchestrator DEFINES no transport of its own (no def _real_transport)" \
  "printf '%s\n' \"\$DEFCHK\" | grep -qx 'nodef'"
assert "REQ-MR-005 orchestrator IMPORTS no http transport (no import urllib/http/requests)" \
  "printf '%s\n' \"\$DEFCHK\" | grep -qx 'noimp'"
assert "REQ-MR-005 orchestrator calls NO urlopen of its own (no own-transport call)" \
  "printf '%s\n' \"\$DEFCHK\" | grep -qx 'nourl'"
assert "REQ-MR-009 orchestrator does NOT call into the dead Arm-A live path (no arm_a_review_runner _cmd_review edit)" \
  "! grep -nE '_cmd_review' \"$RUNNER\""

# ===========================================================================
# 9. SECURITY N1/N2/N3 (REQ-MR-011 / NFR-MR-001)
#    These: "the harness reads inputs + writes records." Gegenthese: a traversal @path
#    reads an arbitrary file; an OSError on the runs.jsonl write is silently swallowed
#    (hiding a partial emission); a malformed injected response fabricates a flag; a real
#    key leaks into output. Schaerfung: (N1) an @path outside the work dir is refused;
#    (N2) an unwritable --out surfaces the error (non-zero / explicit), never swallowed;
#    (leak) no key material in any output; a malformed injected response classifies, never
#    fabricates a flag.
# ===========================================================================
# (N1) An @path inject pointing OUTSIDE the designated work dir is refused (confined).
mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
   --inject-arm-a "@/etc/passwd" --inject-arm-b "{}" \
   --inject-call-counter "$WORK/c_traverse" --json >/dev/null 2>&1
RC_TRAV=$?
assert "REQ-MR-011 N1 @path outside the work dir is REFUSED (non-zero, confined; no arbitrary read)" "[ $RC_TRAV -ne 0 ]"
# And the refusal must not echo any /etc/passwd content (no arbitrary-file leak into output).
TRAVOUT="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
            --inject-arm-a "@/etc/passwd" --inject-arm-b "{}" \
            --inject-call-counter "$WORK/c_traverse2" --json 2>&1)"
assert_not_contains "REQ-MR-011 N1 refusal leaks NO /etc/passwd content (root: marker absent)" "$TRAVOUT" "root:x:0:0"

# (N2) An unwritable --out surfaces the OSError (non-zero / explicit), never silently swallowed.
mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
   --pre-registration "$WORK/prereg_pilot.json" \
   --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_BOTHOK" \
   --out "/proc/nonexistent-dir/runs.jsonl" --inject-call-counter "$WORK/c_oserr" --json >/dev/null 2>&1
RC_OSERR=$?
assert "REQ-MR-011 N2 an unwritable --out surfaces the error (non-zero exit, not silently swallowed)" "[ $RC_OSERR -ne 0 ]"

# (leak) No API key material in any output. Run with a sentinel key in env; --json output
# (offline, gate OFF) must NEVER echo it.
LEAKOUT="$(env -i PATH="$PATH" OPENROUTER_API_KEY="sk-or-LEAK-SENTINEL-DEADBEEF" python3 "$RUNNER" run \
            --corpus "$CORPUS" --preset A --claude-model test-tier \
            --pre-registration "$WORK/prereg_pilot.json" \
            --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_BOTHOK" \
            --out "$WORK/runs_leak.jsonl" --inject-call-counter "$WORK/c_leak" --json 2>&1)"
assert_not_contains "NFR-MR-001 no API key material appears in the --json output" "$LEAKOUT" "sk-or-LEAK-SENTINEL-DEADBEEF"
assert_not_contains "NFR-MR-001 no API key material appears in the emitted runs.jsonl" "$(cat "$WORK/runs_leak.jsonl" 2>/dev/null)" "sk-or-LEAK-SENTINEL-DEADBEEF"

# (N3 / never-fabricate) A malformed injected Arm-A response classifies to an EMPTY flag-set
#  -> the scored claude-only record has catch 0.0 (a real miss), NEVER a fabricated flag.
INJ_A_MALFORMED="$(env -i PATH="$PATH" python3 - "$PROTO_MALFORMED" <<'PY' 2>&1
import json, sys
bad = sys.argv[1]
print(json.dumps({"T1-auth-token": bad, "T2-pagination": bad}))
PY
)"
MALF="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
         --pre-registration "$WORK/prereg_pilot.json" \
         --inject-arm-a "$INJ_A_MALFORMED" --inject-arm-b "$INJ_B_BOTHOK" \
         --out "$WORK/runs_malf.jsonl" --inject-call-counter "$WORK/c_malf" --json 2>&1)"
assert_json_eq "REQ-MR-011 malformed Arm-A output -> claude-only catch is exactly 0.0 (no fabricated flag)" \
  "$MALF" '[r["review_catch_rate"] for r in d["records"] if r.get("arm")=="claude-only"][0]==0.0' True

# ===========================================================================
# 10. OFFLINE FULL-LOOP DETERMINISM + ISOLATION (REQ-MR-001 / REQ-MR-008 / NFR-MR-002/004)
#    These: "the loop runs offline." Gegenthese: a non-deterministic primary score, or a
#    run that pollutes the tree. Schaerfung: the full per-task arm->scorer->emit loop runs
#    OFFLINE (0 calls), is numerically identical on re-run over the same injected inputs,
#    and leaves the repo tree byte-unchanged (git status clean over tracked files).
# ===========================================================================
mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
   --pre-registration "$WORK/prereg_pilot.json" \
   --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_BOTHOK" \
   --out "$WORK/runs_det1.jsonl" --inject-call-counter "$WORK/c_det1" --json >/dev/null 2>&1
mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
   --pre-registration "$WORK/prereg_pilot.json" \
   --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_BOTHOK" \
   --out "$WORK/runs_det2.jsonl" --inject-call-counter "$WORK/c_det2" --json >/dev/null 2>&1
# Compare the per-arm metric tuples (deterministic, numeric equality), independent of run_id.
DET="$(env -i PATH="$PATH" python3 - "$WORK/runs_det1.jsonl" "$WORK/runs_det2.jsonl" <<'PY' 2>&1
import json, sys
def metrics(path):
    out = []
    for l in open(path):
        if not l.strip(): continue
        r = json.loads(l); raw = r.get("raw", {})
        out.append((raw.get("arm"), raw.get("review_catch_rate"),
                    raw.get("review_cry_wolf_rate"), raw.get("review_recall_control")))
    return sorted(out, key=lambda t: (str(t[0]),))
a, b = metrics(sys.argv[1]), metrics(sys.argv[2])
print(json.dumps({"equal": a==b, "n": len(a)}, sort_keys=True))
PY
)"
assert_json_eq "NFR-MR-002 the primary score is deterministic: identical numbers on re-run (numeric equality)" \
  "$DET" 'd["equal"] is True and d["n"]>=2' True
assert "REQ-MR-008 offline determinism run fired 0 transport calls" "[ \"\$(cat \"$WORK/c_det1\" 2>/dev/null)\" = \"0\" ]"
# Isolation (REQ-MR-008/009): the consumed substrate + instrument + corpus are byte-unchanged
# after every offline run above. (run_all.sh and this test file are legitimately edited by the
# 3b change, so the isolation assertion is SCOPED to the read-only consumed paths, not the
# whole tree.) Also: no NEW untracked file landed under the corpus/metrics-script tree.
assert "NFR-MR-004 the consumed substrate + instrument + corpus are byte-unchanged (git diff empty over read-only paths)" \
  "git diff --quiet -- \"$ARMA\" \"$SCORER\" \"$DEEPSEEK\" \"$PRESETS\" \"$INFER\" \"$BACKEND\" \"$CORPUS\""
assert "REQ-MR-008 no stray untracked file landed under the corpus tree (no bench pollution)" \
  "[ -z \"\$(git status --porcelain -- \"$CORPUS\")\" ]"

# ===========================================================================
# 11. CORPUS-FREEZE INTEGRITY (security Note 1 — REQ-MR-003 / REQ-MR-007)
#    These: "the frozen pre-registration carries a corpus_hash." Gegenthese: the artifact
#    records corpus_hash but the orchestrator NEVER validates it against the loaded corpus,
#    so a scored run against a DIFFERENT corpus than the one the pass/fail line was frozen
#    over is laundered as a real result — the pre-registration discipline (judged against the
#    frozen file, never moved after seeing results) is silently defeated by swapping the
#    corpus underneath it. Schaerfung: a --score run whose pre-registration carries a WRONG
#    corpus_hash MUST FAIL CLOSED (non-zero exit, classified corpus_hash error) BEFORE
#    producing ANY outcome; paired green guard — the REAL corpus_hash (the byte-identical
#    frozen artifact, copied to a temp path so ONLY the hash field differs between the two
#    runs) does NOT trip the refusal and proceeds to an outcome — so the check is the hash
#    MATCH, not a blanket refusal of every pre-registration. OFFLINE (0 calls): the live gate
#    is never armed and offline injects are supplied, so 0 real calls can happen either way.
# ===========================================================================
# Build a WRONG-hash pre-registration: byte-identical to the real frozen artifact EXCEPT
# corpus_hash, deliberately set to a value that cannot match the corpus freeze-hash.
env -i PATH="$PATH" python3 - "$PREREG_ARTIFACT" "$WORK/prereg_badhash.json" <<'PY' 2>&1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
d["corpus_hash"] = "sha256:deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"))
PY
# Build a CORRECT-hash pre-registration: a verbatim copy of the real frozen artifact to a
# temp path, so the ONLY difference between the two runs is the corpus_hash field value.
env -i PATH="$PATH" python3 - "$PREREG_ARTIFACT" "$WORK/prereg_goodhash.json" <<'PY' 2>&1
import json, sys
d = json.load(open(sys.argv[1], encoding="utf-8"))
json.dump(d, open(sys.argv[2], "w", encoding="utf-8"))
PY

# (a) FALSIFYING: a --score run with a MISMATCHED corpus_hash must FAIL CLOSED (non-zero exit)
#     before producing an outcome. (Pre-fix: no validation -> proceeds, exit 0 -> RED.)
BADHASH="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
            --pre-registration "$WORK/prereg_badhash.json" --score \
            --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_BOTHOK" \
            --inject-call-counter "$WORK/c_badhash" --json 2>&1)"
RC_BADHASH=$?
assert "REQ-MR-003 mismatched corpus_hash -> --score REFUSES (non-zero exit, fail-closed)" \
  "[ $RC_BADHASH -ne 0 ]"
# The refusal must be a CLASSIFIED corpus_hash error AND must NOT have produced an outcome
# (refused BEFORE scoring, never a laundered result).
assert_contains "REQ-MR-003 mismatched corpus_hash refusal is a classified corpus_hash error" \
  "$BADHASH" "corpus_hash mismatch"
assert_json_eq "REQ-MR-003 mismatched corpus_hash produces NO outcome (refused before scoring)" \
  "$BADHASH" '"outcome" not in d' True
# Offline: even with the mismatch, 0 real transport calls fire (counter 0 or unwritten).
assert "REQ-MR-003 corpus_hash mismatch refusal attempts 0 transport calls (counter 0 or unwritten)" \
  "[ ! -s \"$WORK/c_badhash\" ] || [ \"\$(cat \"$WORK/c_badhash\")\" = \"0\" ]"

# (b) GREEN GUARD: the CORRECT corpus_hash (verbatim frozen artifact) does NOT trip the
#     refusal -> the run proceeds to a classified outcome (exit 0). Proves the check is the
#     hash MATCH, not a blanket refusal of every scored pre-registration.
GOODHASH="$(mr run --corpus "$CORPUS" --preset A --claude-model test-tier \
             --pre-registration "$WORK/prereg_goodhash.json" --score \
             --inject-arm-a "$INJ_A_EMPTY" --inject-arm-b "$INJ_B_BOTHOK" \
             --inject-call-counter "$WORK/c_goodhash" --json 2>&1)"
RC_GOODHASH=$?
assert "REQ-MR-003 matching corpus_hash does NOT trip the refusal (--score proceeds, exit 0)" \
  "[ $RC_GOODHASH -eq 0 ]"
assert_json_eq "REQ-MR-003 matching corpus_hash proceeds to a reachable pilot outcome (not a blanket refusal)" \
  "$GOODHASH" 'd.get("outcome") in ("underpowered","tradeoff-signal-to-investigate")' True

finish "Council measurement-run orchestrator (Slice 3b)"

# ===========================================================================
# CONTRACT DECISIONS for the planner/coder (this test file is the source of truth):
# ---------------------------------------------------------------------------
# C1. Module path: config/claude/metrics/council_measurement_run.py (canvas-scoped). It is
#     the ONLY new code module and consumes the read-only instrument; it MUST NOT edit any
#     of arm_a_review_runner / council_review_scorer / deepseek_review / council_inference /
#     council_presets / council_backend, nor the corpus (section 8 asserts byte-unchanged).
# C2. Import API the tests bind to (the coder MUST expose these):
#       parse_arm_output(raw_text: str, *, arm: str) -> (flags: list, code: str)
#         -- the SINGLE shared parser entrypoint used for BOTH arms; it MUST delegate to
#            arm_a_review_runner.parse_flag_set so both arms are parsed identically (REQ-MR-002).
#     The CLI `run` subcommand owns the orchestration + emission + classification.
# C3. CLI flags the tests drive (stable contract):
#       --corpus --preset --claude-model --pre-registration --max-calls --live --json --out
#       --inject-arm-a <json|@file>  --inject-arm-b <json|@file>  --inject-call-counter <file>
#       --score (force the scored-run path; the run also scores when --pre-registration is given)
# C4. Injection shapes are keyed by corpus task id (see header). Arm-A value = raw model output
#     (string). Arm-B value = list of role dicts mirroring deepseek_review preset positions[]
#     {role, model, code, position}. COUNCIL_INFERENCE_OK is the only OK code; any other code
#     is non-OK -> PAIRED-EXCLUSION.
# C5. `run --json` result top-level keys the tests read: outcome, records[], attrition[],
#     survivors, min_survivors, calls_attempted, arm_a_subject_protocol, arm_b_subject_protocol.
#     Each records[] entry: arm, task, review_catch_rate, review_cry_wolf_rate,
#     review_recall_control, n, task_count, foreign_only_ok, model_scope.
# C6. Outcome strings (the classifier's closed vocabulary at n=2): "underpowered" and
#     "tradeoff-signal-to-investigate" ONLY. "demonstrated"/"refuted" are unreachable at n=2.
# C7. min_survivors is read from the frozen pre-registration artifact (min_survivors key).
#     Below it -> outcome forced to the EXACT string "underpowered".
# C8. Emission routes through the REAL emit_run.py --raw (review metrics under raw, corpus_id
#     top-level via --corpus-id). NO review key may enter the allowlisted --metrics block.
# C9. Live gate: real calls ONLY when --live AND COUNCIL_INFERENCE_LIVE=1 AND --max-calls N.
#     --live without --max-calls REFUSES (non-zero). Default + offline-injected = 0 calls.
#     Arm-A real boundary is reached by calling council_inference.run_inference DIRECTLY
#     (NOT by editing the read-only runner) -- the LIVE smoke itself is out of this offline
#     suite (the spec's real-boundary-smoke for THAT run; this suite proves gate-OFF + wiring).
# C10. Security: @path injects confined to the work dir (N1); OSError on the runs.jsonl write
#     surfaced, never swallowed (N2); strict parser, no fabricated flag on malformed input;
#     no key material in any output (NFR-MR-001).
# ===========================================================================
