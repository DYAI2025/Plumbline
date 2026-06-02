#!/usr/bin/env bash
#
# Contract test for the versioned, fail-closed metrics emitter (STEP 0/1).
# Round-trips emit_run.py --dry-run and asserts: schema version present,
# allowlisted keys pass, non-allowlisted keys fail closed, cost is per-validated-req.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
EMIT="$REPO_DIR/config/claude/metrics/emit_run.py"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

echo "test_metrics_contract"

# 1) allowlisted metric round-trips and carries the schema version
out="$(python3 "$EMIT" --dry-run --metrics '{"first_pass":0.9}' 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r.get("metrics_schema_version")==1, "schema version"
assert r["metrics"]["first_pass"]==0.9, "metric round-trip"
' 2>/dev/null; then ok "allowlisted metric round-trips with schema_version=1"; else bad "allowlisted metric round-trips with schema_version=1"; fi

# 2) NON-allowlisted metric key fails closed (the verified drift: 'tasks' is not scored)
out="$(python3 "$EMIT" --dry-run --metrics '{"tasks":6}' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "tasks"; then
  ok "non-allowlisted metric key fails closed and names the key"
else bad "non-allowlisted metric key fails closed and names the key"; fi

# 3) operational counts go to raw, never rejected
out="$(python3 "$EMIT" --dry-run --metrics '{"mutation":0.8}' --raw '{"tasks":6,"devreview_loops_total":8}' 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r["raw"]["tasks"]==6 and r["raw"]["devreview_loops_total"]==8
assert "tasks" not in r["metrics"]
' 2>/dev/null; then ok "operational counts accepted under raw, kept out of metrics"; else bad "operational counts accepted under raw, kept out of metrics"; fi

# 4) cost is per-VALIDATED-req: cost_per_req = tokens_total / reqs_accepted
out="$(python3 "$EMIT" --dry-run --metrics '{}' --tokens-total 120000 --reqs-accepted 4 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r["metrics"]["cost_per_req"]==30000.0, r["metrics"].get("cost_per_req")
assert r["raw"]["tokens_total"]==120000 and r["raw"]["reqs_accepted"]==4
' 2>/dev/null; then ok "cost_per_req = tokens/validated_reqs with provenance in raw"; else bad "cost_per_req = tokens/validated_reqs with provenance in raw"; fi

# 5) zero validated reqs does not divide by zero (denominator floored at 1)
out="$(python3 "$EMIT" --dry-run --metrics '{}' --tokens-total 1000 --reqs-accepted 0 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
assert json.load(sys.stdin)["metrics"]["cost_per_req"]==1000.0
' 2>/dev/null; then ok "zero validated reqs is div-by-zero safe"; else bad "zero validated reqs is div-by-zero safe"; fi

# 6) the allowlist IS process_health.DIRECTIONS (no drift): cost_per_req is scored, so it passes
out="$(python3 "$EMIT" --dry-run --metrics '{"cost_per_req":1234.5}' 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "scored key cost_per_req is allowlisted (allowlist==DIRECTIONS)"; else bad "scored key cost_per_req is allowlisted (allowlist==DIRECTIONS)"; fi

# 7) --raw must be a JSON OBJECT: a JSON array (non-object) fails closed
out="$(python3 "$EMIT" --dry-run --metrics '{}' --raw '[1,2,3]' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR'; then
  ok "--raw non-object (array) fails closed with ERROR"
else bad "--raw non-object (array) fails closed with ERROR"; fi

# 8) invalid JSON for --raw fails closed with ERROR, NOT a Python traceback
out="$(python3 "$EMIT" --dry-run --metrics '{}' --raw 'notjson' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR' && ! printf '%s' "$out" | grep -q 'Traceback'; then
  ok "--raw invalid JSON fails closed with ERROR and no Traceback"
else bad "--raw invalid JSON fails closed with ERROR and no Traceback"; fi

# 9) invalid JSON for --metrics fails closed with ERROR, NOT a Python traceback
out="$(python3 "$EMIT" --dry-run --metrics 'notjson' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR' && ! printf '%s' "$out" | grep -q 'Traceback'; then
  ok "--metrics invalid JSON fails closed with ERROR and no Traceback"
else bad "--metrics invalid JSON fails closed with ERROR and no Traceback"; fi

# 10) --metrics non-object (array) fails closed with ERROR
out="$(python3 "$EMIT" --dry-run --metrics '[1,2,3]' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR'; then
  ok "--metrics non-object (array) fails closed with ERROR"
else bad "--metrics non-object (array) fails closed with ERROR"; fi

# 11) --gate-outcomes invalid JSON fails closed with ERROR, NOT a Python traceback
out="$(python3 "$EMIT" --dry-run --metrics '{}' --gate-outcomes 'notjson' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR' && ! printf '%s' "$out" | grep -q 'Traceback'; then
  ok "--gate-outcomes invalid JSON fails closed with ERROR and no Traceback"
else bad "--gate-outcomes invalid JSON fails closed with ERROR and no Traceback"; fi

# 12) --gate-outcomes non-object (array) fails closed with ERROR
out="$(python3 "$EMIT" --dry-run --metrics '{}' --gate-outcomes '[1,2,3]' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR'; then
  ok "--gate-outcomes non-object (array) fails closed with ERROR"
else bad "--gate-outcomes non-object (array) fails closed with ERROR"; fi

# 13) negative --tokens-total is rejected (would corrupt SPC baseline via negative cost)
out="$(python3 "$EMIT" --dry-run --metrics '{}' --tokens-total -5 --reqs-accepted 2 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR'; then
  ok "negative --tokens-total rejected with ERROR"
else bad "negative --tokens-total rejected with ERROR"; fi

# 14) negative --reqs-accepted is rejected
out="$(python3 "$EMIT" --dry-run --metrics '{}' --tokens-total 100 --reqs-accepted -1 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR'; then
  ok "negative --reqs-accepted rejected with ERROR"
else bad "negative --reqs-accepted rejected with ERROR"; fi

# 15) cost_per_req supplied BOTH via --metrics AND computed from --tokens-total -> conflict, fail closed
out="$(python3 "$EMIT" --dry-run --metrics '{"cost_per_req":1.0}' --tokens-total 100 --reqs-accepted 2 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR'; then
  ok "double-supplied cost_per_req (--metrics + --tokens-total) fails closed"
else bad "double-supplied cost_per_req (--metrics + --tokens-total) fails closed"; fi

printf '\ntest_metrics_contract: %d run, %d failed\n' "$((pass+fail))" "$fail"
[ "$fail" -eq 0 ]
