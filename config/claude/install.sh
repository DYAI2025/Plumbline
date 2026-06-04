#!/usr/bin/env bash
#
# Bootstrap this repository into a Claude Code installation.
#
# Idempotent by default: existing targets are left untouched unless --force is
# passed. By default targets are symlinked so repo edits stay live; pass --copy
# for machines where symlinks are undesirable (for example Windows/Git Bash).
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
MODE="symlink"
FORCE=0
INSTALL_AGENTS=1
INSTALL_COMMANDS=1
INSTALL_SKILLS=1
INSTALL_HOOK=1
INSTALL_BIN=1
WITH_FLOW=0
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $0 [--copy] [--force] [--dry-run] [--with-flow-agents] [--no-agents] [--no-commands] [--no-skills] [--no-hook] [--no-bin]

Installs the repo for Claude Code by:
  - installing the MCP-free agents into \$CLAUDE_HOME/agents (default; the ~35 claude-flow /
    flow-nexus / sublinear agents are omitted unless --with-flow-agents, so a plain install
    never pulls you toward the heavy claude-flow MCP stack),
  - installing all vendored commands from config/claude/commands/,
  - installing all vendored skills from config/claude/skills/,
  - registering the sentinel-gated learning-loop Stop hook,
  - registering the fail-closed PRIL enforcement Stop hook,
  - installing the plumbline CLI into $CLAUDE_HOME/bin/ with its Python libraries in $CLAUDE_HOME/lib/.

Environment:
  CLAUDE_HOME  Override target Claude home (default: $HOME/.claude)
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --copy) MODE="copy" ;;
    --force) FORCE=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --no-agents) INSTALL_AGENTS=0 ;;
    --no-commands) INSTALL_COMMANDS=0 ;;
    --no-skills) INSTALL_SKILLS=0 ;;
    --no-hook) INSTALL_HOOK=0 ;;
    --no-bin) INSTALL_BIN=0 ;;
    --with-flow-agents) WITH_FLOW=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "unknown arg: $arg" >&2; usage >&2; exit 2 ;;
  esac
done

log_action() {
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "dry-run: $*"
  else
    echo "$*"
  fi
}

same_path() {
  local a="$1" b="$2"
  [ -e "$a" ] && [ -e "$b" ] && [ "$(cd "$a" 2>/dev/null && pwd -P)" = "$(cd "$b" 2>/dev/null && pwd -P)" ]
}

transfer() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then
    echo "missing source: $src" >&2
    exit 1
  fi
  if [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
    log_action "skip (exists): $dst   [use --force to overwrite]"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$MODE" = "copy" ]; then
      log_action "would copy:     $src -> $dst"
    else
      log_action "would symlink:  $dst -> $src"
    fi
    return
  fi
  mkdir -p "$(dirname "$dst")"
  rm -rf "$dst"
  if [ "$MODE" = "copy" ]; then
    cp -R "$src" "$dst"
    echo "copied:   $dst"
  else
    ln -s "$src" "$dst"
    echo "symlinked: $dst -> $src"
  fi
}

# An agent is "flow-coupled" when its distinctive function is calling an external heavy MCP
# server (claude-flow / flow-nexus / sublinear-time-solver). Derived from the prompt, not a
# hardcoded list, so it stays correct as agents are added or changed. These agents are inert
# without that MCP installed separately, and carrying them by default would both bloat the
# agent registry and pull the user toward connecting the token-heavy claude-flow MCP.
is_flow_coupled() {
  grep -qE 'mcp__(claude[-_]flow|flow[-_]nexus|sublinear)' "$1"
}

