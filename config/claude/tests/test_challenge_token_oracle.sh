#!/usr/bin/env bash
# Tests the deterministic challenge-gate token oracle scorer. No model calls.
# Proves the instrument DISCRIMINATES (bench-oracle guardrail) before any real run:
# over-bound -> O1 fails, near-identical -> O3 fails, missing tokens -> MISSING (never a fake pass).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/claude/tests/lib.sh
. "$DIR/lib.sh"
REPO="$(cd "$DIR/../../.." && pwd)"
OR="$REPO/config/claude/metrics/challenge_token_oracle.py"
FIX="$DIR/fixtures/challenge_oracle"

run() { python3 "$OR" score "$FIX/$1" >/dev/null 2>&1; echo $?; }
field() { python3 "$OR" score "$FIX/$1" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('$2'))"; }
# Reports whether verdict.pairwise_similarity has all three pairs as numbers.
pairwise_ok() {
  python3 "$OR" score "$FIX/$1" 2>/dev/null | python3 -c '
import json, sys, numbers
v = json.load(sys.stdin)
ps = v.get("pairwise_similarity")
keys = ("challenger_advisor", "challenger_critic", "advisor_critic")
ok = isinstance(ps, dict) and all(isinstance(ps.get(k), numbers.Real) and not isinstance(ps.get(k), bool) for k in keys)
print("OK" if ok else "BAD")'
}

assert_eq "under-bound+distinct exits 0 (pass)"        "0" "$(run under_bound_distinct.json)"
assert_eq "under-bound+distinct O1 holds"              "True" "$(field under_bound_distinct.json O1_token_bound_hold)"
assert_eq "over-bound exits 1 (scored fail)"           "1" "$(run over_bound.json)"
assert_eq "over-bound O1 fails"                        "False" "$(field over_bound.json O1_token_bound_hold)"
assert_eq "near-identical exits 1 (scored fail)"       "1" "$(run too_similar.json)"
assert_eq "near-identical O3 fails"                    "False" "$(field too_similar.json O3_roles_distinct)"
assert_eq "missing tokens -> MISSING (exit 2, NOT 0)"  "2" "$(run missing_tokens.json)"
assert_eq "missing tokens status is MISSING"           "MISSING" "$(field missing_tokens.json status)"

# Additive transparency: per-pair similarities exposed so the operator can see the
# shared-base (challenger_critic) pair vs. the cross-body pairs. Pass/fail unchanged.
assert_eq "pairwise_similarity has all 3 pairs as numbers" "OK" "$(pairwise_ok under_bound_distinct.json)"

finish "challenge token oracle tests"
