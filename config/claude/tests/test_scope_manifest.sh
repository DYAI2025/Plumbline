#!/usr/bin/env bash
# PLUM-12: canonical scope manifest, provenance and pre-write drift gate.
#
# PLUM-10 contract tests: the machine-critical Allowed Scope must live in an
# explicit, schema-validated manifest -- not in fragile markdown prose.
#
# Measured pilot defects this file pins (all four reproduced on 2026-07-30
# against the pre-fix plumbline_scope.py):
#   A  a `- /src/feature/**` bullet was SILENTLY discarded, and the guard then
#      reported the generic "missing Allowed change scope" -- a false RED with a
#      misleading diagnosis, because the author HAD declared a scope.
#   B  paths written inside a fenced code block were ignored the same way.
#   C  a formatter-wrapped line starting with `*` became a real allowed pattern,
#      which both hid the intended path AND authorized a prose-shaped path
#      ("and every generated artifact under .../v1.json" passed).
#   D  docs/scope/<feature>.scope.json LOST to the canvas: a manifest restricted
#      to src/api/** did not stop a canvas-allowed src/feature/** change.
#
# Contract after the fix:
#   * the manifest is the CANONICAL source and is checked FIRST;
#   * manifest problems are HARD, classified, and name the offending entry;
#   * the legacy canvas keeps working (backward compatible) but never discards a
#     line silently: every ignored line is named with its line number + cause;
#   * prose-shaped candidates are DROPPED (never widen the scope) rather than
#     silently accepted.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
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
- Modify: `docs/scope/demo.scope.json`
- Delete: `src/demo/old.py`
- Test: `bash config/claude/tests/test_demo.sh`
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

CONFLICTING_ACTIONS="$WORK/conflicting-actions"
cp -R "$BASE" "$CONFLICTING_ACTIONS"
printf '%s\n' \
  "- Modify: \`src/demo/app.py\`" \
  "- Delete: \`src/demo/./app.py\`" \
  >"$CONFLICTING_ACTIONS/docs/plans/2026-07-29-demo.md"
assert_output_contains "one normalized path cannot carry conflicting plan actions" \
  "conflicting actions Modify and Delete: src/demo/app.py" \
  "$SCOPE_CHECK" --repo "$CONFLICTING_ACTIONS" --feature demo --preflight

SYMLINK_SCOPE_ESCAPE="$WORK/symlink-scope-escape"
cp -R "$BASE" "$SYMLINK_SCOPE_ESCAPE"
printf 'outside scope\n' >"$SYMLINK_SCOPE_ESCAPE/secret.py"
ln -s ../../secret.py "$SYMLINK_SCOPE_ESCAPE/src/demo/link.py"
printf '%s\n' "- Modify: \`src/demo/link.py\`" \
  >"$SYMLINK_SCOPE_ESCAPE/docs/plans/2026-07-29-demo.md"
assert_output_contains "resolved planned symlink target must remain inside canonical scope" \
  "planned file outside canonical scope: secret.py" \
  "$SCOPE_CHECK" --repo "$SYMLINK_SCOPE_ESCAPE" --feature demo --preflight

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

ROOT_GLOB="$WORK/root-glob"
cp -R "$BASE" "$ROOT_GLOB"
printf '%s\n' "- Create: \`root.py\`" >"$ROOT_GLOB/docs/plans/2026-07-29-demo.md"
python3 - "$ROOT_GLOB/docs/scope/demo.scope.json" <<'PY'
import hashlib, json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["product"] = ["*.py"]
data["provenance"][-1]["scope"] = data["scope"]
payload = json.dumps(data["scope"], sort_keys=True, separators=(",", ":")).encode()
data["provenance"][-1]["scope_digest"] = "sha256:" + hashlib.sha256(payload).hexdigest()
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
assert_exit "clean root-level anchored glob remains valid manifest scope" 0 \
  "$SCOPE_CHECK" --repo "$ROOT_GLOB" --feature demo --preflight

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

assert_exit "confirmed updater can replace superseded plan declarations" 0 \
  "$SCOPE_UPDATE" --repo "$UPDATE" --feature demo \
    --product-path 'src/replacement/**' \
    --governance-path 'CLAUDE.md' \
    --governance-path 'docs/canvas/demo.canvas.md' \
    --governance-path 'docs/plans/2026-07-29-demo.md' \
    --governance-path 'docs/scope/demo.scope.json' \
    --replace-plan-declarations \
    --planned-create 'src/replacement/app.py' \
    --planned-modify 'CLAUDE.md' \
    --origin 'jira:PLUM-12' --decision-maker 'test-user' \
    --decided-at '2026-07-29T22:00:00+00:00' \
    --rationale 'User replaced the superseded implementation path' --confirmed
assert_exit "replacement plan and narrowed manifest remain aligned" 0 \
  "$SCOPE_CHECK" --repo "$UPDATE" --feature demo --preflight
assert_not_contains "superseded declaration is removed from active plan" \
  "$(cat "$UPDATE/docs/plans/2026-07-29-demo.md")" "src/demo/new.py"

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
  "$ALIGNED_BASH_DENY" "not declared as a confirmed Test"

mkdir -p "$BASE/config/claude/tests"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' >"$BASE/config/claude/tests/test_demo.sh"
chmod +x "$BASE/config/claude/tests/test_demo.sh"
TRACKED_TEST_PASS="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"bash config/claude/tests/test_demo.sh"}}
EOF
)"
assert_eq "confirmed project-native Test command passes after preflight" \
  "" "$TRACKED_TEST_PASS"

MARKER_CLEANUP_PASS="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"rm -f docs/context/.active-feature"}}
EOF
)"
assert_eq "exact active-feature cleanup command remains available" \
  "" "$MARKER_CLEANUP_PASS"

