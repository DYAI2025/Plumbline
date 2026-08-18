#!/usr/bin/env bash
#
# PreToolUse hook — VISION_MISSING backstop (REQ-A-011 / AC-A-006 / EV-A-005).
#
# The Claude Code harness invokes this with a JSON tool-dispatch payload on stdin
# (e.g. {"tool_name":"Task","tool_input":{"subagent_type":"planner",...}}) and
# reads a JSON decision from stdout. When the active start-state is VISION_MISSING
# AND the dispatched tool is a planning/coding action, this DENIES the dispatch so
# the harness blocks it — a runtime backstop behind the orchestrator's Phase-0
# gate. Everything else passes through untouched.
#
# Robustness contract: this hook must NEVER crash a session. On ANY internal error
# (missing jq, malformed stdin, classifier failure, unreadable files) it fails
# OPEN — prints nothing and exits 0 — so it can never block normal work due to its
# own failure. `set -uo pipefail` (NOT `set -e`) so we keep control of exit codes.
set -uo pipefail

# Resolve the repo root from the hook's own location (like session-start.sh), so
# the bundled plumbline-start-check classifier is reachable regardless of cwd.
REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." 2>/dev/null && pwd)"
PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"

# Pass through with no output, exit 0 (the fail-open / not-affected path).
pass_through() { exit 0; }

# Read the whole stdin payload. If stdin is empty/unreadable we fail open.
PAYLOAD="$(cat 2>/dev/null || true)"
[ -n "$PAYLOAD" ] || pass_through

# --- Parse tool_name + subagent_type -----------------------------------------
# Prefer jq; fall back to a grep-based extraction if jq is absent.
tool_name=""
subagent_type=""
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  subagent_type="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
else
  # Best-effort grep fallback. If this is uncertain we still default to a safe
  # classification (anything we cannot confidently classify as AFFECTED passes).
  tool_name="$(printf '%s' "$PAYLOAD" \
    | grep -oE '"tool_name"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' || true)"
  subagent_type="$(printf '%s' "$PAYLOAD" \
    | grep -oE '"subagent_type"[[:space:]]*:[[:space:]]*"[^"]*"' \
    | head -n1 | sed -E 's/.*:[[:space:]]*"([^"]*)".*/\1/' || true)"
fi

# --- Classify the dispatched tool as AFFECTED (planning/coding) or not --------
# AFFECTED iff: a direct edit tool, OR a Task to a planning/coding sub-agent role.
is_affected() {
  case "$tool_name" in
    Write|Edit|MultiEdit|NotebookEdit) return 0 ;;
    Task)
      # Case-insensitive substring match on planning/coding role markers.
      local role
      role="$(printf '%s' "$subagent_type" | tr '[:upper:]' '[:lower:]')"
      case "$role" in
        *plan*|*coder*|*architect*|*-dev|*developer*|*implement*) return 0 ;;
        *) return 1 ;;
      esac
      ;;
    *) return 1 ;;
  esac
}

# Not a planning/coding dispatch -> nothing to gate, pass through.
is_affected || pass_through

# --- Ground truth: is the active start-state VISION_MISSING? ------------------
# DUAL independent paths; VISION_MISSING is true if EITHER fires.
vision_missing() {
  local ctx="$PROJECT/docs/context"

  # Path 1 — explicit marker the Phase-0 gate persists.
  if [ -f "$ctx/.start-gate" ] \
     && grep -Eq '^[[:space:]]*VISION_MISSING[[:space:]]*$' "$ctx/.start-gate" 2>/dev/null; then
    return 0
  fi

  # Path 2 — independent recompute (defense-in-depth), even with no marker.
  if [ -f "$ctx/.active-feature" ]; then
    local feature prd vision
    # Trim leading/trailing whitespace from the feature name.
    feature="$(tr -d '[:space:]' < "$ctx/.active-feature" 2>/dev/null || true)"
    if [ -n "$feature" ]; then
      prd="$PROJECT/docs/prd/$feature.prd.md"
      vision="$PROJECT/docs/vision/$feature.vision.md"
      if [ -f "$prd" ] \
         && ! { [ -f "$vision" ] && grep -Eq '^[[:space:]]*Status:[[:space:]]*user-confirmed' "$vision" 2>/dev/null; }; then
        # PRD present but vision unconfirmed. REUSE the classifier (no duplication
        # of branch logic) to confirm the gate is VISION_MISSING.
        local checker out
        checker="$REPO_DIR/config/claude/bin/plumbline-start-check"
        if [ -x "$checker" ]; then
          out="$("$checker" --prd-present --vision-missing --json 2>/dev/null || true)"
          if command -v jq >/dev/null 2>&1; then
            if [ "$(printf '%s' "$out" | jq -r '.planning_allowed' 2>/dev/null)" = "false" ]; then
              return 0
            fi
          else
            # No jq: conservatively recognise the classifier's deny signal.
            if printf '%s' "$out" | grep -Fq '"planning_allowed": false'; then
              return 0
            fi
          fi
        fi
      fi
    fi
  fi

  return 1
}

if vision_missing; then
  # DENY: a planning/coding dispatch under VISION_MISSING.
  printf '%s\n' '{"decision":"deny","reason":"Plumbline start gate: VISION_MISSING — confirmed Product Vision required before planning/coding. Run Vision Extraction and request explicit user confirmation."}'
  exit 0
fi

# Not VISION_MISSING -> pass through.
pass_through
