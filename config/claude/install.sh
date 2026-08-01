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
IGNORE_RUNTIME_STATE=0

usage() {
  cat <<USAGE
Usage: $0 [--copy] [--force] [--update] [--dry-run] [--with-flow-agents] [--ignore-runtime-state] [--no-agents] [--no-commands] [--no-skills] [--no-hook] [--no-bin]

Installs the repo for Claude Code by:
  - installing the MCP-free agents into \$CLAUDE_HOME/agents (default; the ~35 claude-flow /
    flow-nexus / sublinear agents are omitted unless --with-flow-agents, so a plain install
    never pulls you toward the heavy claude-flow MCP stack),
  - installing all vendored commands from config/claude/commands/,
  - installing all vendored skills from config/claude/skills/,
  - registering the sentinel-gated learning-loop Stop hook,
  - registering the fail-closed PRIL enforcement Stop hook,
  - installing the plumbline CLI into $CLAUDE_HOME/bin/ with its runtime libraries in $CLAUDE_HOME/lib/.

--ignore-runtime-state additionally makes THIS repository ignore volatile agent
runtime state (.claude-flow/, .swarm/, .claude/homunculus/, ...) by appending a
marked block to its .gitignore. Purely additive: no existing rule is rewritten, no
file is deleted, and an already-tracked runtime file is never untracked for you --
the check prints the removal command instead (git rm -r --cached, which keeps the
working copy). Without the flag the installer only reports what it would do.

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
    --ignore-runtime-state) IGNORE_RUNTIME_STATE=1 ;;
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

# normalize_remote <url> -- comparable repository identity.
# Reduces https://host/Owner/Repo.git and git@host:Owner/Repo.git to host/owner/repo,
# so the SAME repository reached by different URL forms compares equal and a DIFFERENT
# repository never does.
normalize_remote() {
  local url="$1"
  [ -n "$url" ] || return 1
  url="${url%.git}"
  url="${url#*://}"          # strip scheme
  url="${url#*@}"            # strip user@
  url="$(printf '%s' "$url" | tr ':' '/' | tr '[:upper:]' '[:lower:]')"
  printf '%s' "$url"
}

