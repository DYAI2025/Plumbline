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
# Update mode (PUR-3.2): refresh an existing $CLAUDE_HOME install in place.
# transfer() then OVERWRITES a changed existing target (content-compare) instead
# of skipping it, in BOTH symlink and copy modes, and still ADDS new files. This
# is what lets `plumbline update` actually push new content into a user's home;
# normal (non-update) install behavior is unchanged.
UPDATE=0
INSTALL_AGENTS=1
INSTALL_COMMANDS=1
INSTALL_SKILLS=1
INSTALL_HOOK=1
INSTALL_BIN=1
WITH_FLOW=0
DRY_RUN=0

usage() {
  cat <<USAGE
Usage: $0 [--copy] [--force] [--update] [--dry-run] [--with-flow-agents] [--no-agents] [--no-commands] [--no-skills] [--no-hook] [--no-bin]

Installs the repo for Claude Code by:
  - installing the MCP-free agents into \$CLAUDE_HOME/agents (default; the ~35 claude-flow /
    flow-nexus / sublinear agents are omitted unless --with-flow-agents, so a plain install
    never pulls you toward the heavy claude-flow MCP stack),
  - installing all vendored commands from config/claude/commands/,
  - installing all vendored skills from config/claude/skills/,
  - registering the sentinel-gated learning-loop Stop hook,
  - registering the fail-closed PRIL enforcement Stop hook,
  - installing the plumbline CLI into $CLAUDE_HOME/bin/ with its Python libraries in $CLAUDE_HOME/lib/.

--update refreshes an existing \$CLAUDE_HOME install in place: a CHANGED existing
target is overwritten (content-compared) and new files are added, in both symlink
and copy modes (normal installs leave existing targets untouched without --force).

Environment:
  CLAUDE_HOME  Override target Claude home (default: $HOME/.claude)
USAGE
}

for arg in "$@"; do
  case "$arg" in
    --copy) MODE="copy" ;;
    --force) FORCE=1 ;;
    --update) UPDATE=1 ;;
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

