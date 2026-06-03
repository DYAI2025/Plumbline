#!/usr/bin/env bash
# Gate contract tests: G1 (challenge gate), G3 (vision-GO autonomy, final human gate
# preserved), G4 (team-composition roster). Deterministic, offline. Each gate's negative
# fixture proves its checks are not vacuously green.
# Design: docs/plans/2026-06-03-gate-verification-hardening-design.md
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/claude/tests/lib.sh
. "$DIR/lib.sh"
REPO="$(cd "$DIR/../../.." && pwd)"
CMD="$REPO/config/claude/commands/agileteam.md"
CONC="$REPO/config/claude/commands/concilium.md"
ROSTER="$REPO/config/claude/agileteam-roster.yml"
GC="$REPO/config/claude/lib/gate_contracts.py"
FIX="$DIR/fixtures/gate_contracts"

has()  { TESTS_RUN=$((TESTS_RUN+1)); if grep -qF -- "$3" "$2" 2>/dev/null; then _pass "$1"; else _fail "$1 (missing '$3' in $2)"; fi; }

# ---- G4: team composition roster ----
assert_file "G4 roster manifest exists" "$ROSTER"

# G4-C1: fixed minimum is EXACTLY coder/code-reviewer/tester/product-owner
g4_min="$(python3 "$GC" roster-roles "$ROSTER" minimum | tr '\n' ' ')"
assert_eq "G4-C1 fixed minimum exact" "code-reviewer coder product-owner tester " "$g4_min"

# G4-C2: every roster role resolves to an in-repo agent name (quote-aware)
assert "G4-C2 every roster role resolves in-repo" "python3 '$GC' resolve-roster '$ROSTER' '$REPO'"

# G4-C3: prose examples in agileteam.md are a SUBSET of the manifest (prose uses 'e.g.')
g4_manifest="$(python3 "$GC" roster-roles "$ROSTER")"
while read -r role; do
  [ -z "$role" ] && continue
  TESTS_RUN=$((TESTS_RUN+1))
  if printf '%s\n' "$g4_manifest" | grep -qx "$role"; then _pass "G4-C3 prose specialist '$role' is in the manifest"
  else _fail "G4-C3 prose specialist '$role' missing from manifest"; fi
done < <(python3 "$GC" prose-specialists "$CMD")

# G4-C5 (negative fixture): resolve-roster reddens on a bogus role
assert "G4-C5 resolve-roster reddens on unresolved role" "! python3 '$GC' resolve-roster '$FIX/g4_unresolved_roster.yml' '$REPO'"

# ---- G1: council challenge gate ----
# G1-C1: token bound present, parseable, and EQUAL across both files
g1_conc="$(python3 "$GC" token-bound "$CONC" 2>/dev/null)"
g1_cmd="$(python3 "$GC" token-bound "$CMD" 2>/dev/null)"
assert_eq "G1-C1 token bound equal across concilium.md and agileteam.md" "$g1_conc" "$g1_cmd"
assert "G1-C1 token bound is a positive integer" "[ \"\${g1_conc:-0}\" -gt 0 ]"

# G1-C2: per-round word cap present in both
has "G1-C2 word cap in concilium.md"  "$CONC" "180 words per role"
has "G1-C2 word cap in agileteam.md"  "$CMD"  "180 words per role"

# G1-C3: the three roles present in BOTH files
for role in Challenger Advisor Critic; do
  has "G1-C3 role '$role' in agileteam.md" "$CMD"  "$role"
  has "G1-C3 role '$role' in concilium.md" "$CONC" "$role"
done

# G1-C4: each role alias maps to a body subagent that resolves in-repo
for body in concilium-skeptic concilium-market-realist concilium-tech-arbiter; do
  TESTS_RUN=$((TESTS_RUN+1))
  if grep -rlE "^name: *\"?$body\"?\\s*\$" --include='*.md' "$REPO" 2>/dev/null | grep -qv '/explorer/'; then
    _pass "G1-C4 body '$body' resolves in-repo"
  else _fail "G1-C4 body '$body' does not resolve in-repo"; fi
done

# G1-C5: Phase 0.16 wired in agileteam.md (table + detail) and the invocation in both
has "G1-C5 Phase 0.16 named"            "$CMD"  "Phase 0.16"
has "G1-C5 challenge invocation (cmd)"  "$CMD"  "concilium --mode=challenge"
has "G1-C5 challenge mode (concilium)"  "$CONC" "--mode=challenge"

# G1-C6: intent invariant — friction not approval, one-page summary
has "G1-C6 friction-not-approval" "$CMD" "friction, not approval"

# G1-C7 (negative fixture): token-bound fails closed when no cap is present
assert "G1-C7 token-bound fails closed on capless fixture" "! python3 '$GC' token-bound '$FIX/g1_no_cap.md'"

# ---- G3: vision-GO -> autonomous run, final human gate preserved ----
# G3-C1: BOTH bookends exist — initial GO and the final acceptance gate
has "G3-C1 Vision GO gate present"        "$CMD" "Vision GO gate"
has "G3-C1 USER ACCEPTANCE GATE present"  "$CMD" "USER ACCEPTANCE GATE"

# G3-C2 (negative fixture = the core invariant): a copy with the acceptance gate deleted
# must make the C1 check fail. Prove the check reddens on the broken fixture.
assert "G3-C2 acceptance-gate check reddens when the gate is removed" \
  "! grep -qF 'USER ACCEPTANCE GATE' '$FIX/g3_missing_acceptance_gate.md'"

# G3-C3: bounded autonomy — Watcher may pause; user is final authority
has "G3-C3 user is final authority" "$CMD" "user is the final authority"

# G3-C4/C6: escalation asymmetry + Watcher ownership (uncertainty resolves to the user)
has "G3-C4 Watcher escalates on uncertainty" "$CMD" "escalates to the user"

# G3-C5: vision goal immutable inside re-alignment
has "G3-C5 vision change needs user re-confirmation" "$CMD" "Vision change requiring explicit user re-confirmation"

# G3-C7: /goal ruleset wiring + vision doc path
has "G3-C7 goal-planner ruleset referenced" "$CMD" "goal-planner"
has "G3-C7 vision doc path"                  "$CMD" "docs/vision/"

finish "gate contract tests"