PLANNED_DELETE_PASS="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"rm -f src/demo/old.py"}}
EOF
)"
assert_eq "exact confirmed Delete target remains executable" \
  "" "$PLANNED_DELETE_PASS"

UNPLANNED_DELETE_DENY="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"rm -f src/demo/unplanned.py"}}
EOF
)"
assert_contains "undeclared deletion target is denied" \
  "$UNPLANNED_DELETE_DENY" '"decision":"deny"'

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

INACTIVE_FEATURE_REPAIR_DENY="$(
  CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Bash","tool_input":{"command":"$SCOPE_UPDATE --repo . --feature inactive --confirmed"}}
EOF
)"
assert_contains "trusted updater cannot repair a feature other than the active one" \
  "$INACTIVE_FEATURE_REPAIR_DENY" '"decision":"deny"'

EXPANDED_REPAIR_DENY="$(
  CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Bash","tool_input":{"command":"$SCOPE_UPDATE --repo . --feature demo {--repo=/other/repo,--feature=inactive} --confirmed"}}
EOF
)"
assert_contains "shell expansion syntax cannot alter validated updater arguments" \
  "$EXPANDED_REPAIR_DENY" '"decision":"deny"'

ABBREVIATED_REPAIR_DENY="$(
  CLAUDE_PROJECT_DIR="$HOOK_REPO" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Bash","tool_input":{"command":"$SCOPE_UPDATE --repo . --feature demo --fea inactive --confirmed"}}
EOF
)"
assert_contains "abbreviated updater options cannot override active feature" \
  "$ABBREVIATED_REPAIR_DENY" '"decision":"deny"'

MUTABLE_UPDATER="$WORK/mutable-updater"
cp -R "$BASE" "$MUTABLE_UPDATER"
mkdir -p "$MUTABLE_UPDATER/config/claude/bin" "$MUTABLE_UPDATER/config/claude/lib"
cp "$SCOPE_UPDATE" "$MUTABLE_UPDATER/config/claude/bin/plumbline-scope-update"
cp "$REPO_DIR/config/claude/lib/plumbline_python.sh" \
  "$REPO_DIR/config/claude/lib/plumbline_scope.py" \
  "$REPO_DIR/config/claude/lib/plumbline_scope_update.py" \
  "$MUTABLE_UPDATER/config/claude/lib/"
git -C "$MUTABLE_UPDATER" init -q
git -C "$MUTABLE_UPDATER" add config/claude/bin config/claude/lib
git -C "$MUTABLE_UPDATER" \
  -c user.name=test -c user.email=test@example.invalid commit -qm fixture
printf '\n# mutated after confirmation\n' \
  >>"$MUTABLE_UPDATER/config/claude/lib/plumbline_scope_update.py"
MUTABLE_UPDATER_DENY="$(
  CLAUDE_PROJECT_DIR="$MUTABLE_UPDATER" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Bash","tool_input":{"command":"$MUTABLE_UPDATER/config/claude/bin/plumbline-scope-update --repo . --feature demo --confirmed"}}
EOF
)"
assert_contains "mutable repository updater runtime cannot receive repair exemption" \
  "$MUTABLE_UPDATER_DENY" '"decision":"deny"'

CLEAN_MALICIOUS_UPDATER="$WORK/clean-malicious-updater"
cp -R "$MISSING" "$CLEAN_MALICIOUS_UPDATER"
mkdir -p "$CLEAN_MALICIOUS_UPDATER/config/claude/bin"
printf '%s\n' '#!/usr/bin/env bash' 'touch repository-updater-ran' 'exit 0' \
  >"$CLEAN_MALICIOUS_UPDATER/config/claude/bin/plumbline-scope-update"
chmod +x "$CLEAN_MALICIOUS_UPDATER/config/claude/bin/plumbline-scope-update"
git -C "$CLEAN_MALICIOUS_UPDATER" init -q
git -C "$CLEAN_MALICIOUS_UPDATER" add .
git -C "$CLEAN_MALICIOUS_UPDATER" \
  -c user.name=test -c user.email=test@example.invalid commit -qm fixture
CLEAN_MALICIOUS_UPDATER_DENY="$(
  CLAUDE_PROJECT_DIR="$CLEAN_MALICIOUS_UPDATER" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"config/claude/bin/plumbline-scope-update --repo . --feature demo --confirmed"}}
EOF
)"
assert_contains "foreign repository cannot authenticate its committed updater" \
  "$CLEAN_MALICIOUS_UPDATER_DENY" '"decision":"deny"'
assert "foreign repository updater is never executed" \
  "test ! -e '$CLEAN_MALICIOUS_UPDATER/repository-updater-ran'"

SYMLINKED_UPDATER="$WORK/symlinked-updater"
cp -R "$HOOK_REPO" "$SYMLINKED_UPDATER"
mkdir -p "$SYMLINKED_UPDATER/config/claude/bin"
ln -sf /bin/true \
  "$SYMLINKED_UPDATER/config/claude/bin/plumbline-scope-update"
SYMLINKED_UPDATER_DENY="$(
  CLAUDE_PROJECT_DIR="$SYMLINKED_UPDATER" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"config/claude/bin/plumbline-scope-update --repo . --feature demo --confirmed"}}
EOF
)"
assert_contains "repository-owned updater symlink cannot launder external authority" \
  "$SYMLINKED_UPDATER_DENY" '"decision":"deny"'

OUTSIDE_UPDATER_TARGET="$WORK/outside-updater-target"
cp -R "$MISSING" "$OUTSIDE_UPDATER_TARGET"
mkdir -p "$OUTSIDE_UPDATER_TARGET/config/claude/bin" "$WORK/outside-updater-bin"
printf '%s\n' '#!/usr/bin/env bash' 'touch updater-ran' 'exit 0' \
  >"$OUTSIDE_UPDATER_TARGET/config/claude/bin/plumbline-scope-update"
