#!/usr/bin/env bash
# PLUM-13 contract tests: a green test only counts as evidence for the boundary the
# acceptance criterion actually demanded.
#
# Measured pilot defect (reproduced 2026-07-30 against the pre-fix gate):
#   * a ledger record claiming `real-boundary-smoke` for a requirement about dataset
#     W32 on the product read-through route, whose linked test drove W40 harness
#     fixtures on a different route, PASSED the reality gate (exit 0);
#   * worse, a record whose `evidence_ref` pointed at a file that does not exist at
#     all was credited as `production-verified` (exit 0).
# The gate ranked the CLAIMED class and never asked what the evidence touched.
#
# Contract:
#   * a critical AC declares dataset, boundary, expected result and preconditions in
#     docs/evidence/<feature>.targets.json (AC-1);
#   * a test links as evidence only when that binding is provably met (AC-2);
#   * fixture preconditions are expressible as present/absent (AC-3);
#   * a green test on the WRONG dataset does not satisfy the AC (AC-4);
#   * the gate reports MISSING_BOUNDARY / EVIDENCE_MISMATCH (AC-5);
#   * features without a targets file are unaffected (backward compatible).
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_evidence_target"

REALITY_BIN="$REPO_DIR/config/claude/bin/plumbline-reality-check"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

new_repo() {
  local name="$1" repo
  repo="$WORK/$name"
  mkdir -p "$repo/docs/reality" "$repo/docs/evidence" "$repo/tests"
  printf '%s' "$repo"
}

# The real test that exists in every fixture repo below: it exercises the W32
# default-seed dataset through the product read-through route.
write_correct_test() {
  cat >"$1/tests/test_read_through.sh" <<'EOF'
#!/usr/bin/env bash
# Read-through over the product route.
fixture="fixtures/W32-default-seed.json"
route="GET /api/v1/tree/read-through"
echo "ok $route with $fixture"
EOF
}

# The pilot's actual test: green, but on its own W40 harness fixtures.
write_harness_test() {
  cat >"$1/tests/test_harness_read_through.sh" <<'EOF'
#!/usr/bin/env bash
# Read-through over the W40 harness fixtures.
fixture="fixtures/W40-harness-seed.json"
route="GET /api/v1/harness/read-through"
echo "ok $route with $fixture"
EOF
}

# run_reality <repo> <feature> [args...]
run_reality() {
  local repo="$1" feat="$2"
  shift 2
  local outf="$WORK/reality.out"
  "$REALITY_BIN" --repo "$repo" --feature "$feat" "$@" >"$outf" 2>&1
  REAL_RC=$?
  REAL_OUT="$(cat "$outf")"
}

# ---------------------------------------------------------------------------
# B. Backward compatibility: no targets file -> behaviour unchanged.
# ---------------------------------------------------------------------------

repo="$(new_repo legacy)"
cat >"$repo/docs/reality/legacy.evidence.jsonl" <<'EOF'
{"feature": "legacy", "requirement_id": "REQ-L-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_thing.sh::REQ-L-001", "verified_by": "suite", "note": "no target declared"}
EOF
run_reality "$repo" legacy --min-evidence integration-fake
assert_eq "no targets file: legacy ledger still passes" "0" "$REAL_RC"

# ---------------------------------------------------------------------------
# M. MISSING_BOUNDARY -- a declared target with no usable evidence.
# ---------------------------------------------------------------------------

repo="$(new_repo noevidence)"
write_correct_test "$repo"
cat >"$repo/docs/evidence/noevidence.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "noevidence",
  "targets": [
    {
      "requirement_id": "REQ-N-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "seed ids resolve to the default catalog"
    }
  ]
}
EOF
cat >"$repo/docs/reality/noevidence.evidence.jsonl" <<'EOF'
{"feature": "noevidence", "requirement_id": "REQ-OTHER", "evidence_class": "integration-fake", "evidence_ref": "tests/test_read_through.sh::REQ-OTHER", "verified_by": "suite", "note": "unrelated requirement"}
EOF
run_reality "$repo" noevidence --min-evidence integration-fake
assert_eq "declared target with no record: exit 2" "2" "$REAL_RC"
assert_contains "no record: classified MISSING_BOUNDARY" \
  "$REAL_OUT" "MISSING_BOUNDARY"
