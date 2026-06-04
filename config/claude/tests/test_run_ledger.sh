#!/usr/bin/env bash
#
# Contract test for the executable resumable run-ledger (M6.3).
#   * plumbline_run_ledger.py records one append-only JSONL row per gate event
#     at docs/context/<feature>.run-ledger.jsonl, round-tripping
#     {repo, feature, gate, status, artifact_hash, at}.
#   * `at` is supplied as an ARG (no wall-clock / Date.now in the script).
#   * resume-point prints the FIRST gate (in recorded order) whose LATEST status
#     is not CLEARED; an all-observed-cleared but partial ledger => a
#     start-from-beginning sentinel; an explicit __RUN_COMPLETE__ marker => a
#     complete sentinel; missing/corrupt/empty ledger => a start-from-beginning
#     sentinel (fail-closed to Phase 0, NEVER inferred "all cleared").
#   * revalidate exits non-zero when a CLEARED gate's recorded artifact-hash no
#     longer matches the current hash (a human gate whose artifact changed must
#     be re-asked).
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
LEDGER="$REPO_DIR/config/claude/lib/plumbline_run_ledger.py"
WRAP="$REPO_DIR/config/claude/bin/plumbline-run-ledger"

# Sentinels / synthetic marker the script promises (kept in sync with the lib).
START_SENTINEL="__START__"
COMPLETE_SENTINEL="__COMPLETE__"
RUN_COMPLETE_GATE="__RUN_COMPLETE__"

