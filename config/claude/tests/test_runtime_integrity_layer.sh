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
SCOPE_BIN="$REPO_DIR/config/claude/bin/plumbline-scope-check"
REDACT_BIN="$REPO_DIR/config/claude/bin/plumbline-redact"
CMD="$REPO_DIR/config/claude/commands/agileteam.md"
WATCHER="$REPO_DIR/agileteam/plumbline-watcher.md"
T_TRUE_LINE="$REPO_DIR/docs/templates/true-line-gate-check.template.md"
T_REALITY_SCHEMA="$REPO_DIR/docs/templates/reality-ledger-evidence.schema.json"
PRETOOL_GUARD="$REPO_DIR/config/claude/hooks/pretool-plumbline-guard.sh"
SETTINGS="$REPO_DIR/.claude/settings.json"

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
assert_file "PRIL scope check CLI exists" "$SCOPE_BIN"
assert_file "PRIL redact CLI exists" "$REDACT_BIN"
assert_file "Reality evidence schema exists" "$T_REALITY_SCHEMA"
assert_file "context-pass canvas exists" "$FIXTURES/context-pass/docs/canvas/demo.canvas.md"
assert_file "context-pass PRD exists" "$FIXTURES/context-pass/docs/prd/demo.prd.md"
assert_file "context-pass Vision exists" "$FIXTURES/context-pass/docs/vision/demo.vision.md"
assert_file "context-pass traceability exists" "$FIXTURES/context-pass/docs/traceability.md"
assert_file "reality fake-only fixture exists" "$FIXTURES/reality-fake-only/docs/reality/demo.evidence.jsonl"
assert_file "reality integration fixture exists" "$FIXTURES/reality-integration-pass/docs/reality/demo.evidence.jsonl"
assert_file "reality missing evidence_class fixture exists" "$FIXTURES/reality-missing-evidence-class/docs/reality/demo.evidence.jsonl"
assert_file "scope pass changed-files fixture exists" "$FIXTURES/scope-pass/changed-files.txt"
assert_file "scope fail changed-files fixture exists" "$FIXTURES/scope-fail/changed-files.txt"
assert_file "scope missing-source changed-files fixture exists" "$FIXTURES/scope-missing-source/changed-files.txt"
assert_file "scope traceability-source changed-files fixture exists" "$FIXTURES/scope-traceability-source/changed-files.txt"
assert_file "scope JSON-source changed-files fixture exists" "$FIXTURES/scope-json-source/changed-files.txt"
assert_file "redaction safe JSONL fixture exists" "$FIXTURES/redaction/safe.jsonl"
assert_file "redaction secret JSONL fixture exists" "$FIXTURES/redaction/secret.jsonl"
assert_file "redaction invalid JSONL fixture exists" "$FIXTURES/redaction/invalid.jsonl"
assert_file "optional pretool guard exists" "$PRETOOL_GUARD"

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
assert_exit "production-verified reality evidence passes documented workflow minimum" 0 \
  "$REALITY_BIN" --repo "$FIXTURES/reality-production-verified" --feature demo --min-evidence integration
assert_exit "real-boundary-smoke reality evidence passes documented workflow minimum" 0 \
  "$REALITY_BIN" --repo "$FIXTURES/reality-real-boundary-smoke" --feature demo --min-evidence integration
assert_nonzero "invalid JSONL reality evidence fails closed" \
  "$REALITY_BIN" --repo "$FIXTURES/reality-invalid-jsonl" --feature demo --min-evidence integration
assert_nonzero "missing reality evidence ledger fails closed" \
  "$REALITY_BIN" --repo "$FIXTURES/reality-missing-evidence" --feature demo --min-evidence integration
assert_output_contains "missing evidence_class error is actionable" "evidence_class" \
  "$REALITY_BIN" --repo "$FIXTURES/reality-missing-evidence-class" --feature demo --min-evidence integration
assert_output_contains "fake-only error is actionable" "fake-only" \
  "$REALITY_BIN" --repo "$FIXTURES/reality-fake-only" --feature demo --min-evidence integration

