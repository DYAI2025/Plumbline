#!/usr/bin/env bash
#
# Static contract tests for True-Line Governance (the Plumbline customer-value
# layer). There is no runtime to exercise — the framework is prompts/docs — so,
# like the rest of this suite, these are static contract assertions: the
# load-bearing invariants, files, and gate phrases must be present and mutually
# consistent. Covers TEST-001..008 from the dev brief.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_true_line_governance"

CMD="$REPO_DIR/config/claude/commands/agileteam.md"
CONC="$REPO_DIR/config/claude/commands/concilium.md"
WATCHER="$REPO_DIR/agileteam/plumbline-watcher.md"
CK="$REPO_DIR/agileteam/context-keeper.md"
RA="$REPO_DIR/agileteam/requirements-analyst.md"
PO="$REPO_DIR/agileteam/product-owner.md"
SA="$REPO_DIR/agileteam/spec-auditor.md"
RETRO="$REPO_DIR/agileteam/retro-analyst.md"
TESTER="$REPO_DIR/core/tester.md"
PV="$REPO_DIR/testing/validation/production-validator.md"
SPEC="$REPO_DIR/docs/agileteam-spec-v3.md"
GOV="$REPO_DIR/docs/agileteam-governance.md"
T_VISION="$REPO_DIR/docs/templates/product-vision.template.md"
T_CONTRA="$REPO_DIR/docs/templates/contradiction-ledger.template.md"
T_GATE="$REPO_DIR/docs/templates/true-line-gate-check.template.md"
T_FIELDS="$REPO_DIR/docs/templates/traceability-true-line-fields.template.md"

# has <description> <file> <literal-pattern>  — fixed-string grep assertion.
has() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -Fq -- "$3" "$2"; then _pass "$1"; else _fail "$1 (missing in $2: $3)"; fi
}

# --- new artifacts exist ---------------------------------------------------
assert_file "plumbline-watcher agent exists"            "$WATCHER"
assert_file "product-vision template exists"            "$T_VISION"
assert_file "contradiction-ledger template exists"      "$T_CONTRA"
assert_file "true-line gate-check template exists"      "$T_GATE"
assert_file "traceability true-line fields template"    "$T_FIELDS"

# --- the non-negotiable invariant (highest-level docs) ---------------------
INVARIANT="optimizes for staying true to confirmed human customer value"
has "TEST-CORE invariant in /agileteam command"  "$CMD"     "$INVARIANT"
has "TEST-CORE invariant in spec-v3"             "$SPEC"    "$INVARIANT"
has "TEST-CORE invariant in governance"          "$GOV"     "$INVARIANT"
has "TEST-CORE invariant in watcher"             "$WATCHER" "$INVARIANT"

# --- TEST-001/002: no development without confirmed PRD + Vision -----------
has "TEST-001 command names the Product Vision artifact" "$CMD" "docs/vision/<feature>.vision.md"
has "TEST-001 command requires confirmed Vision"         "$CMD" "Product Vision status is user-confirmed"
has "TEST-001 command hard-blocks development start"      "$CMD" "Development may not start"
has "TEST-002 command requires confirmed PRD"             "$CMD" "PRD status is user-confirmed"
has "TEST-002 command gates on Watcher pass verdict"      "$CMD" "Plumbline Watcher verdict is"

# --- TEST-003: Watcher pauses on contradiction -----------------------------
has "TEST-003 watcher has pause authority"      "$WATCHER" "Pause authority"
has "TEST-003 watcher pause verdict"            "$WATCHER" "Watcher verdict: pause"
has "TEST-003 watcher ties pause to contradiction" "$WATCHER" "contradiction"
has "TEST-003 command stops on pause verdict"   "$CMD"     "verdict \`pause\`"
has "TEST-003 no contradiction carried forward" "$CMD"     "No contradiction may be carried forward"

# --- TEST-004: value-risk requires Watcher review --------------------------
has "TEST-004 watcher review-required verdict"  "$WATCHER" "review-required"
has "TEST-004 watcher value-risk status"        "$WATCHER" "value-risk"
has "TEST-004 command routes value-risk to review" "$CMD"  "review-required"

# --- TEST-005: retro improvement must prove customer-value link ------------
has "TEST-005 retro true-line challenge"        "$RETRO" "Retro True-Line Challenge"
has "TEST-005 retro requires customer-value link" "$RETRO" "customer-value link"
has "TEST-005 retro detects green-but-useless"  "$RETRO" "green-but-useless"
has "TEST-005 governance retro challenge"       "$GOV"   "Retro True-Line Challenge"

