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

# Best-effort request that Apple's tar omit AppleDouble (._*) metadata members
# from the fixture tarballs (documented in Apple's tar(1); harmless unknown-var
# no-op on GNU tar / Linux). Whether macOS tar emits ._* at all is xattr- and
# filesystem-dependent (nondeterministic between runs), so this is a belt only:
# correctness does NOT rely on it. The production extractor is independently
# hardened to ignore AppleDouble / __MACOSX members whatever the source tar did
# (see the AppleDouble regression test below, which synthesizes the members via
# Python tarfile so it triggers on every platform regardless of this var).
export COPYFILE_DISABLE=1

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

# --- P1: tarball payload source (GitHub-release-shaped, fully offline) -------
# Build a payload tree one minor above the current repo version, wrapped in a
# single top-level directory exactly like a GitHub source tarball
# (<owner>-<repo>-<sha>/...). The install.sh stub exits 0 so the apply flow
# reaches verification without running the real installer.
TAR_PAYLOAD="$TMP_ROOT/tar-payload"
TAR_TOP="plumbline-fixture-deadbeef"
PAYLOAD_DIR="$TAR_PAYLOAD/$TAR_TOP"
mkdir -p "$PAYLOAD_DIR/config/claude/tests"
printf '%s\n' "$NEWER_VERSION" > "$PAYLOAD_DIR/VERSION"
printf '{\n  "version": "%s",\n  "schema": 1,\n  "verifyCommand": "true",\n  "frozenContracts": ["VERSION"],\n  "migrations": []\n}\n' "$NEWER_VERSION" > "$PAYLOAD_DIR/compatibility.json"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$PAYLOAD_DIR/config/claude/install.sh"
chmod +x "$PAYLOAD_DIR/config/claude/install.sh"
TARBALL="$TMP_ROOT/payload.tar.gz"
tar -C "$TAR_PAYLOAD" -czf "$TARBALL" "$TAR_TOP"

tar_check_output="$($PLUMBLINE --root "$REPO_DIR" update --check --source "$TARBALL")"
assert "tarball --check reports update-available" "printf '%s\n' '$tar_check_output' | grep -q 'status: update-available'"
assert "tarball --check reports newer latest" "printf '%s\n' '$tar_check_output' | grep -q \"latest: $NEWER_VERSION\""

TAR_TARGET="$TMP_ROOT/tar-target"
cp -R "$FIXTURES/target-0.9.0" "$TAR_TARGET"
tar_apply_output="$($PLUMBLINE --root "$REPO_DIR" update --target "$TAR_TARGET" --source "$TARBALL" --verify-cmd true)"
assert "tarball apply reports verified" "printf '%s\n' '$tar_apply_output' | grep -q 'status: changed and verified'"
assert_eq "tarball apply installs newer version" "$NEWER_VERSION" "$($PLUMBLINE --root "$TAR_TARGET" version)"

# --- P1: AppleDouble (macOS metadata) tarball still applies -----------------
# Regression for the macOS bug where bsdtar injects a top-level `._<dir>`
# AppleDouble member that sorts before the real top dir and broke single-top-
# level-dir detection (apply silently no-op'd, version stayed at base). The
# fixture is synthesized with Python tarfile so the `._*` members exist on EVERY
# platform (Linux/macOS/Windows), making this a deterministic cross-platform
# guard rather than something that only triggers on a Mac.
AD_TARBALL="$TMP_ROOT/appledouble.tar.gz"
python3 - "$AD_TARBALL" "$NEWER_VERSION" <<'PY'
import io, sys, tarfile
tarball, version = sys.argv[1], sys.argv[2]
TOP = "plumbline-appledouble-deadbeef"
def add(t, name, data, mode=0o644):
    ti = tarfile.TarInfo(name); ti.size = len(data); ti.mode = mode
    t.addfile(ti, io.BytesIO(data))
compat = ('{ "version": "%s", "schema": 1, "verifyCommand": "true", '
          '"frozenContracts": ["VERSION"], "migrations": [] }\n' % version).encode()
with tarfile.open(tarball, "w:gz") as t:
    # AppleDouble for the top dir itself — the member that sorts FIRST and broke detection.
    add(t, "._" + TOP, b"Mac OS X AppleDouble\n")
    add(t, f"{TOP}/VERSION", (version + "\n").encode())
    add(t, f"{TOP}/._VERSION", b"Mac OS X AppleDouble\n")
    add(t, f"{TOP}/compatibility.json", compat)
    add(t, f"{TOP}/config/claude/install.sh", b"#!/usr/bin/env bash\nexit 0\n", mode=0o755)