chmod +x "$OUTSIDE_UPDATER_TARGET/config/claude/bin/plumbline-scope-update"
ln -s "$OUTSIDE_UPDATER_TARGET/config/claude/bin/plumbline-scope-update" \
  "$WORK/outside-updater-bin/plumbline-scope-update"
OUTSIDE_UPDATER_TARGET_DENY="$(
  PLUMBLINE_BIN_DIR="$WORK/outside-updater-bin" \
    CLAUDE_PROJECT_DIR="$OUTSIDE_UPDATER_TARGET" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Bash","tool_input":{"command":"$WORK/outside-updater-bin/plumbline-scope-update --repo . --feature demo --confirmed"}}
EOF
)"
assert_contains "outside updater symlink into governed repository is not trusted" \
  "$OUTSIDE_UPDATER_TARGET_DENY" '"decision":"deny"'
assert "outside updater symlink target is never executed" \
  "test ! -e '$OUTSIDE_UPDATER_TARGET/updater-ran'"

ALTERNATE_UPDATER="$WORK/alternate-updater"
cp -R "$BASE" "$ALTERNATE_UPDATER"
mkdir -p "$ALTERNATE_UPDATER/tools"
cp "$SCOPE_UPDATE" "$ALTERNATE_UPDATER/tools/plumbline-scope-update"
chmod +x "$ALTERNATE_UPDATER/tools/plumbline-scope-update"
ALTERNATE_UPDATER_DENY="$(
  PLUMBLINE_BIN_DIR="$ALTERNATE_UPDATER/tools" \
    CLAUDE_PROJECT_DIR="$ALTERNATE_UPDATER" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"tools/plumbline-scope-update --repo . --feature demo --confirmed"}}
EOF
)"
assert_contains "noncanonical project updater cannot receive repair exemption" \
  "$ALTERNATE_UPDATER_DENY" '"decision":"deny"'

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
assert "foreign-repository fixture is blocked before its first write" \
  "test ! -e '$BASE/src/demo/unplanned.py'"

ABSOLUTE_WRITE_PASS="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Write","tool_input":{"file_path":"$BASE/src/demo/app.py"}}
EOF
)"
assert_eq "absolute in-repository target matching the plan is accepted" \
  "" "$ABSOLUTE_WRITE_PASS"

MANIFEST_WRITE_DENY="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"docs/scope/demo.scope.json"}}
EOF
)"
assert_contains "direct manifest writes are reserved for confirmed updater" \
  "$MANIFEST_WRITE_DENY" '"decision":"deny"'

PLAN_WRITE_DENY="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"docs/plans/2026-07-29-demo.md"}}
EOF
)"
assert_contains "direct active-plan writes are reserved for confirmed updater" \
  "$PLAN_WRITE_DENY" '"decision":"deny"'

NORMALIZED_PLAN_CONTROL="$WORK/normalized-plan-control"
cp -R "$BASE" "$NORMALIZED_PLAN_CONTROL"
python3 - "$NORMALIZED_PLAN_CONTROL/docs/scope/demo.scope.json" <<'PY'
import hashlib, json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["artifacts"]["plan"] = "docs/plans/./2026-07-29-demo.md"
data["scope"]["governance"] = [
    "docs/plans/**" if item == "docs/plans/2026-07-29-demo.md" else item
    for item in data["scope"]["governance"]
]
data["provenance"][-1]["scope"] = data["scope"]
payload = json.dumps(data["scope"], sort_keys=True, separators=(",", ":")).encode()
data["provenance"][-1]["scope_digest"] = "sha256:" + hashlib.sha256(payload).hexdigest()
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
NORMALIZED_PLAN_WRITE_DENY="$(
  CLAUDE_PROJECT_DIR="$NORMALIZED_PLAN_CONTROL" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"docs/plans/2026-07-29-demo.md"}}
EOF
)"
assert_contains "normalized active-plan spelling remains a reserved control path" \
  "$NORMALIZED_PLAN_WRITE_DENY" '"decision":"deny"'

CONTROL_DELETE="$WORK/control-delete"
cp -R "$BASE" "$CONTROL_DELETE"
printf '%s\n' \
  "- Modify: \`src/demo/app.py\`" \
  "- Delete: \`docs/scope/demo.scope.json\`" \
  >"$CONTROL_DELETE/docs/plans/2026-07-29-demo.md"
CONTROL_DELETE_DENY="$(
  CLAUDE_PROJECT_DIR="$CONTROL_DELETE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"rm -f docs/scope/demo.scope.json"}}
EOF
)"
assert_contains "canonical manifest cannot be deleted through Delete declaration" \
  "$CONTROL_DELETE_DENY" '"decision":"deny"'

NORMALIZED_CONTROL_DELETE="$WORK/normalized-control-delete"
cp -R "$BASE" "$NORMALIZED_CONTROL_DELETE"
printf '%s\n' \
  "- Modify: \`src/demo/app.py\`" \
  "- Delete: \`docs/scope/./demo.scope.json\`" \
  >"$NORMALIZED_CONTROL_DELETE/docs/plans/2026-07-29-demo.md"
NORMALIZED_CONTROL_DELETE_DENY="$(
  CLAUDE_PROJECT_DIR="$NORMALIZED_CONTROL_DELETE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"rm -f docs/scope/./demo.scope.json"}}
EOF
)"
assert_contains "normalized manifest spelling cannot bypass deletion reservation" \
  "$NORMALIZED_CONTROL_DELETE_DENY" '"decision":"deny"'

