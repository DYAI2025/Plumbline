#!/usr/bin/env bash
#
# Deterministic test for the learning-loop Stop hook (no live session needed).
# Mirrors the "Testing the Stop hook" snippet in README.md, as a CI assertion.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
H="$REPO_DIR/config/claude/hooks/stop-learning-loop.sh"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_stop_hook"

# Isolate $HOME so we control the sentinel and never touch the real one.
CH="$(mktemp -d)"; trap 'rm -rf "$CH"' EXIT
mkdir -p "$CH/.claude"
sentinel="$CH/.claude/.agileteam-reflection-pending"

assert "hook has valid bash syntax" "bash -n '$H'"

# (a) no sentinel -> no output, exit 0
out="$(echo '{"stop_hook_active":false}' | HOME="$CH" bash "$H")"
assert_eq "no sentinel: exits 0" "0" "$?"
assert_eq "no sentinel: emits nothing" "" "$out"

# (b) sentinel present -> emits a decision:block JSON object
touch "$sentinel"
echo '{"stop_hook_active":false}' | HOME="$CH" bash "$H" > "$CH/out.json"
assert "sentinel present: emits valid JSON" "jq -e . '$CH/out.json'"
decision="$(jq -r '.decision' "$CH/out.json" 2>/dev/null)"
assert_eq "sentinel present: decision is 'block'" "block" "$decision"

# (c) loop guard -> stop_hook_active true means do not block again
out="$(echo '{"stop_hook_active":true}' | HOME="$CH" bash "$H")"
assert_eq "loop guard: emits nothing when stop_hook_active=true" "" "$out"

# (d) never exits non-zero even on malformed input
echo 'not json' | HOME="$CH" bash "$H" >/dev/null 2>&1
assert_eq "malformed input: still exits 0" "0" "$?"

finish "test_stop_hook"
