#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

printf 'AgileTeam start gate contract tests\n'

assert_file "start classifier exists" "config/claude/lib/plumbline_start.py"
assert_file "start-check wrapper exists" "config/claude/bin/plumbline-start-check"
assert "start-check wrapper is executable" "[ -x config/claude/bin/plumbline-start-check ]"

panel="$(config/claude/bin/plumbline-start-check --prd-present --vision-missing)"
json="$(python3 config/claude/lib/plumbline_start.py --prd-present --vision-missing --json)"

assert_contains "panel emits VISION_MISSING" "$panel" "Gate: VISION_MISSING"
assert_contains "panel blocks planning" "$panel" "Planning allowed: NO"
assert_contains "panel blocks coding" "$panel" "Coding allowed: NO"
assert_contains "panel names missing confirmed Product Vision Canvas" "$panel" "confirmed Product Vision Canvas"
assert_contains "panel shows next allowed Vision Extraction step" "$panel" "Run Vision Extraction and request explicit user confirmation."
assert_contains "json exposes planning_allowed false" "$json" '"planning_allowed": false'
assert_contains "json exposes coding_allowed false" "$json" '"coding_allowed": false'

for label in "Explicit:" "Assumption:" "Missing:" "Source:" "User decision:"; do
  assert "Product Vision template includes $label" "grep -qF '$label' docs/templates/product-vision.template.md"
done

for section in "Target User" "User Problem" "Desired Change" "Core Value Promise" "Why Now" "Non-Goals" "Success Signal" "Risks if Misbuilt" "QA Value Checks" "User Confirmation"; do
  assert "Product Vision template includes $section" "grep -qF '$section' docs/templates/product-vision.template.md"
done

assert "Product Vision template includes confirmation phrase" "grep -qF 'I confirm this Product Vision as the basis for AgileTeam planning.' docs/templates/product-vision.template.md"
assert "AgileTeam command includes Vision Extraction Procedure" "grep -qF 'Vision Extraction Procedure' config/claude/commands/agileteam.md"
assert "Product Owner includes Vision Extraction Procedure" "grep -qF 'Vision Extraction Procedure' agileteam/product-owner.md"
assert "Vision Extraction asks primary user question" "grep -qF 'Who is the primary user or customer?' config/claude/commands/agileteam.md && grep -qF 'Who is the primary user or customer?' agileteam/product-owner.md"
assert "Vision Extraction asks core value promise question" "grep -qF 'What is the core value promise that must not be broken?' config/claude/commands/agileteam.md && grep -qF 'What is the core value promise that must not be broken?' agileteam/product-owner.md"
assert "Vision Extraction asks wrong or harmful implementation question" "grep -qF 'What would count as a wrong or harmful implementation?' config/claude/commands/agileteam.md && grep -qF 'What would count as a wrong or harmful implementation?' agileteam/product-owner.md"

finish "agileteam start gate contract tests"
