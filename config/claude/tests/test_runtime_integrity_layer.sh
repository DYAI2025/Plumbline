#!/usr/bin/env bash
# Runtime contract tests for Plumbline Runtime Integrity Layer (PRIL) Goal 1:
# confirmed product context and real completion evidence.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_runtime_integrity_layer"

FIXTURES="$REPO_DIR/config/claude/tests/fixtures/pril"
CONTEXT_BIN="$REPO_DIR/config/claude/bin/plumbline-context-check"
REALITY_BIN="$REPO_DIR/config/claude/bin/plumbline-reality-check"
CMD="$REPO_DIR/config/claude/commands/agileteam.md"
WATCHER="$REPO_DIR/agileteam/plumbline-watcher.md"
T_TRUE_LINE="$REPO_DIR/docs/templates/true-line-gate-check.template.md"
T_REALITY_SCHEMA="$REPO_DIR/docs/templates/reality-ledger-evidence.schema.json"

has() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -Fq -- "$3" "$2"; then _pass "$1"; else _fail "$1 (missing in $2: $3)"; fi
}

assert_exit() {
  local description="$1" expected="$2"
  shift 2
  TESTS_RUN=$((TESTS_RUN + 1))
  local output status
  output="$({ "$@"; } 2>&1)"
  status=$?
  if [ "$status" -eq "$expected" ]; then
    _pass "$description"
  else
    _fail "$description (expected exit $expected, got $status; output: $output)"
  fi
}

assert_nonzero() {
  local description="$1"
  shift
  TESTS_RUN=$((TESTS_RUN + 1))
  local output status
  output="$({ "$@"; } 2>&1)"
  status=$?
  if [ "$status" -ne 0 ]; then
    _pass "$description"
  else
    _fail "$description (expected non-zero exit; output: $output)"
  fi
}

assert_output_contains() {
  local description="$1" needle="$2"
  shift 2
  TESTS_RUN=$((TESTS_RUN + 1))
  local output status
  output="$({ "$@"; } 2>&1)"
  status=$?
  if [ "$status" -ne 0 ] && printf '%s' "$output" | grep -Fq -- "$needle"; then
    _pass "$description"
  else
    _fail "$description (exit $status, wanted non-zero output containing '$needle'; output: $output)"
  fi
}

# Harness and fixtures.
assert_file "PRIL context check CLI exists" "$CONTEXT_BIN"
assert_file "PRIL reality check CLI exists" "$REALITY_BIN"
assert_file "Reality evidence schema exists" "$T_REALITY_SCHEMA"
assert_file "context-pass canvas exists" "$FIXTURES/context-pass/docs/canvas/demo.canvas.md"
assert_file "context-pass PRD exists" "$FIXTURES/context-pass/docs/prd/demo.prd.md"
assert_file "context-pass Vision exists" "$FIXTURES/context-pass/docs/vision/demo.vision.md"
assert_file "context-pass traceability exists" "$FIXTURES/context-pass/docs/traceability.md"
assert_file "reality fake-only fixture exists" "$FIXTURES/reality-fake-only/docs/reality/demo.evidence.jsonl"
assert_file "reality integration fixture exists" "$FIXTURES/reality-integration-pass/docs/reality/demo.evidence.jsonl"

# G1-REQ-001 / G1-REQ-002: confirmed context is mandatory.
assert_exit "context-pass exits 0" 0 \
  "$CONTEXT_BIN" --repo "$FIXTURES/context-pass" --feature demo
assert_exit "context-missing-vision exits 2" 2 \
  "$CONTEXT_BIN" --repo "$FIXTURES/context-missing-vision" --feature demo
assert_exit "context-unconfirmed-canvas exits 3" 3 \
  "$CONTEXT_BIN" --repo "$FIXTURES/context-unconfirmed-canvas" --feature demo
assert_output_contains "missing context names exact artifact" "docs/vision/demo.vision.md" \
  "$CONTEXT_BIN" --repo "$FIXTURES/context-missing-vision" --feature demo
assert_output_contains "unconfirmed context names exact artifact" "docs/canvas/demo.canvas.md" \
  "$CONTEXT_BIN" --repo "$FIXTURES/context-unconfirmed-canvas" --feature demo

# G1-REQ-003: completion evidence must be real enough for the declared minimum.
assert_nonzero "fake-only reality evidence fails" \
  "$REALITY_BIN" --repo "$FIXTURES/reality-fake-only" --feature demo --min-evidence integration
assert_exit "integration reality evidence passes" 0 \
  "$REALITY_BIN" --repo "$FIXTURES/reality-integration-pass" --feature demo --min-evidence integration
assert_nonzero "invalid JSONL reality evidence fails closed" \
  "$REALITY_BIN" --repo "$FIXTURES/reality-invalid-jsonl" --feature demo --min-evidence integration
assert_nonzero "missing reality evidence ledger fails closed" \
  "$REALITY_BIN" --repo "$FIXTURES/reality-missing-evidence" --feature demo --min-evidence integration
assert_output_contains "fake-only error is actionable" "fake-only" \
  "$REALITY_BIN" --repo "$FIXTURES/reality-fake-only" --feature demo --min-evidence integration

# G1-REQ-004: /agileteam and Watcher must explicitly use the gates.
has "/agileteam references plumbline-context-check" "$CMD" "plumbline-context-check"
has "/agileteam references plumbline-reality-check" "$CMD" "plumbline-reality-check"
has "/agileteam names PRIL Phase 0.5 context gate" "$CMD" "PRIL Context Integrity gate"
has "/agileteam requires reality before Gate C/D completion" "$CMD" "before Gate C/D completion"
has "Watcher references plumbline-context-check" "$WATCHER" "plumbline-context-check"
has "Watcher references plumbline-reality-check" "$WATCHER" "plumbline-reality-check"
has "Watcher blocks pass on PRIL fail" "$WATCHER" "PRIL fail means Watcher verdict cannot be pass"
has "True-Line template has PRIL output field" "$T_TRUE_LINE" "PRIL check output:"

finish "test_runtime_integrity_layer"
