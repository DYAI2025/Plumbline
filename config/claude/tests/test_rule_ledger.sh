#!/usr/bin/env bash
#
# Contract test for the rule-ledger provenance scaffold (M3.2).
#   * rule_ledger.py appends ONE JSONL line per approved rule, round-tripping
#     {rule_id, approved_at, level, target_file, named_metric, direction}.
#   * approved_at is supplied as an ARG (no wall-clock / Date.now in the script).
#   * a write happens ONLY on explicit CLI input (no silent-write path) — mirrors
#     the human y/n approval gate.
#   * emit_run.py --active-rules round-trips into record["active_rules"]; default [].
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
LEDGER="$REPO_DIR/config/claude/metrics/rule_ledger.py"
WRAP="$REPO_DIR/config/claude/bin/plumbline-rule-ledger"
EMIT="$REPO_DIR/config/claude/metrics/emit_run.py"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

echo "test_rule_ledger"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
out_file="$tmp/rule-ledger.jsonl"

# 1) appending a rule round-trips ALL fields from CLI args (one JSONL line)
python3 "$LEDGER" \
  --rule-id R-2026-001 \
  --approved-at 2026-06-02T10:00:00Z \
  --level A \
  --target-file CLAUDE.md \
  --named-metric escaped_defect_rate \
  --direction lower_is_better \
  --out "$out_file" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -f "$out_file" ] && [ "$(wc -l < "$out_file")" -eq 1 ] \
   && python3 -c '
import json,sys
r=json.loads(open(sys.argv[1]).read().strip())
assert r["rule_id"]=="R-2026-001", r
assert r["approved_at"]=="2026-06-02T10:00:00Z", r
assert r["level"]=="A", r
assert r["target_file"]=="CLAUDE.md", r
assert r["named_metric"]=="escaped_defect_rate", r
assert r["direction"]=="lower_is_better", r
' "$out_file" 2>/dev/null; then
  ok "rule_ledger appends one JSONL line round-tripping all six fields"
else bad "rule_ledger appends one JSONL line round-tripping all six fields"; fi

# 2) approved_at comes from the ARG verbatim (no wall-clock substitution)
python3 "$LEDGER" --rule-id R-X --approved-at 1999-12-31T23:59:59Z --level B \
  --target-file core/coder.md --named-metric first_pass --direction higher_is_better \
  --out "$out_file" >/dev/null 2>&1
if python3 -c '
import json,sys
lines=[l for l in open(sys.argv[1]) if l.strip()]
assert len(lines)==2, "append, not overwrite"
r=json.loads(lines[-1])
assert r["approved_at"]=="1999-12-31T23:59:59Z", r
' "$out_file" 2>/dev/null; then
  ok "approved_at is taken verbatim from the arg (no Date.now); append not overwrite"
else bad "approved_at is taken verbatim from the arg (no Date.now); append not overwrite"; fi

# 3) the script body must NOT call wall-clock helpers (no silent timestamp)
if ! grep -Eq 'datetime\.now|time\.time|utcnow|Date\.now' "$LEDGER"; then
  ok "rule_ledger.py contains no wall-clock call (approved_at is caller-supplied)"
else bad "rule_ledger.py contains no wall-clock call (approved_at is caller-supplied)"; fi

# 4) a required field missing => fail closed, NO file write (no silent path)
nofile="$tmp/should-not-exist.jsonl"
python3 "$LEDGER" --rule-id R-Y --level A --target-file CLAUDE.md \
  --named-metric first_pass --direction higher_is_better --out "$nofile" >/dev/null 2>&1
rc=$?
if [ "$rc" -ne 0 ] && [ ! -f "$nofile" ]; then
  ok "missing required arg (approved_at) fails closed and writes nothing"
else bad "missing required arg (approved_at) fails closed and writes nothing"; fi

# 5) the bin wrapper is executable and forwards to rule_ledger.py
wrapfile="$tmp/wrap-ledger.jsonl"
"$WRAP" --rule-id R-W --approved-at 2026-06-02T11:00:00Z --level C \
  --target-file skills/foo/SKILL.md --named-metric mutation --direction higher_is_better \
  --out "$wrapfile" >/dev/null 2>&1
rc=$?
if [ "$rc" -eq 0 ] && [ -x "$WRAP" ] && [ -f "$wrapfile" ] \
   && python3 -c 'import json,sys; assert json.loads(open(sys.argv[1]).read().strip())["rule_id"]=="R-W"' "$wrapfile" 2>/dev/null; then
  ok "plumbline-rule-ledger wrapper is executable and forwards to rule_ledger.py"
else bad "plumbline-rule-ledger wrapper is executable and forwards to rule_ledger.py"; fi

# 6) emit_run.py --active-rules round-trips into record["active_rules"]
out="$(python3 "$EMIT" --dry-run --metrics '{}' --active-rules '["R1","R2"]' 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r["active_rules"]==["R1","R2"], r.get("active_rules")
' 2>/dev/null; then
  ok "emit_run --active-rules round-trips into record.active_rules"
else bad "emit_run --active-rules round-trips into record.active_rules"; fi

# 7) record.active_rules defaults to [] when --active-rules is omitted
out="$(python3 "$EMIT" --dry-run --metrics '{}' 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
assert json.load(sys.stdin)["active_rules"]==[]
' 2>/dev/null; then
  ok "record.active_rules defaults to [] (no silent state)"
else bad "record.active_rules defaults to [] (no silent state)"; fi

# 8) --active-rules must be a JSON ARRAY: an object fails closed with ERROR
out="$(python3 "$EMIT" --dry-run --metrics '{}' --active-rules '{"a":1}' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'ERROR'; then
  ok "--active-rules non-array fails closed with ERROR"
else bad "--active-rules non-array fails closed with ERROR"; fi

# 9) bash syntax valid
if bash -n "$WRAP" 2>/dev/null; then ok "wrapper passes bash -n"; else bad "wrapper passes bash -n"; fi

printf '\ntest_rule_ledger: %d run, %d failed\n' "$((pass+fail))" "$fail"
[ "$fail" -eq 0 ]
