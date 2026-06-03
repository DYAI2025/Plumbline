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
g4_prose="$(python3 "$GC" prose-specialists "$CMD")"
# Floor: prose-specialists exits 0 even with zero matches, so if agileteam.md's
# "domain roles" line is reworded the subset loop below would run zero times and
# give ZERO coverage while staying green. Assert the prose set is non-empty FIRST,
# mirroring the G1-C1 positive-integer floor. (Subset semantics are kept: prose is
# an intentionally illustrative 'e.g.' list, so the manifest may hold more.)
assert "G4-C3 prose specialist set is non-empty (not vacuous)" \
  "[ \"\$(printf '%s\\n' \"\$g4_prose\" | grep -c .)\" -gt 0 ]"
while read -r role; do
  [ -z "$role" ] && continue
  TESTS_RUN=$((TESTS_RUN+1))
  if printf '%s\n' "$g4_manifest" | grep -qxF "$role"; then _pass "G4-C3 prose specialist '$role' is in the manifest"
  else _fail "G4-C3 prose specialist '$role' missing from manifest"; fi
done <<EOF
$g4_prose
EOF

# G4-C5 (negative fixture): resolve-roster reddens on a bogus role
assert "G4-C5 resolve-roster reddens on unresolved role" "! python3 '$GC' resolve-roster '$FIX/g4_unresolved_roster.yml' '$REPO'"

# ---- G1: council challenge gate ----
# G1-C1: structural bound present + consistent across both files. The earlier numeric
# token-bound check was RETIRED: the "~15k tokens total" figure was measured FALSE and
# withdrawn (metrics/bench-2026-06-03-challenge-token-oracle.md). The real, enforced bound
# is structural — per-role word cap (G1-C2) + collision-round cap (here).
has "G1-C1 collision-round bound in concilium.md" "$CONC" "2 collision rounds"
has "G1-C1 collision-round bound in agileteam.md" "$CMD"  "2 collision rounds"
# G1-C1b: the withdrawn token figure is framed as withdrawn AND bench-cited in BOTH files
# (guards the honest re-baseline against silent reinstatement of a guessed token cap).
has "G1-C1b token figure withdrawn (concilium)" "$CONC" "withdrawn"
has "G1-C1b token figure withdrawn (agileteam)" "$CMD"  "withdrawn"
has "G1-C1b bench evidence cited (concilium)"   "$CONC" "bench-2026-06-03-challenge-token-oracle"
has "G1-C1b bench evidence cited (agileteam)"   "$CMD"  "bench-2026-06-03-challenge-token-oracle"

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

# (G1-C7 retired with the numeric token-bound check; g1_no_cap.md fixture removed —
# the withdrawn token figure is no longer a contract surface. See G1-C1/C1b above.)

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
