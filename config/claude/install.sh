#!/usr/bin/env bash
#
# Bootstrap: make the repo's vendored Claude config active in this machine's
# ~/.claude. Idempotent — only acts when a target is missing (or with --force).
#
# Currently:
#   - transfers  config/claude/commands/agileteam.md       -> ~/.claude/commands/agileteam.md
#   - transfers  config/claude/commands/agileteam-bench.md -> ~/.claude/commands/agileteam-bench.md
#   - transfers  config/claude/skills/konfabulations-audit -> ~/.claude/skills/konfabulations-audit
#   - registers  the learning-loop Stop hook in ~/.claude/settings.json (needs jq)
#
# By default it SYMLINKS the command (so repo edits stay live); pass --copy to copy.
# The Stop hook is merged idempotently (skipped if already present), preserving any
# existing hooks/settings.
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"   # repo root (~/.claude/agents)
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
MODE="symlink"
FORCE=0
for arg in "$@"; do
  case "$arg" in
    --copy) MODE="copy" ;;
    --force) FORCE=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

transfer() {
  local src="$1" dst="$2"
  mkdir -p "$(dirname "$dst")"
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    echo "skip (exists): $dst   [use --force to overwrite]"
    return
  fi
  rm -f "$dst"
  if [ "$MODE" = "copy" ]; then
    cp -R "$src" "$dst"; echo "copied:   $dst"
  else
    ln -s "$src" "$dst"; echo "symlinked: $dst -> $src"
  fi
}

# Idempotently add the learning-loop Stop hook to ~/.claude/settings.json,
# preserving any existing hooks (e.g. agent-deck) and other settings.
register_stop_hook() {
  local settings="$CLAUDE_HOME/settings.json"
  local cmd="bash $REPO_DIR/config/claude/hooks/stop-learning-loop.sh"

  if ! command -v jq >/dev/null 2>&1; then
    echo "skip stop-hook: jq not found — install jq and re-run, or add it manually to $settings"
    return
  fi
  mkdir -p "$CLAUDE_HOME"
  [ -f "$settings" ] || echo '{}' > "$settings"
  if ! jq -e . "$settings" >/dev/null 2>&1; then
    echo "skip stop-hook: $settings is not valid JSON — fix it first"
    return
  fi
  if jq -e '[.hooks.Stop[]?.hooks[]? | .command? // ""] | any(test("stop-learning-loop\\.sh"))' \
       "$settings" >/dev/null 2>&1; then
    echo "skip stop-hook: already registered in $settings"
    return
  fi
  local tmp; tmp="$(mktemp)"
  if jq --arg cmd "$cmd" '
    .hooks //= {} |
    .hooks.Stop //= [] |
    .hooks.Stop += [ { "hooks": [ { "type": "command", "command": $cmd, "timeout": 10 } ] } ]
  ' "$settings" > "$tmp"; then
    mv "$tmp" "$settings"
    echo "registered stop-hook in $settings"
  else
    rm -f "$tmp"
    echo "skip stop-hook: jq failed to update $settings" >&2
  fi
}

transfer "$REPO_DIR/config/claude/commands/agileteam.md" "$CLAUDE_HOME/commands/agileteam.md"
transfer "$REPO_DIR/config/claude/commands/agileteam-bench.md" "$CLAUDE_HOME/commands/agileteam-bench.md"
transfer "$REPO_DIR/config/claude/skills/konfabulations-audit" "$CLAUDE_HOME/skills/konfabulations-audit"
register_stop_hook

echo "done. Open /hooks once (or restart Claude Code) so /agileteam and the Stop hook are picked up."
