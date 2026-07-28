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

# --- CLI resolution -----------------------------------------------------------
# The earlier version hardcoded "$repo/config/claude/bin". That path only exists
# when the working repo IS this repo; in a GOVERNED repo (the normal case — an
# /agileteam run inside some other project) it never exists, so the hook could
# never prove a gate anywhere it actually matters. It blocked fail-closed, which
# was correct, but it made enforcement permanently unprovable rather than
# occasionally unavailable. Measured 2026-07-28 in a governed repo.
#
# Resolution order, first hit wins, per CLI (not per directory — under PATH the
# three CLIs are not required to share a parent):
#   1. $PLUMBLINE_BIN_DIR        explicit operator override
#   2. $repo/config/claude/bin   repo-local install
#   3. PATH (command -v)         normal install on the operator's PATH
#   4. $HOME/.claude/bin         global install
#   5. nothing found             -> BLOCK (never fail open)
#
# No silent deactivation: if any ONE of the three is unresolvable the hook still
# blocks. Resolution is reported on stderr so the path in use is auditable rather
# than guessed.
plumbline_resolve() {
  local name="$1" cand
  if [ -n "${PLUMBLINE_BIN_DIR:-}" ] && [ -x "$PLUMBLINE_BIN_DIR/$name" ]; then
    printf '%s' "$PLUMBLINE_BIN_DIR/$name"
    return 0
  fi
  if [ -x "$repo/config/claude/bin/$name" ]; then
    printf '%s' "$repo/config/claude/bin/$name"
    return 0
  fi
  cand="$(command -v "$name" 2>/dev/null)" || cand=""
  if [ -n "$cand" ] && [ -x "$cand" ]; then
    printf '%s' "$cand"
    return 0
  fi
  if [ -n "${HOME:-}" ] && [ -x "$HOME/.claude/bin/$name" ]; then
    printf '%s' "$HOME/.claude/bin/$name"
    return 0
  fi
  return 1
}

cli_scope="$(plumbline_resolve plumbline-scope-check)" || cli_scope=""
cli_context="$(plumbline_resolve plumbline-context-check)" || cli_context=""
cli_reality="$(plumbline_resolve plumbline-reality-check)" || cli_reality=""

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

# The PRIL CLIs must be present to enforce. If they are absent we cannot prove
# the gate either way; rather than fail OPEN we block with an explicit reason.
if [ -z "$cli_scope" ] || [ -z "$cli_context" ] || [ -z "$cli_reality" ]; then
  emit_block "PRIL enforcement failed: enforcement CLIs not resolvable (searched \$PLUMBLINE_BIN_DIR, <repo>/config/claude/bin, PATH, \$HOME/.claude/bin); cannot prove gates. Fix the install or escalate to the user; do not finish with an unprovable gate."
  exit 0
fi

# Audit trail: which binaries actually ran. Goes to stderr, never stdout — the
# stdout contract is exactly one JSON object, and only on a block.
printf 'plumbline-enforce: scope=%s context=%s reality=%s\n' \
  "$cli_scope" "$cli_context" "$cli_reality" >&2

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
# merge-base(HEAD,main)..HEAD (committed feature work) UNION working-tree UNION
# staged UNION untracked-non-ignored, sorted-unique. Bare `git diff --name-only`
# is vacuous on a committed tree (would fail open); this reads the real ground
# truth. The `ls-files --others --exclude-standard` union closes the
# "write malware, never git add" evasion: an untracked, non-ignored out-of-scope
# file is still part of the C2 surface and is held to the scope guard. Ignored
# files (exclude-standard) are intentionally excluded.
# --- Scope base resolution (no HEAD fallback) ---------------------------------
# This used to be `git merge-base HEAD main` with a fallback to HEAD. Two faults,
# and the second one is the dangerous one:
#
#   * `main` was hardcoded. In a repository whose default branch is `master` the
#     merge-base call simply fails.
#   * On failure `base` fell back to HEAD, so the surface became
#     `git diff HEAD...HEAD` — empty. Committed feature work was then not
#     scope-checked AT ALL, and the gate reported green. The header of this file
#     calls exactly that situation vacuous and fail-open; the fallback produced
#     it on every master-default repository.
#
# Resolution order, first hit wins:
#   1. explicit base — $PLUMBLINE_SCOPE_BASE, else the repo-pinned
#      docs/context/.scope-base (same value, persisted per repo; a Stop hook
#      inherits no per-branch environment, so an env-only interface would be
#      undeliverable in practice). A STACKED feature branch MUST use this: it has
#      to be measured against its stack base, not against the default branch.
#   2. detected default branch via refs/remotes/origin/HEAD
#   3. origin/main, if it exists
#   4. origin/master, if it exists
#   5. nothing resolvable -> BLOCK. There is deliberately no HEAD fallback:
#      an unprovable surface must never read as a passing gate.
base_ref=""
if [ -n "${PLUMBLINE_SCOPE_BASE:-}" ]; then
  base_ref="$PLUMBLINE_SCOPE_BASE"
