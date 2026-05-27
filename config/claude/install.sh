#!/usr/bin/env bash
#
# Bootstrap: make the repo's vendored Claude config active in this machine's
# ~/.claude. Idempotent — only acts when a target is missing (or with --force).
#
# Currently transfers:
#   config/claude/commands/agileteam.md  ->  ~/.claude/commands/agileteam.md
#
# By default it SYMLINKS (so repo edits stay live); pass --copy to copy instead.
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
    cp "$src" "$dst"; echo "copied:   $dst"
  else
    ln -s "$src" "$dst"; echo "symlinked: $dst -> $src"
  fi
}

transfer "$REPO_DIR/config/claude/commands/agileteam.md" "$CLAUDE_HOME/commands/agileteam.md"

echo "done. Restart Claude Code (or open a new session) so /agileteam is discovered."
