#!/usr/bin/env bash
# README honesty (Wave A / A1): the agent count is DERIVED from the explorer extractor
# (the single source of truth), never hand-asserted; and the vendored claude-flow agents
# are framed as a tested-workload dependency, not pure "ready-to-use" marketing. This
# guards Plumbline's radical-honesty brand on its most-read surface against drift.
# See docs/plans/2026-06-03-plumbline-authenticity-roadmap.md (Wave A).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/claude/tests/lib.sh
. "$DIR/lib.sh"
REPO="$(cd "$DIR/../../.." && pwd)"
README="$REPO/README.md"

# Derive the canonical agent count from the explorer extractor — same source the
# Agent Explorer / GitHub Pages demo use, so the README can never drift from reality.
N="$(python3 "$REPO/explorer/extract-agents.py" "$REPO" 2>/dev/null \
     | python3 -c "import json,sys; d=json.load(sys.stdin); print(len(d if isinstance(d,list) else d.get('agents',d)))" 2>/dev/null)"

assert "README-honesty: explorer extractor yields a positive agent count" "[ \"${N:-0}\" -gt 0 ]"

# Every number stated next to 'subagents'/'agents' in the README must equal the derived N
# (no drift, no marketing inflation). Any other count → FAIL listing the offenders.
mismatch="$(python3 - "$README" "${N:-0}" <<'PY'
import re, sys
text = open(sys.argv[1], encoding="utf-8").read()
n = sys.argv[2]
bad = [m.group(1) for m in
       re.finditer(r'(?<![A-Za-z])(\d+)\s+(?:ready-to-use\s+)?(?:Claude Code\s+)?(?:subagents|agents)\b', text)
       if m.group(1) != n]
print(",".join(sorted(set(bad))))
PY
)"
assert_eq "README-honesty: no agent count drifts from the derived $N" "" "$mismatch"

# Vendored agents must be framed honestly, not as bare "ready-to-use" marketing.
assert "README-honesty: vendored agents framed as a tested-workload dependency" "grep -qF 'tested-workload' '$README'"

finish "readme honesty tests"
