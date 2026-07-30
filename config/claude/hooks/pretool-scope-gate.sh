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
write_target=""
if command -v jq >/dev/null 2>&1; then
  tool_name="$(printf '%s' "$PAYLOAD" | jq -r '.tool_name // empty' 2>/dev/null || true)"
  subagent_type="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.subagent_type // empty' 2>/dev/null || true)"
  command_text="$(printf '%s' "$PAYLOAD" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
  write_target="$(printf '%s' "$PAYLOAD" \
    | jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' \
      2>/dev/null || true)"
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
  write_target="$(printf '%s' "$PAYLOAD" \
    | sed -nE 's/.*"file_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
    | head -n1)"
  if [ -z "$write_target" ]; then
    write_target="$(printf '%s' "$PAYLOAD" \
      | sed -nE 's/.*"notebook_path"[[:space:]]*:[[:space:]]*"([^"]*)".*/\1/p' \
      | head -n1)"
  fi
fi

case "$tool_name" in
  Bash|Write|Edit|MultiEdit|NotebookEdit) ;;
  Task|Agent)
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

# The updater is the only repair path allowed through a failed/missing
# preflight. It requires --confirmed and validates artifacts before its atomic
# write. Accept only a single direct updater command: shell composition,
# redirection, substitution, and chained commands keep the gate active.
if [ "$tool_name" = "Bash" ] && command -v python3 >/dev/null 2>&1; then
  trusted_updaters=()
  for updater_candidate in \
    "$PROJECT/config/claude/bin/plumbline-scope-update" \
    "${PLUMBLINE_BIN_DIR:+$PLUMBLINE_BIN_DIR/plumbline-scope-update}" \
    "${CLAUDE_HOME:-$HOME/.claude}/bin/plumbline-scope-update" \
    "$(cd "$(dirname "${BASH_SOURCE[0]}")/.." 2>/dev/null && pwd)/bin/plumbline-scope-update"
  do
    if [ -x "$updater_candidate" ]; then
      trusted_updaters+=("$updater_candidate")
    fi
  done
  if python3 - "$command_text" "$PROJECT" "$feature" "${trusted_updaters[@]}" <<'PY'
import shlex
import shutil
import subprocess
import sys
from pathlib import Path

command = sys.argv[1]
project = Path(sys.argv[2]).resolve()
feature = sys.argv[3]
trusted = {Path(path).resolve() for path in sys.argv[4:]}
if (
    not command
    or any(char in command for char in ("\n", "\r", "`", "$", "{", "}", "*", "?", "[", "]", "~"))
):
    raise SystemExit(1)
lexer = shlex.shlex(command, posix=True, punctuation_chars=";&|<>()")
lexer.whitespace_split = True
lexer.commenters = ""
try:
    tokens = list(lexer)
except ValueError:
    raise SystemExit(1)
operators = set(";&|<>()")
if not tokens:
    raise SystemExit(1)
executable = Path(tokens[0])
if "/" not in tokens[0]:
    resolved = shutil.which(tokens[0])
    if resolved is None:
        raise SystemExit(1)
    executable = Path(resolved)
elif not executable.is_absolute():
    executable = project / executable
try:
    executable = executable.resolve(strict=True)
except OSError:
    raise SystemExit(1)
if (
    executable not in trusted
    or "--confirmed" not in tokens[1:]
    or any(token and set(token) <= operators for token in tokens[1:])
):
    raise SystemExit(1)
try:
    executable.relative_to(project)
except ValueError:
    pass
else:
    immutable_runtime = [
        "config/claude/bin/plumbline-scope-update",
        "config/claude/lib/plumbline_python.sh",
        "config/claude/lib/plumbline_scope_update.py",
        "config/claude/lib/plumbline_scope.py",
    ]
    tracked = subprocess.run(
        ["git", "-C", str(project), "ls-files", "--error-unmatch", "--", *immutable_runtime],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    unchanged = subprocess.run(
        ["git", "-C", str(project), "diff", "--quiet", "HEAD", "--", *immutable_runtime],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        check=False,
    )
    if tracked.returncode != 0 or unchanged.returncode != 0:
        raise SystemExit(1)
allowed_options = {
    "--repo", "--feature", "--product-path", "--governance-path", "--canvas",
    "--plan", "--planned-create", "--planned-modify", "--planned-delete",
    "--planned-test", "--replace-plan-declarations", "--origin",
    "--decision-maker", "--decided-at", "--rationale", "--confirmed",
}
for token in tokens[1:]:
    if token.startswith("--") and token.split("=", 1)[0] not in allowed_options:
        raise SystemExit(1)
def option(name: str) -> str | None:
    values = []
    for index, token in enumerate(tokens[1:], start=1):
        if token == name and index + 1 < len(tokens):
            values.append(tokens[index + 1])
        elif token.startswith(name + "="):
            values.append(token.split("=", 1)[1])
    return values[0] if len(values) == 1 else None

repo_arg = option("--repo")
feature_arg = option("--feature")
if repo_arg is None or feature_arg != feature:
    raise SystemExit(1)
repo_target = Path(repo_arg)
if not repo_target.is_absolute():
    repo_target = project / repo_target
try:
    if repo_target.resolve(strict=True) != project:
        raise SystemExit(1)
except OSError:
    raise SystemExit(1)
raise SystemExit(0)
PY
  then
    exit 0
  fi
fi

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

checker_args=(--repo "$PROJECT" --feature "$feature" --preflight)
case "$tool_name" in
  Write|Edit|MultiEdit|NotebookEdit)
    if [ -z "$write_target" ]; then
      printf '%s\n' '{"decision":"deny","reason":"Plumbline scope preflight blocked: write-capable tool did not provide a file_path/notebook_path target"}'
      exit 0
    fi
    checker_args+=(--write-target "$write_target")
    ;;
  Bash)
    if [ "$command_text" != "rm -f docs/context/.active-feature" ]; then
      delete_target="$(
        python3 - "$command_text" <<'PY' 2>/dev/null
import shlex
import sys

try:
    tokens = shlex.split(sys.argv[1], posix=True)
except ValueError:
    raise SystemExit(1)
if (
    len(tokens) == 3
    and tokens[:2] == ["rm", "-f"]
    and not any(char in tokens[2] for char in ("\n", "\r", "$", "`", "{", "}", "*", "?", "[", "]", "~"))
):
    print(tokens[2])
PY
      )"
      if [ -n "$delete_target" ]; then
        checker_args+=(--delete-target "$delete_target")
      else
        checker_args+=(--test-command "$command_text")
      fi
    fi
    ;;
esac
output="$("$checker" "${checker_args[@]}" 2>&1)"
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