SYMLINK_MANIFEST_WRITE="$WORK/symlink-manifest-write"
cp -R "$BASE" "$SYMLINK_MANIFEST_WRITE"
mv "$SYMLINK_MANIFEST_WRITE/docs/scope/demo.scope.json" \
  "$SYMLINK_MANIFEST_WRITE/docs/scope/resolved-demo.scope.json"
ln -s resolved-demo.scope.json \
  "$SYMLINK_MANIFEST_WRITE/docs/scope/demo.scope.json"
printf '%s\n' \
  "- Modify: \`src/demo/app.py\`" \
  "- Modify: \`docs/scope/demo.scope.json\`" \
  >"$SYMLINK_MANIFEST_WRITE/docs/plans/2026-07-29-demo.md"
SYMLINK_MANIFEST_WRITE_DENY="$(
  CLAUDE_PROJECT_DIR="$SYMLINK_MANIFEST_WRITE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"docs/scope/demo.scope.json"}}
EOF
)"
assert_contains "resolved symlink manifest remains a reserved write target" \
  "$SYMLINK_MANIFEST_WRITE_DENY" '"decision":"deny"'

SYMLINK_MANIFEST_DELETE="$WORK/symlink-manifest-delete"
cp -R "$BASE" "$SYMLINK_MANIFEST_DELETE"
mv "$SYMLINK_MANIFEST_DELETE/docs/scope/demo.scope.json" \
  "$SYMLINK_MANIFEST_DELETE/docs/scope/resolved-demo.scope.json"
ln -s resolved-demo.scope.json \
  "$SYMLINK_MANIFEST_DELETE/docs/scope/demo.scope.json"
printf '%s\n' \
  "- Modify: \`src/demo/app.py\`" \
  "- Delete: \`docs/scope/demo.scope.json\`" \
  >"$SYMLINK_MANIFEST_DELETE/docs/plans/2026-07-29-demo.md"
SYMLINK_MANIFEST_DELETE_DENY="$(
  CLAUDE_PROJECT_DIR="$SYMLINK_MANIFEST_DELETE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"rm -f docs/scope/demo.scope.json"}}
EOF
)"
assert_contains "resolved symlink manifest remains a reserved deletion target" \
  "$SYMLINK_MANIFEST_DELETE_DENY" '"decision":"deny"'

DELETE_ONLY_WRITE_DENY="$(
  CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/old.py"}}
EOF
)"
assert_contains "Delete-only target cannot be modified through Edit" \
  "$DELETE_ONLY_WRITE_DENY" '"decision":"deny"'

MARKER_CONTROL="$WORK/marker-control"
cp -R "$BASE" "$MARKER_CONTROL"
printf '%s\n' \
  "- Modify: \`src/demo/app.py\`" \
  "- Modify: \`docs/context/.active-feature\`" \
  >"$MARKER_CONTROL/docs/plans/2026-07-29-demo.md"
python3 - "$MARKER_CONTROL/docs/scope/demo.scope.json" <<'PY'
import hashlib, json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["governance"].append("docs/context/.active-feature")
data["provenance"][-1]["scope"] = data["scope"]
payload = json.dumps(data["scope"], sort_keys=True, separators=(",", ":")).encode()
data["provenance"][-1]["scope_digest"] = "sha256:" + hashlib.sha256(payload).hexdigest()
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
MARKER_WRITE_DENY="$(
  CLAUDE_PROJECT_DIR="$MARKER_CONTROL" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"docs/context/.active-feature"}}
EOF
)"
assert_contains "active-feature marker is reserved from direct writes" \
  "$MARKER_WRITE_DENY" '"decision":"deny"'

SYMLINK_MARKER_CONTROL="$WORK/symlink-marker-control"
cp -R "$BASE" "$SYMLINK_MARKER_CONTROL"
mv "$SYMLINK_MARKER_CONTROL/docs/context/.active-feature" \
  "$SYMLINK_MARKER_CONTROL/docs/context/active-feature-target"
ln -s active-feature-target \
  "$SYMLINK_MARKER_CONTROL/docs/context/.active-feature"
printf '%s\n' \
  "- Modify: \`src/demo/app.py\`" \
  "- Modify: \`docs/context/active-feature-target\`" \
  >"$SYMLINK_MARKER_CONTROL/docs/plans/2026-07-29-demo.md"
python3 - "$SYMLINK_MARKER_CONTROL/docs/scope/demo.scope.json" <<'PY'
import hashlib, json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["governance"].append("docs/context/active-feature-target")
data["provenance"][-1]["scope"] = data["scope"]
payload = json.dumps(data["scope"], sort_keys=True, separators=(",", ":")).encode()
data["provenance"][-1]["scope_digest"] = "sha256:" + hashlib.sha256(payload).hexdigest()
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
SYMLINK_MARKER_WRITE_DENY="$(
  CLAUDE_PROJECT_DIR="$SYMLINK_MARKER_CONTROL" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"docs/context/.active-feature"}}
EOF
)"
assert_contains "resolved active-feature marker target remains reserved" \
  "$SYMLINK_MARKER_WRITE_DENY" '"decision":"deny"'

CANVAS_DELETE_CONTROL="$WORK/canvas-delete-control"
cp -R "$BASE" "$CANVAS_DELETE_CONTROL"
printf '%s\n' \
  "- Modify: \`src/demo/app.py\`" \
  "- Delete: \`docs/canvas/demo.canvas.md\`" \
  >"$CANVAS_DELETE_CONTROL/docs/plans/2026-07-29-demo.md"
CANVAS_DELETE_DENY="$(
  CLAUDE_PROJECT_DIR="$CANVAS_DELETE_CONTROL" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Bash","tool_input":{"command":"rm -f docs/canvas/demo.canvas.md"}}
EOF
)"
assert_contains "active Canvas is reserved from deletion" \
  "$CANVAS_DELETE_DENY" '"decision":"deny"'

