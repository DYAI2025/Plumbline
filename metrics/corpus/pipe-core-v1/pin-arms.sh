#!/usr/bin/env bash
# pin-arms.sh <commit> <outdir>
# Extract the arm's DNA-relevant agent prompts at a pinned commit (run from the
# claude-agents repo root). The coder prompt is intentionally NOT pinned per-arm — it is
# identical across arms (the only variable is the DNA-differing agents).
set -euo pipefail
COMMIT="${1:?usage: pin-arms.sh <commit> <outdir>}"
OUT="${2:?usage: pin-arms.sh <commit> <outdir>}"
mkdir -p "$OUT"
# DNA-differing agents that the full pipeline uses:
for f in \
  core/tester.md \
  code-reviewer.md \
  testing/validation/production-validator.md \
  agileteam/product-owner.md \
  agileteam/requirements-analyst.md \
  agileteam/spec-auditor.md \
  config/claude/commands/agileteam.md ; do
  name="$(echo "$f" | tr '/' '__')"
  if git cat-file -e "${COMMIT}:${f}" 2>/dev/null; then
    git show "${COMMIT}:${f}" > "$OUT/$name"
    echo "pinned: $f -> $OUT/$name"
  else
    echo "absent at ${COMMIT}: $f (arm did not have this agent — note in run record)"
  fi
done
# Shared (NOT pinned per arm) — same file both arms use:
git show "HEAD:core/coder.md" > "$OUT/SHARED__coder.md" 2>/dev/null || \
  echo "note: core/coder.md not found; use the active coder prompt for BOTH arms"
echo "done. config_fingerprint arm commit = ${COMMIT}"