# canonical_path <path>: print the fully-resolved real absolute path of a file OR
# directory, or print nothing (empty) and return non-zero when the path does not
# resolve to an existing target. FAIL-CLOSED (REQ-PUR-FOLLOWUP-SAMEPATH): this
# "empty + non-zero" post-condition holds for EVERY unresolvable input, namely:
#   * a path that does not exist at all,
#   * a DANGLING symlink whose final target is missing (even when the target's
#     parent directory exists), and
#   * a symlink LOOP or a chain longer than the ~40-hop bound.
# Only a real existing file, directory, or symlink that resolves to an existing
# target prints a non-empty path with return code 0; nothing else ever does.
#
# A DIRECTORY resolves with `cd … && pwd -P` (physical, symlinks collapsed) — same
# as the old code. A FILE (or symlink) cannot be `cd`'d into, so we canonicalize via
# its DIRNAME (`cd "$(dirname …)" && pwd -P`) plus the basename, and dereference a
# FINAL symlink component to its real target — resolving a relative link target
# against the link's own directory and iterating until the result is no longer a
# symlink (so chained links collapse). This is the bash-3.2-safe / macOS-portable
# stand-in for `readlink -f` (BSD readlink lacks -f); it uses plain `readlink` and
# does the dereference manually.
canonical_path() {
  local p="$1"
  [ -e "$p" ] || [ -L "$p" ] || return 1
  # Directory: physical absolute path (collapses symlinked path components).
  if [ -d "$p" ] && [ ! -L "$p" ]; then
    ( cd "$p" 2>/dev/null && pwd -P ) || return 1
    return 0
  fi
  # File or symlink: dereference a final symlink chain, bounded to avoid loops.
  local dir base target hops=0
  while [ -L "$p" ] && [ "$hops" -lt 40 ]; do
    target="$(readlink "$p")" || return 1
    case "$target" in
      /*) p="$target" ;;                       # absolute link target
      *)  p="$(dirname "$p")/$target" ;;       # relative -> resolve against link dir
    esac
    hops=$((hops + 1))
  done
  # Fail-closed (REQ-PUR-FOLLOWUP-SAMEPATH): the deref loop above can exit in two
  # unresolvable states that the docstring forbids resolving to a confident path.
  #   * Still a symlink after the hop bound => a symlink LOOP or an over-long chain;
  #     never canonicalize a mid-chain path -- fail (empty, non-zero).
  [ -L "$p" ] && return 1
  #   * The resolved final target does not exist (a DANGLING link whose target's
  #     parent dir happens to exist) -- fail rather than print a would-be path.
  { [ -e "$p" ] || [ -L "$p" ]; } || return 1
  # If the resolved path is now a directory, canonicalize it as one.
  if [ -d "$p" ]; then
    ( cd "$p" 2>/dev/null && pwd -P ) || return 1
    return 0
  fi
  dir="$(dirname "$p")"
  base="$(basename "$p")"
  local real_dir
  real_dir="$( cd "$dir" 2>/dev/null && pwd -P )" || return 1
  [ -n "$real_dir" ] || return 1
  printf '%s/%s\n' "$real_dir" "$base"
}

# same_path <a> <b>: true (0) when a and b resolve to the SAME real path. File-aware
# via canonical_path, so two DIFFERENT files compare UNEQUAL and a symlink is "same
# path" as its target ONLY when it actually resolves there. False if either side is
# missing/unresolvable (empty canonical_path).
same_path() {
  local a b
  a="$(canonical_path "$1")" || return 1
  b="$(canonical_path "$2")" || return 1
  [ -n "$a" ] && [ -n "$b" ] && [ "$a" = "$b" ]
}

# content_current <src> <dst>: true (0) when the existing target already holds
# the source's content, so an --update refresh can idempotently skip it. Files are
# compared byte-for-byte; directories are compared recursively. A symlink target
# is never "current" under copy-update (it must be replaced by real content), and a
# missing target is never current. Used only by --update; normal installs keep the
# untouched "skip if exists" behavior.
content_current() {
  local src="$1" dst="$2"
  [ -e "$dst" ] || return 1
  # A symlink that already resolves to the same source path is current; otherwise
  # the link must be replaced (e.g. a stale symlink, or a symlink where update now
  # materializes a copy).
  if [ -L "$dst" ]; then
    if [ "$MODE" = "symlink" ] && same_path "$src" "$dst"; then
      return 0
    fi
    return 1
  fi
  if [ -d "$src" ] && [ -d "$dst" ]; then
    diff -rq "$src" "$dst" >/dev/null 2>&1 && return 0
    return 1
  fi
  if [ -f "$src" ] && [ -f "$dst" ]; then
    cmp -s "$src" "$dst" && return 0
    return 1
  fi
  return 1
}

transfer() {
  local src="$1" dst="$2"
  if [ ! -e "$src" ]; then
    echo "missing source: $src" >&2
    exit 1
  fi
  # --update (PUR-3.2): overwrite a CHANGED existing target (content-compare) in
  # BOTH modes; idempotently skip an UNCHANGED one; and fall through to write a
  # NEW (absent) target. This replaces the plain "skip if exists" so a real user's
  # home is actually refreshed.
  if [ "$UPDATE" -eq 1 ]; then
    if [ -e "$dst" ] && content_current "$src" "$dst"; then
      log_action "up-to-date: $dst"
      return
    fi
    # else: changed or new -> fall through and (re)write it below.
  elif [ -e "$dst" ] && [ "$FORCE" -ne 1 ]; then
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

# Write the install-identity anchor ($CLAUDE_HOME/.plumbline-install.json) so the
# INSTALLED plumbline CLI knows which Plumbline it is and where its updates come
# from, INDEPENDENT of whatever directory the user later runs it from. Without
# this anchor the installed lib falls through to the current working directory's
# VERSION / git origin (the cwd-dependence bug). Idempotent: a re-install always
# overwrites it with the CURRENT source values. Plain JSON, no secrets.
write_install_anchor() {
  local anchor="$CLAUDE_HOME/.plumbline-install.json"

  # version: read from the SOURCE VERSION (the repo being installed FROM), taking
  # the first MAJOR.MINOR.PATCH token so release-please comment lines are ignored.
  local version=""
  if [ -f "$REPO_DIR/VERSION" ]; then
    version="$(grep -oE '[0-9]+\.[0-9]+\.[0-9]+' "$REPO_DIR/VERSION" | head -n1)"
  fi
  [ -n "$version" ] || version="0.0.0"

  # repo_slug: from the SOURCE git origin (owner/repo), fallback to the literal.
  local origin_url="" repo_slug="DYAI2025/Plumbline"
  origin_url="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null || true)"
  if [ -n "$origin_url" ]; then
    # Strip a trailing .git and any trailing slash, then take owner/repo.
    local stripped="${origin_url%.git}"
    stripped="${stripped%/}"
    local owner_repo=""
    case "$stripped" in
      *github.com[:/]*)
        owner_repo="${stripped#*github.com}"
        owner_repo="${owner_repo#:}"
        owner_repo="${owner_repo#/}"
        ;;
    esac
    # Accept only a clean owner/repo (exactly one slash, no spaces).
    case "$owner_repo" in
      */*/*|"") : ;;            # too many slashes or empty -> keep fallback
      *" "*) : ;;               # whitespace -> keep fallback
      */*) repo_slug="$owner_repo" ;;
    esac
  fi

  # source_commit: best-effort current HEAD of the source checkout (CR-5). Use
  # `rev-parse --verify HEAD`: on a commitless repo (unborn HEAD) plain
  # `rev-parse HEAD` prints the LITERAL string `HEAD` to stdout and the `|| true`
  # swallows its non-zero exit, recording useless placeholder provenance.
  # `--verify` instead prints nothing for an unborn HEAD, so source_commit stays
  # empty. Belt: accept only an exact 40-hex sha, else record empty — never `HEAD`.
  local source_commit=""
  source_commit="$(git -C "$REPO_DIR" rev-parse --verify HEAD 2>/dev/null || true)"
  case "$source_commit" in
    *[!0-9a-f]* | "") source_commit="" ;;   # any non-hex char (incl. 'HEAD') -> empty
    *) [ "${#source_commit}" -eq 40 ] || source_commit="" ;;  # only a full 40-hex sha
  esac

  # installed_at: UTC timestamp (best-effort; never fail the install on this).
  local installed_at=""
  installed_at="$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || true)"

  if [ "$DRY_RUN" -eq 1 ]; then
    log_action "would write install anchor: $anchor (version=$version repo_slug=$repo_slug)"
    return
  fi
  mkdir -p "$CLAUDE_HOME"
  # Emit the anchor via python3's json.dumps so EVERY field is correctly escaped.
  # An origin/slug containing a double-quote (or any other JSON metacharacter)
  # would corrupt a raw printf-interpolated body into invalid JSON; json.dumps
  # makes the file valid JSON for ANY origin. python3 is a hard dependency of
  # this repo. Values are passed as argv (never interpolated into the program
  # text), so this is injection-free regardless of how exotic the origin is.
  python3 -c 'import json, sys
