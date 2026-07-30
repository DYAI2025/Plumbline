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

# A quoted allowed path must not hide an additional unquoted planned path.
PARTIAL_QUOTE="$WORK/partial-quote"
cp -R "$BASE" "$PARTIAL_QUOTE"
printf '%s\n' "- Modify: \`src/demo/app.py\`, src/outside.py" \
  >"$PARTIAL_QUOTE/docs/plans/2026-07-29-demo.md"
assert_output_contains "partially unquoted plan declaration is rejected" \
  "outside backtick-wrapped paths" \
  "$SCOPE_CHECK" --repo "$PARTIAL_QUOTE" --feature demo --preflight

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
assert_output_contains "contradictory product/governance path is rejected" "overlap across product and governance" \
  "$SCOPE_CHECK" --repo "$CONTRADICTORY" --feature demo --preflight

# Different glob strings may still classify the same path twice.
INTERSECTING="$WORK/intersecting"
cp -R "$BASE" "$INTERSECTING"
python3 - "$INTERSECTING/docs/scope/demo.scope.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["governance"].append("src/demo/private/**")
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
assert_output_contains "intersecting product/governance globs are rejected" "src/demo/private/**" \
  "$SCOPE_CHECK" --repo "$INTERSECTING" --feature demo --preflight

# Intersection must be decided from both glob languages, not guessed witnesses.
CRISS_CROSS="$WORK/criss-cross"
cp -R "$BASE" "$CRISS_CROSS"
python3 - "$CRISS_CROSS/docs/scope/demo.scope.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["product"] = ["src/*/foo"]
data["scope"]["governance"] = ["src/bar/*"]
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
assert_output_contains "criss-cross glob intersection is rejected" "src/bar/*" \
  "$SCOPE_CHECK" --repo "$CRISS_CROSS" --feature demo --preflight

# Overlap validation must include _matches' directory-prefix shortcuts.
DIRECTORY_PREFIX="$WORK/directory-prefix"
cp -R "$BASE" "$DIRECTORY_PREFIX"
python3 - "$DIRECTORY_PREFIX/docs/scope/demo.scope.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["product"] = ["src/demo/app.py"]
data["scope"]["governance"].append("src/demo/")
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
assert_output_contains "directory-prefix runtime overlap is rejected" "src/demo/" \
  "$SCOPE_CHECK" --repo "$DIRECTORY_PREFIX" --feature demo --preflight

DIRECTORY_ROOT="$WORK/directory-root"
cp -R "$BASE" "$DIRECTORY_ROOT"
python3 - "$DIRECTORY_ROOT/docs/scope/demo.scope.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["product"] = ["src/demo"]
data["scope"]["governance"].append("src/demo/**")
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
assert_output_contains "directory-root runtime overlap is rejected" "src/demo/**" \
  "$SCOPE_CHECK" --repo "$DIRECTORY_ROOT" --feature demo --preflight

UNICODE_OVERLAP="$WORK/unicode-overlap"
cp -R "$BASE" "$UNICODE_OVERLAP"
python3 - "$UNICODE_OVERLAP/docs/scope/demo.scope.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["product"] = ["src/[! -~].py"]
data["scope"]["governance"] = ["src/?.py"]
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
assert_output_contains "non-ASCII glob intersection is rejected" "src/?.py" \
  "$SCOPE_CHECK" --repo "$UNICODE_OVERLAP" --feature demo --preflight

LEADING_BRACKET_CLASS="$WORK/leading-bracket-class"
cp -R "$BASE" "$LEADING_BRACKET_CLASS"
python3 - "$LEADING_BRACKET_CLASS/docs/scope/demo.scope.json" <<'PY'
import json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["product"] = ["src/[!]].py"]
data["scope"]["governance"] = ["src/?.py"]
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
assert_output_contains "fnmatch class with leading closing bracket overlaps question glob" \
  "src/?.py" \
  "$SCOPE_CHECK" --repo "$LEADING_BRACKET_CLASS" --feature demo --preflight

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

