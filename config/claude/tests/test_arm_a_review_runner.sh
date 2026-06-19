#!/usr/bin/env bash
set -u
#
# Phase-1 BLACK-BOX acceptance contract for Slice 3a artifact (2):
#   the Arm-A (Claude-only) review RUNNER   config/claude/metrics/arm_a_review_runner.py
#
# Written BEFORE any implementation exists (TDD RED). RED NOW because the module
# is absent. These tests ARE the contract.
#
# Spec sources (frozen, user-confirmed Ben 2026-06-19):
#   docs/prd/council-diversity-measurement.prd.md     (REQ-DM-3a-002; NGOAL-DM-001; BLOCKER-3)
#   docs/canvas/council-diversity-measurement.canvas.md (ART-3a-2)
#   config/claude/lib/deepseek_review.py              (the injected-transport offline seam
#                                                      pattern: --inject-response /
#                                                      --inject-call-counter; --live gate)
#
# ===========================================================================
# SEAM / CLI CONTRACT THE CODER MUST IMPLEMENT (derived independently from spec)
# ===========================================================================
# A SEPARATE entrypoint (NOT an edit to the read-only instrument) — a deterministic,
# NETWORK-FREE, KEY-FREE Python module with an argparse CLI mirroring the deepseek
# offline seams:
#
#   python3 config/claude/metrics/arm_a_review_runner.py review \
#       --task <corpus-task-dir>  --model-scope <claude-tier> \
#       --inject-response <text|@file>  --inject-call-counter <path>  --json
#
# Behaviour the contract pins:
#  * Builds a Claude-only review prompt over the task diff in the STRUCTURED FLAG
#    PROTOCOL (the reviewer is instructed to emit each finding as a machine-parseable
#    {file, line, description}) — so the scorer's deterministic location-overlap
#    matcher (OQ-DM-7) can consume it.
#  * Parses a model RESPONSE into a flag-set: a list of {file, line, description}.
#    The output flag-set is the EXACT schema council_review_scorer consumes.
#  * Offline via an injected response (0 credits, 0 network); a call counter written
#    to --inject-call-counter MUST read 0 (no transport fired) on the offline path.
#  * A malformed / no-flags response classifies to an EMPTY flag-set — NEVER a
#    fabricated flag (the looks-measured-but-isn't failure).
#  * The live path is GATED OFF by default (mirrors deepseek: --live AND an env gate);
#    without the gate the runner makes ZERO network calls.
#  * It does NOT import-and-mutate the read-only instrument libs.
# ===========================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

