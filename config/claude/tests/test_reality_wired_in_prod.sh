#!/usr/bin/env bash
# PLB-HARDEN-001 / Test A (TDD, RED): wired-in-prod=no must fail-closed on a
# value/done/deploy claim.
#
# Pattern #3 (Reality hardening). The Reality Ledger TRACKS `wired_in_prod`, but
# plumbline-reality-check does NOT enforce it: REQUIRED_FIELDS in
# config/claude/lib/plumbline_reality.py = (feature, requirement_id,
# evidence_class, evidence_ref, verified_by) — `wired_in_prod` is absent, and the
# lib only ranks `evidence_class` against `--min-evidence`. So a record can clear
# the evidence floor while wired_in_prod=false — a done/deploy claim on a feature
# that is NOT wired into the running product slips through. This is the exact
# class that shipped a fixture-only "Calculate" preview as if it delivered value.
#
# These:      reality-check gates the Reality Ledger honestly.
# Gegenthese: it gates evidence_class but ignores wired_in_prod, so a green-but-
#             not-wired record passes a done/deploy claim.
# Schaerfung: (A1) plain mode currently PASSES the not-wired record (the gap is
#                  real — positive control, passes today);
#             (A2 RED) a wired-enforcing mode must fail-closed and name the
#                  stop-code STOP-WIRED-PROD plus the offending requirement.
#
# RED expectation: no wired enforcement exists, so A2 produces no STOP-WIRED-PROD
# and never names the culprit. Self-contained throwaway repo; no network.
# NO FIX is implemented here — this test only makes the gap machine-visible.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"
echo "test_reality_wired_in_prod (PLB-HARDEN-001 / Test A, RED)"

REALITY="$REPO_DIR/config/claude/bin/plumbline-reality-check"
FEAT="harden-wired-demo"

# Throwaway repo: a ledger whose record CLEARS the evidence floor (integration=2)
# BUT carries wired_in_prod=false — i.e. green test, not wired into the product.
repo="$(mktemp -d)"
mkdir -p "$repo/docs/reality"
cat > "$repo/docs/reality/$FEAT.evidence.jsonl" <<JSON
{"feature":"$FEAT","requirement_id":"REQ-X1","evidence_class":"integration","evidence_ref":"unit suite green","verified_by":"ci","wired_in_prod":false,"note":"green test, NOT wired into the running product"}
JSON

assert_file "A0: reality-check binary present" "$REALITY"

# A1 (positive control / gap exposure): plain mode currently PASSES a not-wired
# record. This assertion PASSES today and documents the hole.
set +e
"$REALITY" --repo "$repo" --feature "$FEAT" --min-evidence integration >/dev/null 2>&1; rc1=$?
set -e
assert_eq "A1 gap: plain reality-check currently PASSES the not-wired record (exit 0)" "0" "$rc1"

# A2 (RED contract): a wired-enforcing mode must fail-closed and name the
# stop-code. `--require-wired` is the INTENDED enforcement interface (the flag
# name is a placeholder for the fix; the load-bearing assertions are the
# STOP-WIRED-PROD behaviour and naming the culprit REQ, not the exact CLI).
set +e
out2="$("$REALITY" --repo "$repo" --feature "$FEAT" --min-evidence integration --require-wired 2>&1)"
set -e
assert_contains "A2 RED: wired-enforcing rejection carries stop-code STOP-WIRED-PROD" "$out2" "STOP-WIRED-PROD"
assert_contains "A2 RED: rejection names the not-wired requirement (REQ-X1)" "$out2" "REQ-X1"

rm -rf "$repo"
echo "  (RED expected: A2 assertions FAIL until wired-in-prod enforcement exists)"
exit "${TESTS_FAILED:-0}"