# Install the agent prompts into $CLAUDE_HOME/agents. Selective by design: only real agents
# (markdown with a top-level name: frontmatter key) are mounted — not the repo's docs, config,
# metrics or explorer trees — and the flow-coupled set is omitted unless --with-flow-agents.
install_agent_repo() {
  local target="$CLAUDE_HOME/agents"
  # Back-compat: an existing whole-repo symlink (from an older install) is left untouched.
  if same_path "$REPO_DIR" "$target"; then
    log_action "skip agents: $target already points at this repo"
    return
  fi
  local f rel omitted=0
  while IFS= read -r -d '' f; do
    # name: frontmatter marks an agent; this skips README/CLAUDE/SETUP, reports, etc.
    grep -qE '^name:' "$f" || continue
    if [ "$WITH_FLOW" -ne 1 ] && is_flow_coupled "$f"; then
      omitted=$((omitted + 1))
      continue
    fi
    rel="${f#"$REPO_DIR"/}"
    transfer "$f" "$target/$rel"
  done < <(
    find "$REPO_DIR" \
      \( -path "$REPO_DIR/.git" \
         -o -path "$REPO_DIR/.github" \
         -o -path "$REPO_DIR/.claude" \
         -o -path "$REPO_DIR/.pytest_cache" \
         -o -path "$REPO_DIR/config" \
         -o -path "$REPO_DIR/docs" \
         -o -path "$REPO_DIR/metrics" \
         -o -path "$REPO_DIR/explorer" \) -prune -o \
      -type f -name '*.md' -print0
  )
  if [ "$omitted" -gt 0 ]; then
    echo "note: omitted $omitted MCP-coupled agents (claude-flow / flow-nexus / sublinear)."
    echo "      Re-run with --with-flow-agents to include them (they need that external MCP to be useful)."
  fi
}

install_commands() {
  local src_dir="$REPO_DIR/config/claude/commands"
  [ -d "$src_dir" ] || return 0
  while IFS= read -r -d '' cmd; do
    local rel name
    rel="${cmd#"$src_dir"/}"
    name="${rel%.md}"
    transfer "$cmd" "$CLAUDE_HOME/commands/$name.md"
  done < <(find "$src_dir" -maxdepth 1 -type f -name '*.md' -print0 | sort -z)
}

