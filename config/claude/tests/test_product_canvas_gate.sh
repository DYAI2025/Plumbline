#!/usr/bin/env bash
#
# Static contract tests for the Mandatory Product Canvas Gate. Like the rest of
# this suite, the framework is prompts/docs with no runtime to exercise, so these
# are static contract assertions: the load-bearing canvas invariants, files, gate
# phrases, the six mandatory Canvas traceability fields, and the Watcher Canvas-
# alignment checks must be present and mutually consistent across the command, the
# template, the spec, and the agent prompts. Covers REQ-F-001..005, REQ-A-001/002,
# REQ-S-001 and the follow-up patch (six Canvas trace fields + Watcher alignment).
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
T_FIELDS="$REPO_DIR/docs/templates/traceability-true-line-fields.template.md"

# has <description> <file> <literal-pattern>  — fixed-string grep assertion.
has() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -Fq -- "$3" "$2"; then _pass "$1"; else _fail "$1 (missing in $2: $3)"; fi
}

# detects_removal <description> <file> <literal>  — proves the assertion has teeth:
# if every line carrying the literal is removed, the literal must be gone. Guards
# against false-positive contract tests (the requirement: tests must FAIL when a
# required field is removed).
detects_removal() {
  TESTS_RUN=$((TESTS_RUN + 1))
  local stripped
  stripped="$(grep -vF -- "$3" "$2")"
  if printf '%s' "$stripped" | grep -Fq -- "$3"; then
    _fail "$1 (removal not detectable: '$3' survives stripping in $2)"
  else
    _pass "$1"
  fi
}

# The six mandatory Canvas traceability fields (REQ patch §1).
CANVAS_FIELDS=(
  canvas-link
  canvas-problem
  canvas-target-user
  canvas-value-claim
  canvas-success-signal
  canvas-risk-status
)

# ============================================================================
# REQ-A-002: template lives by the existing convention (docs/templates/)
# ============================================================================
assert_file "REQ-A-002 product-canvas template exists in docs/templates/" "$T_CANVAS"

# ============================================================================
# REQ-F-005: all ten canvas fields present, none removed
# ============================================================================
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

# ============================================================================
# REQ-F-002: status field with the three allowed values + confirmation block
# ============================================================================
has "REQ-F-002 template Status field"            "$T_CANVAS" "Status: draft"
has "REQ-F-002 template allows user-confirmed"   "$T_CANVAS" "user-confirmed"
has "REQ-F-002 template allows blocked"          "$T_CANVAS" "blocked"
has "REQ-F-002 template user-confirmation block" "$T_CANVAS" "Confirmed by user: no"

# ============================================================================
# REQ-F-003: no silent assumptions — explicit gap markers
# ============================================================================
has "REQ-F-003 template MISSING marker"          "$T_CANVAS" "MISSING"
has "REQ-F-003 template OPEN QUESTION marker"    "$T_CANVAS" "OPEN QUESTION"
has "REQ-F-003 template BLOCKER marker"          "$T_CANVAS" "BLOCKER"

# ============================================================================
# REQ-F-001: command makes the canvas a mandatory pre-PRD/pre-dev gate
# ============================================================================
has "REQ-F-001 command has a Product Canvas gate"    "$CMD" "Mandatory Product Canvas gate"
has "REQ-F-001 command names the canvas artifact"    "$CMD" "docs/canvas/<feature>.canvas.md"
has "REQ-F-001 command has a Phase 0.15 canvas step" "$CMD" "Phase 0.15"

# ============================================================================
# REQ-F-002: development entry requires a user-confirmed canvas
# ============================================================================
has "REQ-F-002 dev entry requires confirmed canvas" "$CMD" "Canvas status is user-confirmed"
has "REQ-F-002 no agent may self-confirm canvas"    "$CMD" "No agent may self-confirm the canvas"

# ============================================================================
# REQ-F-003: open product-critical fields block Phase 1
# ============================================================================
has "REQ-F-003 command forbids silent assumptions"   "$CMD" "No silent assumptions"
has "REQ-F-003 command blocks Phase 1 on open field" "$CMD" "BLOCKER for Phase 1"

# ============================================================================
# REQ-S-001 / REQ-A-001: canvas is additive, never weakens existing gates
# ============================================================================
has "REQ-S-001 canvas does not replace later gates" "$CMD" "addition, not a replacement"
has "REQ-A-001 existing entry conditions preserved" "$CMD" "Product Vision status is user-confirmed"
has "REQ-A-001 watcher pass still gated"            "$CMD" "The Plumbline Watcher verdict is \`pass\`"

