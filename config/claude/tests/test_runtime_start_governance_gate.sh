#!/usr/bin/env bash
# Phase-1 (TDD, RED) acceptance test for the /agileteam command-level start gate.
#
# Covers REQ-A-001..007, AC-A-001..005, EV-A-002, EV-A-004 (the EXECUTABLE parts)
# plus the EV-A-002 real-boundary-trace artifact contract.
#
# This is the INDEPENDENT, black-box test contract derived from the FROZEN PRD.
# It deliberately does NOT assume any particular wrapper/function name beyond the
# spec-mandated reuse of `config/claude/bin/plumbline-start-check`.
#
# Boundary classes (kritische semantische Glättung — Beat 0):
#   * REQ-A-002/003/004 (classifier emits VISION_MISSING / Planning NO / Coding
#     NO strings)                         -> PURE (in-process Python, no I/O).
#     Already proven by test_agileteam_start_gate.sh; re-pinned here only as the
#     INPUT the gate must consume, not re-litigated.
#   * REQ-A-001/005/006/007 (the /agileteam command FLOW consumes that verdict
#     and HALTS before planning)          -> BOUNDARY (wired across components
#     into a markdown-defined command flow + a behavioral trace artifact).
#
# These → Gegenthese → Schärfung (REQ-A-001/006 — the load-bearing zone):
#   These:      "/agileteam classifies VISION_MISSING and the panel says NO."
#   Gegenthese: The classifier returns VISION_MISSING and the strings are all
#               green, YET the markdown command never actually consults the
#               verdict (it stays prose), so a live /agileteam run sails into
#               planning anyway. Green strings, zero governance — exactly the
#               RISK-A-003 / spec-audit failure mode ("evidence proves text, not
#               the real gate halt").
#   Schärfung:  The ONE thing that kills it is a BEHAVIORAL real-boundary trace
#               (EV-A-002) of the actual gate path that records: Gate=VISION_MISSING,
#               Planning/Coding allowed: NO, the missing artifact, AND an explicit
#               HALT-before-planning marker — produced by running the gate path,
#               not hand-typed. This test pins the trace artifact's existence and
#               required content; it CANNOT by itself prove the markdown flow was
#               executed by a live model (see BLOCKER note at the bottom + the
#               coverage map returned to the orchestrator).
#
# RED expectation:
#   - the command-gate consumer wiring in agileteam.md does not yet call
#     plumbline-start-check as a control-flow precondition (it is prose today);
#   - the EV-A-002 trace artifact does not exist yet.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_runtime_start_governance_gate"

CMD="config/claude/commands/agileteam.md"
START_CHECK="config/claude/bin/plumbline-start-check"
TRACE="docs/benchmarks/2026-06-18-runtime-start-governance.md"

# === Part A — EV-A-001/EV-A-004: the verdict the gate MUST consume (PURE). =====
# This is the real-now executable input. We assert the exact strings the gate
# branches on, so the consumption test below is grounded in real classifier
# output (PRD-present + Vision-missing -> VISION_MISSING short-circuit).
assert "start-check wrapper is executable" "[ -x $START_CHECK ]"
panel="$($START_CHECK --prd-present --vision-missing 2>/dev/null)"
json="$(python3 config/claude/lib/plumbline_start.py --prd-present --vision-missing --json 2>/dev/null)"
assert_contains "AC-A-001: verdict is Gate: VISION_MISSING" "$panel" "Gate: VISION_MISSING"
assert_contains "AC-A-002: verdict blocks planning" "$panel" "Planning allowed: NO"
assert_contains "AC-A-003: verdict blocks coding" "$panel" "Coding allowed: NO"
assert_contains "AC-A-004: verdict offers only Vision Extraction next step" "$panel" \
  "Run Vision Extraction and request explicit user confirmation."
assert_contains "REQ-A-002 json: planning_allowed false" "$json" '"planning_allowed": false'
assert_contains "REQ-A-002 json: coding_allowed false" "$json" '"coding_allowed": false'

# EDGE-A-002 (verified spec finding): PRD + UNCONFIRMED vision draft -> still
# VISION_MISSING (short-circuit), NOT START_ARTIFACTS_MISSING. Pin it so an impl
# cannot "fix" the gate by mis-routing an unconfirmed draft to a softer branch.
edge="$($START_CHECK --prd-present --vision-missing --canvas-confirmed --traceability-present 2>/dev/null)"
assert_contains "EDGE-A-002: unconfirmed vision still VISION_MISSING" "$edge" "Gate: VISION_MISSING"