install_skills() {
  local src_dir="$REPO_DIR/config/claude/skills"
  [ -d "$src_dir" ] || return 0
  while IFS= read -r -d '' skill; do
    [ -f "$skill/SKILL.md" ] || continue
    transfer "$skill" "$CLAUDE_HOME/skills/$(basename "$skill")"
  done < <(find "$src_dir" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
}

install_bin_libs() {
  local src_dir="$REPO_DIR/config/claude/lib"
  [ -d "$src_dir" ] || return 0
  while IFS= read -r -d '' lib; do
    transfer "$lib" "$CLAUDE_HOME/lib/$(basename "$lib")"
  done < <(find "$src_dir" -maxdepth 1 -type f -name '*.py' -print0 | sort -z)
}

install_bin() {
  local src_dir="$REPO_DIR/config/claude/bin"
  [ -d "$src_dir" ] || return 0
  while IFS= read -r -d '' tool; do
    transfer "$tool" "$CLAUDE_HOME/bin/$(basename "$tool")"
  done < <(find "$src_dir" -maxdepth 1 -type f -print0 | sort -z)
  install_bin_libs
}

# Idempotently add the learning-loop Stop hook to ~/.claude/settings.json,
# preserving any existing hooks and other settings.
register_stop_hook() {
  local settings="$CLAUDE_HOME/settings.json"
  local hook_script="$REPO_DIR/config/claude/hooks/stop-learning-loop.sh"
  if [ -f "$CLAUDE_HOME/agents/config/claude/hooks/stop-learning-loop.sh" ]; then
    hook_script="$CLAUDE_HOME/agents/config/claude/hooks/stop-learning-loop.sh"
  fi
  local cmd="bash $hook_script"

  if ! command -v jq >/dev/null 2>&1; then
    echo "skip stop-hook: jq not found — install jq and re-run, or add it manually to $settings"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log_action "would register stop-hook in $settings with command: $cmd"
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

# Idempotently add the fail-closed PRIL enforcement Stop hook to
# ~/.claude/settings.json. Mirrors register_stop_hook: it preserves any existing
# hooks and is dedup-keyed on the hook filename so re-runs never double-register.
# This is what actually closes C-1 — a fail-closed hook that is never wired into
# settings.json is inert. It uses a 15s timeout because it shells out to the PRIL
# CLIs over the real git diff (heavier than the learning-loop hook).
register_enforce_hook() {
  local settings="$CLAUDE_HOME/settings.json"
  local hook_script="$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"
  if [ -f "$CLAUDE_HOME/agents/config/claude/hooks/plumbline-enforce.sh" ]; then
    hook_script="$CLAUDE_HOME/agents/config/claude/hooks/plumbline-enforce.sh"
  fi
  local cmd="bash $hook_script"

  if ! command -v jq >/dev/null 2>&1; then
    echo "skip enforce-hook: jq not found — install jq and re-run, or add it manually to $settings"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log_action "would register enforce-hook in $settings with command: $cmd"
    return
  fi
  mkdir -p "$CLAUDE_HOME"
  [ -f "$settings" ] || echo '{}' > "$settings"
  if ! jq -e . "$settings" >/dev/null 2>&1; then
    echo "skip enforce-hook: $settings is not valid JSON — fix it first"
    return
  fi
  if jq -e '[.hooks.Stop[]?.hooks[]? | .command? // ""] | any(test("plumbline-enforce\\.sh"))' \
       "$settings" >/dev/null 2>&1; then
    echo "skip enforce-hook: already registered in $settings"
    return
  fi
  local tmp; tmp="$(mktemp)"
  if jq --arg cmd "$cmd" '
    .hooks //= {} |
    .hooks.Stop //= [] |
    .hooks.Stop += [ { "hooks": [ { "type": "command", "command": $cmd, "timeout": 15 } ] } ]
  ' "$settings" > "$tmp"; then
    mv "$tmp" "$settings"
    echo "registered enforce-hook in $settings"
  else
    rm -f "$tmp"
    echo "skip enforce-hook: jq failed to update $settings" >&2
  fi
}

if [ "$DRY_RUN" -eq 1 ]; then
  echo "dry-run: no changes will be written (target CLAUDE_HOME=$CLAUDE_HOME)"
fi

mkdir -p "$CLAUDE_HOME"
[ "$INSTALL_AGENTS" -eq 1 ] && install_agent_repo
[ "$INSTALL_COMMANDS" -eq 1 ] && install_commands
[ "$INSTALL_SKILLS" -eq 1 ] && install_skills
if [ "$INSTALL_HOOK" -eq 1 ]; then
  register_stop_hook
  register_enforce_hook
fi
[ "$INSTALL_BIN" -eq 1 ] && install_bin

echo "done. Restart Claude Code (or reload /hooks) so agents, commands, skills, hooks, and plumbline CLI are picked up."

# The plumbline CLI lands in $CLAUDE_HOME/bin. If that's not on the user's $PATH, a bare
# `plumbline ...` is "command not found" — so say so unmistakably (the install audit's
# top user-facing symptom).
# shellcheck disable=SC2016  # the $PATH and `export PATH=...` are intentional literals to paste
case ":${PATH:-}:" in
  *":$CLAUDE_HOME/bin:"*) : ;;  # already discoverable — nothing to say
  *)
    printf '\n'
    printf '  ======================================================================\n'
    printf '   ACTION NEEDED: the plumbline CLI is installed but NOT on your $PATH.\n'
    printf '   Without this, "plumbline ..." will be command not found.\n'
    printf '\n'
    printf '       export PATH="%s/bin:$PATH"\n' "$CLAUDE_HOME"
    printf '\n'
    printf '   Add that line to your shell rc (~/.zshrc or ~/.bashrc), then restart\n'
    printf '   your shell. (/plumbline-update is the Claude Code slash command,\n'
    printf '   separate from the plumbline terminal CLI.)\n'
    printf '  ======================================================================\n'
    ;;
esac
