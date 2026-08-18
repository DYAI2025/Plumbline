#!/usr/bin/env bash
#
# SessionStart hook — make /agileteam work out-of-the-box in Claude Code on the
# web ("co-work") and any fresh clone.
#
# Claude Code on the web clones this repo into a fresh, ephemeral container each
# session, with an empty ~/.claude. The /agileteam + /agileteam-bench commands,
# the vendored konfabulations-audit skill and the learning-loop Stop hook live
# under config/claude/ and are normally activated by a manual `install.sh` run.
# That manual step does not happen on the web, so this hook runs it at session
# start — restoring the commands, skill and hook before the agent loop begins.
#
# Contract (see ~/.claude/skills/session-start-hook):
#   - Synchronous so the commands/skill exist before the session proceeds.
#   - Idempotent: install.sh skips targets that already exist.
#   - On success it prints ONLY a SessionStart JSON object asking Claude Code to
#     reloadSkills — skill/command discovery runs *before* SessionStart hooks
#     finish, so without this the freshly-copied konfabulations-audit skill (and
#     the commands) would only appear next session. All human/installer log lines
#     go to stderr so stdout stays a single parseable JSON value.
#   - Non-interactive and NEVER fatal: a setup hiccup must not abort the session,
#     so this always exits 0. `set -u` is deliberately omitted (this runs in an
#     environment we don't fully control; an unset var must never abort us — all
#     expansions below already carry `:-` defaults).
#   - Remote-only by default: locally you run install.sh yourself (see SETUP.md).
#     Set AGILETEAM_FORCE_BOOTSTRAP=1 to force it anywhere (used by the tests).
set -o pipefail

# Repo root resolved from the hook's own location, so cwd does not matter.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$REPO_DIR}"

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ] && [ "${AGILETEAM_FORCE_BOOTSTRAP:-}" != "1" ]; then
  # Local session: leave the user's global ~/.claude untouched.
  exit 0
fi

installer="$PROJECT_DIR/config/claude/install.sh"
if [ ! -f "$installer" ]; then
  echo "agileteam session-start: installer not found at $installer — skipping" >&2
  exit 0
fi

# --copy (not symlink): the result must survive even if the repo path changes,
# and symlinks are unreliable across some web/Windows containers.
# 1>&2: keep installer chatter off stdout so stdout stays a single JSON object.
if bash "$installer" --copy 1>&2; then
  echo "agileteam session-start: /agileteam + konfabulations-audit ready in ${CLAUDE_HOME:-$HOME/.claude}" >&2
else
  echo "agileteam session-start: bootstrap reported an issue (non-fatal) — see SETUP.md" >&2
fi

# Optional, non-fatal update check. This is deliberately opt-in and check-only:
# set PLUMBLINE_AUTO_UPDATE_CHECK=1 and PLUMBLINE_UPDATE_SOURCE=<local release metadata>
# to surface available MINOR/PATCH releases. MAJOR updates are never applied here.
if [ "${PLUMBLINE_AUTO_UPDATE_CHECK:-}" = "1" ]; then
  update_source="${PLUMBLINE_UPDATE_SOURCE:-}"
  if [ -n "$update_source" ] && [ -x "$PROJECT_DIR/config/claude/bin/plumbline" ]; then
    if "$PROJECT_DIR/config/claude/bin/plumbline" --root "$PROJECT_DIR" update --check --source "$update_source" 1>&2; then
      echo "plumbline session-start: update check completed (check-only; MAJOR requires confirmation)" >&2
    else
      echo "plumbline session-start: update check failed (non-fatal)" >&2
    fi
  else
    echo "plumbline session-start: auto update check requested but PLUMBLINE_UPDATE_SOURCE or plumbline CLI is missing" >&2
  fi
fi

# Ask Claude Code to rescan skills + commands now, so what we just copied is
# usable in THIS session rather than only the next one. Prefer jq; fall back to
# a literal so a missing jq can't suppress the rescan.
jq -cn '{hookSpecificOutput:{hookEventName:"SessionStart",reloadSkills:true}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","reloadSkills":true}}\n'

exit 0