assert_contains "no record: names the requirement" "$REAL_OUT" "REQ-N-001"

# A record exists but carries no binding at all: the boundary is still unevidenced.
cat >"$repo/docs/reality/noevidence.evidence.jsonl" <<'EOF'
{"feature": "noevidence", "requirement_id": "REQ-N-001", "evidence_class": "real-boundary-smoke", "evidence_ref": "tests/test_read_through.sh::REQ-N-001", "verified_by": "suite", "note": "no dataset or boundary declared"}
EOF
run_reality "$repo" noevidence --min-evidence integration-fake
assert_eq "record without binding fields: exit 2" "2" "$REAL_RC"
assert_contains "unbound record: classified MISSING_BOUNDARY" \
  "$REAL_OUT" "MISSING_BOUNDARY"
assert_contains "unbound record: names the missing field" "$REAL_OUT" "dataset"

# ---------------------------------------------------------------------------
# E. EVIDENCE_MISMATCH -- evidence exists but proves the wrong thing (AC-4).
# ---------------------------------------------------------------------------

# The pilot case, exactly: a GREEN test at the wrong dataset and route.
repo="$(new_repo wrongdataset)"
write_correct_test "$repo"
write_harness_test "$repo"
cat >"$repo/docs/evidence/wrongdataset.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "wrongdataset",
  "targets": [
    {
      "requirement_id": "REQ-W-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "seed ids resolve to the default catalog"
    }
  ]
}
EOF
cat >"$repo/docs/reality/wrongdataset.evidence.jsonl" <<'EOF'
{"feature": "wrongdataset", "requirement_id": "REQ-W-001", "evidence_class": "real-boundary-smoke", "evidence_ref": "tests/test_harness_read_through.sh::REQ-W-001", "dataset": "W40-harness-seed", "boundary": "GET /api/v1/harness/read-through", "expected_result": "seed ids resolve to the default catalog", "verified_by": "suite", "note": "green, but on the harness fixtures"}
EOF
run_reality "$repo" wrongdataset --min-evidence integration-fake
assert_eq "green test at the wrong dataset: exit 3" "3" "$REAL_RC"
assert_contains "wrong dataset: classified EVIDENCE_MISMATCH" \
  "$REAL_OUT" "EVIDENCE_MISMATCH"
assert_contains "wrong dataset: names the demanded dataset" \
  "$REAL_OUT" "W32-default-seed"
assert_contains "wrong dataset: names the evidenced dataset" \
  "$REAL_OUT" "W40-harness-seed"

# Positive control on the SAME repo: the correctly-bound record passes, so the
# gate is discriminating between the two tests rather than rejecting everything.
cat >"$repo/docs/reality/wrongdataset.evidence.jsonl" <<'EOF'
{"feature": "wrongdataset", "requirement_id": "REQ-W-001", "evidence_class": "real-boundary-smoke", "evidence_ref": "tests/test_read_through.sh::REQ-W-001", "dataset": "W32-default-seed", "boundary": "GET /api/v1/tree/read-through", "expected_result": "seed ids resolve to the default catalog", "verified_by": "suite", "note": "the product route on the demanded dataset"}
EOF
run_reality "$repo" wrongdataset --min-evidence integration-fake
assert_eq "correctly bound record at the same target passes" "0" "$REAL_RC"
assert_contains "pass names the bound requirement" "$REAL_OUT" "REQ-W-001"

# A matching binding whose referenced test does NOT contain the dataset token is a
# self-declared claim, not proof. This is the pilot's mechanism: the record can be
# written to agree with the target while the test still drives other fixtures.
repo="$(new_repo unproven)"
write_correct_test "$repo"
write_harness_test "$repo"
cat >"$repo/docs/evidence/unproven.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "unproven",
  "targets": [
    {
      "requirement_id": "REQ-U-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "seed ids resolve"
    }
  ]
}
EOF
cat >"$repo/docs/reality/unproven.evidence.jsonl" <<'EOF'
{"feature": "unproven", "requirement_id": "REQ-U-001", "evidence_class": "real-boundary-smoke", "evidence_ref": "tests/test_harness_read_through.sh::REQ-U-001", "dataset": "W32-default-seed", "boundary": "GET /api/v1/tree/read-through", "expected_result": "seed ids resolve", "verified_by": "suite", "note": "binding CLAIMS the right target; the test drives W40"}
EOF
run_reality "$repo" unproven --min-evidence integration-fake
assert_eq "binding not provable in the referenced test: exit 3" "3" "$REAL_RC"
assert_contains "unproven binding: classified EVIDENCE_MISMATCH" \
  "$REAL_OUT" "EVIDENCE_MISMATCH"
