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

# A genuine Claude Code PreToolUse deny is either the permission object
#   {"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny",...}}
# on stdout, or exit code 2 (the documented blocking exit) from an EXISTING hook.
# The top-level "decision" member is the LEGACY approve|block enum: Claude Code
# 2.1.252 rejects {"decision":"deny"} at its hook-output validator and the
# dispatch proceeds — that shape is fail-OPEN and must NOT count as a deny.
# Exit 1 is a non-blocking error (execution continues); 255 is our "hook absent"
# sentinel and 127 (command-not-found) indicates no real hook ran.
is_deny() { # is_deny <permission-decision> <rc>
  [ "$1" = "deny" ] && return 0
  [ "$2" = "2" ] && return 0
  return 1
}

# Extract the PreToolUse permission decision from hook stdout. Prints "deny"
# only for the accepted permission object; anything the harness would discard
# prints nothing: a legacy top-level decision (also when it rides along with a
# valid envelope — the whole object fails validation), several JSON documents
# or trailing text (treated as plain text), or no JSON at all.
pretool_decision() { # pretool_decision <hook-stdout>
  printf '%s' "$1" \
    | jq -rs 'if length == 1 then .[0] else empty end
              | select(.hookSpecificOutput.hookEventName == "PreToolUse"
                       and (.decision // "") != "deny")
              | .hookSpecificOutput.permissionDecision // empty' 2>/dev/null
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

# --- Beat 1.5: contract canary — rejected shapes must not read as a deny. ------
# Guards the extractor itself: if it is ever re-widened to accept a shape the
# validator discards, this goes red before a hook regression could hide behind it.
VALID_DENY='{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"x"}}'
TESTS_RUN=$((TESTS_RUN + 1))
if [ "$(pretool_decision "$VALID_DENY")" = "deny" ] \
   && [ -z "$(pretool_decision '{"decision":"deny","reason":"legacy"}')" ] \
   && [ -z "$(pretool_decision '{"decision":"deny","reason":"legacy","hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","permissionDecisionReason":"x"}}')" ] \
   && [ -z "$(pretool_decision "$(printf '{"a":1}\n%s' "$VALID_DENY")")" ] \
   && [ -z "$(pretool_decision "$(printf '%s\ngarbage' "$VALID_DENY")")" ] \
   && [ -z "$(pretool_decision '')" ]; then
  _pass "contract canary: only a single hookSpecificOutput.permissionDecision:deny object is a deny (legacy, hybrid, multi-document, trailing text, empty are not)"
else
  _fail "contract canary: extractor must accept exactly the valid permission object and reject legacy/hybrid/multi-document/trailing-text/empty stdout"
fi

# --- Beat 2 (Schärfung 1a): VISION_MISSING + a PLANNING tool dispatch -> DENY. -
# A planning/coding tool dispatch (Task to a planner/coder, or Edit/Write of
# production code) under VISION_MISSING must be denied harness-enforced:
# either the PreToolUse permission object (hookSpecificOutput.permissionDecision
# "deny") on stdout OR exit code 2 (the two ways a PreToolUse hook can block a
# dispatch).
vm_repo="$(make_vision_missing_repo)"
run_hook "$vm_repo" '{"tool_name":"Task","tool_input":{"subagent_type":"planner","description":"plan the feature"}}'
TESTS_RUN=$((TESTS_RUN + 1))
vdecision="$(pretool_decision "$HOOK_OUT")"
if is_deny "$vdecision" "$HOOK_RC"; then
  _pass "VISION_MISSING planning dispatch is DENIED (permissionDecision=deny or exit 2)"
else
  _fail "VISION_MISSING planning dispatch must be denied (rc=$HOOK_RC, out: $HOOK_OUT)"
fi
TESTS_RUN=$((TESTS_RUN + 1))
vreason="$(printf '%s' "$HOOK_OUT" | jq -r '.hookSpecificOutput.permissionDecisionReason // empty' 2>/dev/null)"
if [ -n "$vreason" ]; then
  _pass "deny carries a permissionDecisionReason"
else
  _fail "deny must carry a permissionDecisionReason (out: $HOOK_OUT)"
fi

# Coding dispatch (Write of production code) under VISION_MISSING -> DENY too.
run_hook "$vm_repo" '{"tool_name":"Write","tool_input":{"file_path":"src/feature.py","content":"x=1"}}'
TESTS_RUN=$((TESTS_RUN + 1))
cdecision="$(pretool_decision "$HOOK_OUT")"
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
ndecision="$(pretool_decision "$HOOK_OUT")"
# Pass-through requires a REAL hook (rc 0, not the 255 absent-sentinel) that
# prints NOTHING: an empty stdout is the hook's documented pass path, and it is
# the only shape that can neither block (legacy "block", exit 2) nor prompt.
if [ "$HOOK_RC" -eq 0 ] && [ -z "$ndecision" ] && [ -z "$HOOK_OUT" ]; then
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
rdecision="$(pretool_decision "$HOOK_OUT")"
if [ "$HOOK_RC" -eq 0 ] && [ -z "$rdecision" ] && [ -z "$HOOK_OUT" ]; then
  _pass "VISION_MISSING: read-only dispatch passes through (fail-open for non-affected)"
else
  _fail "VISION_MISSING read-only must pass through (rc=$HOOK_RC, out: $HOOK_OUT)"
fi

# --- Beat 3.5 (Path-2: independent recompute — defense-in-depth) --------------
# The hook must ALSO derive VISION_MISSING with NO .start-gate marker, from
# docs/context/.active-feature + the real artifact state, REUSING
# plumbline-start-check. This is the load-bearing Option-A independence path: it
# must fire even when the command-gate never wrote a marker. (Without this the
# whole "dual-path" claim is unproven — the marker path alone would mask a dead
# recompute, the exact built-but-not-wired failure this file guards against.)

# Active feature whose PRD exists but whose Vision is NOT user-confirmed, and NO
# .start-gate -> path-2 must DENY planning.
make_path2_vision_missing_repo() {
  local repo feat="acme-feature"
  repo="$(mktemp -d -p "$WORK")"
  mkdir -p "$repo/docs/context" "$repo/docs/prd" "$repo/docs/vision"
  printf '%s' "$feat" > "$repo/docs/context/.active-feature"
  printf '# PRD\n' > "$repo/docs/prd/$feat.prd.md"
  printf '# Vision\nStatus: draft\n' > "$repo/docs/vision/$feat.vision.md"
  printf '%s' "$repo"
}

# Active feature whose Vision IS user-confirmed, NO .start-gate -> pass through.
make_path2_confirmed_repo() {
  local repo feat="acme-feature"
  repo="$(mktemp -d -p "$WORK")"
  mkdir -p "$repo/docs/context" "$repo/docs/prd" "$repo/docs/vision"
  printf '%s' "$feat" > "$repo/docs/context/.active-feature"
  printf '# PRD\n' > "$repo/docs/prd/$feat.prd.md"
  printf '# Vision\nStatus: user-confirmed\n' > "$repo/docs/vision/$feat.vision.md"
  printf '%s' "$repo"
}

p2_vm_repo="$(make_path2_vision_missing_repo)"
run_hook "$p2_vm_repo" '{"tool_name":"Task","tool_input":{"subagent_type":"planner","description":"plan"}}'
TESTS_RUN=$((TESTS_RUN + 1))
p2decision="$(pretool_decision "$HOOK_OUT")"
if is_deny "$p2decision" "$HOOK_RC"; then
  _pass "path-2: active-feature + PRD + unconfirmed vision DENIES planning (no marker)"
else
  _fail "path-2 must deny via independent recompute (rc=$HOOK_RC, out: $HOOK_OUT)"
fi

p2_ok_repo="$(make_path2_confirmed_repo)"
run_hook "$p2_ok_repo" '{"tool_name":"Task","tool_input":{"subagent_type":"planner","description":"plan"}}'
TESTS_RUN=$((TESTS_RUN + 1))
p2okdecision="$(pretool_decision "$HOOK_OUT")"
if [ "$HOOK_RC" -eq 0 ] && [ -z "$p2okdecision" ] && [ -z "$HOOK_OUT" ]; then
  _pass "path-2: active-feature + confirmed vision PASSES THROUGH"
else
  _fail "path-2 confirmed-vision must pass through (rc=$HOOK_RC, out: $HOOK_OUT)"
fi

# Matcher precision (verified spec-audit decision): the gate targets PLANNING/
# CODING roles only. A non-coding ops role (devops) under VISION_MISSING must
# PASS THROUGH — the backstop must not be a blanket Task-killer (the orchestrator
# Phase-0 gate is the broad control; this is the planning/coding backstop).
run_hook "$vm_repo" '{"tool_name":"Task","tool_input":{"subagent_type":"devops","description":"deploy"}}'
TESTS_RUN=$((TESTS_RUN + 1))
opsdecision="$(pretool_decision "$HOOK_OUT")"
if [ "$HOOK_RC" -eq 0 ] && [ -z "$opsdecision" ] && [ -z "$HOOK_OUT" ]; then
  _pass "VISION_MISSING: non-coding ops role (devops) passes through (matcher not over-broad)"
else
  _fail "devops dispatch must pass through; matcher over-broad (rc=$HOOK_RC, out: $HOOK_OUT)"
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
