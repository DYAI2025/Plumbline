#!/usr/bin/env bash
# PLB-HARDEN-001 / Test B (TDD, RED): WAIT_STATE_LOCK must block state-changing /
# meta toolcalls after a WAIT/STOP.
#
# Pattern #10/#11 (WAIT_STATE_BYPASS / Meta-Arbeit-ist-Arbeit). After the user
# says STOP/WAIT there is no deterministic gate: a state-changing toolcall
# (Write/Edit/Bash) or meta-work (Task/skill-gen/session-scan) keeps running.
# The existing pretool-plumbline-guard.sh is an inert no-op (exit 0, "not wired
# into settings"). This codifies the lock the harness is missing.
#
# Boundary: a PreToolUse hook is a separate process — JSON tool-dispatch on
# stdin, a decision on stdout / exit code. Exercised through that real boundary
# (spawn the hook, feed stdin, read stdout + exit), mirroring
# test_pretool_vision_gate_hook.sh.
#
# These:      a PreToolUse hook denies state-changing toolcalls under a wait-lock.
# Gegenthese: (a) it denies EVERYTHING (bricks read-only work too), or (b) it is
#             never registered, so the harness never calls it.
# Schaerfung: (B1 RED) lock SET + Write -> DENY + STOP-WAIT-BYPASS;
#             (B2) lock SET + Read -> PASS-THROUGH (read-only survives — kills the
#                  "deny everything" twin);
#             (B3) no lock + Write -> PASS-THROUGH (normal work);
#             (B4 RED) lock SET + meta Task -> STOP-META-WORK;
#             (B5 RED) install.sh registers the hook under PreToolUse (kills the
#                  "built but never wired" twin).
#
# RED expectation: pretool-wait-state.sh does not exist and is unregistered, so
# B0/B1/B4/B5 fail. Self-contained; no network. NO hook is implemented here.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
echo "test_pretool_wait_state_hook (PLB-HARDEN-001 / Test B, RED)"

# Contract: the wait-state lock hook lives here — distinct from the inert
# pretool-plumbline-guard.sh, which must stay a no-op.
HOOK="$REPO_DIR/config/claude/hooks/pretool-wait-state.sh"
INSTALL="$REPO_DIR/config/claude/install.sh"

WRITE_CALL='{"tool_name":"Write","tool_input":{"file_path":"/x","content":"y"}}'
READ_CALL='{"tool_name":"Read","tool_input":{"file_path":"/x"}}'
TASK_CALL='{"tool_name":"Task","tool_input":{"subagent_type":"coder"}}'

# Run the hook; echo "<decision>|<rc>". A MISSING hook yields sentinel rc 255 so
# "absent" can never be misread as a deny (mirrors the vision-gate test).
run_hook() { # run_hook <project> <stdin-json>
  local project="$1" payload="$2" outf rc decision
  if [ ! -f "$HOOK" ]; then echo "|255"; return; fi
  outf="$(mktemp)"
  CLAUDE_PROJECT_DIR="$project" bash "$HOOK" >"$outf" 2>/dev/null <<<"$payload"; rc=$?
  decision="$(grep -oiE '"decision"[[:space:]]*:[[:space:]]*"(deny|allow)"' "$outf" 2>/dev/null | grep -oiE 'deny|allow' | head -1)"
  rm -f "$outf"
  echo "${decision}|${rc}"
}
# A genuine deny: decision=="deny" OR a deliberate non-zero from an EXISTING hook
# (1 or 2). 255 = "hook absent" sentinel, 127 = bash missing-file: NOT a deny.
# shellcheck disable=SC2317,SC2329  # invoked indirectly via assert's eval'd condition string
is_deny() { # is_deny "<decision>|<rc>"
  local d="${1%%|*}" rc="${1##*|}"
  [ "$d" = "deny" ] && return 0
  { [ "$rc" = "1" ] || [ "$rc" = "2" ]; } && return 0
  return 1
}
# Capture the hook's stdout text for stop-code assertions (empty when absent).
# shellcheck disable=SC2317,SC2329  # invoked indirectly via command substitution inside assert args
hook_out() { # hook_out <project> <stdin-json>
  local project="$1" payload="$2"
  [ ! -f "$HOOK" ] && { printf ''; return; }
  CLAUDE_PROJECT_DIR="$project" bash "$HOOK" 2>/dev/null <<<"$payload" || true
}
mk_repo() { # mk_repo <locked|unlocked> ; echoes repo path
  local locked="$1" repo; repo="$(mktemp -d)"; mkdir -p "$repo/docs/context"
  [ "$locked" = "locked" ] && printf 'LOCKED reason=user-stop\n' > "$repo/docs/context/.wait-lock"
  printf '%s' "$repo"
}

assert_file "B0: wait-state hook exists" "$HOOK"

# B1 (RED): lock SET + state-changing Write -> DENY + STOP-WAIT-BYPASS
repo="$(mk_repo locked)"
r="$(run_hook "$repo" "$WRITE_CALL")"
assert "B1 RED: Write under wait-lock is DENIED" "is_deny \"$r\""
assert_contains "B1 RED: deny carries stop-code STOP-WAIT-BYPASS" "$(hook_out "$repo" "$WRITE_CALL")" "STOP-WAIT-BYPASS"
rm -rf "$repo"

# B2 (kills 'deny everything' twin): lock SET + Read -> PASS-THROUGH
repo="$(mk_repo locked)"
r="$(run_hook "$repo" "$READ_CALL")"
assert "B2: Read under wait-lock PASSES THROUGH (read-only survives)" "! is_deny \"$r\""
rm -rf "$repo"

# B3 (normal work): no lock + Write -> PASS-THROUGH
repo="$(mk_repo unlocked)"
r="$(run_hook "$repo" "$WRITE_CALL")"
assert "B3: Write with no wait-lock PASSES THROUGH" "! is_deny \"$r\""
rm -rf "$repo"

# B4 (RED): lock SET + meta Task -> STOP-META-WORK
repo="$(mk_repo locked)"
assert_contains "B4 RED: meta toolcall under wait-lock carries STOP-META-WORK" "$(hook_out "$repo" "$TASK_CALL")" "STOP-META-WORK"
rm -rf "$repo"

# B5 (RED, kills 'never wired' twin): install.sh registers the hook under PreToolUse
if [ -f "$INSTALL" ]; then
  assert "B5 RED: install.sh registers pretool-wait-state under PreToolUse" "grep -q 'pretool-wait-state' \"$INSTALL\""
else
  _fail "B5 RED: install.sh present to register the hook (missing: $INSTALL)"
fi

echo "  (RED expected: B0/B1/B4/B5 FAIL until pretool-wait-state.sh exists + is registered)"
exit "${TESTS_FAILED:-0}"
