#!/usr/bin/env bash
# A2 / Wave A: DEPENDENCIES.md must honestly disclose the install boundary — EXTERNAL
# prerequisites vs SHIPPED-in-repo vs REFERENCED-but-not-shipped. In particular, EVERY
# external MCP tool family that any agent references must be documented as not-shipped
# (the F1 root: agents' frontmatter lists mcp__claude-flow__* etc. that install.sh never
# provides). Families are derived dynamically, so a new external ref can't slip in
# undocumented. See docs/plans/2026-06-03-plumbline-authenticity-roadmap.md (Wave A / A2).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/claude/tests/lib.sh
. "$DIR/lib.sh"
REPO="$(cd "$DIR/../../.." && pwd)"
DEP="$REPO/DEPENDENCIES.md"

assert_file "DEPENDENCIES.md exists" "$DEP"
assert "DEPENDENCIES.md documents EXTERNAL prerequisites"        "grep -qiE 'external' '$DEP'"
assert "DEPENDENCIES.md documents what is SHIPPED in-repo"       "grep -qiE 'shipped' '$DEP'"
assert "DEPENDENCIES.md documents REFERENCED-but-not-shipped"    "grep -qiE 'referenced|not[ -]shipped' '$DEP'"

# Every MCP tool family any agent references must be disclosed in DEPENDENCIES.md.
# Family names appear in BOTH hyphen (mcp__claude-flow__) and underscore (mcp__claude_flow__)
# forms across the vendored agents, so the class includes '_' and we accept either form in
# the doc (same logical server). DEPENDENCIES.md is excluded from the scan so it cannot
# satisfy its own claim — a phantom doc row must not pass, and the F1 root (an *agent* ref
# that is undocumented) is what fails closed.
missing=""
while read -r fam; do
  [ -z "$fam" ] && continue
  grep -qF "$fam" "$DEP" 2>/dev/null || grep -qF "${fam//_/-}" "$DEP" 2>/dev/null || missing="$missing $fam"
done < <(grep -rhoE 'mcp__[a-z0-9_-]+__' --include='*.md' --exclude='DEPENDENCIES.md' "$REPO" 2>/dev/null \
          | grep -vE '/\.git/' | sed -E 's/^mcp__([a-z0-9_-]+)__$/\1/' | sort -u)
assert_eq "every referenced MCP family is disclosed in DEPENDENCIES.md" "" "$missing"

finish "dependencies doc tests"