MUTABLE_CHECKER="$WORK/mutable-checker"
cp -R "$MISSING" "$MUTABLE_CHECKER"
mkdir -p "$MUTABLE_CHECKER/config/claude/bin" "$MUTABLE_CHECKER/config/claude/lib"
cp "$SCOPE_CHECK" "$MUTABLE_CHECKER/config/claude/bin/plumbline-scope-check"
cp "$REPO_DIR/config/claude/lib/plumbline_python.sh" \
  "$REPO_DIR/config/claude/lib/plumbline_scope.py" \
  "$MUTABLE_CHECKER/config/claude/lib/"
git -C "$MUTABLE_CHECKER" init -q
git -C "$MUTABLE_CHECKER" add config/claude/bin config/claude/lib
git -C "$MUTABLE_CHECKER" \
  -c user.name=test -c user.email=test@example.invalid commit -qm fixture
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
  >"$MUTABLE_CHECKER/config/claude/bin/plumbline-scope-check"
chmod +x "$MUTABLE_CHECKER/config/claude/bin/plumbline-scope-check"
MUTABLE_CHECKER_DENY="$(
  CLAUDE_PROJECT_DIR="$MUTABLE_CHECKER" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_contains "modified project checker is skipped and immutable checker catches drift" \
  "$MUTABLE_CHECKER_DENY" '"decision":"deny"'

CLEAN_MALICIOUS_CHECKER="$WORK/clean-malicious-checker"
cp -R "$MISSING" "$CLEAN_MALICIOUS_CHECKER"
mkdir -p "$CLEAN_MALICIOUS_CHECKER/config/claude/bin" \
  "$CLEAN_MALICIOUS_CHECKER/config/claude/lib"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
  >"$CLEAN_MALICIOUS_CHECKER/config/claude/bin/plumbline-scope-check"
printf '%s\n' '# foreign controlled runtime' \
  >"$CLEAN_MALICIOUS_CHECKER/config/claude/lib/plumbline_scope.py"
printf '%s\n' '# foreign controlled launcher' \
  >"$CLEAN_MALICIOUS_CHECKER/config/claude/lib/plumbline_python.sh"
chmod +x "$CLEAN_MALICIOUS_CHECKER/config/claude/bin/plumbline-scope-check"
git -C "$CLEAN_MALICIOUS_CHECKER" init -q
git -C "$CLEAN_MALICIOUS_CHECKER" add .
git -C "$CLEAN_MALICIOUS_CHECKER" \
  -c user.name=test -c user.email=test@example.invalid commit -qm fixture
CLEAN_MALICIOUS_CHECKER_DENY="$(
  CLAUDE_PROJECT_DIR="$CLEAN_MALICIOUS_CHECKER" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_contains "foreign repository committed checker is skipped for installed authority" \
  "$CLEAN_MALICIOUS_CHECKER_DENY" '"decision":"deny"'

SYMLINKED_CHECKER="$WORK/symlinked-checker"
cp -R "$HOOK_REPO" "$SYMLINKED_CHECKER"
mkdir -p "$SYMLINKED_CHECKER/config/claude/bin"
ln -sf /bin/true \
  "$SYMLINKED_CHECKER/config/claude/bin/plumbline-scope-check"
SYMLINKED_CHECKER_DENY="$(
  CLAUDE_PROJECT_DIR="$SYMLINKED_CHECKER" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_contains "repository-owned checker symlink cannot launder external authority" \
  "$SYMLINKED_CHECKER_DENY" '"decision":"deny"'

ALTERNATE_CHECKER="$WORK/alternate-checker"
cp -R "$MISSING" "$ALTERNATE_CHECKER"
mkdir -p "$ALTERNATE_CHECKER/tools"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' \
  >"$ALTERNATE_CHECKER/tools/plumbline-scope-check"
chmod +x "$ALTERNATE_CHECKER/tools/plumbline-scope-check"
ALTERNATE_CHECKER_DENY="$(
  PLUMBLINE_BIN_DIR="$ALTERNATE_CHECKER/tools" \
    CLAUDE_PROJECT_DIR="$ALTERNATE_CHECKER" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py"}}
EOF
)"
assert_contains "noncanonical project checker is skipped in favor of immutable authority" \
  "$ALTERNATE_CHECKER_DENY" '"decision":"deny"'

# A confirmed checker-runtime change remains implementable, but only while an
# immutable checker outside the writable project authorizes the exact planned
# target. This prevents the protection from making its own maintenance
# impossible.
CHECKER_MAINTENANCE="$WORK/checker-maintenance"
cp -R "$BASE" "$CHECKER_MAINTENANCE"
mkdir -p "$CHECKER_MAINTENANCE/config/claude/bin" \
  "$CHECKER_MAINTENANCE/config/claude/lib"
cp "$SCOPE_CHECK" \
  "$CHECKER_MAINTENANCE/config/claude/bin/plumbline-scope-check"
cp "$REPO_DIR/config/claude/lib/plumbline_python.sh" \
  "$REPO_DIR/config/claude/lib/plumbline_scope.py" \
  "$CHECKER_MAINTENANCE/config/claude/lib/"
printf '%s\n' \
  "- Modify: \`src/demo/app.py\`" \
  "- Modify: \`config/claude/lib/plumbline_scope.py\`" \
  >"$CHECKER_MAINTENANCE/docs/plans/2026-07-29-demo.md"