RUNNER="config/claude/metrics/arm_a_review_runner.py"
INSTRUMENT_LIB="config/claude/lib/deepseek_review.py"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A minimal fixture task dir (the runner reads the diff; the corpus is a separate
# artifact — here we stage a throwaway task OUTSIDE the corpus tree, per RISK-DM-007).
TASK="$WORK/task-fixture"
mkdir -p "$TASK"
printf '%s\n' "--- a/svc.py" "+++ b/svc.py" "@@ -10,3 +10,4 @@" "+    return total  # off-by-one" > "$TASK/diff.patch"

# Run the runner hermetically: no real key in env (env -i), offline.
arma() { env -i PATH="$PATH" python3 "$RUNNER" "$@" 2>&1; }

printf 'Arm-A (Claude-only) review runner — Phase-1 contract (RED until built)\n'

# ===========================================================================
# 0. PRESENCE — drives RED.
# ===========================================================================
assert_file "REQ-DM-3a-002 arm-a runner module exists" "$RUNNER"

# ===========================================================================
# 1. STRUCTURED-FLAG-PROTOCOL PROMPT  (REQ-DM-3a-002; OQ-DM-7)
#    These: "the runner builds a prompt." Gegenthese: a free-text prompt yields
#    findings the deterministic matcher cannot parse → the primary catch metric is
#    un-scorable / judge-dependent. Schärfung: the built prompt MUST instruct the
#    structured flag protocol (file + line + description per finding) and embed the
#    task diff. The runner exposes `build-prompt` to disclose what WOULD be sent.
# ===========================================================================
# Require valid JSON with a `prompt` field, then assert the protocol literals live
# INSIDE that prompt text — so an absent-module error string can never false-pass.
PROMPT="$(arma build-prompt --task "$TASK" --model-scope opus-tier --json)"
assert_json_eq "REQ-DM-3a-002 build-prompt emits valid JSON carrying a prompt field" "$PROMPT" 'isinstance(d.get("prompt"),str) and bool(d["prompt"])' True
PROMPT_TEXT="$(printf '%s' "$PROMPT" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("prompt",""))' 2>/dev/null)"
assert_contains "REQ-DM-3a-002 prompt instructs the structured flag protocol (file)" "$PROMPT_TEXT" "file"
assert_contains "REQ-DM-3a-002 prompt instructs the structured flag protocol (line)" "$PROMPT_TEXT" "line"
assert_contains "REQ-DM-3a-002 prompt instructs the structured flag protocol (description)" "$PROMPT_TEXT" "description"
assert_contains "REQ-DM-3a-002 prompt embeds the task diff under review" "$PROMPT_TEXT" "off-by-one"
assert_contains "REQ-DM-3a-002 prompt discloses the Arm-A model scope" "$PROMPT_TEXT" "opus-tier"

# ===========================================================================
# 2. RESPONSE -> FLAG-SET PARSING  (REQ-DM-3a-002; the scorer's input schema)
#    These: "the runner returns flags." Gegenthese: a parser that fabricates or
#    drops the file/line makes the scorer's location-overlap meaningless. Schärfung:
#    feed a structured response, assert the EXACT parsed flag fields, and assert the
#    flag-set carries arm + model_scope (the scope-visible requirement, REQ-DM-3a-002).
# ===========================================================================
# A structured model response: two findings in the protocol the prompt requested.
RESP='{"flags":[{"file":"svc.py","line":13,"description":"off-by-one in total"},{"file":"svc.py","line":20,"description":"missing guard"}]}'
printf '%s' "$RESP" > "$WORK/resp.json"
FLAGSET="$(arma review --task "$TASK" --model-scope opus-tier --inject-response "@$WORK/resp.json" --inject-call-counter "$WORK/calls" --json)"
assert_contains "REQ-DM-3a-002 parsed flag carries file svc.py" "$FLAGSET" '"file": "svc.py"'
assert_contains "REQ-DM-3a-002 parsed flag carries line 13" "$FLAGSET" '"line": 13'
assert_contains "REQ-DM-3a-002 parsed flag carries the description" "$FLAGSET" "off-by-one in total"
assert_json_eq "REQ-DM-3a-002 flag-set has exactly 2 flags" "$FLAGSET" 'len(d["flags"])==2' True
assert_contains "REQ-DM-3a-002 flag-set discloses arm=claude-only" "$FLAGSET" '"arm": "claude-only"'
assert_contains "REQ-DM-3a-002 flag-set discloses model_scope" "$FLAGSET" "opus-tier"

# ===========================================================================
# 3. OFFLINE ISOLATION — ZERO network calls via the counter (REQ-DM-3a-002/006)
#    These: "it ran offline." Gegenthese: a runner could quietly hit the network
#    even with an injected response (the Slice-1 dead-seam class). Schärfung: assert
#    the call counter the runner wrote reads EXACTLY 0 on the injected path.
# ===========================================================================
assert "REQ-DM-3a-006 injected-response path fires ZERO transport calls (counter==0)" "[ \"\$(cat \"$WORK/calls\" 2>/dev/null)\" = \"0\" ]"

# ===========================================================================
# 4. MALFORMED / NO-FLAGS RESPONSE -> EMPTY flag-set, never fabricated
#    (REQ-DM-3a-002; the looks-measured-but-isn't guard)
#    These: "the model answered." Gegenthese: on garbage output a 'helpful' parser
#    invents flags → fake catches/cry-wolves. Schärfung: a malformed response and a
#    no-findings response BOTH yield an empty flag-set (0 flags), classified, with
#    no Python traceback.
# ===========================================================================
BAD="$(arma review --task "$TASK" --model-scope opus-tier --inject-response 'this is not json at all {' --inject-call-counter "$WORK/calls2" --json 2>&1)"
# Require valid JSON output (so an ABSENT module fails here too) AND no traceback.
# Valid-JSON parse of $BAD (captured with 2>&1) succeeds ONLY if the runner emitted
# clean JSON and NO traceback leaked into the stream — a traceback would make the
# whole payload invalid JSON and fail the parse. So this single eval-free check
# preserves both the "valid JSON" and "no traceback" meaning of the original.
assert_json_eq "REQ-DM-3a-002 malformed response emits valid JSON with no traceback" "$BAD" 'True' True
assert_json_eq "REQ-DM-3a-002 malformed response => empty flag-set (0 flags, none fabricated)" "$BAD" 'len(d.get("flags",[]))==0' True
EMPTY="$(arma review --task "$TASK" --model-scope opus-tier --inject-response '{"flags":[]}' --inject-call-counter "$WORK/calls3" --json 2>&1)"
assert_json_eq "REQ-DM-3a-002 no-findings response => empty flag-set (0 flags)" "$EMPTY" 'len(d.get("flags",[]))==0' True

# ===========================================================================
# 5. LIVE GATE OFF BY DEFAULT  (REQ-DM-3a-002/006; mirrors deepseek_review _make_transport)
#    These: "a live path exists." Gegenthese: an always-armed live path spends
#    credits / hits the network inside the offline suite. Schärfung: with NO env gate
#    and NO injected response, the runner must NOT make a network call — it classifies
#    (live-disabled / needs-injection), counter stays 0, no key required.
# ===========================================================================
GATED="$(arma review --task "$TASK" --model-scope opus-tier --live --inject-call-counter "$WORK/calls4" --json 2>&1)"
# Counter must EXIST and read 0 (an absent module never writes it -> RED here too).
assert "REQ-DM-3a-006 --live without env gate fires ZERO calls (counter file written, ==0)" "[ -f \"$WORK/calls4\" ] && [ \"\$(cat \"$WORK/calls4\")\" = \"0\" ]"
assert_json_eq "REQ-DM-3a-006 --live without env gate classifies (valid JSON, no fabricated live result)" "$GATED" 'bool(d.get("code") or d.get("status")) and len(d.get("flags",[]))==0' True

# ===========================================================================
# 6. SEPARATE ENTRYPOINT — does NOT mutate the read-only instrument (NGOAL-DM-001)
#    These: "Arm-A is its own module." Gegenthese: it could `import deepseek_review`
#    and monkeypatch / mutate it, violating the read-only invariant. Schärfung: the
#    runner source must not import-and-mutate the instrument; and the instrument file
#    is byte-unchanged after the runner runs (no side-effect write).
# ===========================================================================
assert "NGOAL-DM-001 runner does not assign into a deepseek_review.* attribute (no mutation)" "! grep -nE 'deepseek_review\\.[A-Za-z_]+[[:space:]]*=' \"$RUNNER\""
BEFORE="$(env -i PATH="$PATH" python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$INSTRUMENT_LIB" 2>/dev/null)"
arma review --task "$TASK" --model-scope opus-tier --inject-response "@$WORK/resp.json" --json >/dev/null 2>&1
AFTER="$(env -i PATH="$PATH" python3 -c 'import hashlib,sys; print(hashlib.sha256(open(sys.argv[1],"rb").read()).hexdigest())' "$INSTRUMENT_LIB" 2>/dev/null)"
assert_eq "NFR-DM-3a-003 instrument deepseek_review.py byte-unchanged after a runner run" "$BEFORE" "$AFTER"

finish "Arm-A (Claude-only) review runner"