# === Part B — REQ-A-001/008: the command FLOW must CONSUME the verdict. ========
# REQ-A-008: reuse plumbline-start-check, do NOT duplicate classification logic.
# REQ-A-001: the verdict is a binding control-flow precondition, not a doc hint.
# Black-box contract: agileteam.md's Phase-0 gate must invoke the wrapper by name
# AND express the VISION_MISSING -> refuse-planning/coding control flow. A pure
# prose mention is insufficient; the gate must name the executable consumed.
assert_file "agileteam command exists" "$CMD"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -Fq 'plumbline-start-check' "$CMD"; then
  _pass "REQ-A-001/008: agileteam.md invokes plumbline-start-check (reuse, no dup)"
else
  _fail "REQ-A-001/008: agileteam.md Phase-0 gate must call plumbline-start-check by name"
fi

# REQ-A-001/003/004: the flow must tie the VISION_MISSING verdict to refusing
# entry into planning/coding (control-flow precondition wording, co-located).
TESTS_RUN=$((TESTS_RUN + 1))
if grep -A40 'plumbline-start-check' "$CMD" 2>/dev/null \
     | grep -Eqi 'VISION_MISSING' \
   && grep -A40 'plumbline-start-check' "$CMD" 2>/dev/null \
     | grep -Eqi 'do not enter planning|refuse.*planning|block.*planning|not enter.*planning|halt.*before planning'; then
  _pass "REQ-A-001/003: gate ties VISION_MISSING to refusing planning entry"
else
  _fail "REQ-A-001/003: gate must state VISION_MISSING refuses entry into planning"
fi

# REQ-A-008 (no duplication): the classification branch logic (the gate string
# table) must NOT be re-implemented inside agileteam.md. Heuristic: the markdown
# must not itself emit the START_ARTIFACTS_MISSING branch literal (that lives in
# plumbline_start.py only); if it does, it is reimplementing the classifier.
TESTS_RUN=$((TESTS_RUN + 1))
if grep -Fq 'START_ARTIFACTS_MISSING' "$CMD"; then
  _fail "REQ-A-008: agileteam.md must not duplicate classifier branch literals"
else
  _pass "REQ-A-008: agileteam.md does not duplicate classifier branch logic"
fi

# === Part C — EV-A-002 / AC-A-005 / REQ-A-006: behavioral real-boundary trace. =
# The Schärfung that kills the "prose-only gate" Gegenthese. The trace artifact
# must exist AND record the four facts the PRD requires, AND it must evidence an
# actual HALT-before-planning — not a hand-written snapshot.
assert_file "EV-A-002: real-boundary trace artifact exists" "$TRACE"
if [ -f "$TRACE" ]; then
  trace_body="$(cat "$TRACE")"
  assert_contains "EV-A-002: trace records Gate VISION_MISSING" "$trace_body" "VISION_MISSING"
  assert_contains "EV-A-002: trace records Planning allowed: NO" "$trace_body" "Planning allowed: NO"
  assert_contains "EV-A-002: trace records Coding allowed: NO" "$trace_body" "Coding allowed: NO"
  assert_contains "EV-A-002: trace names the missing artifact" "$trace_body" "Product Vision"
  # AC-A-005: the trace must explicitly assert the HALT happened BEFORE planning.
  TESTS_RUN=$((TESTS_RUN + 1))
  if printf '%s' "$trace_body" | grep -Eqi 'halt(ed)? before planning|stopped before planning|did not enter planning|HALT.*planning'; then
    _pass "AC-A-005: trace asserts /agileteam halted BEFORE planning"
  else
    _fail "AC-A-005: trace must evidence a halt BEFORE planning (not just the verdict)"
  fi
  # EV-A-002 honesty: the trace must declare its evidence-class explicitly. The
  # closure condition (F3) forbids silently downgrading the RED — the artifact
  # must state real-boundary-smoke OR explicitly carry PASS(tests)/RED(confidence).
  TESTS_RUN=$((TESTS_RUN + 1))
  if printf '%s' "$trace_body" | grep -Eq 'real-boundary-smoke|RED\(confidence\)'; then
    _pass "EV-A-002: trace declares its evidence-class honestly"
  else
    _fail "EV-A-002: trace must declare evidence-class (real-boundary-smoke or RED(confidence))"
  fi
  # RISK-A-003 / F3 anti-fake guard: the trace must NOT silently call itself a
  # hand-written snapshot and still claim closure. If it admits being hand-typed
  # it must also carry the RED(confidence) downgrade, never a bare green claim.
  TESTS_RUN=$((TESTS_RUN + 1))
  if printf '%s' "$trace_body" | grep -Eqi 'hand-?written snapshot|hand-?typed' \
     && ! printf '%s' "$trace_body" | grep -Eq 'RED\(confidence\)'; then
    _fail "RISK-A-003: a hand-written snapshot may not claim closure without RED(confidence)"
  else
    _pass "RISK-A-003: trace does not pass off a hand-written snapshot as closure"
  fi
fi

finish "test_runtime_start_governance_gate"