# The same confirmed updater can revise the active plan and record provenance
# in one validated operation, avoiding a deadlock caused by exact target checks.
assert_exit "confirmed updater can add a newly approved planned file" 0 \
  "$SCOPE_UPDATE" --repo "$UPDATE" --feature demo \
    --product-path 'src/demo/**' \
    --governance-path 'CLAUDE.md' \
    --governance-path 'docs/canvas/demo.canvas.md' \
    --governance-path 'docs/plans/2026-07-29-demo.md' \
    --governance-path 'docs/scope/demo.scope.json' \
    --planned-create 'src/demo/new.py' \
    --origin 'jira:PLUM-12' --decision-maker 'test-user' \
    --decided-at '2026-07-29T21:30:00+00:00' \
    --rationale 'User confirmed the new implementation file' --confirmed
assert_exit "joint plan/manifest revision remains aligned" 0 \
  "$SCOPE_CHECK" --repo "$UPDATE" --feature demo --preflight
assert_eq "plan repair records a provenance revision" "3" \
  "$(python3 -c 'import json,sys; print(len(json.load(open(sys.argv[1]))["provenance"]))' \
    "$UPDATE/docs/scope/demo.scope.json")"
UPDATED_PLAN_TARGET_PASS="$(
  CLAUDE_PROJECT_DIR="$UPDATE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Write","tool_input":{"file_path":"src/demo/new.py"}}
EOF
)"
assert_eq "newly confirmed planned target passes the hook" "" "$UPDATED_PLAN_TARGET_PASS"

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

BASH_DENY="$(
  CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"python3 build.py"}}
EOF
)"
assert_contains "Bash write path runs the pre-write scope gate" "$BASH_DENY" '"decision":"deny"'

ALIGNED_BASH_DENY="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"printf x > src/demo/unplanned.py"}}
EOF
)"
assert_contains "opaque Bash writes fail closed even when artifacts are aligned" \
  "$ALIGNED_BASH_DENY" '"decision":"deny"'
assert_contains "Bash denial explains exact target proof requirement" \
  "$ALIGNED_BASH_DENY" "exact planned-file declarations"

SCOPE_REPAIR_PASS="$(
  CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Bash","tool_input":{"command":"$SCOPE_UPDATE --repo . --feature demo --confirmed"}}
EOF
)"
assert_eq "direct atomic scope updater remains available as repair path" \
  "" "$SCOPE_REPAIR_PASS"

UNTRUSTED_UPDATER="$WORK/plumbline-scope-update"
printf '%s\n' '#!/usr/bin/env bash' 'printf bypass' >"$UNTRUSTED_UPDATER"
chmod +x "$UNTRUSTED_UPDATER"
UNTRUSTED_REPAIR_DENY="$(
  CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Bash","tool_input":{"command":"$UNTRUSTED_UPDATER --confirmed"}}
EOF
)"
assert_contains "untrusted same-named updater cannot bypass preflight" \
  "$UNTRUSTED_REPAIR_DENY" '"decision":"deny"'

PATH_REPAIR_PASS="$(
  PATH="$(dirname "$SCOPE_UPDATE"):$PATH" \
    CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"plumbline-scope-update --repo . --feature demo --confirmed"}}
EOF
)"
assert_eq "trusted updater installed on PATH remains available as repair path" \
  "" "$PATH_REPAIR_PASS"

UNTRUSTED_PATH_REPAIR_DENY="$(
  PATH="$WORK:$PATH" CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"plumbline-scope-update --confirmed"}}
EOF
)"
assert_contains "untrusted same-named updater found on PATH cannot bypass preflight" \
  "$UNTRUSTED_PATH_REPAIR_DENY" '"decision":"deny"'

CHAINED_REPAIR_DENY="$(
  CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"config/claude/bin/plumbline-scope-update --confirmed; printf bypass > src/outside.py"}}
EOF
)"
assert_contains "chained scope-updater command cannot bypass the gate" \
  "$CHAINED_REPAIR_DENY" '"decision":"deny"'

MULTILINE_SCHEMA="$WORK/multiline-schema"
cp -R "$MISSING" "$MULTILINE_SCHEMA"
python3 - "$MULTILINE_SCHEMA/docs/scope/demo.scope.json" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(
    path.read_text(encoding="utf-8").replace('"schema_version": 1', '"schema_version":\n  1'),
    encoding="utf-8",
)
PY
MULTILINE_DENY="$(
  CLAUDE_PROJECT_DIR="$MULTILINE_SCHEMA" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_contains "multiline schema_version still activates the pre-write gate" \
  "$MULTILINE_DENY" '"decision":"deny"'