PY
AD_TARGET="$TMP_ROOT/appledouble-target"
cp -R "$FIXTURES/target-0.9.0" "$AD_TARGET"
ad_check="$($PLUMBLINE --root "$REPO_DIR" update --check --source "$AD_TARBALL" 2>&1)"
assert "AppleDouble tarball --check reports update-available" "printf '%s\n' '$ad_check' | grep -q 'status: update-available'"
ad_apply="$($PLUMBLINE --root "$REPO_DIR" update --target "$AD_TARGET" --source "$AD_TARBALL" --verify-cmd true 2>&1)"
assert "AppleDouble tarball apply reports verified" "printf '%s\n' '$ad_apply' | grep -q 'status: changed and verified'"
assert_eq "AppleDouble tarball installs newer version" "$NEWER_VERSION" "$($PLUMBLINE --root "$AD_TARGET" version)"
assert "AppleDouble metadata is not written to target" "test ! -e '$AD_TARGET/._plumbline-appledouble-deadbeef'"

# --- P1: safe-extract rejects path traversal -------------------------------
# A tarball whose member escapes the extraction root must be refused before any
# file is written, and nothing may land outside the target.
EVIL_DIR="$TMP_ROOT/evil-build"
mkdir -p "$EVIL_DIR"
printf '%s\n' "owned" > "$EVIL_DIR/evil"
EVIL_TARBALL="$TMP_ROOT/evil.tar.gz"
# Portable across GNU and BSD/macOS tar: build the path-traversal member with Python's
# tarfile (macOS BSD tar lacks --transform / --absolute-names, which falsely RED-ed the
# whole suite on macOS). The member name "../evil" is the attack the production extractor
# must refuse; the production code itself uses portable tarfile, so this only fixes the
# fixture, not the behaviour under test.
python3 - "$EVIL_TARBALL" "$EVIL_DIR/evil" <<'PY'
import sys, tarfile
tarball, payload = sys.argv[1], sys.argv[2]
with tarfile.open(tarball, "w:gz") as t:
    t.add(payload, arcname="../evil")
PY
EVIL_TARGET="$TMP_ROOT/evil-target"
cp -R "$FIXTURES/target-0.9.0" "$EVIL_TARGET"
EVIL_SENTINEL="$TMP_ROOT/evil"
rm -f "$EVIL_SENTINEL"
if "$PLUMBLINE" --root "$REPO_DIR" update --target "$EVIL_TARGET" --source "$EVIL_TARBALL" --verify-cmd true >"$TMP_ROOT/evil.log" 2>&1; then
  evil_status=0
else
  evil_status=$?
fi
assert_eq "unsafe tarball exits non-zero" "1" "$evil_status"
assert "unsafe tarball reports unsafe member" "grep -q 'unsafe tarball' '$TMP_ROOT/evil.log'"
assert "unsafe tarball writes nothing outside target" "test ! -e '$EVIL_SENTINEL'"
assert_eq "unsafe tarball leaves target version intact" "0.9.0" "$($PLUMBLINE --root "$EVIL_TARGET" version)"

# --- P1: network failure is a clean message, never a traceback -------------
# Point the API at a closed port so the fetch fails fast and deterministically.
if PLUMBLINE_GITHUB_API="http://127.0.0.1:1" "$PLUMBLINE" --root "$REPO_DIR" update --check >"$TMP_ROOT/net.log" 2>&1; then
  net_status=0
else
  net_status=$?
fi
assert_eq "network failure exits non-zero" "1" "$net_status"
assert "network failure reports could-not-reach GitHub" "grep -q 'could not reach GitHub' '$TMP_ROOT/net.log'"
assert "network failure has no traceback" "! grep -q 'Traceback' '$TMP_ROOT/net.log'"

# --- SECURITY (HIGH-1): payload-supplied verifyCommand is NEVER executed -----
# A downloaded payload's compatibility.json must not be able to run arbitrary
# shell via its verifyCommand. Applying WITHOUT --verify-cmd must run the fixed
# standard verify (the payload's run_all.sh stub), never the payload's string.
EVILV_TOP="plumbline-evilverify-deadbeef"
EVILV_BUILD="$TMP_ROOT/evilverify-build"
EVILV_DIR="$EVILV_BUILD/$EVILV_TOP"
mkdir -p "$EVILV_DIR/config/claude/tests"
printf '%s\n' "$NEWER_VERSION" > "$EVILV_DIR/VERSION"
printf '{\n  "version": "%s",\n  "schema": 1,\n  "verifyCommand": "touch EVIL_VERIFY_SENTINEL",\n  "frozenContracts": ["VERSION"],\n  "migrations": []\n}\n' "$NEWER_VERSION" > "$EVILV_DIR/compatibility.json"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$EVILV_DIR/config/claude/install.sh"
printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$EVILV_DIR/config/claude/tests/run_all.sh"
chmod +x "$EVILV_DIR/config/claude/install.sh" "$EVILV_DIR/config/claude/tests/run_all.sh"
EVILV_TARBALL="$TMP_ROOT/evilverify.tar.gz"
tar -C "$EVILV_BUILD" -czf "$EVILV_TARBALL" "$EVILV_TOP"
EVILV_TARGET="$TMP_ROOT/evilverify-target"
cp -R "$FIXTURES/target-0.9.0" "$EVILV_TARGET"
evilv_out="$($PLUMBLINE --root "$REPO_DIR" update --target "$EVILV_TARGET" --source "$EVILV_TARBALL")"
assert "verify falls back to the fixed standard command" "printf '%s\n' '$evilv_out' | grep -q 'status: changed and verified'"
assert "payload-supplied verifyCommand is NOT executed" "test ! -e '$EVILV_TARGET/EVIL_VERIFY_SENTINEL'"
assert_eq "evil-verify payload still applies its version" "$NEWER_VERSION" "$($PLUMBLINE --root "$EVILV_TARGET" version)"

