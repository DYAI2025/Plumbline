#!/usr/bin/env bash
#
# Tests for the Claude Code on the web SessionStart bootstrap:
#   config/claude/hooks/session-start.sh  +  .claude/settings.json
#
# The hook must make /agileteam, /agileteam-bench and the konfabulations-audit
# skill available in a fresh clone (web/co-work) without a manual install step,
# be idempotent, never fatal, and stay a no-op outside the remote environment.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
HOOK="$REPO_DIR/config/claude/hooks/session-start.sh"
SETTINGS="$REPO_DIR/.claude/settings.json"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_web_bootstrap"

# --- static structure ------------------------------------------------------
assert_file "session-start hook exists" "$HOOK"
assert ".claude/settings.json is valid JSON" "jq -e . '$SETTINGS'"
assert "settings registers SessionStart -> session-start.sh" \
  "jq -e '[.hooks.SessionStart[]?.hooks[]?.command? // \"\"] | any(test(\"session-start\\\\.sh\"))' '$SETTINGS'"
assert "hook script has valid bash syntax" "bash -n '$HOOK'"

# --- behaviour: remote bootstrap into an isolated CLAUDE_HOME --------------
CH="$(mktemp -d)"; trap 'rm -rf "$CH"' EXIT
CLAUDE_CODE_REMOTE=true CLAUDE_HOME="$CH" HOME="$CH" bash "$HOOK" >"$CH/stdout" 2>/dev/null
rc=$?
assert_eq "hook exits 0 in remote mode" "0" "$rc"
# A SessionStart hook's stdout must be ONLY a JSON object (extra text would be
# injected as raw context); jq -e . succeeds only if stdout is one valid JSON value.
assert "remote stdout is a single valid JSON object (no log leakage)" "jq -e . '$CH/stdout'"
assert "remote stdout sets hookEventName=SessionStart" \
  "jq -e '.hookSpecificOutput.hookEventName == \"SessionStart\"' '$CH/stdout'"
assert "remote stdout requests reloadSkills (skill/command rescan this session)" \
  "jq -e '.hookSpecificOutput.reloadSkills == true' '$CH/stdout'"
assert_file "agileteam command transferred"       "$CH/commands/agileteam.md"
assert_file "agileteam-bench command transferred"  "$CH/commands/agileteam-bench.md"
assert_file "konfabulations-audit skill transferred" "$CH/skills/konfabulations-audit/SKILL.md"
assert "stop-learning-loop hook registered in CLAUDE_HOME settings" \
  "jq -e '[.hooks.Stop[]?.hooks[]?.command? // \"\"] | any(test(\"stop-learning-loop\\\\.sh\"))' '$CH/settings.json'"

# --- idempotency: a second run must not error or duplicate the hook --------
CLAUDE_CODE_REMOTE=true CLAUDE_HOME="$CH" HOME="$CH" bash "$HOOK" >/dev/null 2>&1
assert_eq "second run still exits 0" "0" "$?"
count="$(jq '[.hooks.Stop[]?.hooks[]?.command? // "" | select(test("stop-learning-loop"))] | length' "$CH/settings.json")"
assert_eq "stop hook registered exactly once (no duplicate)" "1" "$count"

# --- local safety: no-op when not remote (user runs install.sh manually) ---
CH2="$(mktemp -d)"
local_out="$(CLAUDE_CODE_REMOTE="" AGILETEAM_FORCE_BOOTSTRAP="" CLAUDE_HOME="$CH2" HOME="$CH2" bash "$HOOK" 2>/dev/null)"
rc2=$?
assert_eq "hook exits 0 when not remote" "0" "$rc2"
assert_eq "local no-op emits no stdout" "" "$local_out"
assert "no commands installed in local (non-remote) mode" "[ ! -e '$CH2/commands/agileteam.md' ]"
rm -rf "$CH2"

# --- explicit override still works locally ---------------------------------
CH3="$(mktemp -d)"
AGILETEAM_FORCE_BOOTSTRAP=1 CLAUDE_HOME="$CH3" HOME="$CH3" bash "$HOOK" >/dev/null 2>&1
assert_file "AGILETEAM_FORCE_BOOTSTRAP=1 forces install locally" "$CH3/commands/agileteam.md"
rm -rf "$CH3"

finish "test_web_bootstrap"