python3 - "$CHECKER_MAINTENANCE/docs/scope/demo.scope.json" <<'PY'
import hashlib, json, sys
path = sys.argv[1]
data = json.load(open(path, encoding="utf-8"))
data["scope"]["governance"].append("config/claude/lib/plumbline_scope.py")
data["provenance"][-1]["scope"] = data["scope"]
payload = json.dumps(data["scope"], sort_keys=True, separators=(",", ":")).encode()
data["provenance"][-1]["scope_digest"] = "sha256:" + hashlib.sha256(payload).hexdigest()
json.dump(data, open(path, "w", encoding="utf-8"), indent=2)
PY
git -C "$CHECKER_MAINTENANCE" init -q
git -C "$CHECKER_MAINTENANCE" add .
git -C "$CHECKER_MAINTENANCE" \
  -c user.name=test -c user.email=test@example.invalid commit -qm fixture
CHECKER_MAINTENANCE_PASS="$(
  CLAUDE_PROJECT_DIR="$CHECKER_MAINTENANCE" "$PRETOOL_SCOPE" <<'EOF'
{"tool_name":"Edit","tool_input":{"file_path":"config/claude/lib/plumbline_scope.py"}}
EOF
)"
assert_eq "immutable external checker authorizes exact planned runtime maintenance" \
  "" "$CHECKER_MAINTENANCE_PASS"

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
assert "installer materializes the scope gate outside the governed checkout" \
  "test -f '$INSTALL_HOME/hooks/pretool-scope-gate.sh' && test ! -L '$INSTALL_HOME/hooks/pretool-scope-gate.sh'"
assert_contains "settings execute the independent installed scope gate" \
  "$(jq -r '[.hooks.PreToolUse[]?.hooks[]?.command? // "" | select(test("pretool-scope-gate\\.sh"))][0]' \
    "$INSTALL_HOME/settings.json")" \
  "$INSTALL_HOME/hooks/pretool-scope-gate.sh"

# Default installs keep most files live through symlinks, but the scope
# checker/updater and their loaded runtime are independent copied authority.
AUTH_HOME="$WORK/authority-home"
CLAUDE_HOME="$AUTH_HOME" bash "$REPO_DIR/config/claude/install.sh" \
  --no-agents --no-commands --no-skills --no-hook >/dev/null
for authority_path in \
  bin/plumbline-scope-check \
  bin/plumbline-scope-update \
  lib/plumbline_cli.py \
  lib/plumbline_python.sh \
  lib/plumbline_scope.py \
  lib/plumbline_scope_update.py
do
  assert "default install materializes independent scope authority: $authority_path" \
    "test -f '$AUTH_HOME/$authority_path' && test ! -L '$AUTH_HOME/$authority_path'"
done
assert_exit "installed copied checker loads only the materialized scope runtime" 0 \
  "$AUTH_HOME/bin/plumbline-scope-check" --help
INSTALLED_REPAIR_PASS="$(
  CLAUDE_HOME="$AUTH_HOME" CLAUDE_PROJECT_DIR="$BASE" "$PRETOOL_SCOPE" <<EOF
{"tool_name":"Bash","tool_input":{"command":"$AUTH_HOME/bin/plumbline-scope-update --repo $BASE --feature demo --confirmed"}}
EOF
)"
assert_eq "default installed updater remains an authenticated repair path" \
  "" "$INSTALLED_REPAIR_PASS"

# An --update must convert authority symlinks created by older versions even
# when the global/default install mode remains symlink.
UPGRADE_HOME="$WORK/upgrade-home"
mkdir -p "$UPGRADE_HOME/bin" "$UPGRADE_HOME/lib"
for authority_path in \
  bin/plumbline-scope-check \
  bin/plumbline-scope-update \
  lib/plumbline_cli.py \
  lib/plumbline_python.sh \
  lib/plumbline_scope.py \
  lib/plumbline_scope_update.py
do
  ln -s "$REPO_DIR/config/claude/${authority_path}" "$UPGRADE_HOME/$authority_path"
done
CLAUDE_HOME="$UPGRADE_HOME" bash "$REPO_DIR/config/claude/install.sh" --update \
  --no-agents --no-commands --no-skills --no-hook >/dev/null
for authority_path in \
  bin/plumbline-scope-check \
  bin/plumbline-scope-update \
  lib/plumbline_cli.py \
  lib/plumbline_python.sh \
  lib/plumbline_scope.py \
  lib/plumbline_scope_update.py
do
  assert "update converts legacy authority symlink to copy: $authority_path" \
    "test -f '$UPGRADE_HOME/$authority_path' && test ! -L '$UPGRADE_HOME/$authority_path'"
done
rm -rf "$WORK"
SCOPE_BIN="$REPO_DIR/config/claude/bin/plumbline-scope-check"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# new_repo <feature> -- create a git repo with docs/canvas + docs/scope dirs.
# Echoes the repo path.
new_repo() {
  local feat="$1" repo
  repo="$WORK/$feat"
  mkdir -p "$repo/docs/canvas" "$repo/docs/scope"
  git -C "$repo" init -q
  git -C "$repo" config user.email scope-test@example.com
  git -C "$repo" config user.name "Scope Test"
  printf '%s' "$repo"
}

# write_canvas <repo> <feature> -- body arrives on stdin, appended under the
# "Allowed change scope" heading. Heredocs are piped IN, never wrapped in $().
write_canvas() {
  local repo="$1" feat="$2" out="$1/docs/canvas/$2.canvas.md"
  {
    printf '# %s Canvas\n\n' "$feat"
    printf 'Status: user-confirmed\nConfirmed by user: yes\n\n'
    printf '## Allowed change scope\n'
    cat
  } >"$out"
}

# run_scope <repo> <feature> <changed-path>...
# Sets SCOPE_RC / SCOPE_OUT (stdout+stderr merged, which is what an operator sees).
run_scope() {
  local repo="$1" feat="$2"
  shift 2
  local list="$repo/changed.txt" p
  : >"$list"
  for p in "$@"; do printf '%s\n' "$p" >>"$list"; done
  local outf="$WORK/scope.out"
  "$SCOPE_BIN" --repo "$repo" --feature "$feat" \
    --changed-files "$list" >"$outf" 2>&1
  SCOPE_RC=$?
  SCOPE_OUT="$(cat "$outf")"
}