# --- SECURITY (MEDIUM-2): non-http(s) API scheme is refused, not opened ------
if PLUMBLINE_GITHUB_API="file:///tmp" "$PLUMBLINE" --root "$REPO_DIR" update --check >"$TMP_ROOT/scheme.log" 2>&1; then
  scheme_status=0
else
  scheme_status=$?
fi
assert_eq "file:// API scheme exits non-zero" "1" "$scheme_status"
assert "file:// API scheme is refused by name" "grep -qi 'refus' '$TMP_ROOT/scheme.log'"
assert "file:// API scheme produces no traceback" "! grep -q 'Traceback' '$TMP_ROOT/scheme.log'"

# --- SECURITY (MEDIUM-1): extraction strips setuid (tarfile data filter) -----
if python3 - "$REPO_DIR" "$TMP_ROOT" >"$TMP_ROOT/setuid.log" 2>&1 <<'PY'
import sys, io, tarfile
from pathlib import Path
repo, tmp = sys.argv[1], sys.argv[2]
sys.path.insert(0, str(Path(repo) / "config" / "claude" / "lib"))
import plumbline_update as P
tar_path = Path(tmp) / "setuid.tar.gz"
with tarfile.open(tar_path, "w:gz") as t:
    data = b"#!/bin/sh\n"
    ti = tarfile.TarInfo("top/payload.sh")
    ti.size = len(data)
    ti.mode = 0o4755  # setuid + rwxr-xr-x
    t.addfile(ti, io.BytesIO(data))
top = P.safe_extract_tarball(tar_path, Path(tmp) / "setuid-extract")
mode = (top / "payload.sh").stat().st_mode
assert mode & 0o4000 == 0, "setuid bit survived extraction: %o" % mode
print("setuid stripped OK")
PY
then setuid_status=0; else setuid_status=$?; fi
assert_eq "extraction strips setuid bit" "0" "$setuid_status"
assert "extraction setuid guard confirmed" "grep -q 'setuid stripped OK' '$TMP_ROOT/setuid.log'"

# --- SECURITY (NEW-1): redirect targets are re-validated on every hop --------
# urllib's own redirect allowlist includes ftp://; the scheme guard must be
# authoritative on redirects too, not just the initial URL.
if python3 - "$REPO_DIR" >"$TMP_ROOT/redirect.log" 2>&1 <<'PY'
import sys, urllib.request
from pathlib import Path
sys.path.insert(0, str(Path(sys.argv[1]) / "config" / "claude" / "lib"))
import plumbline_update as P
handler = P._SafeRedirectHandler()
req = urllib.request.Request("https://example.invalid/start")
try:
    handler.redirect_request(req, None, 302, "Found", {}, "ftp://127.0.0.1:1/payload.tar.gz")
    print("ftp redirect NOT refused")
except P.PlumblineError:
    print("ftp redirect refused OK")
out = handler.redirect_request(req, None, 302, "Found", {}, "https://codeload.example/x")
print("https redirect allowed OK" if out is not None else "https redirect WRONGLY blocked")
PY
then redirect_status=0; else redirect_status=$?; fi
assert_eq "redirect re-validation runs cleanly" "0" "$redirect_status"
assert "ftp:// redirect target is refused" "grep -q 'ftp redirect refused OK' '$TMP_ROOT/redirect.log'"
assert "https:// redirect target stays allowed" "grep -q 'https redirect allowed OK' '$TMP_ROOT/redirect.log'"

# --- P2: plumbline install subcommand wraps install.sh ----------------------
assert "install --help exits 0" "$PLUMBLINE --root '$REPO_DIR' install --help"
INSTALL_HOME="$(mktemp -d)"
if CLAUDE_HOME="$INSTALL_HOME" "$PLUMBLINE" --root "$REPO_DIR" install --dry-run --no-agents --no-commands --no-skills --no-hook --no-bin >"$TMP_ROOT/install-sub.log" 2>&1; then
  install_sub_status=0
else
  install_sub_status=$?
fi
rm -rf "$INSTALL_HOME"
assert_eq "install subcommand exits 0" "0" "$install_sub_status"
assert "install subcommand shows dry-run marker" "grep -q 'dry-run' '$TMP_ROOT/install-sub.log'"

finish "update layer tests"
