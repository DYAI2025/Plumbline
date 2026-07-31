#!/usr/bin/env bash
# PLUM-12 contract tests: the canonical scope manifest is the single source of
# truth, and drift between plan / canvas / manifest is caught BEFORE coding.
#
# Measured starting state (2026-07-30): nothing in config/claude/{lib,bin,hooks}
# parsed an implementation plan, and no gate compared planned files against the
# allowed scope. A plan naming `.gitignore`, `CLAUDE.md` or a generator directory
# that the scope did not authorize passed every pre-coding gate; the conflict only
# surfaced when the fail-closed Stop hook blocked mid-build. That is the pilot's
# harm: authorized-in-conversation, missing-in-machine-state.
#
# Contract:
#   * plan vs scope is validated and BLOCKS before coding (AC-4);
#   * the canvas is validated against the manifest, never the reverse (AC-2);
#   * governance paths and product paths are modelled separately (AC-5);
#   * a scope entry can be required to carry provenance -- origin, decider,
#     timestamp, reason (AC-3);
#   * missing, additional and contradictory paths are all covered (AC-6).
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_plan_scope_drift"

PLAN_BIN="$REPO_DIR/config/claude/bin/plumbline-plan-check"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

assert_file "plan-check CLI exists" "$PLAN_BIN"

new_repo() {
  local feat="$1" repo
  repo="$WORK/$feat"
  mkdir -p "$repo/docs/canvas" "$repo/docs/scope" "$repo/docs/plans"
  git -C "$repo" init -q
  git -C "$repo" config user.email plan-test@example.com
  git -C "$repo" config user.name "Plan Test"
  printf '%s' "$repo"
}

# run_plan <repo> <feature> [extra args...] -- plan defaults to the feature plan.
run_plan() {
  local repo="$1" feat="$2"
  shift 2
  local outf="$WORK/plan.out"
  "$PLAN_BIN" --repo "$repo" --feature "$feat" \
    --plan "$repo/docs/plans/$feat.md" "$@" >"$outf" 2>&1
  PLAN_RC=$?
  PLAN_OUT="$(cat "$outf")"
}

# ---------------------------------------------------------------------------
# P. Plan vs scope.
# ---------------------------------------------------------------------------

# A declared touches block is authoritative and exact.
repo="$(new_repo covered)"
cat >"$repo/docs/scope/covered.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "covered",
  "allowed_change_scope": ["src/feature/**", "tests/test_feature.py"]
}
EOF
cat >"$repo/docs/plans/covered.md" <<'EOF'
# Plan

Implement the feature.

```plumbline-touches
src/feature/api.py
tests/test_feature.py
```
EOF
run_plan "$repo" covered
assert_eq "declared plan fully inside scope passes" "0" "$PLAN_RC"
assert_contains "declared plan reports the exact mode" "$PLAN_OUT" "mode=declared"

# The pilot case: files named by the plan that the scope never authorized.
repo="$(new_repo drift)"
cat >"$repo/docs/scope/drift.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "drift",
  "allowed_change_scope": ["packages/contracts/openapi/v1.json"]
}
EOF
cat >"$repo/docs/plans/drift.md" <<'EOF'
# Plan

```plumbline-touches
packages/contracts/openapi/v1.json
packages/contracts/src/openapi/**
.gitignore
CLAUDE.md
scripts/read-through-harness.sh
```
EOF
run_plan "$repo" drift
assert_eq "planned-but-unauthorized paths block (exit 3)" "3" "$PLAN_RC"
assert_contains "block names the generator directory" \
  "$PLAN_OUT" "packages/contracts/src/openapi/**"
assert_contains "block names .gitignore" "$PLAN_OUT" ".gitignore"
assert_contains "block names CLAUDE.md" "$PLAN_OUT" "CLAUDE.md"
assert_contains "block names the harness script" \
  "$PLAN_OUT" "scripts/read-through-harness.sh"
assert_contains "block names the manifest to edit" \
  "$PLAN_OUT" "docs/scope/drift.scope.json"
assert_not_contains "authorized path is not reported as drift" \
  "$PLAN_OUT" "unauthorized: packages/contracts/openapi/v1.json"

# Without a declared block the check still runs, but says it is heuristic so an
# operator can tell a read-only mention from a real write target.
repo="$(new_repo heuristic)"
cat >"$repo/docs/scope/heuristic.scope.json" <<'EOF'
{"schema": 1, "feature": "heuristic", "allowed_change_scope": ["src/feature/**"]}
EOF
cat >"$repo/docs/plans/heuristic.md" <<'EOF'
# Plan

