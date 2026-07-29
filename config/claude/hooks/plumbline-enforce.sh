#!/usr/bin/env bash
#
# Fail-closed PRIL enforcement Stop hook (git ground-truth).
#
# Runs the Plumbline Runtime Integrity Layer (PRIL) gates against the real git
# diff when an /agileteam feature run is active, so "fail-closed" is a runtime
# property and not just prose addressed to a cooperative LLM. On any PRIL gate
# failure it returns a `decision: block` so the agent must fix the gate (or
# escalate to the user) before the session ends.
#
# Activation (C1) is a GROUND-TRUTH MARKER the orchestrator writes:
#   docs/context/.active-feature  (the confirmed feature slug)
# It is NOT gated on PLUMBLINE_FEATURE — the runtime never sets that, so a
# variable-gated hook would be a permanent no-op. A normal (non-feature) session
# has no marker, so this hook is an immediate no-op exit 0.
#
# TRUST BOUNDARY: enforcement is only as trustworthy as write-access to
# docs/context/. The orchestrator owns this marker (same trust model as the
# user-confirmed canvas/vision). Therefore a marker that is PRESENT but
# empty/whitespace-only is treated as suspicious (an armed-then-blanked marker by
# which enforcement could be silently disabled) and BLOCKS — it is not a no-op.
# Only a truly ABSENT marker is a no-op (a normal session that was never armed).
#
# Safety contract (mirrors stop-learning-loop.sh):
#   - NEVER exits non-zero (an accidental error must not crash the session).
#   - Honors stop_hook_active (exit 0, no output) to avoid infinite stop loops.
#   - On a PRIL failure emits exactly ONE JSON object to stdout.
#   - FAILS CLOSED: a PRIL gate returning non-zero -> block. It never fails open.
#
# This is a NEW, distinct filename from the deliberately-inert optional pretool
# guard, so the runtime-integrity test's "optional pretool guard is not
# activated" pin stays valid (that pin asserts the inert guard is unregistered).
#
# `set` is intentionally omitted: with `set -e` a single PRIL sub-command failure
# would abort the hook before it could emit the block decision (fail OPEN). We
# want the opposite — collect every failure, then block.

input="$(cat 2>/dev/null)"

# Honor stop_hook_active first: if we already blocked once this stop cycle, let
# the agent finish (no infinite loop). Short-circuits before any enforcement.
# M-1: do not hard-depend on jq for the loop guard — if jq is unavailable a naive
# jq-only parse silently fails and the hook could re-fire. Fall back to a grep on
# the raw payload so the loop guard still holds without jq.
if command -v jq >/dev/null 2>&1; then
  active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
  [ "$active" = "true" ] && exit 0
elif printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# emit_block <reason>: print exactly one block-decision JSON object to stdout.
# Uses jq when available; otherwise a jq-less fallback that strips the only two
# bytes which could break a hand-built JSON string (`"` and `\`). Reasons here are
# controlled literals, so this lossy strip never corrupts a meaningful message.
emit_block() {
  local r="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$r" '{decision:"block", reason:$r}' 2>/dev/null && return 0
  fi
  local safe="${r//\\/}"
  safe="${safe//\"/}"
  printf '{"decision":"block","reason":"%s"}\n' "$safe"
}

: "${CLAUDE_PROJECT_DIR:=$PWD}"
repo="$CLAUDE_PROJECT_DIR"

# --- C1 activation: ground-truth marker the orchestrator writes ---------------
# No marker -> not an active feature run -> no-op. This is what keeps normal
# sessions completely untouched.
marker="$repo/docs/context/.active-feature"
[ -f "$marker" ] || exit 0

# Read the slug; strip any surrounding whitespace/newlines.
feat="$(tr -d ' \t\r\n' < "$marker" 2>/dev/null)"
# H-1 (marker laundering): the marker is PRESENT (we passed the -f check) but the
# slug is empty/whitespace-only. That is an armed-then-blanked marker by which
# enforcement could be silently disabled — BLOCK, never silently no-op. (A truly
# ABSENT marker already exited above as a normal, un-armed session.)
if [ -z "$feat" ]; then
  emit_block "PRIL enforcement: active-feature marker present but empty — enforcement cannot be silently disabled. Restore the confirmed feature slug in docs/context/.active-feature or remove the marker if no feature is active."
  exit 0