ESCAPED_SCHEMA="$WORK/escaped-schema"
cp -R "$MISSING" "$ESCAPED_SCHEMA"
python3 - "$ESCAPED_SCHEMA/docs/scope/demo.scope.json" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
path.write_text(
    path.read_text(encoding="utf-8").replace(
        '"schema_version"', '"schema\\u005fversion"'
    ),
    encoding="utf-8",
)
PY
ESCAPED_SCHEMA_DENY="$(
  CLAUDE_PROJECT_DIR="$ESCAPED_SCHEMA" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_contains "escaped canonical JSON key still activates the gate" \
  "$ESCAPED_SCHEMA_DENY" '"decision":"deny"'

MISSING_MANIFEST="$WORK/missing-manifest"
cp -R "$BASE" "$MISSING_MANIFEST"
mv "$MISSING_MANIFEST/docs/scope/demo.scope.json" \
  "$MISSING_MANIFEST/docs/scope/demo.scope.json.removed"
MISSING_MANIFEST_DENY="$(
  CLAUDE_PROJECT_DIR="$MISSING_MANIFEST" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_contains "referenced missing manifest fails closed before writes" \
  "$MISSING_MANIFEST_DENY" '"decision":"deny"'
assert_contains "missing-manifest denial is actionable" \
  "$MISSING_MANIFEST_DENY" "missing canonical scope manifest"

MISSING_MANIFEST_REPAIR="$(
  CLAUDE_PROJECT_DIR="$MISSING_MANIFEST" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Bash","tool_input":{"command":"$SCOPE_UPDATE --repo . --feature demo --confirmed"}}
EOF
)"
assert_eq "scope updater can create a newly referenced missing manifest" \
  "" "$MISSING_MANIFEST_REPAIR"

HOOK_PASS="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_eq "pre-write hook passes an aligned plan without output" "" "$HOOK_PASS"

UNPLANNED_WRITE_DENY="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/unplanned.py"}}
EOF
)"
assert_contains "explicit write target absent from plan is denied before dispatch" \
  "$UNPLANNED_WRITE_DENY" '"decision":"deny"'
assert_contains "unplanned write denial names the concrete target" \
  "$UNPLANNED_WRITE_DENY" "src/demo/unplanned.py"

ABSOLUTE_WRITE_PASS="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$BASE/src/demo/app.py"}}
EOF
)"
assert_eq "absolute in-repository target matching the plan is accepted" \
  "" "$ABSOLUTE_WRITE_PASS"

NOTEBOOK_WRITE_PASS="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"NotebookEdit","tool_input":{"notebook_path":"src/demo/app.py"}}
EOF
)"
assert_eq "NotebookEdit reads notebook_path and accepts a planned target" \
  "" "$NOTEBOOK_WRITE_PASS"

OUTSIDE_WRITE_DENY="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Edit","tool_input":{"file_path":"$WORK/outside.py"}}
EOF
)"
assert_contains "write target outside the repository is denied" \
  "$OUTSIDE_WRITE_DENY" '"decision":"deny"'

AGENT_DENY="$(
  CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Agent","tool_input":{"subagent_type":"backend-developer"}}
EOF
)"
assert_contains "Agent implementation dispatch runs the scope preflight" \
  "$AGENT_DENY" '"decision":"deny"'

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
assert_eq "installer registers the scope gate for Bash writes" "1" \
  "$(jq '[.hooks.PreToolUse[]? | select(.matcher | split("|") | index("Bash")) | .hooks[]?.command? // "" | select(test("pretool-scope-gate\\.sh"))] | length' \
    "$INSTALL_HOME/settings.json")"
assert_eq "installer registers the scope gate for Agent dispatches" "1" \
  "$(jq '[.hooks.PreToolUse[]? | select(.matcher | split("|") | index("Agent")) | .hooks[]?.command? // "" | select(test("pretool-scope-gate\\.sh"))] | length' \
    "$INSTALL_HOME/settings.json")"
CLAUDE_HOME="$INSTALL_HOME" bash "$REPO_DIR/config/claude/install.sh" \
  --no-agents --no-commands --no-skills --no-bin >/dev/null
assert_eq "scope preflight registration is idempotent" "1" \
  "$(jq '[.hooks.PreToolUse[]?.hooks[]?.command? // "" | select(test("pretool-scope-gate\\.sh"))] | length' \
    "$INSTALL_HOME/settings.json")"

finish "test_scope_manifest"