pass=0; fail=0
ok()  { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad() { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

echo "test_run_ledger"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
repo="$tmp/repo"
mkdir -p "$repo/docs/context"

# record CLEARED gate A, then PENDING gate B
python3 "$LEDGER" record --repo "$repo" --feature demo \
  --gate phase0 --status CLEARED --artifact-hash hA \
  --at 2026-06-02T10:00:00Z >/dev/null 2>&1
python3 "$LEDGER" record --repo "$repo" --feature demo \
  --gate gateA --status PENDING --artifact-hash hB \
  --at 2026-06-02T10:01:00Z >/dev/null 2>&1

led="$repo/docs/context/demo.run-ledger.jsonl"

# 1) ledger is the per-feature append-only JSONL at the documented path
if [ -f "$led" ] && [ "$(wc -l < "$led")" -eq 2 ]; then
  ok "record appends to docs/context/<feature>.run-ledger.jsonl (one row each)"
else bad "record appends to docs/context/<feature>.run-ledger.jsonl (one row each)"; fi

# 2) round-trip of all fields from the FIRST recorded row
if python3 -c '
import json,sys
r=json.loads(open(sys.argv[1]).readlines()[0])
assert r["repo"], r
assert r["feature"]=="demo", r
assert r["gate"]=="phase0", r
assert r["status"]=="CLEARED", r
assert r["artifact_hash"]=="hA", r
assert r["at"]=="2026-06-02T10:00:00Z", r
' "$led" 2>/dev/null; then
  ok "row round-trips {repo, feature, gate, status, artifact_hash, at}"
else bad "row round-trips {repo, feature, gate, status, artifact_hash, at}"; fi

# 3) resume-point = first non-CLEARED gate in recorded order (gateB is PENDING)
rp="$(python3 "$LEDGER" resume-point --repo "$repo" --feature demo 2>/dev/null)"
if [ "$rp" = "gateA" ]; then
  ok "resume-point returns the first non-CLEARED gate (gateA)"
else bad "resume-point returns the first non-CLEARED gate (got: '$rp')"; fi

# 4) latest-status wins: clear gateA, but without an explicit completion marker the
# ledger may be partial (crash between gates) and must fail closed to START.
python3 "$LEDGER" record --repo "$repo" --feature demo \
  --gate gateA --status CLEARED --artifact-hash hB \
  --at 2026-06-02T10:02:00Z >/dev/null 2>&1
rp="$(python3 "$LEDGER" resume-point --repo "$repo" --feature demo 2>/dev/null)"
if [ "$rp" = "$START_SENTINEL" ]; then
  ok "all-observed-CLEARED partial ledger fails closed to the START sentinel"
else bad "all-observed-CLEARED partial ledger fails closed to START (got: '$rp')"; fi

# 5) explicit completion marker is the only way resume-point can return complete
python3 "$LEDGER" record --repo "$repo" --feature demo \
  --gate "$RUN_COMPLETE_GATE" --status CLEARED --artifact-hash hDONE \
  --at 2026-06-02T10:03:00Z >/dev/null 2>&1
rp="$(python3 "$LEDGER" resume-point --repo "$repo" --feature demo 2>/dev/null)"
if [ "$rp" = "$COMPLETE_SENTINEL" ]; then
  ok "explicit run-complete marker returns the complete sentinel"
else bad "explicit run-complete marker returns the complete sentinel (got: '$rp')"; fi

# 6) a re-PAUSED gate after a CLEAR means latest wins => resume there again
python3 "$LEDGER" record --repo "$repo" --feature demo \
  --gate phase0 --status PAUSED --artifact-hash hA \
  --at 2026-06-02T10:04:00Z >/dev/null 2>&1
rp="$(python3 "$LEDGER" resume-point --repo "$repo" --feature demo 2>/dev/null)"
if [ "$rp" = "phase0" ]; then
  ok "latest status wins: a re-PAUSED cleared gate becomes the resume-point"
else bad "latest status wins: a re-PAUSED cleared gate becomes the resume-point (got: '$rp')"; fi

# 7) MISSING ledger => start sentinel (fail-closed to Phase 0, never complete)
rp="$(python3 "$LEDGER" resume-point --repo "$repo" --feature nonexistent 2>/dev/null)"
if [ "$rp" = "$START_SENTINEL" ]; then
  ok "missing ledger fails closed to the START sentinel (never complete)"
else bad "missing ledger fails closed to the START sentinel (got: '$rp')"; fi

# 8) CORRUPT ledger => start sentinel (fail-closed, never complete)
corrupt_repo="$tmp/corrupt"
mkdir -p "$corrupt_repo/docs/context"
printf 'not json at all\n{partial' > "$corrupt_repo/docs/context/demo.run-ledger.jsonl"
rp="$(python3 "$LEDGER" resume-point --repo "$corrupt_repo" --feature demo 2>/dev/null)"
if [ "$rp" = "$START_SENTINEL" ]; then
  ok "corrupt ledger fails closed to the START sentinel (never complete)"
else bad "corrupt ledger fails closed to the START sentinel (got: '$rp')"; fi

# 9) EMPTY ledger => start sentinel (fail-closed, never complete)
empty_repo="$tmp/empty"
mkdir -p "$empty_repo/docs/context"
: > "$empty_repo/docs/context/demo.run-ledger.jsonl"
rp="$(python3 "$LEDGER" resume-point --repo "$empty_repo" --feature demo 2>/dev/null)"
if [ "$rp" = "$START_SENTINEL" ]; then
  ok "empty ledger fails closed to the START sentinel (never complete)"
else bad "empty ledger fails closed to the START sentinel (got: '$rp')"; fi

# 10) revalidate: CLEARED human gate whose artifact changed => non-zero (re-ask)
hrepo="$tmp/hrepo"
mkdir -p "$hrepo/docs/context"
python3 "$LEDGER" record --repo "$hrepo" --feature demo \
  --gate usergate --status CLEARED --artifact-hash hOLD \
  --at 2026-06-02T10:00:00Z >/dev/null 2>&1
if ! python3 "$LEDGER" revalidate --repo "$hrepo" --feature demo \
  --gate usergate --current-hash hNEW >/dev/null 2>&1; then
  ok "revalidate of a CLEARED gate with a changed hash exits non-zero (stale)"
else bad "revalidate of a CLEARED gate with a changed hash exits non-zero (stale)"; fi

# 11) revalidate: CLEARED human gate with the SAME hash => exit 0 (trusted)
if python3 "$LEDGER" revalidate --repo "$hrepo" --feature demo \
  --gate usergate --current-hash hOLD >/dev/null 2>&1; then
  ok "revalidate of a CLEARED gate with an unchanged hash exits 0 (trusted)"
else bad "revalidate of a CLEARED gate with an unchanged hash exits 0 (trusted)"; fi

# 12) revalidate: a gate that is NOT latest-CLEARED => non-zero (must re-run)
if ! python3 "$LEDGER" revalidate --repo "$hrepo" --feature demo \
  --gate neverseen --current-hash hX >/dev/null 2>&1; then
  ok "revalidate of a non-cleared/unknown gate exits non-zero (fail-closed)"
else bad "revalidate of a non-cleared/unknown gate exits non-zero (fail-closed)"; fi

# 13) no wall-clock call in the ledger script (at is caller-supplied)
if ! grep -Eq 'datetime\.now|time\.time|utcnow|Date\.now|datetime\.today' "$LEDGER"; then
  ok "plumbline_run_ledger.py contains no wall-clock call (at is caller-supplied)"
else bad "plumbline_run_ledger.py contains no wall-clock call (at is caller-supplied)"; fi

# 14) the bin wrapper is executable and forwards to plumbline_run_ledger.py
wrap_repo="$tmp/wrap"
mkdir -p "$wrap_repo/docs/context"
"$WRAP" record --repo "$wrap_repo" --feature demo \
  --gate phase0 --status PENDING --artifact-hash hW \
  --at 2026-06-02T12:00:00Z >/dev/null 2>&1
rc=$?
rpw="$("$WRAP" resume-point --repo "$wrap_repo" --feature demo 2>/dev/null)"
if [ "$rc" -eq 0 ] && [ -x "$WRAP" ] && [ "$rpw" = "phase0" ]; then
  ok "plumbline-run-ledger wrapper is executable and forwards to the lib"
else bad "plumbline-run-ledger wrapper is executable and forwards to the lib"; fi

# 15) record fails closed on a bad --status (no silent default)
if ! python3 "$LEDGER" record --repo "$wrap_repo" --feature demo \
  --gate phase0 --status BOGUS --artifact-hash h --at 2026-06-02T00:00:00Z >/dev/null 2>&1; then
  ok "record rejects an unknown --status (fail-closed, no silent default)"
else bad "record rejects an unknown --status (fail-closed, no silent default)"; fi

# 16) bash syntax valid
if bash -n "$WRAP" 2>/dev/null; then ok "wrapper passes bash -n"; else bad "wrapper passes bash -n"; fi

printf '\ntest_run_ledger: %d run, %d failed\n' "$((pass+fail))" "$fail"
[ "$fail" -eq 0 ]
