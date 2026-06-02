#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

PLUMBLINE="$REPO_DIR/config/claude/bin/plumbline"
FIXTURES="$HERE/fixtures/update"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

assert "plumbline CLI exists" "test -x '$PLUMBLINE'"
# Version is release-please-managed; assert the CLI reports whatever VERSION holds
# (not a hardcoded number that breaks the suite on every release bump).
REPO_VERSION="$(grep -oE '^[0-9]+\.[0-9]+\.[0-9]+' "$REPO_DIR/VERSION" | head -1)"
assert_eq "version reads release-please-managed VERSION" "$REPO_VERSION" "$($PLUMBLINE --root "$REPO_DIR" version)"

# Synthesize a "latest release" one minor above the current version so update-available
# stays valid across every release bump (not pinned to a literal the repo catches up to).
NEWER_VERSION="$(awk -F. -v OFS=. '{print $1, $2+1, 0}' <<<"$REPO_VERSION")"
LATEST_SRC="$TMP_ROOT/latest-newer"
mkdir -p "$LATEST_SRC"
printf '{\n  "tag_name": "v%s",\n  "draft": false,\n  "prerelease": false\n}\n' "$NEWER_VERSION" > "$LATEST_SRC/latest-release.json"

check_output="$($PLUMBLINE --root "$REPO_DIR" update --check --source "$LATEST_SRC")"
assert "update --check reports newer release" "printf '%s\n' '$check_output' | grep -q 'status: update-available'"
assert "update --check reads GitHub release tag fixture" "printf '%s\n' '$check_output' | grep -q \"latest: $NEWER_VERSION\""

assert "doctor validates frozen contracts" "$PLUMBLINE --root '$REPO_DIR' doctor"
assert "honest-status keeps Plumbline language" "$PLUMBLINE --root '$REPO_DIR' honest-status | grep -q 'changed, not yet verified'"

SYMLINK_HOME="$TMP_ROOT/install-symlink-home"
CLAUDE_HOME="$SYMLINK_HOME" "$REPO_DIR/config/claude/install.sh" --no-agents --no-commands --no-skills --no-hook --force >"$TMP_ROOT/install-symlink.log"
assert_file "install creates symlinked plumbline wrapper" "$SYMLINK_HOME/bin/plumbline"
assert_file "install creates symlinked plumbline library" "$SYMLINK_HOME/lib/plumbline_update.py"
assert_eq "installed symlink wrapper resolves library" "$REPO_VERSION" "$("$SYMLINK_HOME/bin/plumbline" --root "$REPO_DIR" version)"

COPY_HOME="$TMP_ROOT/install-copy-home"
CLAUDE_HOME="$COPY_HOME" "$REPO_DIR/config/claude/install.sh" --copy --no-agents --no-commands --no-skills --no-hook --force >"$TMP_ROOT/install-copy.log"
assert_file "install creates copied plumbline wrapper" "$COPY_HOME/bin/plumbline"
assert_file "install creates copied plumbline library" "$COPY_HOME/lib/plumbline_update.py"
assert_eq "installed copy wrapper resolves library" "$REPO_VERSION" "$("$COPY_HOME/bin/plumbline" --root "$REPO_DIR" version)"

TARGET="$TMP_ROOT/target"
cp -R "$FIXTURES/target-0.9.0" "$TARGET"
apply_output="$($PLUMBLINE --root "$REPO_DIR" update --target "$TARGET" --source "$FIXTURES/source-0.9.1" --verify-cmd 'bash config/claude/tests/run_all.sh')"
assert_eq "update applies source version" "0.9.1" "$($PLUMBLINE --root "$TARGET" version)"
assert_file "update copies payload" "$TARGET/UPDATED"
assert_file "update records last success" "$TARGET/.plumbline/update/last-success.json"
assert "update reports verified" "printf '%s\n' '$apply_output' | grep -q 'status: changed and verified (0.9.0 -> 0.9.1)'"

rollback_output="$($PLUMBLINE --root "$REPO_DIR" rollback --target "$TARGET")"
assert_eq "rollback restores previous version" "0.9.0" "$($PLUMBLINE --root "$TARGET" version)"
assert "rollback removes updated payload" "test ! -f '$TARGET/UPDATED'"
assert "rollback reports snapshot" "printf '%s\n' '$rollback_output' | grep -q 'status: rolled back'"

FAIL_TARGET="$TMP_ROOT/fail-target"
cp -R "$FIXTURES/target-0.9.0" "$FAIL_TARGET"
if "$PLUMBLINE" --root "$REPO_DIR" update --target "$FAIL_TARGET" --source "$FIXTURES/source-0.9.1" --verify-cmd 'test -f DOES_NOT_EXIST' >"$TMP_ROOT/fail.log" 2>&1; then
  fail_status=0
else
  fail_status=$?
fi
assert_eq "failed verification exits non-zero" "1" "$fail_status"
assert_eq "failed verification reverts version" "0.9.0" "$($PLUMBLINE --root "$FAIL_TARGET" version)"
assert "failed verification reverts payload" "test ! -f '$FAIL_TARGET/UPDATED'"
assert "failed verification reports revert" "grep -q 'status: reverted to snapshot' '$TMP_ROOT/fail.log'"

MAJOR_TARGET="$TMP_ROOT/major-target"
cp -R "$FIXTURES/target-0.9.0" "$MAJOR_TARGET"
if "$PLUMBLINE" --root "$REPO_DIR" update --target "$MAJOR_TARGET" --source "$FIXTURES/source-1.0.0" --verify-cmd 'true' >"$TMP_ROOT/major.log" 2>&1; then
  major_status=0
else
  major_status=$?
fi
assert_eq "MAJOR update requires explicit confirmation" "1" "$major_status"
assert "MAJOR refusal names --yes-major" "grep -q -- '--yes-major' '$TMP_ROOT/major.log'"

finish "update layer tests"