Edit `src/feature/api.py`, then update `scripts/deploy.sh`.
Run `pytest -q` and call `build_thing()`; see `https://example.com/docs/x`.
EOF
run_plan "$repo" heuristic
assert_eq "heuristic plan with an unauthorized path blocks" "3" "$PLAN_RC"
assert_contains "heuristic mode is announced" "$PLAN_OUT" "mode=heuristic"
assert_contains "heuristic mode names the unauthorized path" \
  "$PLAN_OUT" "scripts/deploy.sh"
assert_not_contains "heuristic mode ignores shell commands" "$PLAN_OUT" "pytest -q"
assert_not_contains "heuristic mode ignores code identifiers" \
  "$PLAN_OUT" "build_thing()"
assert_not_contains "heuristic mode ignores URLs" "$PLAN_OUT" "example.com"

# ---------------------------------------------------------------------------
# C. Canvas vs manifest: the canvas is validated AGAINST the manifest.
# ---------------------------------------------------------------------------

repo="$(new_repo canvasdrift)"
cat >"$repo/docs/scope/canvasdrift.scope.json" <<'EOF'
{"schema": 1, "feature": "canvasdrift", "allowed_change_scope": ["src/feature/**"]}
EOF
cat >"$repo/docs/canvas/canvasdrift.canvas.md" <<'EOF'
# canvasdrift Canvas

Status: user-confirmed

## Allowed change scope
- `src/feature/**`
- `src/extra/**`
EOF
cat >"$repo/docs/plans/canvasdrift.md" <<'EOF'
# Plan

```plumbline-touches
src/feature/api.py
```
EOF
run_plan "$repo" canvasdrift
assert_eq "canvas claiming more than the manifest is a contradiction (exit 3)" \
  "3" "$PLAN_RC"
assert_contains "canvas contradiction names the extra pattern" \
  "$PLAN_OUT" "src/extra/**"
assert_contains "canvas contradiction names the canvas file" \
  "$PLAN_OUT" "docs/canvas/canvasdrift.canvas.md"

# A canvas that documents a subset is fine: the canvas is documentation.
repo="$(new_repo canvassubset)"
cat >"$repo/docs/scope/canvassubset.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "canvassubset",
  "allowed_change_scope": ["src/feature/**", "docs/notes.md"]
}
EOF
cat >"$repo/docs/canvas/canvassubset.canvas.md" <<'EOF'
# canvassubset Canvas

## Allowed change scope
- `src/feature/**`
EOF
cat >"$repo/docs/plans/canvassubset.md" <<'EOF'
# Plan

```plumbline-touches
src/feature/api.py
```
EOF
run_plan "$repo" canvassubset
assert_eq "canvas documenting a subset passes" "0" "$PLAN_RC"
assert_contains "canvas subset is reported, not hidden" \
  "$PLAN_OUT" "docs/notes.md"

# ---------------------------------------------------------------------------
# G. Governance paths and product paths are modelled separately.
# ---------------------------------------------------------------------------

repo="$(new_repo classes)"
cat >"$repo/docs/scope/classes.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "classes",
  "allowed_change_scope": ["src/feature/**"],
  "governance_paths": [
    "docs/canvas/classes.canvas.md",
    "docs/reality/classes.evidence.jsonl",
    "CLAUDE.md"
  ]
}
EOF
cat >"$repo/docs/plans/classes.md" <<'EOF'
# Plan

```plumbline-touches
src/feature/api.py
docs/reality/classes.evidence.jsonl
CLAUDE.md
```
EOF
run_plan "$repo" classes
assert_eq "governance paths authorize governance artifacts" "0" "$PLAN_RC"
assert_contains "coverage names the product class" "$PLAN_OUT" "product"
assert_contains "coverage names the governance class" "$PLAN_OUT" "governance"

# A governance-looking path declared in the PRODUCT list is reported (visible
# misclassification), but never silently accepted as a product path.
repo="$(new_repo misclass)"
cat >"$repo/docs/scope/misclass.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "misclass",
  "allowed_change_scope": ["src/feature/**", "docs/canvas/misclass.canvas.md"]
}
EOF
cat >"$repo/docs/plans/misclass.md" <<'EOF'
# Plan

```plumbline-touches
src/feature/api.py
```
EOF
run_plan "$repo" misclass
assert_eq "misclassified governance path still passes the plan check" "0" "$PLAN_RC"
assert_contains "misclassification is named" \
  "$PLAN_OUT" "docs/canvas/misclass.canvas.md"

