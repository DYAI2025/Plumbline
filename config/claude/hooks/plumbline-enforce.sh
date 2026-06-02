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
bin="$repo/config/claude/bin"

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
if [ ! -x "$bin/plumbline-scope-check" ] || \
   [ ! -x "$bin/plumbline-context-check" ] || \
   [ ! -x "$bin/plumbline-reality-check" ]; then
  emit_block "PRIL enforcement failed: enforcement CLIs missing under config/claude/bin; cannot prove gates. Fix the install or escalate to the user; do not finish with an unprovable gate."
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
# merge-base(HEAD,main)..HEAD (committed feature work) UNION working-tree UNION
# staged UNION untracked-non-ignored, sorted-unique. Bare `git diff --name-only`
# is vacuous on a committed tree (would fail open); this reads the real ground
# truth. The `ls-files --others --exclude-standard` union closes the
# "write malware, never git add" evasion: an untracked, non-ignored out-of-scope
# file is still part of the C2 surface and is held to the scope guard. Ignored
# files (exclude-standard) are intentionally excluded.
base="$(git -C "$repo" merge-base HEAD main 2>/dev/null)" || base=""
[ -n "$base" ] || base="HEAD"
{
  git -C "$repo" diff --name-only "$base"...HEAD 2>/dev/null
  git -C "$repo" diff --name-only 2>/dev/null
  git -C "$repo" diff --name-only --cached 2>/dev/null
  git -C "$repo" ls-files --others --exclude-standard 2>/dev/null
} | sort -u > "$errd/changed"

# Scope guard: changed files must stay inside the feature's allowed scope.
"$bin/plumbline-scope-check" --repo "$repo" --feature "$feat" \
  --changed-files "$errd/changed" >/dev/null 2>"$errd/scope" || fails="$fails scope"

# Context gate: confirmed product context must exist for the feature.
"$bin/plumbline-context-check" --repo "$repo" --feature "$feat" \
  >/dev/null 2>"$errd/ctx" || fails="$fails context"

# --- I2: reality gate mirrors the feature's boundary class --------------------
# Only a feature that declares an integration boundary (docs/context/.feature-
# boundary marker) is held to integration-class evidence. A pure-logic feature
# has no integration boundary to evidence, so we SKIP the reality gate entirely
# rather than block it for lacking a ledger it never needed. We cannot express
# "presence-only" via --min-evidence (plumbline_reality.FORBIDDEN_TOKENS rejects
# the "fake-only" token), so the correct behavior is to skip, not invent a floor.
if [ -f "$repo/docs/context/.feature-boundary" ]; then
  "$bin/plumbline-reality-check" --repo "$repo" --feature "$feat" \
    --min-evidence integration >/dev/null 2>"$errd/real" || fails="$fails reality"
fi

# --- Decision: fail CLOSED on any gate failure --------------------------------
if [ -n "$fails" ]; then
  emit_block "PRIL enforcement failed:$fails. Fix the failing gate(s) or escalate to the user; do not finish with a failing gate."
fi

exit 0