keys = ["version", "repo_slug", "source_commit", "installed_at"]
print(json.dumps(dict(zip(keys, sys.argv[1:])), indent=2))' \
    "$version" "$repo_slug" "$source_commit" "$installed_at" > "$anchor"
  echo "wrote install anchor: $anchor"
}

install_bin_libs() {
  local src_dir="$REPO_DIR/config/claude/lib"
  [ -d "$src_dir" ] || return 0
  while IFS= read -r -d '' lib; do
    transfer "$lib" "$CLAUDE_HOME/lib/$(basename "$lib")"
  done < <(find "$src_dir" -maxdepth 1 -type f -name '*.py' -print0 | sort -z)
  write_install_anchor
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

# Idempotently add the PreToolUse VISION_MISSING backstop hook to
# ~/.claude/settings.json. Mirrors register_enforce_hook exactly in structure
# (jq presence check, DRY_RUN, mkdir, valid-JSON check, dedup, mktemp+mv) but
# targets .hooks.PreToolUse and carries a matcher so the harness only invokes it
# for planning/coding-capable tools. A backstop hook that is never wired here is
# inert (built-but-not-wired), so this is what actually closes REQ-A-011.
register_pretool_vision_hook() {
  local settings="$CLAUDE_HOME/settings.json"
  local hook_script="$REPO_DIR/config/claude/hooks/pretool-vision-gate.sh"
  if [ -f "$CLAUDE_HOME/agents/config/claude/hooks/pretool-vision-gate.sh" ]; then
    hook_script="$CLAUDE_HOME/agents/config/claude/hooks/pretool-vision-gate.sh"
  fi
  local cmd="bash \"$hook_script\""

  if ! command -v jq >/dev/null 2>&1; then
    echo "skip pretool-vision-hook: jq not found — install jq and re-run, or add it manually to $settings"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log_action "would register pretool-vision-hook in $settings with command: $cmd"
    return
  fi
  mkdir -p "$CLAUDE_HOME"
  [ -f "$settings" ] || echo '{}' > "$settings"
  if ! jq -e . "$settings" >/dev/null 2>&1; then
    echo "skip pretool-vision-hook: $settings is not valid JSON — fix it first"
    return
  fi
  if jq -e '[.hooks.PreToolUse[]?.hooks[]? | .command? // ""] | any(test("pretool-vision-gate\\.sh"))' \
       "$settings" >/dev/null 2>&1; then
    echo "skip pretool-vision-hook: already registered in $settings"
    return
  fi
  local tmp; tmp="$(mktemp)"
  if jq --arg cmd "$cmd" '
    .hooks //= {} |
    .hooks.PreToolUse //= [] |
    .hooks.PreToolUse += [ { "matcher": "Task|Write|Edit|MultiEdit|NotebookEdit", "hooks": [ { "type": "command", "command": $cmd, "timeout": 10 } ] } ]
  ' "$settings" > "$tmp"; then
    mv "$tmp" "$settings"
    echo "registered pretool-vision-hook in $settings"
  else
    rm -f "$tmp"
    echo "skip pretool-vision-hook: jq failed to update $settings" >&2
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
  register_pretool_vision_hook
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