assert_contains "unproven binding: names the token it could not find" \
  "$REAL_OUT" "W32-default-seed"
assert_contains "unproven binding: names the file it searched" \
  "$REAL_OUT" "tests/test_harness_read_through.sh"

# The second reproduced false green: an evidence_ref that resolves to nothing.
repo="$(new_repo unresolvable)"
write_correct_test "$repo"
cat >"$repo/docs/evidence/unresolvable.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "unresolvable",
  "targets": [
    {
      "requirement_id": "REQ-R-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "seed ids resolve"
    }
  ]
}
EOF
cat >"$repo/docs/reality/unresolvable.evidence.jsonl" <<'EOF'
{"feature": "unresolvable", "requirement_id": "REQ-R-001", "evidence_class": "production-verified", "evidence_ref": "tests/does_not_exist_at_all.sh::REQ-R-001", "dataset": "W32-default-seed", "boundary": "GET /api/v1/tree/read-through", "expected_result": "seed ids resolve", "verified_by": "suite", "note": "the referenced artifact does not exist"}
EOF
run_reality "$repo" unresolvable --min-evidence integration-fake
assert_eq "unresolvable evidence_ref: exit 3" "3" "$REAL_RC"
assert_contains "unresolvable ref: classified EVIDENCE_MISMATCH" \
  "$REAL_OUT" "EVIDENCE_MISMATCH"
assert_contains "unresolvable ref: names the unresolved path" \
  "$REAL_OUT" "does_not_exist_at_all.sh"
assert_contains "unresolvable ref: says it could not be resolved" \
  "$REAL_OUT" "unresolvable"

# A per-target evidence floor is enforced even when the CLI floor is lower, so a
# target that demands a real boundary cannot be closed with an offline fake.
repo="$(new_repo targetfloor)"
write_correct_test "$repo"
cat >"$repo/docs/evidence/targetfloor.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "targetfloor",
  "targets": [
    {
      "requirement_id": "REQ-F-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "seed ids resolve",
      "min_evidence": "real-boundary-smoke"
    }
  ]
}
EOF
cat >"$repo/docs/reality/targetfloor.evidence.jsonl" <<'EOF'
{"feature": "targetfloor", "requirement_id": "REQ-F-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_read_through.sh::REQ-F-001", "dataset": "W32-default-seed", "boundary": "GET /api/v1/tree/read-through", "expected_result": "seed ids resolve", "verified_by": "suite", "note": "offline only"}
EOF
run_reality "$repo" targetfloor --min-evidence integration-fake
assert_eq "per-target floor outranks a lower CLI floor: exit 3" "3" "$REAL_RC"
assert_contains "target floor: names the demanded class" \
  "$REAL_OUT" "real-boundary-smoke"

# ---------------------------------------------------------------------------
# P. Preconditions: present/absent, and no vacuous absence test (AC-3).
# ---------------------------------------------------------------------------

repo="$(new_repo precond)"
write_correct_test "$repo"
cat >"$repo/docs/evidence/precond.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "precond",
  "targets": [
    {
      "requirement_id": "REQ-C-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "seed ids resolve",
      "preconditions": [{"fixture": "seed-catalog", "state": "present"}]
    }
  ]
}
EOF
cat >"$repo/docs/reality/precond.evidence.jsonl" <<'EOF'
{"feature": "precond", "requirement_id": "REQ-C-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_read_through.sh::REQ-C-001", "dataset": "W32-default-seed", "boundary": "GET /api/v1/tree/read-through", "expected_result": "seed ids resolve", "preconditions": [{"fixture": "seed-catalog", "state": "absent"}], "verified_by": "suite", "note": "ran with the fixture ABSENT, not present"}
EOF
run_reality "$repo" precond --min-evidence integration-fake
assert_eq "precondition state mismatch: exit 3" "3" "$REAL_RC"
assert_contains "precondition mismatch: classified EVIDENCE_MISMATCH" \
  "$REAL_OUT" "EVIDENCE_MISMATCH"
