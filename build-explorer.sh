#!/usr/bin/env bash
#
# Regenerate agent-explorer.html from the current agent frontmatter.
#
# Extracts every agent's frontmatter -> JSON, scaffolds a fresh React/Vite
# project via the artifacts-builder skill, overlays the source in explorer/,
# bundles to a single self-contained HTML file, and writes it to
# agent-explorer.html at the repo root.
#
# Requirements: bash, python3 + PyYAML, pnpm/node, and the artifacts-builder
# skill (default ~/.claude/skills/artifacts-builder, override with
# ARTIFACTS_BUILDER_SKILL).
#
set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="$REPO_DIR/explorer"
SKILL="${ARTIFACTS_BUILDER_SKILL:-$HOME/.claude/skills/artifacts-builder}"
OUT="$REPO_DIR/agent-explorer.html"

if [ ! -d "$SKILL/scripts" ]; then
  echo "error: artifacts-builder skill not found at '$SKILL'" >&2
  echo "       set ARTIFACTS_BUILDER_SKILL to its path and retry." >&2
  exit 1
fi

WORK="$(mktemp -d -t agent-explorer.XXXXXX)"
trap 'rm -rf "$WORK"' EXIT

echo "==> extracting agent frontmatter"
python3 "$SRC/extract-agents.py" "$REPO_DIR" > "$WORK/agents-data.json"

echo "==> scaffolding project"
( cd "$WORK" && bash "$SKILL/scripts/init-artifact.sh" proj >/dev/null )
PROJ="$WORK/proj"

echo "==> applying explorer source overlay"
cp "$SRC/App.tsx"        "$PROJ/src/App.tsx"
cp "$SRC/index.css"      "$PROJ/src/index.css"
cp "$SRC/agents-data.ts" "$PROJ/src/agents-data.ts"
cp "$SRC/index.html"     "$PROJ/index.html"
cp "$WORK/agents-data.json" "$PROJ/src/agents-data.json"

# Allow importing the JSON snapshot under TS.
if ! grep -q '"resolveJsonModule"' "$PROJ/tsconfig.app.json"; then
  sed -i 's/"moduleResolution": "bundler",/"moduleResolution": "bundler",\n    "resolveJsonModule": true,/' "$PROJ/tsconfig.app.json"
fi

echo "==> bundling"
( cd "$PROJ" && bash "$SKILL/scripts/bundle-artifact.sh" >/dev/null )

cp "$PROJ/bundle.html" "$OUT"
echo "==> wrote $OUT ($(du -h "$OUT" | cut -f1))"

# Keep the GitHub Pages live demo (served from /docs) in lockstep with the bundle,
# so the demo and the committed explorer can never drift apart.
PAGES="$REPO_DIR/docs/index.html"
mkdir -p "$REPO_DIR/docs"
cp "$OUT" "$PAGES"
echo "==> synced $PAGES (GitHub Pages live demo)"
