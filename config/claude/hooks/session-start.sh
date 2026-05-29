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
#   - Synchronous (no async JSON on stdout) so the commands exist before the
#     session proceeds — avoids a race where /agileteam isn't yet discoverable.
#   - Idempotent: install.sh skips targets that already exist.
#   - Non-interactive and NEVER fatal: a setup hiccup must not abort the session,
#     so this always exits 0 and routes all output to stderr (stdout stays clean
#     because a sync SessionStart hook's stdout is injected into the context).
#   - Remote-only by default: locally you run install.sh yourself (see SETUP.md).
#     Set AGILETEAM_FORCE_BOOTSTRAP=1 to force it anywhere (used by the tests).
set -uo pipefail

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
if bash "$installer" --copy 1>&2; then
  echo "agileteam session-start: /agileteam + konfabulations-audit ready in ${CLAUDE_HOME:-$HOME/.claude}" >&2
else
  echo "agileteam session-start: bootstrap reported an issue (non-fatal) — see SETUP.md" >&2
fi

exit 0