assert_contains "precondition mismatch: names the fixture" \
  "$REAL_OUT" "seed-catalog"

# An `absent`-state target is a vacuum risk: it passes trivially while the
# counter-set does not exist yet. It therefore requires a paired present-state
# control, named in the record.
repo="$(new_repo vacuum)"
write_correct_test "$repo"
cat >"$repo/docs/evidence/vacuum.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "vacuum",
  "targets": [
    {
      "requirement_id": "REQ-V-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "a missing seed yields a classified 404",
      "preconditions": [{"fixture": "seed-catalog", "state": "absent"}]
    }
  ]
}
EOF
cat >"$repo/docs/reality/vacuum.evidence.jsonl" <<'EOF'
{"feature": "vacuum", "requirement_id": "REQ-V-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_read_through.sh::REQ-V-001", "dataset": "W32-default-seed", "boundary": "GET /api/v1/tree/read-through", "expected_result": "a missing seed yields a classified 404", "preconditions": [{"fixture": "seed-catalog", "state": "absent"}], "verified_by": "suite", "note": "absence proven with no present-state control"}
EOF
run_reality "$repo" vacuum --min-evidence integration-fake
assert_eq "absence evidence without a control: exit 3" "3" "$REAL_RC"
assert_contains "vacuous absence: classified EVIDENCE_MISMATCH" \
  "$REAL_OUT" "EVIDENCE_MISMATCH"
assert_contains "vacuous absence: names the missing control" \
  "$REAL_OUT" "control_ref"

# With the control named and resolvable, the absence evidence is accepted.
cat >"$repo/docs/reality/vacuum.evidence.jsonl" <<'EOF'
{"feature": "vacuum", "requirement_id": "REQ-V-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_read_through.sh::REQ-V-001", "control_ref": "tests/test_read_through.sh::REQ-V-001-present", "dataset": "W32-default-seed", "boundary": "GET /api/v1/tree/read-through", "expected_result": "a missing seed yields a classified 404", "preconditions": [{"fixture": "seed-catalog", "state": "absent"}], "verified_by": "suite", "note": "paired with a present-state control"}
EOF
run_reality "$repo" vacuum --min-evidence integration-fake
assert_eq "absence evidence WITH a resolvable control passes" "0" "$REAL_RC"

# A control_ref that resolves to nothing is not a control.
cat >"$repo/docs/reality/vacuum.evidence.jsonl" <<'EOF'
{"feature": "vacuum", "requirement_id": "REQ-V-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_read_through.sh::REQ-V-001", "control_ref": "tests/no_such_control.sh::x", "dataset": "W32-default-seed", "boundary": "GET /api/v1/tree/read-through", "expected_result": "a missing seed yields a classified 404", "preconditions": [{"fixture": "seed-catalog", "state": "absent"}], "verified_by": "suite", "note": "control does not exist"}
EOF
run_reality "$repo" vacuum --min-evidence integration-fake
assert_eq "unresolvable control_ref: exit 3" "3" "$REAL_RC"
assert_contains "unresolvable control: names the control path" \
  "$REAL_OUT" "no_such_control.sh"

# ---------------------------------------------------------------------------
# T. Malformed targets file is classified, never ignored.
# ---------------------------------------------------------------------------

repo="$(new_repo badtargets)"
write_correct_test "$repo"
printf '{"schema": 1, "targets": [\n' >"$repo/docs/evidence/badtargets.targets.json"
cat >"$repo/docs/reality/badtargets.evidence.jsonl" <<'EOF'
{"feature": "badtargets", "requirement_id": "REQ-B-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_read_through.sh::REQ-B-001", "verified_by": "suite", "note": "x"}
EOF
run_reality "$repo" badtargets --min-evidence integration-fake
assert_eq "truncated targets file: malformed exit 4" "4" "$REAL_RC"
assert_not_contains "broken targets file does not silently pass" \
  "$REAL_OUT" "reality check passed"

