#!/usr/bin/env bash
# Contract: installing from a checkout REPOINTS a hook registered from another one.
#
# Measured defect (2026-07-30, this machine): the Stop hook registered in
# ~/.claude/settings.json pointed at `_TOOLZ/plumbline_v1/Plumbline/...` -- a different
# checkout of the same repo, HEAD 2 days behind, containing NONE of the four CLIs shipped
# that day. Re-running install.sh from the current checkout did not fix it: registration
# tested "is ANY plumbline-enforce.sh present?", found the stale one, printed
# "already registered" and returned.
#
# So the enforcement TRANSPORT silently pointed at a stale tree while the installer
# reported success -- idempotence that had become blindness. Every gate in the repo was
# unreachable at runtime and nothing said so.
#
# Contract now: same path -> idempotent skip. DIFFERENT path -> repoint, loudly.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_install_hook_repoint"

if ! command -v jq >/dev/null 2>&1; then
  _skip "jq not installed; hook registration is jq-gated"
  finish "test_install_hook_repoint"
  exit $?
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

STALE="/some/other/checkout/Plumbline/config/claude/hooks"

# A settings file already carrying hooks registered from a DIFFERENT checkout, plus a
# foreign hook that must survive untouched.
mk_settings() {
  cat >"$1" <<EOF
{
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "bash /unrelated/other-tool.sh" } ] },
      { "hooks": [ { "type": "command", "command": "bash $STALE/plumbline-enforce.sh", "timeout": 15 } ] }
    ],
    "PreToolUse": [
      { "hooks": [ { "type": "command", "command": "bash $STALE/pretool-vision-gate.sh" } ] }
    ]
  }
}
EOF
}

run_install() { # run_install <claude-home>
  local home="$1" outf="$WORK/install.out"
  env CLAUDE_HOME="$home" HOME="$home" \
    bash "$REPO_DIR/config/claude/install.sh" --no-agents --no-commands \
    --no-skills --no-bin >"$outf" 2>&1
  INSTALL_RC=$?
  INSTALL_OUT="$(cat "$outf")"
}

# --- R1: a hook from another checkout is repointed at this one ----------------
home="$WORK/home1"
mkdir -p "$home"
mk_settings "$home/settings.json"
run_install "$home"
assert_eq "R1 the installer itself succeeds" "0" "$INSTALL_RC"

enforce_now="$(jq -r '[.hooks.Stop[]?.hooks[]? | .command? // ""]
  | map(select(test("plumbline-enforce"))) | .[0] // ""' "$home/settings.json")"
vision_now="$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | .command? // ""]
  | map(select(test("pretool-vision-gate"))) | .[0] // ""' "$home/settings.json")"

assert_contains "R1 enforce hook now points at THIS checkout" \
  "$enforce_now" "$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"
assert_not_contains "R1 enforce hook no longer points at the stale checkout" \
  "$enforce_now" "/some/other/checkout"
assert_contains "R1 vision hook now points at THIS checkout" \
  "$vision_now" "$REPO_DIR/config/claude/hooks/pretool-vision-gate.sh"
assert_not_contains "R1 vision hook no longer points at the stale checkout" \
  "$vision_now" "/some/other/checkout"
assert_contains "R1 the repoint is announced, not silent" \
  "$INSTALL_OUT" "REPOINTING"

# The old behaviour must be gone: a stale registration must never report as fine.
assert_not_contains "R1 a stale path is NOT reported as 'already registered'" \
  "$INSTALL_OUT" "skip enforce-hook: already registered"

# --- R2: unrelated hooks survive ---------------------------------------------
foreign="$(jq -r '[.hooks.Stop[]?.hooks[]? | .command? // ""]
  | map(select(test("other-tool"))) | .[0] // ""' "$home/settings.json")"
assert_eq "R2 an unrelated Stop hook is preserved verbatim" \
  "bash /unrelated/other-tool.sh" "$foreign"
assert "R2 settings.json is still valid JSON" "jq -e . '$home/settings.json'"

# --- R3: re-running from the SAME checkout is a genuine no-op -----------------
before="$(cat "$home/settings.json")"
run_install "$home"
after="$(cat "$home/settings.json")"
assert_eq "R3 second install from the same checkout changes nothing" "$before" "$after"
assert_contains "R3 second install reports idempotent skip" \
  "$INSTALL_OUT" "already registered"
