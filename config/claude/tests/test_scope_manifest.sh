#!/usr/bin/env bash
# PLUM-12: canonical scope manifest, provenance and pre-write drift gate.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_scope_manifest"

SCOPE_CHECK="$REPO_DIR/config/claude/bin/plumbline-scope-check"
SCOPE_UPDATE="$REPO_DIR/config/claude/bin/plumbline-scope-update"
PRETOOL_SCOPE="$REPO_DIR/config/claude/hooks/pretool-scope-gate.sh"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

assert_exit() {
  local description="$1" expected="$2"
  shift 2
  TESTS_RUN=$((TESTS_RUN + 1))
  local output status
  output="$({ "$@"; } 2>&1)"
  status=$?
  if [ "$status" -eq "$expected" ]; then
    _pass "$description"
  else
    _fail "$description (expected exit $expected, got $status; output: $output)"
  fi
}

assert_output_contains() {
  local description="$1" needle="$2"
  shift 2
  TESTS_RUN=$((TESTS_RUN + 1))
  local output status
  output="$({ "$@"; } 2>&1)"
  status=$?
  if [ "$status" -ne 0 ] && printf '%s' "$output" | grep -Fq -- "$needle"; then
    _pass "$description"
  else
    _fail "$description (exit $status, wanted non-zero output containing '$needle'; output: $output)"
  fi
}

