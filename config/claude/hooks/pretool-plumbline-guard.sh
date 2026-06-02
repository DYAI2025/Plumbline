#!/usr/bin/env bash
# Optional PRIL pre-tool guard prototype.
# Intentionally not referenced from .claude/settings.json in PRIL Iteration 2.
# Manual usage example after producing a changed-files list:
#   config/claude/bin/plumbline-scope-check --repo "$PWD" --feature "$FEATURE" --changed-files changed-files.txt
#   config/claude/bin/plumbline-redact --mode check < artifact.jsonl
set -euo pipefail

: "${CLAUDE_PROJECT_DIR:=$PWD}"
: "${PLUMBLINE_FEATURE:=}"

if [ -z "$PLUMBLINE_FEATURE" ]; then
  echo "pretool-plumbline-guard is inactive: PLUMBLINE_FEATURE is not set" >&2
  exit 0
fi

echo "pretool-plumbline-guard is optional and not wired into Claude settings" >&2
exit 0