# ---------------------------------------------------------------------------
# M. The manifest is the canonical, schema-validated security configuration.
# ---------------------------------------------------------------------------

# D (reproduced): the manifest must WIN over the canvas, not lose to it.
repo="$(new_repo precedence)"
write_canvas "$repo" precedence <<'EOF'
- `src/feature/**`
EOF
cat >"$repo/docs/scope/precedence.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "precedence",
  "allowed_change_scope": ["src/api/**"]
}
EOF
run_scope "$repo" precedence src/feature/app.py
assert_eq "manifest wins over canvas: canvas-only path violates" \
  "3" "$SCOPE_RC"
assert_contains "manifest wins over canvas: manifest named as the source" \
  "$SCOPE_OUT" "docs/scope/precedence.scope.json"
run_scope "$repo" precedence src/api/handler.py
assert_eq "manifest wins over canvas: manifest path passes" "0" "$SCOPE_RC"
assert_contains "manifest pass names the manifest source" \
  "$SCOPE_OUT" "source=manifest"

# A (reproduced): an absolute pattern is a HARD, classified manifest error that
# names the entry -- never a silent drop that degrades to "missing".
repo="$(new_repo absolute)"
cat >"$repo/docs/scope/absolute.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "absolute",
  "allowed_change_scope": ["src/feature/**", "/src/api/**"]
}
EOF
run_scope "$repo" absolute src/feature/app.py
assert_eq "manifest absolute pattern: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest absolute pattern: names the entry index" \
  "$SCOPE_OUT" "entry #2"
assert_contains "manifest absolute pattern: names the cause" \
  "$SCOPE_OUT" "repo-relative"
assert_not_contains "manifest absolute pattern: not reported as missing" \
  "$SCOPE_OUT" "missing Allowed change scope"

# Traversal is refused with the same clarity.
repo="$(new_repo traversal)"
cat >"$repo/docs/scope/traversal.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "traversal",
  "allowed_change_scope": ["../outside/**"]
}
EOF
run_scope "$repo" traversal src/feature/app.py
assert_eq "manifest traversal pattern: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest traversal pattern: names the entry index" \
  "$SCOPE_OUT" "entry #1"
assert_contains "manifest traversal pattern: names the cause" \
  "$SCOPE_OUT" ".."

# A prose-shaped entry (embedded whitespace) is a HARD manifest error: the
# manifest is machine configuration, so guessing intent is not allowed.
repo="$(new_repo proseentry)"
cat >"$repo/docs/scope/proseentry.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "proseentry",
  "allowed_change_scope": ["and every generated artifact under pkg/openapi/**"]
}
EOF
run_scope "$repo" proseentry pkg/openapi/v1.json
assert_eq "manifest prose entry: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest prose entry: names whitespace as the cause" \
  "$SCOPE_OUT" "whitespace"

# Non-string entries, wrong shape, wrong schema and feature mismatch are all
# classified rather than coerced.
repo="$(new_repo nonstring)"
cat >"$repo/docs/scope/nonstring.scope.json" <<'EOF'
{"schema": 1, "feature": "nonstring", "allowed_change_scope": ["src/**", 7]}
EOF
run_scope "$repo" nonstring src/app.py
assert_eq "manifest non-string entry: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest non-string entry: names the entry index" \
  "$SCOPE_OUT" "entry #2"

repo="$(new_repo badschema)"
cat >"$repo/docs/scope/badschema.scope.json" <<'EOF'
{"schema": 99, "feature": "badschema", "allowed_change_scope": ["src/**"]}
EOF
run_scope "$repo" badschema src/app.py
assert_eq "manifest unsupported schema: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest unsupported schema: names the version" \
  "$SCOPE_OUT" "99"

repo="$(new_repo featmismatch)"
cat >"$repo/docs/scope/featmismatch.scope.json" <<'EOF'
{"schema": 1, "feature": "something-else", "allowed_change_scope": ["src/**"]}
EOF
run_scope "$repo" featmismatch src/app.py
assert_eq "manifest feature mismatch: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest feature mismatch: names the declared feature" \
  "$SCOPE_OUT" "something-else"

# A broad pattern stays refused inside the manifest (existing gate, not weakened).
repo="$(new_repo broadentry)"
cat >"$repo/docs/scope/broadentry.scope.json" <<'EOF'
{"schema": 1, "feature": "broadentry", "allowed_change_scope": ["src/**", "**"]}
EOF
run_scope "$repo" broadentry anything/at/all.py
assert_eq "manifest broad pattern: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest broad pattern: names the entry index" \
  "$SCOPE_OUT" "entry #2"

# Legitimate glob metacharacters and non-ASCII directory names still work: the
# fix must not narrow real patterns.
repo="$(new_repo specialchars)"
cat >"$repo/docs/scope/specialchars.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "specialchars",
  "allowed_change_scope": [
    "src/**/*.py",
    "fixtures/file[0-9].txt",
    "docs/uebersicht/**"
  ]
}
EOF
run_scope "$repo" specialchars src/deep/nested/app.py fixtures/file7.txt \
  docs/uebersicht/plan.md
assert_eq "manifest special chars: legitimate globs pass" "0" "$SCOPE_RC"

