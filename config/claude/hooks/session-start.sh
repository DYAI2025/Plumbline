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

# --------------------------------------------------------------------------
# Update check (REQ-PUR-08): ON BY DEFAULT, opt-OUT, THROTTLED (<=1/day),
# NON-blocking, NOTIFY-only. This runs the INSTALLED `plumbline update --check`
# (the CLI in $CLAUDE_HOME/bin), reads its `status:`/`latest:` lines, and — only
# when the install is BEHIND the latest release — prints a single
# "update available: vN -> vM, run `plumbline update`" notice to STDERR. It
# NEVER applies an update, NEVER writes under $CLAUDE_HOME beyond a tiny
# throttle cache, and NEVER blocks the session (a hung network is bounded by a
# portable watchdog and the CLI's own HTTP timeout). All output is on stderr so
# stdout stays a single SessionStart JSON object (the web-bootstrap contract).
#
#   * Opt-out:  PLUMBLINE_NO_UPDATE_CHECK set non-empty => skip entirely (no
#               check, no notice, no network).
#   * Throttle: $CLAUDE_HOME/.plumbline/update/last-check.json records the epoch
#               of the last real check; a session within the window (<=1/day)
#               reuses the cached result and does NOT re-hit the network.
plumbline_update_check() {
  # 1) Opt-out short-circuits BEFORE any network/cache work (F3: ZERO hits).
  if [ -n "${PLUMBLINE_NO_UPDATE_CHECK:-}" ]; then
    return 0
  fi

  # The INSTALLED CLI is the one whose identity anchor records the installed
  # version (REQ-PUR-02). Prefer $CLAUDE_HOME/bin/plumbline; never pass --root
  # (so it reads the anchor's version, not the cwd's VERSION) and never pass
  # --source (so the release check goes over PLUMBLINE_GITHUB_API).
  local home cli cache_dir cache now last window
  home="${CLAUDE_HOME:-$HOME/.claude}"
  cli="$home/bin/plumbline"
  if [ ! -x "$cli" ]; then
    return 0
  fi

  cache_dir="$home/.plumbline/update"
  cache="$cache_dir/last-check.json"
  window=86400  # <=1/day

  # 2) Throttle: if a recent check exists, reuse it and skip the network.
  now="$(date +%s 2>/dev/null || echo 0)"
  if [ -f "$cache" ]; then
    last="$(sed -n 's/.*"checked_at"[[:space:]]*:[[:space:]]*\([0-9][0-9]*\).*/\1/p' "$cache" 2>/dev/null | head -n 1)"
    [ -n "$last" ] || last=0
    if [ "$now" -gt 0 ] && [ "$((now - last))" -lt "$window" ]; then
      # Within the throttle window: re-surface a cached notice (if any), no network.
      local cached_notice
      cached_notice="$(sed -n 's/.*"notice"[[:space:]]*:[[:space:]]*"\(.*\)".*/\1/p' "$cache" 2>/dev/null | head -n 1)"
      if [ -n "$cached_notice" ]; then
        echo "$cached_notice" >&2
      fi
      return 0
    fi
  fi

  # 3) Real check, NON-blocking. Capture the CLI output to a temp file. A portable
  # watchdog (no timeout(1), absent on macOS) caps a hung network: run the CLI in
  # the background and kill it if it overruns the budget. The CLI's own
  # HTTP_TIMEOUT(30s) is the inner bound; the watchdog is the belt.
  local out rc
  out="$(mktemp 2>/dev/null || echo "${TMPDIR:-/tmp}/plumbline-update-check.$$")"
  rc=0
  (
    "$cli" update --check >"$out" 2>/dev/null
  ) &
  local check_pid waited
  check_pid=$!
  waited=0
  # Budget: 50 * 0.2s = 10s of polling; well under the F4 20s watchdog and the
  # CLI's 30s HTTP timeout, generous for a single prompt fetch.
  while kill -0 "$check_pid" 2>/dev/null && [ "$waited" -lt 50 ]; do
    sleep 0.2
    waited=$((waited + 1))
  done
  if kill -0 "$check_pid" 2>/dev/null; then
    kill "$check_pid" 2>/dev/null || true
    rc=1
  fi
  wait "$check_pid" 2>/dev/null || rc=$?

  # 4) Notify-only: parse status/latest/local and surface a notice when BEHIND.
  local status latest local_ver notice
  status=""
  latest=""
  local_ver=""
  notice=""
  if [ "$rc" -eq 0 ] && [ -f "$out" ]; then
    status="$(sed -n 's/^status:[[:space:]]*\(.*\)$/\1/p' "$out" | head -n 1)"
    latest="$(sed -n 's/^latest:[[:space:]]*\(.*\)$/\1/p' "$out" | head -n 1)"
    local_ver="$(sed -n 's/^local:[[:space:]]*\(.*\)$/\1/p' "$out" | head -n 1)"
    if [ "$status" = "update-available" ]; then
      notice="update available: v${local_ver} -> v${latest}, run \`plumbline update\`"
      echo "$notice" >&2
    fi
  else
    echo "plumbline session-start: update check failed or timed out (non-fatal)" >&2
  fi

  # 5) Write/refresh the throttle cache (the ONLY write under $CLAUDE_HOME). Even
  # an up-to-date result records checked_at, so a second session this window is
  # throttled. Best-effort: a write failure must never break the session.
  if [ "$rc" -eq 0 ]; then
    mkdir -p "$cache_dir" 2>/dev/null || true
    {
      printf '{"checked_at": %s, "status": "%s", "latest": "%s", "notice": "%s"}\n' \
        "${now:-0}" "${status:-unknown}" "${latest:-}" "${notice:-}"
    } >"$cache" 2>/dev/null || true
  fi

  rm -f "$out" 2>/dev/null || true
  return 0
}

# Run the update check defensively: it must NEVER abort the session.
plumbline_update_check || true

# Ask Claude Code to rescan skills + commands now, so what we just copied is
# usable in THIS session rather than only the next one. Prefer jq; fall back to
# a literal so a missing jq can't suppress the rescan.
jq -cn '{hookSpecificOutput:{hookEventName:"SessionStart",reloadSkills:true}}' 2>/dev/null \
  || printf '{"hookSpecificOutput":{"hookEventName":"SessionStart","reloadSkills":true}}\n'

exit 0
