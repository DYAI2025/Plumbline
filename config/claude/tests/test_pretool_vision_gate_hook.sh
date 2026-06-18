#!/usr/bin/env bash
# Phase-1 (TDD, RED) acceptance test for the PreToolUse VISION_MISSING backstop.
#
# Covers REQ-A-011 / AC-A-006 / EV-A-005.
#
# Boundary class (kritische semantische Glättung — Beat 0): BOUNDARY.
#   The hook is a separate process the Claude Code harness invokes with a JSON
#   tool-dispatch payload on stdin and reads a JSON decision from stdout. We
#   exercise it through that real process boundary (spawn the hook, feed stdin,
#   read stdout/exit code) -> evidence-class `real-boundary-smoke` for the hook
#   itself. (The harness *registration* is a second boundary; covered separately
#   by the install/settings assertions at the bottom.)
#
# These → Gegenthese → Schärfung (REQ-A-011):
#   These:      "A PreToolUse hook exists that denies planning/coding."
#   Gegenthese: The hook exists and unit-passes, BUT (a) it denies EVERYTHING so
#               normal sessions are bricked (fail-closed for the wrong set), or
#               (b) it is never registered in settings.json so the harness never
#               calls it -> built but not wired -> user value zero.
#   Schärfung:  Two reality tests that the counter-thesis cannot survive:
#               (1) a VISION_MISSING planning/coding dispatch is DENIED, AND a
#                   normal dispatch with no VISION_MISSING state PASSES THROUGH
#                   (kills the "denies everything" twin);
#               (2) install.sh registers the hook under PreToolUse in
#                   settings.json exactly once (kills the "never wired" twin).
#
# RED expectation: the hook script does not exist yet, so run_hook cannot produce
# a deny/pass-through; the registration assertion finds no PreToolUse entry.
#
# Self-contained: builds throwaway repos/CLAUDE_HOMEs; no network.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_pretool_vision_gate_hook"

# Contract: the backstop hook lives here. (Distinct from the inert
# pretool-plumbline-guard.sh, which must stay unregistered.)
HOOK="$REPO_DIR/config/claude/hooks/pretool-vision-gate.sh"
INSTALL="$REPO_DIR/config/claude/install.sh"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Run the PreToolUse hook with a project dir, a VISION_MISSING state file flag,
# and a JSON tool-dispatch payload on stdin. Captures stdout + exit code.
# Sets globals: HOOK_OUT HOOK_RC
run_hook() {
  local project="$1" stdin_payload="$2"
  local outf
  outf="$(mktemp -p "$WORK")"
  # Guard against a false "deny" from a MISSING script: `bash <missing>` exits
  # 127, which a naive "non-zero == deny" check would read as a block. If the
  # hook file does not exist there is no deny signal at all -> RC sentinel 255.
  if [ ! -f "$HOOK" ]; then
    HOOK_RC=255
    HOOK_OUT=""
    rm -f "$outf"
    return
  fi
  CLAUDE_PROJECT_DIR="$project" bash "$HOOK" >"$outf" 2>/dev/null <<<"$stdin_payload"
  HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"
  rm -f "$outf"
}

# A genuine PreToolUse deny is either a JSON {"decision":"deny"} on stdout, or a
# deliberate non-zero exit from an EXISTING hook (1 or 2 — the documented block
# codes). 255 is our "hook absent" sentinel and must NOT count as a deny; 127
# (command-not-found) likewise indicates no real hook ran.
is_deny() { # is_deny <decision> <rc>
  [ "$1" = "deny" ] && return 0
  case "$2" in 1|2) return 0 ;; esac
  return 1
}

# A repo whose start state is VISION_MISSING. The orchestrator's Phase-0 gate is
# the source of truth for "current start state". We model the VISION_MISSING
# ground-truth the same way the Stop hook models active-feature: a marker file
# the gate writes. The hook MUST derive its decision from real ground truth, not
# from a cooperative prompt.
make_vision_missing_repo() {
  local repo
  repo="$(mktemp -d -p "$WORK")"
  mkdir -p "$repo/docs/context"
  # Ground-truth start-state marker the Phase-0 gate persists. Exact filename is
  # an impl detail the hook+gate must agree on; this test pins the CONTRACT that
  # a VISION_MISSING marker -> deny. (If impl chooses another marker name, this
  # test is the place that must be updated in lockstep — by design.)
  printf 'VISION_MISSING' > "$repo/docs/context/.start-gate"
  printf '%s' "$repo"
}

# A normal repo: no VISION_MISSING state (e.g. start gate cleared / never armed).
make_normal_repo() {
  local repo
  repo="$(mktemp -d -p "$WORK")"
  mkdir -p "$repo/docs/context"
  printf '%s' "$repo"
}

# --- Beat 1: hook file must exist & be valid bash (RED until created). ---------
assert_file "PreToolUse vision-gate hook exists" "$HOOK"
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$HOOK" ] && bash -n "$HOOK" 2>/dev/null; then
  _pass "hook has valid bash syntax"
else
  _fail "hook missing or failed bash -n"
fi