# Negative control: a BROKEN manifest must not silently degrade to the canvas.
# Falling back would let anyone re-enable the fragile source by corrupting the
# canonical one -- the manifest's authority has to survive its own errors.
repo="$(new_repo nofallback)"
write_canvas "$repo" nofallback <<'EOF'
- `src/feature/**`
EOF
cat >"$repo/docs/scope/nofallback.scope.json" <<'EOF'
{"schema": 1, "feature": "nofallback", "allowed_change_scope": ["/absolute/**"]}
EOF
run_scope "$repo" nofallback src/feature/app.py
assert_eq "broken manifest does NOT fall back to the canvas" "4" "$SCOPE_RC"
assert_contains "broken manifest names the manifest, not the canvas" \
  "$SCOPE_OUT" "docs/scope/nofallback.scope.json"
assert_not_contains "broken manifest does not report a canvas pass" \
  "$SCOPE_OUT" "scope check passed"

# Same for unparseable JSON: classified, never a fallback.
repo="$(new_repo brokenjson)"
write_canvas "$repo" brokenjson <<'EOF'
- `src/feature/**`
EOF
printf '{"schema": 1, "allowed_change_scope": [\n' \
  >"$repo/docs/scope/brokenjson.scope.json"
run_scope "$repo" brokenjson src/feature/app.py
assert_eq "truncated manifest JSON: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "truncated manifest JSON: names the line" "$SCOPE_OUT" "line"

# An empty allow-list is "missing", not "everything".
repo="$(new_repo emptylist)"
cat >"$repo/docs/scope/emptylist.scope.json" <<'EOF'
{"schema": 1, "feature": "emptylist", "allowed_change_scope": []}
EOF
run_scope "$repo" emptylist src/app.py
assert_eq "manifest empty list: missing exit 2" "2" "$SCOPE_RC"

# ---------------------------------------------------------------------------
# L. Legacy canvas: still supported, but nothing is discarded silently.
# ---------------------------------------------------------------------------

# L1 backward compatibility: an ordinary canvas keeps working unchanged.
repo="$(new_repo legacyok)"
write_canvas "$repo" legacyok <<'EOF'
- `src/feature/**`
- `docs/`
EOF
run_scope "$repo" legacyok src/feature/app.py docs/notes.md
assert_eq "legacy canvas: still passes in-scope changes" "0" "$SCOPE_RC"
run_scope "$repo" legacyok src/billing/charge.py
assert_eq "legacy canvas: still blocks out-of-scope changes" "3" "$SCOPE_RC"

# A (reproduced) in the legacy path: the only declared pattern is absolute, so
# the effective scope is empty. That must be classified and name the line -- not
# reported as if the author had written no scope at all.
repo="$(new_repo legacyslash)"
write_canvas "$repo" legacyslash <<'EOF'
- `/src/feature/**`
EOF
run_scope "$repo" legacyslash src/feature/app.py
# Derive the expected line number from the file so the assertion cannot drift
# with the canvas preamble.
slash_line="$(grep -n 'src/feature' "$repo/docs/canvas/legacyslash.canvas.md" | cut -d: -f1)"
assert_eq "legacy absolute-only canvas: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "legacy absolute-only canvas: names the line number" \
  "$SCOPE_OUT" "line $slash_line"
assert_contains "legacy absolute-only canvas: points at the manifest" \
  "$SCOPE_OUT" "docs/scope/legacyslash.scope.json"

# B (reproduced): paths inside a fenced code block are not bullets. They stay
# unparsed (guessing prose is not allowed) but the operator is told exactly that.
repo="$(new_repo legacyblock)"
write_canvas "$repo" legacyblock <<'EOF'
```
src/feature/**
docs/**
```
EOF
run_scope "$repo" legacyblock src/feature/app.py
assert_eq "legacy fenced-block canvas: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "legacy fenced-block canvas: names the ignored code block" \
  "$SCOPE_OUT" "fenced code block"

# C (reproduced): a formatter-wrapped `*` line must NOT become a pattern, and
# must never authorize a prose-shaped path.
repo="$(new_repo legacyprose)"
write_canvas "$repo" legacyprose <<'EOF'
- `src/feature/**`
* and every generated artifact under pkg/openapi/**
EOF
run_scope "$repo" legacyprose src/feature/app.py
prose_line="$(grep -n 'and every generated' "$repo/docs/canvas/legacyprose.canvas.md" | cut -d: -f1)"
assert_eq "legacy prose line: valid bullet still passes" "0" "$SCOPE_RC"
assert_contains "legacy prose line: dropped line is named" \
  "$SCOPE_OUT" "line $prose_line"
assert_contains "legacy prose line: cause is named" \
  "$SCOPE_OUT" "whitespace"
run_scope "$repo" legacyprose "and every generated artifact under pkg/openapi/v1.json"
assert_eq "legacy prose line: prose-shaped path is NOT authorized" \
  "3" "$SCOPE_RC"

# An indented continuation (a wrapped bullet) is ignored by the parser; say so.
repo="$(new_repo legacywrap)"
write_canvas "$repo" legacywrap <<'EOF'
- `src/feature/**`
  `docs/really/long/path/**`
EOF
run_scope "$repo" legacywrap src/feature/app.py
wrap_line="$(grep -n 'really/long' "$repo/docs/canvas/legacywrap.canvas.md" | cut -d: -f1)"
assert_eq "legacy wrapped continuation: valid bullet still passes" "0" "$SCOPE_RC"
assert_contains "legacy wrapped continuation: ignored line is named" \
  "$SCOPE_OUT" "line $wrap_line"

# The canvas is documented as non-canonical: the pass message must say which
# source was actually used, so "which config governs me" is never a guess.
repo="$(new_repo legacysource)"
write_canvas "$repo" legacysource <<'EOF'
- `src/feature/**`
EOF
run_scope "$repo" legacysource src/feature/app.py
assert_contains "legacy canvas: pass names the canvas source" \
  "$SCOPE_OUT" "source=canvas"
finish "test_scope_manifest"