repo="$(new_repo targetmissingfield)"
write_correct_test "$repo"
cat >"$repo/docs/evidence/targetmissingfield.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "targetmissingfield",
  "targets": [
    {"requirement_id": "REQ-T-001", "dataset": "W32-default-seed"}
  ]
}
EOF
cat >"$repo/docs/reality/targetmissingfield.evidence.jsonl" <<'EOF'
{"feature": "targetmissingfield", "requirement_id": "REQ-T-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_read_through.sh::REQ-T-001", "verified_by": "suite", "note": "x"}
EOF
run_reality "$repo" targetmissingfield --min-evidence integration-fake
assert_eq "target missing a required field: malformed exit 4" "4" "$REAL_RC"
assert_contains "incomplete target names the missing field" \
  "$REAL_OUT" "boundary"

repo="$(new_repo targetfeatmismatch)"
write_correct_test "$repo"
cat >"$repo/docs/evidence/targetfeatmismatch.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "some-other-feature",
  "targets": [
    {
      "requirement_id": "REQ-X-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "x"
    }
  ]
}
EOF
cat >"$repo/docs/reality/targetfeatmismatch.evidence.jsonl" <<'EOF'
{"feature": "targetfeatmismatch", "requirement_id": "REQ-X-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_read_through.sh::REQ-X-001", "verified_by": "suite", "note": "x"}
EOF
run_reality "$repo" targetfeatmismatch --min-evidence integration-fake
assert_eq "targets file for the wrong feature: malformed exit 4" "4" "$REAL_RC"

# ---------------------------------------------------------------------------
# X. Explicit proof tokens, for a boundary that is not literal in the test.
# ---------------------------------------------------------------------------

repo="$(new_repo prooftokens)"
cat >"$repo/tests/test_route.sh" <<'EOF'
#!/usr/bin/env bash
# The route is assembled, so neither the dataset name nor the path appears whole.
base="/api/v1/tree"; printf 'GET %s/read-through\n' "$base"
seed_id="W32"; variant="default-seed"; printf '%s-%s\n' "$seed_id" "$variant"
echo "PROOF-REQ-P-001-w32-readthrough"
EOF
cat >"$repo/docs/evidence/prooftokens.targets.json" <<'EOF'
{
  "schema": 1,
  "feature": "prooftokens",
  "targets": [
    {
      "requirement_id": "REQ-P-001",
      "dataset": "W32-default-seed",
      "boundary": "GET /api/v1/tree/read-through",
      "expected_result": "seed ids resolve",
      "proof_tokens": ["PROOF-REQ-P-001-w32-readthrough"]
    }
  ]
}
EOF
cat >"$repo/docs/reality/prooftokens.evidence.jsonl" <<'EOF'
{"feature": "prooftokens", "requirement_id": "REQ-P-001", "evidence_class": "integration-fake", "evidence_ref": "tests/test_route.sh::REQ-P-001", "dataset": "W32-default-seed", "boundary": "GET /api/v1/tree/read-through", "expected_result": "seed ids resolve", "verified_by": "suite", "note": "proof token pinned in the test"}
EOF
run_reality "$repo" prooftokens --min-evidence integration-fake
assert_eq "explicit proof token satisfies the binding" "0" "$REAL_RC"

# The same target, with the token removed from the test, must fail.
printf '#!/usr/bin/env bash\necho "no token here"\n' >"$repo/tests/test_route.sh"
run_reality "$repo" prooftokens --min-evidence integration-fake
assert_eq "removing the proof token from the test reddens it" "3" "$REAL_RC"
assert_contains "missing proof token is named" \
  "$REAL_OUT" "PROOF-REQ-P-001-w32-readthrough"

# ---------------------------------------------------------------------------
# R. This repository's own ledgers must keep passing (regression guard).
# ---------------------------------------------------------------------------

run_reality "$REPO_DIR" openrouter-gui --min-evidence integration-fake
assert_eq "Plumbline's own openrouter-gui ledger still passes" "0" "$REAL_RC"

finish "test_evidence_target"
