#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

printf 'Scope Shift Notice contract tests\n'

assert_file "Scope Shift Notice template exists" "docs/templates/scope-shift-notice.template.md"
assert "Scope Shift template includes decision header" "grep -qF 'SCOPE SHIFT DECISION REQUIRED' docs/templates/scope-shift-notice.template.md"
assert "Scope Shift template includes Original Goal Status" "grep -qF 'Original Goal Status: NOT DONE' docs/templates/scope-shift-notice.template.md"
assert "Scope Shift template includes Current Iteration Status" "grep -qF 'Current Iteration Status: PARTIAL / STAGED / UNVERIFIED' docs/templates/scope-shift-notice.template.md"
assert "Scope Shift template includes A option" "grep -qF 'A) Resolve the blocker and continue toward the original goal.' docs/templates/scope-shift-notice.template.md"
assert "Scope Shift template includes B option" "grep -qF 'B) Accept reduced scope, but keep original goal NOT DONE.' docs/templates/scope-shift-notice.template.md"
assert "Scope Shift template includes C option" "grep -qF 'C) Move this feature to backlog.' docs/templates/scope-shift-notice.template.md"
assert "Scope Shift template includes D option" "grep -qF 'D) Stop and document the contradiction.' docs/templates/scope-shift-notice.template.md"
assert "Scope Shift template rejects generic OK" "grep -qF 'Generic OK / continue / sounds good is not sufficient for this decision.' docs/templates/scope-shift-notice.template.md"
assert "Scope Shift template says original goal is not done" "grep -qF 'If you accept this deviation, the original goal is NOT done.' docs/templates/scope-shift-notice.template.md"

assert "AgileTeam command references Scope Shift Decision Rule" "grep -qF 'Scope Shift Decision Rule' config/claude/commands/agileteam.md"
assert "AgileTeam command references Scope Shift Notice block" "grep -qF 'SCOPE SHIFT DECISION REQUIRED' config/claude/commands/agileteam.md"
assert "AgileTeam command rejects generic OK" "grep -qF 'Generic OK / continue / sounds good is insufficient for this decision.' config/claude/commands/agileteam.md"
assert "AgileTeam command separates Original Goal and Current Iteration status" "grep -qF 'Original Goal Status' config/claude/commands/agileteam.md && grep -qF 'Current Iteration Status' config/claude/commands/agileteam.md"

finish "scope shift notice contract tests"