# --- TEST-006: mock/placeholder/fake/known-limitation cannot resolve -------
for f_desc in "watcher:$WATCHER" "contradiction-template:$T_CONTRA"; do
  f="${f_desc#*:}"; d="${f_desc%%:*}"
  has "TEST-006 $d forbids placeholder"        "$f" "placeholder"
  has "TEST-006 $d forbids mock"               "$f" "mock"
  has "TEST-006 $d forbids known limitation"   "$f" "known limitation"
done

# --- TEST-007: user reframe only with updated, re-approved confirmation ----
has "TEST-007 watcher reframe needs user confirmation" "$WATCHER" "explicit user confirmation of a reframe"
has "TEST-007 watcher reframe needs re-approved PRD+Vision" "$WATCHER" "updated and re-approved PRD and Vision"
has "TEST-007 contradiction template allows user reframe"  "$T_CONTRA" "User confirms reframing"

# --- TEST-008: traceability matrix carries True-Line fields ----------------
for field in vision-link value-check-id true-line-status contradiction-id user-decision; do
  has "TEST-008 context-keeper owns field $field" "$CK" "$field"
done
has "TEST-008 fields template lists true-line-status" "$T_FIELDS" "true-line-status"

# --- TEST-009: token-bounded council challenge gate (Phase 0.16, G1) -------
has "TEST-009 command has council challenge gate section"   "$CMD"  "Council challenge gate"
has "TEST-009 gate is Phase 0.16"                           "$CMD"  "Phase 0.16"
has "TEST-009 gate runs after Canvas-confirm"               "$CMD"  "after the Product Canvas is user-confirmed"
has "TEST-009 gate runs before PRD finalization"            "$CMD"  "before the PRD is finalized"
has "TEST-009 gate is token-bounded with explicit cap"      "$CMD"  "token-bounded"
has "TEST-009 gate states concrete token cap"               "$CMD"  "15k tokens"
has "TEST-009 gate produces user-facing summary"            "$CMD"  "user-facing"
has "TEST-009 summary is at most one page"                  "$CMD"  "1-page"
has "TEST-009 orchestrator asks user about amending request" "$CMD" "asks the user whether any legitimate point changes the product request"
has "TEST-009 adopting a point re-confirms the Canvas"      "$CMD"  "amend the Canvas and re-confirm"
has "TEST-009 council may not auto-edit canvas/PRD"         "$CMD"  "may not auto-edit the Canvas or PRD"
has "TEST-009 only the user reclassifies (suggests not seizes)" "$CMD" "suggests, never seizes"
has "TEST-009 names the three challenge roles"              "$CMD"  "Challenger"
has "TEST-009 names the Advisor role"                       "$CMD"  "Advisor"
has "TEST-009 names the Critic role"                        "$CMD"  "Critic"
has "TEST-009 invokes concilium challenge mode"             "$CMD"  "concilium --mode=challenge"

# --- TEST-009b: concilium gains a --mode=challenge (3-role) section ---------
has "TEST-009b concilium has challenge mode section"        "$CONC" "--mode=challenge"
has "TEST-009b challenge mode is the three-role gate"       "$CONC" "Challenge mode"
has "TEST-009b challenge mode names Challenger"             "$CONC" "Challenger"
has "TEST-009b challenge mode names Advisor"                "$CONC" "Advisor"
has "TEST-009b challenge mode names Critic"                 "$CONC" "Critic"
has "TEST-009b challenge mode is token-bounded"             "$CONC" "token-bounded"
has "TEST-009b default 4-body council unchanged"           "$CONC" "Distribution Realist"

# --- agent-role coverage (every role pulls the same plumbline) -------------
has "requirements-analyst: bounded brainstorming" "$RA"     "Bounded Brainstorming"
has "product-owner: owns Product Vision"          "$PO"     "Product Vision Responsibility"
has "product-owner: final value gate"             "$PO"     "Final Value Gate"
has "spec-auditor: true-line spec audit"          "$SA"     "True-Line Spec Audit"
has "tester: customer-value QA"                   "$TESTER" "Customer-Value QA"
has "production-validator: value alignment"       "$PV"     "Value Alignment"
has "context-keeper owns vision artifact"         "$CK"     "docs/vision/<feature>.vision.md"
has "context-keeper owns contradiction ledger"    "$CK"     "docs/contradictions/<feature>.contradictions.md"

finish "test_true_line_governance"