elif [ -f "$repo/docs/context/.scope-base" ]; then
  base_ref="$(tr -d ' \t\r\n' < "$repo/docs/context/.scope-base" 2>/dev/null)"
fi
if [ -z "$base_ref" ]; then
  if origin_head="$(git -C "$repo" symbolic-ref --quiet refs/remotes/origin/HEAD 2>/dev/null)"; then
    base_ref="${origin_head#refs/remotes/}"
  elif git -C "$repo" rev-parse --verify --quiet origin/main >/dev/null 2>&1; then
    base_ref="origin/main"
  elif git -C "$repo" rev-parse --verify --quiet origin/master >/dev/null 2>&1; then
    base_ref="origin/master"
  fi
fi
if [ -z "$base_ref" ]; then
  emit_block "PRIL enforcement failed: scope base not resolvable (tried \$PLUMBLINE_SCOPE_BASE, docs/context/.scope-base, refs/remotes/origin/HEAD, origin/main, origin/master). Committed work cannot be scope-checked against an unknown base; pin the base explicitly or escalate to the user."
  exit 0
fi

# The ref must exist AND share history with HEAD, otherwise the three-dot diff
# below would be meaningless. Both failures block rather than degrade.
base="$(git -C "$repo" merge-base HEAD "$base_ref" 2>/dev/null)" || base=""
if [ -z "$base" ]; then
  emit_block "PRIL enforcement failed: scope base '$base_ref' has no merge-base with HEAD (unknown ref or unrelated history); the committed scope surface cannot be computed. Fix the base or escalate to the user."
  exit 0
fi
printf 'plumbline-enforce: scope-base=%s (%s)\n' "$base_ref" "$base" >&2

{
  git -C "$repo" diff --name-only "$base"...HEAD 2>/dev/null
  git -C "$repo" diff --name-only 2>/dev/null
  git -C "$repo" diff --name-only --cached 2>/dev/null
  git -C "$repo" ls-files --others --exclude-standard 2>/dev/null
} | sort -u > "$errd/changed"

# Scope guard: changed files must stay inside the feature's allowed scope.
"$cli_scope" --repo "$repo" --feature "$feat" \
  --changed-files "$errd/changed" >/dev/null 2>"$errd/scope" || fails="$fails scope"

# Context gate: confirmed product context must exist for the feature.
"$cli_context" --repo "$repo" --feature "$feat" \
  >/dev/null 2>"$errd/ctx" || fails="$fails context"

# --- I2: reality gate mirrors the feature's boundary class --------------------
# Only a feature that declares an integration boundary (docs/context/.feature-
# boundary marker) is held to integration-class evidence. A pure-logic feature
# has no integration boundary to evidence, so we SKIP the reality gate entirely
# rather than block it for lacking a ledger it never needed. We cannot express
# "presence-only" via --min-evidence (plumbline_reality.FORBIDDEN_TOKENS rejects
# the "fake-only" token), so the correct behavior is to skip, not invent a floor.
if [ -f "$repo/docs/context/.feature-boundary" ]; then
  "$cli_reality" --repo "$repo" --feature "$feat" \
    --min-evidence integration >/dev/null 2>"$errd/real" || fails="$fails reality"
fi

# --- Decision: fail CLOSED on any gate failure --------------------------------
if [ -n "$fails" ]; then
  emit_block "PRIL enforcement failed:$fails. Fix the failing gate(s) or escalate to the user; do not finish with a failing gate."
fi

exit 0
