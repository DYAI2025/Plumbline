#!/usr/bin/env bash
#
# Static contract tests for the Mandatory Product Canvas Gate. Like the rest of
# this suite, the framework is prompts/docs with no runtime to exercise, so these
# are static contract assertions: the load-bearing canvas invariants, files, and
# gate phrases must be present and mutually consistent across the command, the
# template, and the agent prompts. Covers REQ-F-001..005, REQ-A-001/002, REQ-S-001.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_product_canvas_gate"

CMD="$REPO_DIR/config/claude/commands/agileteam.md"
RA="$REPO_DIR/agileteam/requirements-analyst.md"
CK="$REPO_DIR/agileteam/context-keeper.md"
PO="$REPO_DIR/agileteam/product-owner.md"
WATCHER="$REPO_DIR/agileteam/plumbline-watcher.md"
SPEC="$REPO_DIR/docs/agileteam-spec-v3.md"
README="$REPO_DIR/README.md"
T_CANVAS="$REPO_DIR/docs/templates/product-canvas.template.md"

# has <description> <file> <literal-pattern>  — fixed-string grep assertion.
has() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -Fq -- "$3" "$2"; then _pass "$1"; else _fail "$1 (missing in $2: $3)"; fi
}

# --- REQ-A-002: template lives by the existing convention (docs/templates/) ----
assert_file "REQ-A-002 product-canvas template exists in docs/templates/" "$T_CANVAS"

# --- REQ-F-005: all ten canvas fields are present and none removed -------------
has "REQ-F-005 field 1 Problem"                  "$T_CANVAS" "## 1. Problem"
has "REQ-F-005 field 2 Target user / customer"   "$T_CANVAS" "## 2. Target user / customer"
has "REQ-F-005 field 3 Current workaround"       "$T_CANVAS" "## 3. Current workaround"
has "REQ-F-005 field 4 Value proposition"        "$T_CANVAS" "## 4. Value proposition"
has "REQ-F-005 field 5 Success signal"           "$T_CANVAS" "## 5. Success signal"
has "REQ-F-005 field 6 Core use case"            "$T_CANVAS" "## 6. Core use case"
has "REQ-F-005 field 7 Non-goals"                "$T_CANVAS" "## 7. Non-goals"
has "REQ-F-005 field 8 Risks / contradictions"   "$T_CANVAS" "## 8. Risks / contradictions"
has "REQ-F-005 field 9 Evidence needed"          "$T_CANVAS" "## 9. Evidence needed"
has "REQ-F-005 field 10 Traceability links"      "$T_CANVAS" "## 10. Traceability links"

# --- REQ-F-002: status field with the three allowed values --------------------
has "REQ-F-002 template Status field"            "$T_CANVAS" "Status: draft"
has "REQ-F-002 template allows user-confirmed"   "$T_CANVAS" "user-confirmed"
has "REQ-F-002 template allows blocked"          "$T_CANVAS" "blocked"
has "REQ-F-002 template user-confirmation block" "$T_CANVAS" "Confirmed by user: no"

# --- REQ-F-003: no silent assumptions — explicit gap markers ------------------
has "REQ-F-003 template MISSING marker"          "$T_CANVAS" "MISSING"
has "REQ-F-003 template OPEN QUESTION marker"    "$T_CANVAS" "OPEN QUESTION"
has "REQ-F-003 template BLOCKER marker"          "$T_CANVAS" "BLOCKER"

# --- REQ-F-001: command makes the canvas a mandatory pre-PRD/pre-dev gate ------
has "REQ-F-001 command has a Product Canvas gate"   "$CMD" "Mandatory Product Canvas gate"
has "REQ-F-001 command names the canvas artifact"   "$CMD" "docs/canvas/<feature>.canvas.md"
has "REQ-F-001 command has a Phase 0.15 canvas step" "$CMD" "Phase 0.15"

# --- REQ-F-002: development entry requires a user-confirmed canvas -------------
has "REQ-F-002 dev entry requires confirmed canvas" "$CMD" "Canvas status is user-confirmed"
has "REQ-F-002 no agent may self-confirm canvas"    "$CMD" "No agent may self-confirm the canvas"

# --- REQ-F-003: open product-critical fields block Phase 1 --------------------
has "REQ-F-003 command forbids silent assumptions"  "$CMD" "No silent assumptions"
has "REQ-F-003 command blocks Phase 1 on open field" "$CMD" "BLOCKER for Phase 1"

# --- REQ-F-004: canvas linked from PRD, Vision, traceability ------------------
has "REQ-F-004 PRD and Vision link back to canvas"  "$CMD" "each link back to \`docs/canvas/<feature>.canvas.md\`"
has "REQ-F-004 matrix carries canvas-link field"    "$CMD" "canvas-link"

# --- REQ-S-001 / REQ-A-001: canvas is additive, never weakens existing gates --
has "REQ-S-001 canvas does not replace later gates" "$CMD" "addition, not a replacement"
has "REQ-A-001 existing entry conditions preserved" "$CMD" "Product Vision status is user-confirmed"
has "REQ-A-001 watcher pass still gated"            "$CMD" "The Plumbline Watcher verdict is \`pass\`"

# --- agent-role coverage: every relevant role knows the canvas ----------------
has "requirements-analyst owns the Product Canvas"  "$RA"      "Product Canvas (mandatory, before the PRD)"
has "requirements-analyst may not self-confirm"     "$RA"      "may not self-confirm"
has "context-keeper owns the canvas artifact"       "$CK"      "docs/canvas/<feature>.canvas.md"
has "context-keeper carries canvas-link field"      "$CK"      "canvas-link"
has "product-owner links Vision to canvas"          "$PO"      "docs/canvas/<feature>.canvas.md"
has "watcher reads the canvas"                       "$WATCHER" "docs/canvas/<feature>.canvas.md"
has "watcher pauses on unconfirmed canvas"           "$WATCHER" "Product Canvas is missing or its status is not"

# --- doc coverage: spec-v3 + README -------------------------------------------
has "spec-v3 has Required Product Canvas section"   "$SPEC"   "Required Product Canvas"
has "spec-v3 names canvas template path"            "$SPEC"   "docs/templates/product-canvas.template.md"
has "README documents the Product Canvas gate"      "$README" "Product Canvas"

finish "test_product_canvas_gate"