# G2-REQ-001: scope guard keeps implementation inside confirmed allowed scope.
assert_exit "scope-pass exits 0" 0 \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-pass" --feature demo --changed-files "$FIXTURES/scope-pass/changed-files.txt"
assert_output_contains "scope-fail names out-of-scope file" "src/billing/payment.py" \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-fail" --feature demo --changed-files "$FIXTURES/scope-fail/changed-files.txt"
assert_output_contains "explicit missing scope source fails closed" "Allowed change scope" \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-missing-source" --feature demo --changed-files "$FIXTURES/scope-missing-source/changed-files.txt"
assert_exit "traceability scope source exits 0" 0 \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-traceability-source" --feature demo --changed-files "$FIXTURES/scope-traceability-source/changed-files.txt"
assert_exit "JSON scope source exits 0" 0 \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-json-source" --feature demo --changed-files "$FIXTURES/scope-json-source/changed-files.txt"
# H-2: an overly-broad self-authored scope pattern (a bare `**` with no concrete
# path segment) must be REFUSED when loading scope — otherwise a one-line wildcard
# legitimizes every path and defeats the scope guard. Fails closed (non-zero).
assert_nonzero "broad wildcard scope pattern fails closed" \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-broad" --feature demo --changed-files "$FIXTURES/scope-broad/changed-files.txt"
assert_output_contains "broad scope error names the rejected pattern" "too broad" \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-broad" --feature demo --changed-files "$FIXTURES/scope-broad/changed-files.txt"
# A normal scoped canvas must STILL pass (legitimate `src/...**` patterns work).
assert_exit "normal scoped canvas still passes after broad-pattern guard" 0 \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-pass" --feature demo --changed-files "$FIXTURES/scope-pass/changed-files.txt"
# Residual H-2: glob character-classes and `?` wildcards (`?*`, `[a-z]*`, `[!/]*`,
# `[0-9a-zA-Z_]*`, …) also match EVERY repo path via fnmatch, yet the old anchor
# test only stripped `*`/`.` and misread them as a concrete anchor. These must
# ALSO be refused (fail closed) when loading scope.
assert_nonzero "broad ?* scope pattern fails closed" \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-broad-qstar" --feature demo --changed-files "$FIXTURES/scope-broad-qstar/changed-files.txt"
assert_output_contains "broad ?* scope error names too-broad pattern" "too broad" \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-broad-qstar" --feature demo --changed-files "$FIXTURES/scope-broad-qstar/changed-files.txt"
assert_nonzero "broad [a-z]* glob-class scope pattern fails closed" \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-broad-class" --feature demo --changed-files "$FIXTURES/scope-broad-class/changed-files.txt"
assert_output_contains "broad [a-z]* scope error names too-broad pattern" "too broad" \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-broad-class" --feature demo --changed-files "$FIXTURES/scope-broad-class/changed-files.txt"
# A glob character-class that still carries a literal anchor (`file[0-9].txt` ->
# `file`/`.txt`) is legitimately scoped and must STILL pass.
assert_exit "literal-anchored glob-class scope still passes" 0 \
  "$SCOPE_BIN" --repo "$FIXTURES/scope-broad-literalclass" --feature demo --changed-files "$FIXTURES/scope-broad-literalclass/changed-files.txt"

# G2-REQ-002: redaction rejects unsafe persistence and can produce a safe redacted stream.
assert_exit "redaction safe JSONL check exits 0" 0 \
  "$REDACT_BIN" --mode check < "$FIXTURES/redaction/safe.jsonl"
assert_output_contains "redaction secret JSONL check fails closed" "secret" \
  "$REDACT_BIN" --mode check < "$FIXTURES/redaction/secret.jsonl"
assert_output_contains "redaction invalid JSONL check fails closed" "invalid JSONL" \
  "$REDACT_BIN" --mode check < "$FIXTURES/redaction/invalid.jsonl"
TESTS_RUN=$((TESTS_RUN + 1))
redacted_output="$("$REDACT_BIN" --mode auto < "$FIXTURES/redaction/plain-secret.txt")"
if printf '%s' "$redacted_output" | grep -Fq '[REDACTED:' && ! printf '%s' "$redacted_output" | grep -Fq 'sk-test-1234567890abcdef1234567890abcdef'; then
  _pass "redaction auto mode removes original secret"
else
  _fail "redaction auto mode removes original secret (output: $redacted_output)"
fi

# G2-REQ-003: optional pretool guard exists but is not activated by settings.
assert_exit "optional pretool guard has valid bash syntax" 0 bash -n "$PRETOOL_GUARD"
TESTS_RUN=$((TESTS_RUN + 1))
if grep -Fq 'pretool-plumbline-guard.sh' "$SETTINGS"; then
  _fail "optional pretool guard is not activated in .claude/settings.json"
else
  _pass "optional pretool guard is not activated in .claude/settings.json"
fi

# G1/G2-REQ-004: /agileteam and Watcher must explicitly use the gates.
has "/agileteam references plumbline-context-check" "$CMD" "plumbline-context-check"
has "/agileteam references plumbline-reality-check" "$CMD" "plumbline-reality-check"
has "/agileteam references plumbline-scope-check" "$CMD" "plumbline-scope-check"
has "/agileteam references plumbline-redact" "$CMD" "plumbline-redact"
has "/agileteam names PRIL Phase 0.5 context gate" "$CMD" "PRIL Context Integrity gate"
has "/agileteam requires reality before Gate C/D completion" "$CMD" "before Gate C/D completion"
has "Watcher references plumbline-context-check" "$WATCHER" "plumbline-context-check"
has "Watcher references plumbline-reality-check" "$WATCHER" "plumbline-reality-check"
has "Watcher references plumbline-scope-check" "$WATCHER" "plumbline-scope-check"
has "Watcher references plumbline-redact" "$WATCHER" "plumbline-redact"
has "Watcher blocks pass on PRIL fail" "$WATCHER" "PRIL fail means Watcher verdict cannot be pass"
has "Watcher blocks pass on scope/redaction fail" "$WATCHER" "scope/redaction failure means Watcher verdict cannot be pass"
has "True-Line template has PRIL output field" "$T_TRUE_LINE" "PRIL check output:"
has "True-Line template has scope output field" "$T_TRUE_LINE" "Scope check output:"
has "True-Line template has redaction output field" "$T_TRUE_LINE" "Redaction check output:"

finish "test_runtime_integrity_layer"