# plumbline_managed_symlink <path> -- true only for a symlink this installer owns.
#
# transfer() only ever writes inside $CLAUDE_HOME/{agents,commands,skills,bin,lib}, so
# the DESTINATION is already our domain; the question is whether the entry sitting there
# came from a previous run of this installer or from something else.
#
# "Ours" = a symlink whose basename matches AND whose target lies in one of the source
# shapes this installer links from: `config/claude/...` (bin, lib, commands, skills) or
# an `agents/` tree. A link pointing anywhere else -- e.g. another tool's binary that
# happens to share a name -- is foreign and is never replaced.
#
# The first version of this only accepted config/claude/{bin,lib} and therefore refused
# to refresh AGENT symlinks, breaking --update. Caught by the update-layer suite.
plumbline_managed_symlink() {
  local dst="$1" target="" root=""
  [ -L "$dst" ] || return 1
  target="$(readlink "$dst" 2>/dev/null)" || return 1
  case "$target" in /*) ;; *) target="$(dirname "$dst")/$target" ;; esac

  # A DANGLING link at one of our destinations is ours to repair: the checkout it
  # pointed into was moved or deleted, which is exactly the case a repoint must be
  # able to fix. Refusing here would dead-end every moved-checkout migration.
  #
  # But adoption must be a NAMED decision, not a silent one. A foreign link that is
  # merely broken right now -- unmounted volume, tool mid-upgrade, target moved -- is
  # adopted by this rule, and the contract a few lines below is "a name collision must
  # not become a silent takeover". Nothing is destroyed either way (removing a symlink
  # never touches its target), so the honest fix is to say so, not to refuse.
  if [ ! -e "$target" ]; then
    log_action "adopting dangling link: $dst -> $target (previous target is gone)"
    return 0
  fi

  # Canonicalize before walking. The walk is otherwise purely lexical, so a relative
  # target like ../../plumbtree/../elsewhere/x matches "plumbtree" and is accepted even
  # though it resolves outside any Plumbline tree.
  local canon=""
  canon="$(canonical_path "$target")" || canon=""
  [ -n "$canon" ] && target="$canon"

  # Otherwise: ours iff the link points INTO a Plumbline checkout, i.e. some ancestor
  # of the target carries the installer itself. One uniform rule for all five layers
  # (agents, commands, skills, bin, lib) -- an earlier version matched only
  # config/claude/{bin,lib} and therefore classified all 61 agent, 11 command and 16
  # skill links as foreign, refusing to repoint them while repointing the CLIs. That
  # is precisely the mixed runtime this work exists to prevent, and it exited 0.
  # Bound the walk. A single stray `config/claude/install.sh` at a HIGH ancestor --
  # $HOME being the obvious one -- would otherwise mark every link under it as ours and
  # disable the foreign-symlink refusal wholesale. A Plumbline checkout is never $HOME
  # and never an ancestor of $CLAUDE_HOME, so those are hard stops.
  local stop_home="" stop_claude=""
  stop_home="$(canonical_path "$HOME")" || stop_home=""
  stop_claude="$(canonical_path "$CLAUDE_HOME")" || stop_claude=""
  # Test the marker BEFORE the ancestor stops, so a directory that is genuinely a
  # Plumbline checkout is recognised even when $CLAUDE_HOME happens to live inside it
  # (a dev-sandbox layout the installer documents via the CLAUDE_HOME override).
  # Checking the stops first refused those outright: 7 refusals, 0 layers repointed --
  # a complete inversion of the repoint this work exists to perform.
  #
  # $HOME itself is still never accepted: that is the stray-marker case, where one
  # `config/claude/install.sh` at a high ancestor would otherwise mark every link
  # beneath it as ours and disable the foreign-symlink refusal wholesale.
  root="$(dirname "$target")"
  while [ -n "$root" ] && [ "$root" != "/" ] && [ "$root" != "." ]; do
    if [ -f "$root/config/claude/install.sh" ] && [ "$root" != "$stop_home" ]; then
      return 0
    fi
    if [ -n "$stop_home" ] && [ "$root" = "$stop_home" ]; then return 1; fi
    if [ -n "$stop_claude" ]; then
      case "$stop_claude/" in
        "$root"/*) return 1 ;;   # root is $CLAUDE_HOME or an ancestor of it
      esac
    fi
    root="$(dirname "$root")"
  done
  return 1
}

# safe_to_replace <dst> -- may transfer() overwrite this destination?
#
# The unguarded `rm -rf "$dst"` below would happily delete a symlink belonging to
# another tool. That is the case worth refusing: a link at one of our destination
# paths that points OUTSIDE any install source is somebody else's, and a name
# collision must not become a silent takeover.
#
# A regular FILE is different, and an earlier stricter rule got this wrong. Control
# only reaches here when the caller explicitly asked to write -- a plain install
# returns early on any existing target (skip-if-exists), so a real file here means
# --update or --force. Refusing it would make a --copy install permanently
# un-updatable and break the documented refresh path; the update-layer suite plants
# exactly that stale real file and requires it to be overwritten.
#
# Paths the installer never writes (another tool's script that merely lives in
# $CLAUDE_HOME/bin) are never destinations, so they are never considered at all.
safe_to_replace() {
  local dst="$1"
  [ -e "$dst" ] || [ -L "$dst" ] || return 0          # absent: free to write
  if [ -L "$dst" ]; then
    plumbline_managed_symlink "$dst" && return 0
    echo "REFUSING to replace foreign symlink: $dst -> $(readlink "$dst")" >&2
    return 1
  fi
  return 0
}

TRANSFER_REFUSALS=0

# layer_root_safe <layer-dir> -- may we write into this install layer at all?
#
# $CLAUDE_HOME/{agents,commands,skills,bin,lib} can each be a SYMLINK. If one resolves
# OUTSIDE $CLAUDE_HOME, every transfer() into it writes through the link and lands
# somewhere we were never asked to touch -- and `rm -rf "$dst"` then deletes whatever
# shares a name there.
#
# This is not hypothetical: it happened during review of this very change. A reviewer
# copied ~/.claude with `cp -a`, which preserved `skills -> ~/.claude/skills-unified` as
# an ABSOLUTE link back into the real home; installing into the copy rewrote 16 entries
# in the user's actual shared skills directory. Nothing was lost, but nothing stopped it
# either.
#
# A layer root that resolves INSIDE $CLAUDE_HOME is fine (that same
# `skills -> skills-unified` layout is legitimate and common). Only an escape is refused.
layer_root_safe() {
  local layer="$1" real_home="" real_layer=""
  # `-e` FOLLOWS symlinks, so a DANGLING layer root reads as "absent" and sails past
  # every check below -- then transfer()'s `mkdir -p` fails, `set -e` kills the run at
  # exit 1 with no REFUSING line, no count, and a partially applied home. Test for the
  # link itself too.
  if [ ! -e "$layer" ] && [ ! -L "$layer" ]; then
    return 0                              # genuinely absent: transfer() creates it
  fi
  if [ -L "$layer" ] && [ ! -e "$layer" ]; then
    # A dangling layer root: create what it points at (if that is inside $CLAUDE_HOME)
    # rather than dying in mkdir. Announced, never silent -- same stance as adopting a
    # dangling wrapper link.
    local dangling_target=""
    dangling_target="$(readlink "$layer" 2>/dev/null)" || dangling_target=""
    case "$dangling_target" in
      /*) ;;
      *) dangling_target="$(dirname "$layer")/$dangling_target" ;;
    esac
    real_home="$(canonical_path "$CLAUDE_HOME")" || real_home=""
    # The target does not exist, so canonical_path cannot resolve it directly.
    # Canonicalize its PARENT and re-append the basename -- otherwise a /var vs
    # /private/var mismatch makes an in-home target look like an escape (the macOS
    # path-canonicalization class this repo has already been bitten by twice).
    local dt_parent="" dt_canon=""
    dt_parent="$(canonical_path "$(dirname "$dangling_target")")" || dt_parent=""
    if [ -n "$dt_parent" ]; then
      dt_canon="$dt_parent/$(basename "$dangling_target")"
    else
      dt_canon="$dangling_target"
    fi
    case "$dt_canon/" in
      "$real_home"/*)
        log_action "creating dangling layer root: $layer -> $dt_canon"
        mkdir -p "$dt_canon" 2>/dev/null || true
        return 0
        ;;
    esac
    echo "REFUSING to write into $layer: it is a dangling symlink to $dangling_target, OUTSIDE \$CLAUDE_HOME." >&2
    return 1
  fi
  real_home="$(canonical_path "$CLAUDE_HOME")" || real_home=""
  real_layer="$(canonical_path "$layer")" || real_layer=""
  if [ -z "$real_home" ] || [ -z "$real_layer" ]; then
    log_action "REFUSING to write into $layer: cannot canonicalize it or \$CLAUDE_HOME"
    return 1
  fi
  case "$real_layer/" in
    "$real_home"/*) return 0 ;;
  esac
  # Routed through log_action so a --dry-run preview reads "dry-run: REFUSING …" rather
  # than claiming an action already taken. A preview that lies in either direction is
  # worse than no preview.
  log_action "REFUSING to write into $layer: it resolves to $real_layer, OUTSIDE \$CLAUDE_HOME ($real_home)."
  log_action "         Writing there would modify files this install was never pointed at."
  return 1
}

# resolve_hook_script <hook-basename>
#
# Which copy of a hook should be REGISTERED in settings.json. The old rule was "if a
# file of that name exists under $CLAUDE_HOME/agents, prefer it" -- which assumes that
# directory belongs to this repo. Measured 2026-07-30 on a real machine: it did not, and
# the installer "repointed" enforcement into a 7-week-old copy carrying none of the
# current gates -- worse than the stale path it was fixing, and invisible because it
# reported success.
#
# Corrected 2026-07-31 (the first version of this comment was wrong): `~/.claude/agents`
# there has NO .git of its own. `git rev-parse` from inside it walks UP and reports
# $HOME, which IS a working tree (origin DYAI2025/azodiac) whose .gitignore excludes
# .claude/*. So the stale copy is an UNTRACKED file in a gitignored subtree of an
# unrelated repository -- which is exactly why an ancestor's identity cannot stand in
# for the file's provenance (see the tracked-ness check below).
#
# The agents copy may now be used ONLY when all of these hold:
#   1. it lives in a git repository;
#   2. that repository's normalized remote identity equals $REPO_DIR's;
#   3. that repository root is itself a Plumbline checkout (carries
#      config/claude/install.sh);
#   4. the hook file is TRACKED by that repository (an ancestor's identity says
#      nothing about an untracked file sitting under it);
#   5. the hook file there is byte-identical to this checkout's;
# and the chosen source plus the REASON is always printed. Anything else -- including
# "identity cannot be determined" -- falls back to this checkout. Fail-safe means
# preferring the source we can verify, never the foreign one.
#
# Sets HOOK_SRC_REASON. Never modifies the agents tree.
HOOK_SRC_REASON=""
HOOK_SRC_PATH=""
resolve_hook_script() {
  local name="$1"
  local repo_hook="$REPO_DIR/config/claude/hooks/$name"
  local agents_dir="$CLAUDE_HOME/agents"
  local agents_hook="$agents_dir/config/claude/hooks/$name"

  if [ ! -f "$agents_hook" ]; then
    HOOK_SRC_REASON="no copy under $agents_dir"
    HOOK_SRC_PATH="$repo_hook"; return 0
  fi

  local agents_root=""
  agents_root="$(git -C "$agents_dir" rev-parse --show-toplevel 2>/dev/null)" || agents_root=""
  if [ -z "$agents_root" ]; then
    HOOK_SRC_REASON="$agents_dir is not inside a git repository (identity unverifiable)"
    HOOK_SRC_PATH="$repo_hook"; return 0
  fi

  # Order matters: identity first (the contract's clause 2), then provenance, then
  # byte-identity. Checking provenance first would report "not a Plumbline checkout"
  # for a foreign repo whose real disqualifier is that it is a DIFFERENT repository.
  local a_remote r_remote
  a_remote="$(normalize_remote "$(git -C "$agents_root" remote get-url origin 2>/dev/null)")" || a_remote=""
  r_remote="$(normalize_remote "$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null)")" || r_remote=""
  if [ -z "$a_remote" ] || [ -z "$r_remote" ]; then
    HOOK_SRC_REASON="repository identity undeterminable (fail-safe: using this checkout)"
    HOOK_SRC_PATH="$repo_hook"; return 0
  fi
  if [ "$a_remote" != "$r_remote" ]; then
    HOOK_SRC_REASON="$agents_dir is a DIFFERENT repository ($a_remote, not $r_remote)"
    HOOK_SRC_PATH="$repo_hook"; return 0
  fi

  # `rev-parse --show-toplevel` walks UP: it answers "which repository CONTAINS this
  # directory", never "is this file part of it". Measured on the real machine:
  # ~/.claude/agents has NO .git at all, and rev-parse from inside it reports $HOME --
  # itself a working tree (origin azodiac) whose .gitignore excludes .claude/*, so the
  # stale hook there is UNTRACKED. A matching ancestor identity must not launder a file
  # git knows nothing about, so require BOTH: the root looks like a Plumbline checkout,
  # and the hook is actually tracked by it.
  if [ ! -f "$agents_root/config/claude/install.sh" ]; then
    HOOK_SRC_REASON="$agents_root is not a Plumbline checkout (no config/claude/install.sh)"
    HOOK_SRC_PATH="$repo_hook"; return 0
  fi
  if ! git -C "$agents_root" ls-files --error-unmatch -- "$agents_hook" >/dev/null 2>&1; then
    HOOK_SRC_REASON="the agents copy of $name is UNTRACKED by $agents_root (provenance unverifiable)"
    HOOK_SRC_PATH="$repo_hook"; return 0
  fi

  if ! cmp -s "$agents_hook" "$repo_hook"; then
    HOOK_SRC_REASON="agents copy of $name differs from this checkout"
    HOOK_SRC_PATH="$repo_hook"; return 0
  fi

  HOOK_SRC_REASON="agents copy is the same repository and byte-identical"
  HOOK_SRC_PATH="$agents_hook"; return 0
}

transfer() {
  local src="$1" dst="$2" effective_mode="${3:-$MODE}"
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
  # The refusal check runs BEFORE the dry-run preview, so the preview models what the
  # real run will actually do. Previously --dry-run reported "would symlink" for targets
  # the real run then refused -- a preview that lies is worse than no preview, and this
  # one is used to decide whether to touch global settings.
  if ! safe_to_replace "$dst"; then
    TRANSFER_REFUSALS=$((TRANSFER_REFUSALS + 1))
    # NOT `[ cond ] && cmd` as the last statement: under `set -e` that returns 1 when
    # the condition is false and kills the installer mid-run -- which it did, right
    # after printing the first refusal.
    if [ "$DRY_RUN" -eq 1 ]; then
      log_action "would REFUSE:   $dst"
    fi
    return 0
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    if [ "$effective_mode" = "copy" ]; then
      log_action "would copy:     $src -> $dst"
    else
      log_action "would symlink:  $dst -> $src"
    fi
    return
  fi
  mkdir -p "$(dirname "$dst")"
  rm -rf "$dst"
  if [ "$effective_mode" = "copy" ]; then
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
  # Back-compat FIRST, before the escape guard. An older install created
  # `~/.claude/agents -> $REPO_DIR` as a whole-repo symlink, and $REPO_DIR is by
  # definition outside $CLAUDE_HOME -- so checking the guard first refused it, made this
  # branch unreachable dead code, and turned every legacy machine's `plumbline update`
  # into exit 3. plumbline_update.py reverts the WHOLE $CLAUDE_HOME on a non-zero exit,
  # so that would have been an unrecoverable loop on every attempt.
  #
  # A link to this very checkout is not the foreign-escape class the guard exists for:
  # it IS the install source. Recognise it, then guard everything else.
  if same_path "$REPO_DIR" "$target"; then
    log_action "skip agents: $target already points at this repo"
    return
  fi
  if ! layer_root_safe "$target"; then
    TRANSFER_REFUSALS=$((TRANSFER_REFUSALS + 1))
    return 0
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
  if ! layer_root_safe "$CLAUDE_HOME/commands"; then
    TRANSFER_REFUSALS=$((TRANSFER_REFUSALS + 1))
    return 0
  fi
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
  if ! layer_root_safe "$CLAUDE_HOME/skills"; then
    TRANSFER_REFUSALS=$((TRANSFER_REFUSALS + 1))
    return 0
  fi
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
  if ! layer_root_safe "$CLAUDE_HOME/lib"; then
    TRANSFER_REFUSALS=$((TRANSFER_REFUSALS + 1))
    return 0
  fi
  local src_dir="$REPO_DIR/config/claude/lib"
  local name transfer_mode
  [ -d "$src_dir" ] || return 0
  while IFS= read -r -d '' lib; do
    name="$(basename "$lib")"
    transfer_mode="$MODE"
    case "$name" in
      plumbline_python.sh|plumbline_scope.py|plumbline_scope_update.py)
        # These files form the executable scope authority. A symlink back into
        # the governed checkout would let that checkout authenticate itself and
        # would also strand confirmed replanning once project-local authority is
        # correctly rejected. Keep an independent install-time snapshot.
        transfer_mode="copy"
        ;;
    esac
    transfer "$lib" "$CLAUDE_HOME/lib/$name" "$transfer_mode"
  done < <(find "$src_dir" -maxdepth 1 -type f -print0 | sort -z)
  write_install_anchor
}

install_bin() {
  if ! layer_root_safe "$CLAUDE_HOME/bin"; then
    TRANSFER_REFUSALS=$((TRANSFER_REFUSALS + 1))
    return 0
  fi
  local src_dir="$REPO_DIR/config/claude/bin"
  local name transfer_mode
  [ -d "$src_dir" ] || return 0
  while IFS= read -r -d '' tool; do
    name="$(basename "$tool")"
    transfer_mode="$MODE"
    case "$name" in
      plumbline-scope-check|plumbline-scope-update)
        # Scope authorization and its sole confirmed repair path must resolve
        # outside the repository whose writes they judge, even in the default
        # live/symlink install mode.
        transfer_mode="copy"
        ;;
    esac
    transfer "$tool" "$CLAUDE_HOME/bin/$name" "$transfer_mode"
  done < <(find "$src_dir" -maxdepth 1 -type f -print0 | sort -z)
}

# Idempotently add the learning-loop Stop hook to ~/.claude/settings.json,
# preserving any existing hooks and other settings.
register_stop_hook() {
  local settings="$CLAUDE_HOME/settings.json"
  resolve_hook_script stop-learning-loop.sh
  local hook_script="$HOOK_SRC_PATH"
  echo "hook source (stop-learning-loop.sh): $hook_script"
  echo "  reason: $HOOK_SRC_REASON"
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
  # Same repoint contract as the enforce and vision hooks. Without it this function
  # printed a resolved "hook source" and then did NOT use it: any existing registration
  # -- including a copy at an unmanaged path that no identity or provenance check ever
  # validated -- was left in place, while its two siblings repointed. That is a mixed
  # HOOK runtime, and the log actively misreported which source had been chosen.
  local matches=""
  matches="$(jq -r '[.hooks.Stop[]?.hooks[]? | .command? // ""]
    | map(select(test("stop-learning-loop\\.sh"))) | .[]' "$settings" 2>/dev/null)"
  if [ -n "$matches" ]; then
    local n_match stale=0
    n_match="$(printf '%s\n' "$matches" | grep -c .)"
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      case "$m" in
        *"$hook_script"*) ;;
        *) stale=1; echo "  stale: $m" ;;
      esac
    done <<EOF
$matches
EOF
    if [ "$n_match" -gt 1 ]; then
      echo "NOTE: stop-hook is registered $n_match times in $settings."
      echo "      All are repointed; remove the extra entr(ies) by hand if unwanted."
    fi
    if [ "$stale" -eq 0 ]; then
      echo "skip stop-hook: already registered in $settings"
      return
    fi
    echo "REPOINTING stop-hook in $settings -> $hook_script"
    local rtmp; rtmp="$(mktemp)"
    if jq --arg p "$hook_script" '
      .hooks.Stop = [ .hooks.Stop[]? |
        if has("hooks") and (.hooks | type == "array") then
          .hooks = [ .hooks[]? |
            if (.command? // "" | test("stop-learning-loop\\.sh"))
            then .command = (.command | sub("[^ \"]*stop-learning-loop\\.sh"; $p))
            else . end ]
        else . end ]
    ' "$settings" > "$rtmp"; then
      mv "$rtmp" "$settings"
      jq -r '[.hooks.Stop[]?.hooks[]? | .command? // ""]
        | map(select(test("stop-learning-loop\\.sh"))) | .[]' "$settings" 2>/dev/null \
        | sed 's/^/  now: /'
      echo "repointed stop-hook to this checkout"
    else
      rm -f "$rtmp"
      echo "skip stop-hook: jq failed to repoint $settings" >&2
    fi
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
  resolve_hook_script plumbline-enforce.sh
  local hook_script="$HOOK_SRC_PATH"
  echo "hook source (plumbline-enforce.sh): $hook_script"
  echo "  reason: $HOOK_SRC_REASON"
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
  # Idempotence must not become blindness. Registering by "is ANY plumbline-enforce.sh
  # present?" meant a hook registered from an OLD checkout survived every re-install:
  # the installer reported "already registered" while the path pointed at a different,
  # stale tree that lacked the current gates entirely. Measured on this machine
  # 2026-07-30: the registered Stop hook pointed at a checkout 2 days and 4 CLIs behind.
  # So: same path -> genuinely idempotent; DIFFERENT path -> repoint, loudly.
  # ALL matches are considered, not just the first: with two registrations, checking
  # only [0] either declared success while a second stale entry survived, or rewrote
  # every entry to an identical command and produced duplicates.
  # Only the PATH is substituted, never the whole command, so a hand-added env prefix
  # or flag (`env FOO=1 bash /old/... --strict`) survives the repoint.
  local matches=""
  matches="$(jq -r '[.hooks.Stop[]?.hooks[]? | .command? // ""]
    | map(select(test("plumbline-enforce\\.sh"))) | .[]' "$settings" 2>/dev/null)"
  if [ -n "$matches" ]; then
    local n_match stale=0
    n_match="$(printf '%s\n' "$matches" | grep -c .)"
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      case "$m" in
        *"$hook_script"*) ;;
        *) stale=1; echo "  stale: $m" ;;
      esac
    done <<EOF
$matches
EOF
    if [ "$n_match" -gt 1 ]; then
      echo "NOTE: enforce-hook is registered $n_match times in $settings."
      echo "      All are repointed; remove the extra entr(ies) by hand if unwanted."
      echo "      (Registrations are never deleted for you.)"
    fi
    if [ "$stale" -eq 0 ]; then
      echo "skip enforce-hook: already registered in $settings"
      return
    fi
    echo "REPOINTING enforce-hook in $settings -> $hook_script"
    local rtmp; rtmp="$(mktemp)"
    if jq --arg p "$hook_script" '
      .hooks.Stop = [ .hooks.Stop[]? |
        if has("hooks") and (.hooks | type == "array") then
          .hooks = [ .hooks[]? |
            if (.command? // "" | test("plumbline-enforce\\.sh"))
            then .command = (.command | sub("[^ \"]*plumbline-enforce\\.sh"; $p))
            else . end ]
        else . end ]
    ' "$settings" > "$rtmp"; then
      mv "$rtmp" "$settings"
      jq -r '[.hooks.Stop[]?.hooks[]? | .command? // ""]
        | map(select(test("plumbline-enforce\\.sh"))) | .[]' "$settings" 2>/dev/null \
        | sed 's/^/  now: /'
      echo "repointed enforce-hook to this checkout"
    else
      rm -f "$rtmp"
      echo "skip enforce-hook: jq failed to repoint $settings" >&2
    fi
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
  resolve_hook_script pretool-vision-gate.sh
  local hook_script="$HOOK_SRC_PATH"
  echo "hook source (pretool-vision-gate.sh): $hook_script"
  echo "  reason: $HOOK_SRC_REASON"
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
  # Same stale-path blindness, same treatment: all matches, path-only substitution,
  # groups without a `.hooks` array left alone.
  local matches=""
  matches="$(jq -r '[.hooks.PreToolUse[]?.hooks[]? | .command? // ""]
    | map(select(test("pretool-vision-gate\\.sh"))) | .[]' "$settings" 2>/dev/null)"
  if [ -n "$matches" ]; then
    local n_match stale=0
    n_match="$(printf '%s\n' "$matches" | grep -c .)"
    while IFS= read -r m; do
      [ -n "$m" ] || continue
      case "$m" in
        *"$hook_script"*) ;;
        *) stale=1; echo "  stale: $m" ;;
      esac
    done <<EOF
$matches
EOF
    if [ "$n_match" -gt 1 ]; then
      echo "NOTE: pretool-vision-hook is registered $n_match times in $settings."
      echo "      All are repointed; remove the extra entr(ies) by hand if unwanted."
    fi
    if [ "$stale" -eq 0 ]; then
      echo "skip pretool-vision-hook: already registered in $settings"
      return
    fi
    echo "REPOINTING pretool-vision-hook in $settings -> $hook_script"
    local rtmp; rtmp="$(mktemp)"
    if jq --arg p "$hook_script" '
      .hooks.PreToolUse = [ .hooks.PreToolUse[]? |
        if has("hooks") and (.hooks | type == "array") then
          .hooks = [ .hooks[]? |
            if (.command? // "" | test("pretool-vision-gate\\.sh"))
            then .command = (.command | sub("[^ \"]*pretool-vision-gate\\.sh"; $p))
            else . end ]
        else . end ]
    ' "$settings" > "$rtmp"; then
      mv "$rtmp" "$settings"
      jq -r '[.hooks.PreToolUse[]?.hooks[]? | .command? // ""]
        | map(select(test("pretool-vision-gate\\.sh"))) | .[]' "$settings" 2>/dev/null \
        | sed 's/^/  now: /'
      echo "repointed pretool-vision-hook to this checkout"
    else
      rm -f "$rtmp"
      echo "skip pretool-vision-hook: jq failed to repoint $settings" >&2
    fi
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

# Idempotently add the PLUM-12 canonical-scope preflight. It runs only for
# write-capable tools and implementation subagents. Canvas-only legacy features
# pass through; versioned manifests fail closed on missing/extra/contradictory
# plan paths before the first implementation write.
register_pretool_scope_hook() {
  local settings="$CLAUDE_HOME/settings.json"
  local hook_script="$REPO_DIR/config/claude/hooks/pretool-scope-gate.sh"
  if [ -f "$CLAUDE_HOME/agents/config/claude/hooks/pretool-scope-gate.sh" ]; then
    hook_script="$CLAUDE_HOME/agents/config/claude/hooks/pretool-scope-gate.sh"
  fi
  local cmd="bash \"$hook_script\""

  if ! command -v jq >/dev/null 2>&1; then
    echo "skip pretool-scope-hook: jq not found — install jq and re-run, or add it manually to $settings"
    return
  fi
  if [ "$DRY_RUN" -eq 1 ]; then
    log_action "would register pretool-scope-hook in $settings with command: $cmd"
    return
  fi
  mkdir -p "$CLAUDE_HOME"
  [ -f "$settings" ] || echo '{}' > "$settings"
  if ! jq -e . "$settings" >/dev/null 2>&1; then
    echo "skip pretool-scope-hook: $settings is not valid JSON — fix it first"
    return
  fi
  local tmp; tmp="$(mktemp)"
  if jq --arg cmd "$cmd" '
    .hooks //= {} |
    .hooks.PreToolUse //= [] |
    if ([.hooks.PreToolUse[]?.hooks[]? | .command? // ""] |
        any(test("pretool-scope-gate\\.sh"))) then
      .hooks.PreToolUse |= map(
        if ([.hooks[]? | .command? // ""] |
            any(test("pretool-scope-gate\\.sh"))) then
          .matcher = "Agent|Bash|Task|Write|Edit|MultiEdit|NotebookEdit"
        else .
        end
      )
    else
      .hooks.PreToolUse += [ {
        "matcher": "Agent|Bash|Task|Write|Edit|MultiEdit|NotebookEdit",
        "hooks": [ { "type": "command", "command": $cmd, "timeout": 10 } ]
      } ]
    end
  ' "$settings" > "$tmp"; then
    mv "$tmp" "$settings"
    echo "registered or updated pretool-scope-hook in $settings"
  else
    rm -f "$tmp"
    echo "skip pretool-scope-hook: jq failed to update $settings" >&2
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
  register_pretool_scope_hook
fi
# bin and lib are SEPARATE layers with separate escape guards. install_bin used to call
# install_bin_libs itself, so a refusal in `bin` returned early and silently skipped the
# whole `lib` layer AND the install anchor -- while the machine-readable count still said
# one target was refused. Dispatch them independently so each is evaluated and counted.
if [ "$INSTALL_BIN" -eq 1 ]; then
  install_bin
  install_bin_libs
fi

# PLUM-11: volatile agent runtime state must not contaminate a product repository
# or block its scope gates. Reporting is unconditional; WRITING an ignore rule into
# somebody else's repository is opt-in, and nothing is ever deleted or untracked.
runtime_state_hygiene() {
  local hyg="$REPO_DIR/config/claude/bin/plumbline-runtime-hygiene"
  [ -x "$hyg" ] || return 0
  git -C "$REPO_DIR" rev-parse --git-dir >/dev/null 2>&1 || return 0
  if [ "$DRY_RUN" -eq 1 ]; then
    echo "would check agent runtime-state hygiene for $REPO_DIR"
    return 0
  fi
  if [ "$IGNORE_RUNTIME_STATE" -eq 1 ]; then
    "$hyg" --repo "$REPO_DIR" --fix-ignore || true
  else
    "$hyg" --repo "$REPO_DIR" || \
      echo "hint: re-run with --ignore-runtime-state to append the missing ignore rules (additive; deletes nothing)"
  fi
}
runtime_state_hygiene

# Partial failure must be DETECTABLE, not just visible. The refusal counter existed but
# was never read: refusals printed one prose line to stderr, the installer exited 0, and
# an orchestrator (or `plumbline update`, which gates its snapshot-revert on the exit
# code) recorded success over an incoherent runtime. Emit a machine-readable count on
# stdout and exit non-zero so a caller can roll back.
if [ "${TRANSFER_REFUSALS:-0}" -gt 0 ]; then
  echo "PLUMBLINE_INSTALL_REFUSALS=$TRANSFER_REFUSALS"
  echo "INCOMPLETE: $TRANSFER_REFUSALS target(s) were refused; the runtime is NOT coherent."
  echo "            See the REFUSING lines above. Nothing was deleted."
  exit 3
fi

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