make_repo() {
  local repo="$1"
  mkdir -p "$repo/docs/scope" "$repo/docs/canvas" "$repo/docs/plans" \
    "$repo/docs/context" "$repo/src/demo" "$repo/config/claude/tests"
  printf 'demo\n' >"$repo/docs/context/.active-feature"
  cat >"$repo/docs/canvas/demo.canvas.md" <<'EOF'
# Product Canvas: demo

Status: user-confirmed

## Allowed change scope

Status: CONFIRMED

Scope manifest: `docs/scope/demo.scope.json`
EOF
  cat >"$repo/docs/plans/2026-07-29-demo.md" <<'EOF'
# Demo implementation plan

- Create: `src/demo/app.py`
- Modify: `config/claude/tests/test_demo.sh`
EOF
  python3 - "$repo/docs/scope/demo.scope.json" <<'PY'
import hashlib
import json
import sys

scope = {
    "product": ["src/demo/**"],
    "governance": [
        "config/claude/tests/test_demo.sh",
        "docs/canvas/demo.canvas.md",
        "docs/plans/2026-07-29-demo.md",
        "docs/scope/demo.scope.json",
    ],
}
payload = json.dumps(scope, sort_keys=True, separators=(",", ":")).encode()
manifest = {
    "schema_version": 1,
    "feature": "demo",
    "scope": scope,
    "artifacts": {
        "canvas": "docs/canvas/demo.canvas.md",
        "plan": "docs/plans/2026-07-29-demo.md",
    },
    "provenance": [{
        "revision": 1,
        "origin": "jira:PLUM-12",
        "decision_maker": "test-user",
        "decided_at": "2026-07-29T20:00:00+00:00",
        "rationale": "Confirmed pilot scope",
        "confirmed": True,
        "scope": scope,
        "scope_digest": "sha256:" + hashlib.sha256(payload).hexdigest(),
    }],
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
}

BASE="$WORK/base"
make_repo "$BASE"

# Canonical happy path: Canvas references the manifest, and every planned file
# matches exactly one of the separated product/governance path sets.
assert_exit "manifest preflight passes aligned Canvas and plan" 0 \
  "$SCOPE_CHECK" --repo "$BASE" --feature demo --preflight

# The manifest is the runtime Source of Truth. Even if freely formatted Canvas
# Markdown carries a copied list, changed-file containment reads the manifest;
# the separate preflight then catches that copy as drift.
SOURCE_OF_TRUTH="$WORK/source-of-truth"
cp -R "$BASE" "$SOURCE_OF_TRUTH"
printf '%s\n' "- \`src/other/**\`" >>"$SOURCE_OF_TRUTH/docs/canvas/demo.canvas.md"
printf 'src/demo/app.py\n' >"$SOURCE_OF_TRUTH/changed-files.txt"
assert_exit "changed-file guard reads canonical manifest before Canvas Markdown" 0 \
  "$SCOPE_CHECK" --repo "$SOURCE_OF_TRUTH" --feature demo \
    --changed-files "$SOURCE_OF_TRUTH/changed-files.txt"
assert_output_contains "preflight independently detects copied Canvas drift" "duplicated scope path" \
  "$SCOPE_CHECK" --repo "$SOURCE_OF_TRUTH" --feature demo --preflight

# Missing: a plan path absent from the canonical manifest blocks before coding.
MISSING="$WORK/missing"
cp -R "$BASE" "$MISSING"
printf '%s\n' "- Create: \`src/demo/app.py\`" "- Modify: \`CLAUDE.md\`" \
  >"$MISSING/docs/plans/2026-07-29-demo.md"
assert_output_contains "missing allowed path blocks preflight" "CLAUDE.md" \
  "$SCOPE_CHECK" --repo "$MISSING" --feature demo --preflight

# Extra: Canvas must only reference the manifest. A copied scope bullet is a
# second truth source and therefore deliberate drift, even if the path is valid.
EXTRA="$WORK/extra"
cp -R "$BASE" "$EXTRA"
printf '%s\n' "- \`src/other/**\`" >>"$EXTRA/docs/canvas/demo.canvas.md"
assert_output_contains "extra Canvas scope path is rejected as drift" "duplicated scope path" \
  "$SCOPE_CHECK" --repo "$EXTRA" --feature demo --preflight

# Contradictory: one path cannot be classified as both product and governance.
CONTRADICTORY="$WORK/contradictory"
cp -R "$BASE" "$CONTRADICTORY"
python3 - "$CONTRADICTORY/docs/scope/demo.scope.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["governance"].append("src/demo/**")
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
assert_output_contains "contradictory product/governance path is rejected" "both product and governance" \
  "$SCOPE_CHECK" --repo "$CONTRADICTORY" --feature demo --preflight

# Every revision must retain complete decision provenance.
NO_PROVENANCE="$WORK/no-provenance"
cp -R "$BASE" "$NO_PROVENANCE"
python3 - "$NO_PROVENANCE/docs/scope/demo.scope.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
del data["provenance"][0]["rationale"]
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
assert_output_contains "missing decision provenance fails closed" "rationale" \
  "$SCOPE_CHECK" --repo "$NO_PROVENANCE" --feature demo --preflight

# A confirmed change is written through the updater as one atomic manifest
# replacement and records a new, digest-bound provenance revision.
UPDATE="$WORK/update"
cp -R "$BASE" "$UPDATE"
printf '%s\n' "- Create: \`src/demo/app.py\`" "- Modify: \`CLAUDE.md\`" \
  >"$UPDATE/docs/plans/2026-07-29-demo.md"
assert_exit "confirmed scope update succeeds atomically" 0 \
  "$SCOPE_UPDATE" --repo "$UPDATE" --feature demo \
    --product-path 'src/demo/**' \
    --governance-path 'CLAUDE.md' \
    --governance-path 'docs/canvas/demo.canvas.md' \
    --governance-path 'docs/plans/2026-07-29-demo.md' \
    --governance-path 'docs/scope/demo.scope.json' \
    --origin 'jira:PLUM-12' --decision-maker 'test-user' \
    --decided-at '2026-07-29T21:00:00+00:00' \
    --rationale 'User confirmed CLAUDE.md for the increment' --confirmed
assert_exit "updated manifest and derived artifacts remain aligned" 0 \
  "$SCOPE_CHECK" --repo "$UPDATE" --feature demo --preflight
assert_eq "scope update appends provenance revision" "2" \
  "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["provenance"]))' \
    "$UPDATE/docs/scope/demo.scope.json")"

# Integration-real boundary: an active feature with a manifest is validated by
# the PreToolUse hook before the first write-capable dispatch.
HOOK_REPO="$WORK/hook"
cp -R "$MISSING" "$HOOK_REPO"
HOOK_DENY="$(
  CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_contains "pre-write hook denies a drifted plan" "$HOOK_DENY" '"decision":"deny"'
assert_contains "pre-write hook names the out-of-scope planned path" "$HOOK_DENY" "CLAUDE.md"

HOOK_PASS="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_eq "pre-write hook passes an aligned plan without output" "" "$HOOK_PASS"

# PLUM-10 owns migration of the old JSON shape. Its presence must not
# unexpectedly activate PLUM-12's stricter runtime contract.
LEGACY_HOOK="$WORK/legacy-hook"
mkdir -p "$LEGACY_HOOK/docs/context" "$LEGACY_HOOK/docs/scope"
printf 'demo\n' >"$LEGACY_HOOK/docs/context/.active-feature"
printf '{"feature":"demo","allowed_change_scope":["src/demo/**"]}\n' \
  >"$LEGACY_HOOK/docs/scope/demo.scope.json"
LEGACY_PASS="$(
  CLAUDE_PROJECT_DIR="$LEGACY_HOOK" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_eq "legacy JSON scope remains outside PLUM-12 pre-write contract" "" "$LEGACY_PASS"

# The install path is the runtime boundary: registration is idempotent and does
# not repurpose the intentionally inert historical prototype.
INSTALL_HOME="$WORK/install-home"
CLAUDE_HOME="$INSTALL_HOME" bash "$REPO_DIR/config/claude/install.sh" \
  --no-agents --no-commands --no-skills --no-bin >/dev/null
assert_eq "installer registers canonical scope preflight exactly once" "1" \
  "$(jq '[.hooks.PreToolUse[]?.hooks[]?.command? // "" | select(test("pretool-scope-gate\\.sh"))] | length' \
    "$INSTALL_HOME/settings.json")"
CLAUDE_HOME="$INSTALL_HOME" bash "$REPO_DIR/config/claude/install.sh" \
  --no-agents --no-commands --no-skills --no-bin >/dev/null
assert_eq "scope preflight registration is idempotent" "1" \
  "$(jq '[.hooks.PreToolUse[]?.hooks[]?.command? // "" | select(test("pretool-scope-gate\\.sh"))] | length' \
    "$INSTALL_HOME/settings.json")"

finish "test_scope_manifest"