# ============================================================================
# PATCH §1: the six mandatory Canvas traceability fields, documented
# consistently across command, spec, context-keeper, and the matrix template.
# ============================================================================
for field in "${CANVAS_FIELDS[@]}"; do
  has "§1 command documents trace field $field"        "$CMD"      "$field"
  has "§1 spec documents trace field $field"           "$SPEC"     "$field"
  has "§1 context-keeper carries trace field $field"   "$CK"       "$field"
  has "§1 matrix-guidance template lists field $field" "$T_FIELDS" "$field"
done
has "§1 command requires REQ traceable to canvas value" "$CMD" "traceable to a confirmed Product Canvas value"
has "§1 matrix-guidance: REQ missing a field not satisfiable" "$T_FIELDS" "not satisfiable"

# §4: removal-detection — the field assertions FAIL if a field is stripped.
for field in "${CANVAS_FIELDS[@]}"; do
  detects_removal "§4 removing $field from command is detectable" "$CMD"      "$field"
  detects_removal "§4 removing $field from matrix template is detectable" "$T_FIELDS" "$field"
done

# ============================================================================
# PATCH §2: Plumbline Watcher Canvas-alignment checks (seven dimensions) +
# the ability to issue review-required / pause / blocked.
# ============================================================================
has "§2 watcher has a Canvas alignment checks section" "$WATCHER" "Canvas alignment checks"
has "§2 watcher checks problem alignment"        "$WATCHER" "Problem alignment"
has "§2 watcher checks target-user alignment"    "$WATCHER" "Target-user alignment"
has "§2 watcher checks value-proposition align"  "$WATCHER" "Value-proposition alignment"
has "§2 watcher checks success-signal alignment" "$WATCHER" "Success-signal alignment"
has "§2 watcher checks non-goal violation"       "$WATCHER" "Non-goal violation"
has "§2 watcher checks Canvas risk"              "$WATCHER" "Canvas risk"
has "§2 watcher checks trace completeness"       "$WATCHER" "Canvas traceability completeness"
has "§2 watcher can issue review-required"       "$WATCHER" "review-required"
has "§2 watcher can issue pause"                 "$WATCHER" "pause"
has "§2 watcher can issue blocked"               "$WATCHER" "blocked"
has "§2 watcher pauses on non-goal/risk/missing field" "$WATCHER" "violates a confirmed Canvas non-goal"

# §2 mirrored into the command and the spec (consistency).
has "§2 command has Watcher Canvas alignment check"  "$CMD"  "Canvas alignment check (every Watcher pass"
has "§2 command Watcher checks the Canvas problem"   "$CMD"  "Canvas **problem**"
has "§2 command Watcher checks the Canvas non-goal"  "$CMD"  "Canvas **non-goal**"
has "§2 spec documents Watcher Canvas alignment"     "$SPEC" "Canvas alignment checks (Phase 1 onward)"
has "§2 spec Watcher reads the Product Canvas"       "$SPEC" "reads the Product Canvas"

# ============================================================================
# PATCH §3: README repository layout exposes the real directories
# ============================================================================
assert_file "§3 docs/canvas/ directory exists (documented path is real)" "$REPO_DIR/docs/canvas/README.md"
has "§3 README documents docs/canvas"   "$README" "docs/canvas"
has "§3 README documents docs/templates" "$README" "docs/templates"
has "§3 README still documents the Canvas gate" "$README" "Product Canvas"

# ============================================================================
# agent-role coverage: every relevant role knows the canvas
# ============================================================================
has "requirements-analyst owns the Product Canvas"  "$RA"      "Product Canvas (mandatory, before the PRD)"
has "requirements-analyst may not self-confirm"     "$RA"      "may not self-confirm"
has "context-keeper owns the canvas artifact"       "$CK"      "docs/canvas/<feature>.canvas.md"
has "product-owner links Vision to canvas"          "$PO"      "docs/canvas/<feature>.canvas.md"
has "watcher reads the canvas"                       "$WATCHER" "docs/canvas/<feature>.canvas.md"
has "watcher pauses on unconfirmed canvas"           "$WATCHER" "Product Canvas is missing or its status is not"

# ============================================================================
# doc coverage: spec-v3 Product Canvas section + template path
# ============================================================================
has "spec-v3 has Required Product Canvas section"   "$SPEC"   "Required Product Canvas"
has "spec-v3 names canvas template path"            "$SPEC"   "docs/templates/product-canvas.template.md"

finish "test_product_canvas_gate"