# --- Beat 2 (Schärfung 1a): VISION_MISSING + a PLANNING tool dispatch -> DENY. -
# A planning/coding tool dispatch (Task to a planner/coder, or Edit/Write of
# production code) under VISION_MISSING must be denied harness-enforced:
# either a JSON {"decision":"deny"} on stdout OR a non-zero exit (the two ways a
# PreToolUse hook can block a dispatch).
vm_repo="$(make_vision_missing_repo)"
run_hook "$vm_repo" '{"tool_name":"Task","tool_input":{"subagent_type":"planner","description":"plan the feature"}}'
TESTS_RUN=$((TESTS_RUN + 1))
vdecision="$(printf '%s' "$HOOK_OUT" | jq -r '.decision // empty' 2>/dev/null)"
if is_deny "$vdecision" "$HOOK_RC"; then
  _pass "VISION_MISSING planning dispatch is DENIED (decision=deny or block exit code)"
else
  _fail "VISION_MISSING planning dispatch must be denied (rc=$HOOK_RC, out: $HOOK_OUT)"
fi

# Coding dispatch (Write of production code) under VISION_MISSING -> DENY too.
run_hook "$vm_repo" '{"tool_name":"Write","tool_input":{"file_path":"src/feature.py","content":"x=1"}}'
TESTS_RUN=$((TESTS_RUN + 1))
cdecision="$(printf '%s' "$HOOK_OUT" | jq -r '.decision // empty' 2>/dev/null)"
if is_deny "$cdecision" "$HOOK_RC"; then
  _pass "VISION_MISSING coding dispatch is DENIED"
else
  _fail "VISION_MISSING coding dispatch must be denied (rc=$HOOK_RC, out: $HOOK_OUT)"
fi

# --- Beat 3 (Schärfung 1b): NO VISION_MISSING -> PASS THROUGH. -----------------
# Kills the "denies everything" twin: a normal session must be unhindered.
normal_repo="$(make_normal_repo)"
run_hook "$normal_repo" '{"tool_name":"Task","tool_input":{"subagent_type":"planner","description":"plan the feature"}}'
TESTS_RUN=$((TESTS_RUN + 1))
ndecision="$(printf '%s' "$HOOK_OUT" | jq -r '.decision // empty' 2>/dev/null)"
# Pass-through requires a REAL hook (rc 0, not the 255 absent-sentinel) that does
# not deny.
if [ "$HOOK_RC" -eq 0 ] && [ "$ndecision" != "deny" ]; then
  _pass "no VISION_MISSING: planning dispatch PASSES THROUGH (not denied)"
else
  _fail "normal session must pass through (rc=$HOOK_RC, out: $HOOK_OUT)"
fi

# Even under VISION_MISSING, a non-planning/non-coding read-only dispatch (Read)
# should pass through — the gate is fail-CLOSED for planning/coding, fail-OPEN
# for non-affected actions (REQ-A-011 explicit). Pins the gate is targeted, not
# a blanket session-kill that would also block the Vision-Extraction work itself.
run_hook "$vm_repo" '{"tool_name":"Read","tool_input":{"file_path":"docs/prd/x.md"}}'
TESTS_RUN=$((TESTS_RUN + 1))
rdecision="$(printf '%s' "$HOOK_OUT" | jq -r '.decision // empty' 2>/dev/null)"
if [ "$HOOK_RC" -eq 0 ] && [ "$rdecision" != "deny" ]; then
  _pass "VISION_MISSING: read-only dispatch passes through (fail-open for non-affected)"
else
  _fail "VISION_MISSING read-only must pass through (rc=$HOOK_RC, out: $HOOK_OUT)"
fi

# --- Beat 4: never reference the deliberately-inert guard. ---------------------
TESTS_RUN=$((TESTS_RUN + 1))
if [ -f "$HOOK" ] && grep -Fq 'pretool-plumbline-guard.sh' "$HOOK"; then
  _fail "hook must NOT reference the inert pretool-plumbline-guard.sh"
else
  _pass "hook does not reference the inert pretool-plumbline-guard.sh"
fi

# --- Beat 5 (Schärfung 2 — kills the "never wired" twin): install registers it.
# A backstop hook that is never wired into settings.json under PreToolUse is
# inert — built-but-not-wired, user value zero. Prove install.sh registers it
# exactly once under PreToolUse, idempotently, and that the inert guard stays
# unregistered.
assert_file "install.sh exists" "$INSTALL"
CH="$(mktemp -d -p "$WORK")"
CLAUDE_HOME="$CH" HOME="$CH" bash "$INSTALL" --copy --no-skills --no-bin >/dev/null 2>&1
SETTINGS_OUT="$CH/settings.json"
assert_file "install produced settings.json" "$SETTINGS_OUT"

count_pretool() { # count_pretool <regex> -> # of PreToolUse hook commands matching
  jq "[.hooks.PreToolUse[]?.hooks[]?.command? // \"\" | select(test(\"$1\"))] | length" \
     "$SETTINGS_OUT" 2>/dev/null
}

assert_eq "vision-gate hook registered under PreToolUse exactly once" "1" \
  "$(count_pretool 'pretool-vision-gate\\.sh')"
assert_eq "inert pretool-plumbline-guard.sh is NOT registered under PreToolUse" "0" \
  "$(count_pretool 'pretool-plumbline-guard\\.sh')"

# Idempotency: a second install must not double-register.
CLAUDE_HOME="$CH" HOME="$CH" bash "$INSTALL" --copy --no-skills --no-bin >/dev/null 2>&1
assert_eq "second install: vision-gate hook still registered exactly once" "1" \
  "$(count_pretool 'pretool-vision-gate\\.sh')"

finish "test_pretool_vision_gate_hook"
