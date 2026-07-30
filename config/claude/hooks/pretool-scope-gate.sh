#!/usr/bin/env bash
#
# PreToolUse backstop for PLUM-12. When an active feature uses a versioned
# canonical scope manifest, validate its Canvas reference and implementation
# plan before the first write-capable dispatch. Legacy Canvas-only features pass
# through until their explicitly versioned migration (PLUM-10).
set -uo pipefail

PROJECT="${CLAUDE_PROJECT_DIR:-$PWD}"
PAYLOAD="$(cat 2>/dev/null || true)"
[ -n "$PAYLOAD" ] || exit 0

tool_name=""
subagent_type=""
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  subagent_type="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
else
  tool_name="$(printf '%s' "$PAYLOAD" \
    | sed -nE 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
    | head -n1)"
  subagent_type="$(printf '%s' "$PAYLOAD" \
    | sed -nE 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
    | head -n1)"
fi

case "$tool_name" in
  Bash|Write|Edit|MultiEdit|NotebookEdit) ;;
  Task)
    role="$(printf '%s' "$subagent_type" | tr '[:upper:]' '[:lower:]')"
    case "$role" in
      *coder*|*-dev|*developer*|*implement*) ;;
      *) exit 0 ;;
    esac
    ;;
  *) exit 0 ;;
esac

marker="$PROJECT/docs/context/.active-feature"
[ -f "$marker" ] || exit 0
feature="$(tr -d '[:space:]' <"$marker" 2>/dev/null || true)"
[ -n "$feature" ] || exit 0
manifest="$PROJECT/docs/scope/$feature.scope.json"
[ -f "$manifest" ] || exit 0
# A legacy `allowed_change_scope` JSON file is not a PLUM-12 versioned manifest.
# The presence of the canonical key activates the Python validator, which parses
# and verifies its value. Do not use a line-oriented value regex: valid JSON may
# place the value on a later line.
grep -Fq '"schema_version"' "$manifest" 2>/dev/null || exit 0

checker=""
for candidate in \
  "${PLUMBLINE_BIN_DIR:+$PLUMBLINE_BIN_DIR/plumbline-scope-check}" \
  "$PROJECT/config/claude/bin/plumbline-scope-check" \
  "$(command -v plumbline-scope-check 2>/dev/null || true)" \
  "${CLAUDE_HOME:-$HOME/.claude}/bin/plumbline-scope-check" \
  "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/bin/plumbline-scope-check"
do
  if [ -n "$candidate" ] && [ -x "$candidate" ]; then
    checker="$candidate"
    break
  fi
done
if [ ! -x "$checker" ]; then
  printf '%s\n' '{"decision":"deny","reason":"Plumbline scope gate unavailable: plumbline-scope-check is missing"}'
  exit 0
fi

output="$("$checker" --repo "$PROJECT" --feature "$feature" --preflight 2>&1)"
status=$?
[ "$status" -eq 0 ] && exit 0

reason="Plumbline scope preflight blocked before coding: $output"
if command -v jq >/dev/null 2>&1; then
  jq -cn --arg reason "$reason" '{decision:"deny",reason:$reason}'
else
  # The detailed validator output may contain quotes. Without jq, keep the
  # decision valid JSON and fail closed with a stable diagnostic.
  printf '%s\n' '{"decision":"deny","reason":"Plumbline scope preflight blocked before coding; run plumbline-scope-check --preflight for details"}'
fi
exit 0
