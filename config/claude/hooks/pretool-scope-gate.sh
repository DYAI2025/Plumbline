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
command_text=""
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  subagent_type="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
  command_text="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
else
  tool_name="$(printf '%s' "$PAYLOAD" \
    | sed -nE 's/.*"tool_name"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
    | head -n1)"
  subagent_type="$(printf '%s' "$PAYLOAD" \
    | sed -nE 's/.*"subagent_type"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
    | head -n1)"
  command_text="$(printf '%s' "$PAYLOAD" \
    | sed -nE 's/.*"command"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
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

# The updater is the only repair path allowed through a failed/missing
# preflight. It requires --confirmed and validates artifacts before its atomic
# write. Accept only a single direct updater command: shell composition,
# redirection, substitution, and chained commands keep the gate active.
if [ "$tool_name" = "Bash" ] && command -v python3 >/dev/null 2>&1; then
  if python3 - "$command_text" <<'PY'
import shlex
import sys
from pathlib import Path

command = sys.argv[1]
if not command or "\n" in command or "\r" in command or "`" in command or "$(" in command:
    raise SystemExit(1)
lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|<>()")
lexer.whitespace_split = True
lexer.commenters = ""
try:
    tokens = list(lexer)
except ValueError:
    raise SystemExit(1)
operators = set(";&|<>()")
if (
    not tokens
    or Path(tokens[0]).name != "plumbline-scope-update"
    or any(token and set(token) <= operators for token in tokens[1:])
):
    raise SystemExit(1)
raise SystemExit(0)
PY
  then
    exit 0
  fi
fi

marker="$PROJECT/docs/context/.active-feature"
[ -f "$marker" ] || exit 0
feature="$(tr -d '[:space:]' <"$marker" 2>/dev/null || true)"
[ -n "$feature" ] || exit 0
manifest="$PROJECT/docs/scope/$feature.scope.json"
if [ ! -f "$manifest" ]; then
  canvas="$PROJECT/docs/canvas/$feature.canvas.md"
  reference="Scope manifest: \`docs/scope/$feature.scope.json\`"
  if [ -f "$canvas" ] && grep -Fq "$reference" "$canvas" 2>/dev/null; then
    printf '%s\n' '{"decision":"deny","reason":"Plumbline scope preflight blocked: Canvas references a missing canonical scope manifest"}'
  fi
  exit 0
fi
# Parse the object before deciding it is legacy. JSON permits escaped member
# names (for example schema\u005fversion), so raw-text key matching can fail
# open on a canonical manifest.
manifest_kind="$(
  python3 - "$manifest" <<'PY' 2>/dev/null
import json
import sys

try:
    with open(sys.argv[1], encoding="utf-8") as handle:
        data = json.load(handle)
except (OSError, UnicodeError, json.JSONDecodeError):
    print("invalid")
    raise SystemExit(0)
if isinstance(data, dict) and "schema_version" in data:
    print("canonical")
elif (
    isinstance(data, dict)
    and "allowed_change_scope" in data
    and "schema_version" not in data
):
    print("legacy")
else:
    print("invalid")
PY
)" || manifest_kind="invalid"
[ "$manifest_kind" = "legacy" ] && exit 0

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