# ---------------------------------------------------------------------------
# V. Provenance: origin, decider, timestamp, reason (opt-in gate).
# ---------------------------------------------------------------------------

repo="$(new_repo noprov)"
cat >"$repo/docs/scope/noprov.scope.json" <<'EOF'
{"schema": 1, "feature": "noprov", "allowed_change_scope": ["src/feature/**"]}
EOF
cat >"$repo/docs/plans/noprov.md" <<'EOF'
# Plan

```plumbline-touches
src/feature/api.py
```
EOF
run_plan "$repo" noprov
assert_eq "provenance is opt-in: default run still passes" "0" "$PLAN_RC"
run_plan "$repo" noprov --require-provenance
assert_eq "--require-provenance blocks an unattributed entry" "4" "$PLAN_RC"
assert_contains "unattributed entry is named" "$PLAN_OUT" "src/feature/**"

repo="$(new_repo goodprov)"
cat >"$repo/docs/scope/goodprov.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "goodprov",
  "allowed_change_scope": ["src/feature/**"],
  "governance_paths": ["docs/canvas/goodprov.canvas.md"],
  "provenance": [
    {
      "paths": ["src/feature/**", "docs/canvas/goodprov.canvas.md"],
      "origin": "requirements confirmation, session 2026-07-30",
      "decided_by": "product owner (human)",
      "decided_at": "2026-07-30T09:15:00Z",
      "reason": "confirmed feature surface plus its own canvas"
    }
  ]
}
EOF
cat >"$repo/docs/plans/goodprov.md" <<'EOF'
# Plan

```plumbline-touches
src/feature/api.py
```
EOF
run_plan "$repo" goodprov --require-provenance
assert_eq "complete provenance passes" "0" "$PLAN_RC"

repo="$(new_repo partialprov)"
cat >"$repo/docs/scope/partialprov.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "partialprov",
  "allowed_change_scope": ["src/feature/**"],
  "provenance": [
    {
      "paths": ["src/feature/**"],
      "origin": "chat",
      "decided_by": "",
      "decided_at": "2026-07-30",
      "reason": "because"
    }
  ]
}
EOF
cat >"$repo/docs/plans/partialprov.md" <<'EOF'
# Plan

```plumbline-touches
src/feature/api.py
```
EOF
run_plan "$repo" partialprov --require-provenance
assert_eq "empty decider blocks" "4" "$PLAN_RC"
assert_contains "empty decider is named as the missing field" \
  "$PLAN_OUT" "decided_by"

repo="$(new_repo baddate)"
cat >"$repo/docs/scope/baddate.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "baddate",
  "allowed_change_scope": ["src/feature/**"],
  "provenance": [
    {
      "paths": ["src/feature/**"],
      "origin": "chat",
      "decided_by": "human",
      "decided_at": "last tuesday",
      "reason": "because"
    }
  ]
}
EOF
cat >"$repo/docs/plans/baddate.md" <<'EOF'
# Plan

```plumbline-touches
src/feature/api.py
```
EOF
run_plan "$repo" baddate --require-provenance
assert_eq "unparseable timestamp blocks" "4" "$PLAN_RC"
assert_contains "unparseable timestamp is named" "$PLAN_OUT" "last tuesday"

# ---------------------------------------------------------------------------
# S. Shared failure modes stay classified.
# ---------------------------------------------------------------------------

repo="$(new_repo noscope)"
cat >"$repo/docs/plans/noscope.md" <<'EOF'
# Plan

```plumbline-touches
src/feature/api.py
```
EOF
run_plan "$repo" noscope
assert_eq "no scope at all: missing exit 2" "2" "$PLAN_RC"

repo="$(new_repo noplan)"
cat >"$repo/docs/scope/noplan.scope.json" <<'EOF'
{"schema": 1, "feature": "noplan", "allowed_change_scope": ["src/feature/**"]}
EOF
run_plan "$repo" noplan
assert_eq "missing plan file: missing exit 2" "2" "$PLAN_RC"
assert_contains "missing plan names the path" "$PLAN_OUT" "docs/plans/noplan.md"

repo="$(new_repo emptytouches)"
cat >"$repo/docs/scope/emptytouches.scope.json" <<'EOF'
{"schema": 1, "feature": "emptytouches", "allowed_change_scope": ["src/feature/**"]}
EOF
cat >"$repo/docs/plans/emptytouches.md" <<'EOF'
# Plan

```plumbline-touches
```
EOF
run_plan "$repo" emptytouches
assert_eq "declared-but-empty touches block is malformed, not 'all clear'" \
  "4" "$PLAN_RC"

finish "test_plan_scope_drift"