assert_not_contains "R3 second install does not repoint" \
  "$INSTALL_OUT" "REPOINTING"

# --- R4: no duplicate registration is created --------------------------------
enforce_count="$(jq -r '[.hooks.Stop[]?.hooks[]? | .command? // ""]
  | map(select(test("plumbline-enforce"))) | length' "$home/settings.json")"
assert_eq "R4 exactly one enforce-hook registration exists" "1" "$enforce_count"
vision_count="$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | .command? // ""]
  | map(select(test("pretool-vision-gate"))) | length' "$home/settings.json")"
assert_eq "R4 exactly one vision-hook registration exists" "1" "$vision_count"

# --- R5: a fresh machine still gets a first registration ---------------------
home2="$WORK/home2"
mkdir -p "$home2"
printf '{}\n' >"$home2/settings.json"
run_install "$home2"
fresh="$(jq -r '[.hooks.Stop[]?.hooks[]? | .command? // ""]
  | map(select(test("plumbline-enforce"))) | .[0] // ""' "$home2/settings.json")"
assert_contains "R5 a fresh settings.json gets the enforce hook registered" \
  "$fresh" "$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"

# --- R6: a command with a wrapper/flags keeps them; only the PATH is substituted ----
# Replacing the whole .command silently discarded a hand-added `env` prefix or flag.
home3="$WORK/home3"
mkdir -p "$home3"
cat >"$home3/settings.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[{"type":"command","command":"env FOO=1 bash /OLD/config/claude/hooks/plumbline-enforce.sh --strict","timeout":15}]}]}}
EOF
run_install "$home3"
kept="$(jq -r '[.hooks.Stop[]?.hooks[]?.command] | map(select(test("plumbline-enforce"))) | .[0]' "$home3/settings.json")"
assert_contains "R6 the env prefix survives the repoint" "$kept" "env FOO=1"
assert_contains "R6 the trailing flag survives the repoint" "$kept" "--strict"
assert_contains "R6 the path was repointed to this checkout" \
  "$kept" "$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"
assert_not_contains "R6 the old path is gone" "$kept" "/OLD/"

# --- R7: TWO stale registrations -- neither may survive, and none is deleted --------
# Checking only the first match either left a second stale entry behind or rewrote
# every entry to an identical command, producing duplicates.
home4="$WORK/home4"
mkdir -p "$home4"
cat >"$home4/settings.json" <<'EOF'
{"hooks":{"Stop":[{"hooks":[
  {"type":"command","command":"bash /OLD_A/config/claude/hooks/plumbline-enforce.sh"},
  {"type":"command","command":"bash /OLD_B/config/claude/hooks/plumbline-enforce.sh"}
]}]}}
EOF
run_install "$home4"
stale_left="$(jq -r '[.hooks.Stop[]?.hooks[]?.command] | map(select(test("OLD_A|OLD_B"))) | length' "$home4/settings.json")"
assert_eq "R7 no stale registration survives" "0" "$stale_left"
total_after="$(jq -r '[.hooks.Stop[]?.hooks[]?.command] | map(select(test("plumbline-enforce"))) | length' "$home4/settings.json")"
assert_eq "R7 both registrations are kept (none deleted for the user)" "2" "$total_after"
assert_contains "R7 the duplication is reported, not silently normalised" \
  "$INSTALL_OUT" "registered 2 times"

# --- R8: one CURRENT + one stale -- the stale one must not hide behind the good one --
home5="$WORK/home5"
mkdir -p "$home5"
cat >"$home5/settings.json" <<EOF
{"hooks":{"Stop":[{"hooks":[
  {"type":"command","command":"bash $REPO_DIR/config/claude/hooks/plumbline-enforce.sh"},
  {"type":"command","command":"bash /OLD_C/config/claude/hooks/plumbline-enforce.sh"}
]}]}}
EOF
run_install "$home5"
stale5="$(jq -r '[.hooks.Stop[]?.hooks[]?.command] | map(select(test("OLD_C"))) | length' "$home5/settings.json")"
assert_eq "R8 a stale entry behind a current one is still repointed" "0" "$stale5"

finish "test_install_hook_repoint"