fi
# A present slug that could escape into a path/git argument, or be read as a CLI
# flag, is a tampered/suspicious marker (not a blank one) — also BLOCK rather than
# risk it or silently ignore an armed marker.
case "$feat" in
  */*|*\\*|.|..|-*)
    emit_block "PRIL enforcement: active-feature marker present but malformed (slug '$feat' is not a safe feature name). Restore the confirmed feature slug in docs/context/.active-feature or remove the marker."
    exit 0
    ;;
esac

# The feature must have a confirmed canvas to be a real active feature; without
# it there is nothing to enforce against -> no-op.
[ -f "$repo/docs/canvas/$feat.canvas.md" ] || exit 0

# --- PLUM-7: resolve every required CLI independently -------------------------
# Installation identity and the governed product repository are different
# things. Resolve each executable in this documented order:
#   1. PLUMBLINE_BIN_DIR (explicit installation/pilot override)
#   2. project-local config/claude/bin (legacy/vendored layout)
#   3. PATH
#   4. CLAUDE_HOME/bin, then HOME/.claude/bin (normal user install)
#
# Do not use `readlink -f`: macOS does not provide the GNU option. Canonicalize
# the containing directory with pwd -P and append the basename instead.
canonical_executable() {
  local candidate="$1" dir base physical_dir
  [ -f "$candidate" ] && [ -x "$candidate" ] || return 1
  dir="$(dirname "$candidate")" || return 1
  base="$(basename "$candidate")" || return 1
  physical_dir="$(cd "$dir" 2>/dev/null && pwd -P)" || return 1
  [ -n "$physical_dir" ] || return 1
  printf '%s/%s\n' "$physical_dir" "$base"
}

resolved_cli_path=""
resolved_cli_source=""
resolve_cli() {
  local name="$1" candidate="" found="" user_bin=""
  resolved_cli_path=""
  resolved_cli_source=""

  if [ -n "${PLUMBLINE_BIN_DIR:-}" ]; then
    candidate="$PLUMBLINE_BIN_DIR/$name"
    found="$(canonical_executable "$candidate" 2>/dev/null)" || found=""
    if [ -n "$found" ]; then
      resolved_cli_path="$found"
      resolved_cli_source="PLUMBLINE_BIN_DIR"
    fi
  fi

  if [ -z "$resolved_cli_path" ]; then
    candidate="$repo/config/claude/bin/$name"
    found="$(canonical_executable "$candidate" 2>/dev/null)" || found=""
    if [ -n "$found" ]; then
      resolved_cli_path="$found"
      resolved_cli_source="project-local"
    fi
  fi

  if [ -z "$resolved_cli_path" ]; then
    candidate="$(command -v "$name" 2>/dev/null)" || candidate=""
    found=""
    if [ -n "$candidate" ]; then
      found="$(canonical_executable "$candidate" 2>/dev/null)" || found=""
    fi
    if [ -n "$found" ]; then
      resolved_cli_path="$found"
      resolved_cli_source="PATH"
    fi
  fi

  if [ -z "$resolved_cli_path" ] && [ -n "${CLAUDE_HOME:-}" ]; then
    user_bin="$CLAUDE_HOME/bin"
    found="$(canonical_executable "$user_bin/$name" 2>/dev/null)" || found=""
    if [ -n "$found" ]; then
      resolved_cli_path="$found"
      resolved_cli_source="CLAUDE_HOME/bin"
    fi
  fi

  if [ -z "$resolved_cli_path" ] && [ -n "${HOME:-}" ]; then
    user_bin="$HOME/.claude/bin"
    found="$(canonical_executable "$user_bin/$name" 2>/dev/null)" || found=""
    if [ -n "$found" ]; then
      resolved_cli_path="$found"
      resolved_cli_source="HOME/.claude/bin"
    fi
  fi

  [ -n "$resolved_cli_path" ] || return 1
  printf 'PRIL CLI resolved: %s source=%s path=%s\n' \
    "$name" "$resolved_cli_source" "$resolved_cli_path" >&2
  return 0
}

missing_clis=""
scope_bin=""
context_bin=""
reality_bin=""
for required_cli in \
  plumbline-scope-check plumbline-context-check plumbline-reality-check
do
  if resolve_cli "$required_cli"; then
    case "$required_cli" in
      plumbline-scope-check) scope_bin="$resolved_cli_path" ;;
      plumbline-context-check) context_bin="$resolved_cli_path" ;;
      plumbline-reality-check) reality_bin="$resolved_cli_path" ;;
    esac
  else
    missing_clis="$missing_clis $required_cli"
  fi
done

if [ -n "$missing_clis" ]; then
  emit_block "PRIL_CLI_UNAVAILABLE: missing executable(s):$missing_clis. Search order: PLUMBLINE_BIN_DIR, project-local config/claude/bin, PATH, CLAUDE_HOME/bin, HOME/.claude/bin. Cannot prove gates; fix the install or escalate to the user."
  exit 0
fi

# --- I1: route all sub-command stderr to a temp dir, never the repo CWD -------
# M-2: a failed mktemp must never leave errd empty — an empty errd would write
# "/changed", "/scope", ... to the filesystem ROOT. Block instead of proceeding.
errd="$(mktemp -d)" || { emit_block "PRIL enforcement failed: scratch dir unavailable (mktemp -d). Cannot run gates safely; fix the environment or escalate to the user."; exit 0; }
if [ -z "$errd" ] || [ ! -d "$errd" ]; then
  emit_block "PRIL enforcement failed: scratch dir unavailable (mktemp -d). Cannot run gates safely; fix the environment or escalate to the user."
  exit 0
fi
trap 'rm -rf "$errd"' EXIT

fails=""

# --- C2 scope surface: the WHOLE feature surface, not bare `git diff` ----------
# resolved merge-base..HEAD (committed feature work) UNION working-tree UNION
# staged UNION untracked-non-ignored, sorted-unique. Bare `git diff --name-only`
# is vacuous on a committed tree (would fail open); this reads the real ground
# truth. A missing/unrelated base is NOT replaced by HEAD: HEAD...HEAD is a
# false-green empty surface.
#
# Explicit stack pins are authoritative. `PLUMBLINE_STACK_BASE` is canonical;
# `PLUMBLINE_BASE_REF` is accepted as a compatibility alias. Auto-resolution:
# remote default -> origin/main -> origin/master -> local main -> local master.
base_ref=""
base_commit=""
base_merge=""
base_source=""
base_error_code=""
base_error_ref=""

try_git_base() {
  local candidate="$1" source="$2" commit="" common=""
  case "$candidate" in
    ""|-*) return 1 ;;
  esac
  commit="$(git -C "$repo" rev-parse --verify "${candidate}^{commit}" \
    2>/dev/null)" || return 1
  [ -n "$commit" ] || return 1
  common="$(git -C "$repo" merge-base HEAD "$commit" 2>/dev/null)" || return 2
  [ -n "$common" ] || return 2
  base_ref="$candidate"
  base_commit="$commit"
  base_merge="$common"
  base_source="$source"
  return 0
}

resolve_git_base() {
  local explicit="" remote_default="" candidate="" source="" rc=0

  if [ -n "${PLUMBLINE_STACK_BASE:-}" ] && \
     [ -n "${PLUMBLINE_BASE_REF:-}" ] && \
     [ "$PLUMBLINE_STACK_BASE" != "$PLUMBLINE_BASE_REF" ]; then
    base_error_code="PRIL_GIT_BASE_CONFLICT"
    base_error_ref="$PLUMBLINE_STACK_BASE != $PLUMBLINE_BASE_REF"
    return 1
  fi

  if [ -n "${PLUMBLINE_STACK_BASE:-}" ]; then
    explicit="$PLUMBLINE_STACK_BASE"
    source="PLUMBLINE_STACK_BASE"
  elif [ -n "${PLUMBLINE_BASE_REF:-}" ]; then
    explicit="$PLUMBLINE_BASE_REF"
    source="PLUMBLINE_BASE_REF"
  fi

  if [ -n "$explicit" ]; then
    try_git_base "$explicit" "$source"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    elif [ "$rc" -eq 2 ]; then
      base_error_code="PRIL_GIT_BASE_UNRELATED"
    else
      base_error_code="PRIL_GIT_BASE_UNRESOLVED"
    fi
    base_error_ref="$explicit"
    return 1
  fi

  remote_default="$(git -C "$repo" symbolic-ref --quiet --short \
    refs/remotes/origin/HEAD 2>/dev/null)" || remote_default=""
  if [ -n "$remote_default" ]; then
    try_git_base "$remote_default" "remote-default"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    elif [ "$rc" -eq 2 ]; then
      base_error_code="PRIL_GIT_BASE_UNRELATED"
      base_error_ref="$remote_default"
      return 1
    fi
  fi

  for candidate in origin/main origin/master main master
  do
    case "$candidate" in
      origin/main) source="origin-main" ;;
      origin/master) source="origin-master" ;;
      main) source="local-main" ;;
      master) source="local-master" ;;
    esac
    try_git_base "$candidate" "$source"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    elif [ "$rc" -eq 2 ]; then
      base_error_code="PRIL_GIT_BASE_UNRELATED"
      base_error_ref="$candidate"
      return 1
    fi
  done

  base_error_code="PRIL_GIT_BASE_UNRESOLVED"
  base_error_ref="remote default, origin/main, origin/master, main, master"
  return 1
}

if ! resolve_git_base; then
  emit_block "$base_error_code: cannot establish a related Git baseline ($base_error_ref). Set PLUMBLINE_STACK_BASE to the intended parent for a stacked branch; refusing a false-green HEAD...HEAD fallback."
  exit 0
fi

printf 'PRIL Git base resolved: ref=%s source=%s commit=%s merge-base=%s\n' \
  "$base_ref" "$base_source" "$base_commit" "$base_merge" >&2

# Collect each surface independently and check every Git command. A failed diff
# command must not disappear behind the final `sort` process in a pipeline.
if ! git -C "$repo" diff --name-only "$base_merge"...HEAD \
  >"$errd/committed" 2>"$errd/git-committed" ||
   ! git -C "$repo" diff --name-only \
  >"$errd/working" 2>"$errd/git-working" ||
   ! git -C "$repo" diff --name-only --cached \
  >"$errd/staged" 2>"$errd/git-staged" ||
   ! git -C "$repo" ls-files --others --exclude-standard \
  >"$errd/untracked" 2>"$errd/git-untracked"
then
  emit_block "PRIL_GIT_DIFF_UNAVAILABLE: Git could not enumerate the complete committed, working, staged, and untracked change surface. Refusing an incomplete scope proof."
  exit 0
fi
if ! sort -u "$errd/committed" "$errd/working" "$errd/staged" \
  "$errd/untracked" >"$errd/changed"
then
  emit_block "PRIL_GIT_DIFF_UNAVAILABLE: could not assemble the complete Git change surface. Refusing an incomplete scope proof."
  exit 0
fi

# Scope guard: changed files must stay inside the feature's allowed scope.
"$scope_bin" --repo "$repo" --feature "$feat" \
  --changed-files "$errd/changed" >/dev/null 2>"$errd/scope" || fails="$fails scope"

# Context gate: confirmed product context must exist for the feature.
"$context_bin" --repo "$repo" --feature "$feat" \
  >/dev/null 2>"$errd/ctx" || fails="$fails context"

# --- I2: reality gate mirrors the feature's boundary class --------------------
# Only a feature that declares an integration boundary (docs/context/.feature-
# boundary marker) is held to integration-class evidence. A pure-logic feature
# has no integration boundary to evidence, so we SKIP the reality gate entirely
# rather than block it for lacking a ledger it never needed. We cannot express
# "presence-only" via --min-evidence (plumbline_reality.FORBIDDEN_TOKENS rejects
# the "fake-only" token), so the correct behavior is to skip, not invent a floor.
if [ -f "$repo/docs/context/.feature-boundary" ]; then
  "$reality_bin" --repo "$repo" --feature "$feat" \
    --min-evidence integration >/dev/null 2>"$errd/real" || fails="$fails reality"
fi

# --- Decision: fail CLOSED on any gate failure --------------------------------
if [ -n "$fails" ]; then
  emit_block "PRIL enforcement failed:$fails. Fix the failing gate(s) or escalate to the user; do not finish with a failing gate."
fi

exit 0
