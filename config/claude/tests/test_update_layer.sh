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
REPO_VERSION="$(repo_version "$REPO_DIR")"
assert_eq "version reads release-please-managed VERSION" "$REPO_VERSION" "$($PLUMBLINE --root "$REPO_DIR" version)"

# Synthesize a "latest release" one minor above the current version so update-available
# stays valid across every release bump (not pinned to a literal the repo catches up to).
NEWER_VERSION="$(awk -F. -v OFS=. '{print $1, $2+1, 0}' <<<"$REPO_VERSION")"
BASELINE_FIXTURE_VERSION="0.9.0"
UPDATE_FIXTURE_VERSION="0.9.1"
BASELINE_FIXTURE="$FIXTURES/target-$BASELINE_FIXTURE_VERSION"
UPDATE_FIXTURE="$FIXTURES/source-$UPDATE_FIXTURE_VERSION"
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
cp -R "$BASELINE_FIXTURE" "$TARGET"
apply_output="$($PLUMBLINE --root "$REPO_DIR" update --target "$TARGET" --source "$UPDATE_FIXTURE" --verify-cmd 'bash config/claude/tests/run_all.sh')"
assert_eq "update applies source version" "$UPDATE_FIXTURE_VERSION" "$($PLUMBLINE --root "$TARGET" version)"
assert_file "update copies payload" "$TARGET/UPDATED"
assert_file "update records last success" "$TARGET/.plumbline/update/last-success.json"
assert_contains "update reports verified" "$apply_output" "status: changed and verified ($BASELINE_FIXTURE_VERSION -> $UPDATE_FIXTURE_VERSION)"

rollback_output="$($PLUMBLINE --root "$REPO_DIR" rollback --target "$TARGET")"
assert_eq "rollback restores previous version" "$BASELINE_FIXTURE_VERSION" "$($PLUMBLINE --root "$TARGET" version)"
assert "rollback removes updated payload" "test ! -f '$TARGET/UPDATED'"
assert "rollback reports snapshot" "printf '%s\n' '$rollback_output' | grep -q 'status: rolled back'"

FAIL_TARGET="$TMP_ROOT/fail-target"
cp -R "$BASELINE_FIXTURE" "$FAIL_TARGET"
if "$PLUMBLINE" --root "$REPO_DIR" update --target "$FAIL_TARGET" --source "$UPDATE_FIXTURE" --verify-cmd 'test -f DOES_NOT_EXIST' >"$TMP_ROOT/fail.log" 2>&1; then
  fail_status=0
else
  fail_status=$?
fi
assert_eq "failed verification exits non-zero" "1" "$fail_status"
assert_eq "failed verification reverts version" "$BASELINE_FIXTURE_VERSION" "$($PLUMBLINE --root "$FAIL_TARGET" version)"
assert "failed verification reverts payload" "test ! -f '$FAIL_TARGET/UPDATED'"
assert "failed verification reports revert" "grep -q 'status: reverted to snapshot' '$TMP_ROOT/fail.log'"

MAJOR_TARGET="$TMP_ROOT/major-target"
cp -R "$BASELINE_FIXTURE" "$MAJOR_TARGET"
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
cp -R "$BASELINE_FIXTURE" "$TAR_TARGET"
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
cp -R "$BASELINE_FIXTURE" "$AD_TARGET"
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
cp -R "$BASELINE_FIXTURE" "$EVIL_TARGET"
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
assert_eq "unsafe tarball leaves target version intact" "$BASELINE_FIXTURE_VERSION" "$($PLUMBLINE --root "$EVIL_TARGET" version)"

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
cp -R "$BASELINE_FIXTURE" "$EVILV_TARGET"
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

# --- SPRINT 1 (PUR-1.1): fixed install identity, cwd-INDEPENDENT --------------
# REQ-PUR-01 (install-identity anchor) + REQ-PUR-02 (cwd-independent version/check).
# These drive the INSTALLED copy of the CLI (NOT --source / NOT --root), so they
# exercise the real "what does plumbline report when run from anywhere" path that
# every user relies on. RED-for-the-right-reason TODAY:
#   * no anchor file is written by install.sh, so the installed lib falls through to
#     repo_root()'s Path.cwd() -> it reads the CWD's VERSION/origin, not the
#     installed Plumbline's. From /tmp that errors ("VERSION not found"); from a
#     foreign repo it prints 9.9.9 and queries the foreign origin slug.
# SANDBOX-ONLY (NFR-PUR-01): every path below is under mktemp dirs; the real
# ~/.claude is NEVER touched. Offline (0 network): the slug assertion uses a local
# recording http stub via the PLUMBLINE_GITHUB_API seam. bash-3.2-safe (no
# $()-wrapped heredocs), ASCII-only, eval-free.

# The installed Plumbline version is the source VERSION captured at install time.
INSTALLED_VERSION="$REPO_VERSION"

# Sandbox CLAUDE_HOME + a fresh --copy install (copy mode so the installed lib runs
# from $CLAUDE_HOME/lib and resolves identity as the installed copy, not the repo).
PUR_HOME="$TMP_ROOT/pur-claude-home"
CLAUDE_HOME="$PUR_HOME" "$REPO_DIR/config/claude/install.sh" --copy --no-agents --no-commands --no-skills --no-hook --force >"$TMP_ROOT/pur-install.log" 2>&1
PUR_CLI="$PUR_HOME/bin/plumbline"
assert_file "PUR install: installed plumbline wrapper exists in sandbox" "$PUR_CLI"

# Safety belt: prove this test never wrote to the operator's real ~/.claude.
assert "PUR safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$PUR_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"

# A foreign repo with its OWN VERSION=9.9.9 and its OWN git origin. The installed
# CLI must ignore ALL of it (identity is the install's, not the cwd's).
FAKEREPO="$TMP_ROOT/fakerepo"
mkdir -p "$FAKEREPO"
printf '9.9.9\n' > "$FAKEREPO/VERSION"
git -C "$FAKEREPO" init -q
git -C "$FAKEREPO" remote add origin "https://github.com/EVILFORK/NotPlumbline.git"

# AC-PUR-01.1/.2 -- the install-identity anchor is written, carrying version + slug
# (+ source_commit + installed_at). RED now: install.sh writes no anchor.
PUR_ANCHOR="$PUR_HOME/.plumbline-install.json"
assert_file "PUR-1.1 AC-PUR-01.1: install writes .plumbline-install.json anchor" "$PUR_ANCHOR"
assert "PUR-1.1 AC-PUR-01.2: anchor carries version" "test -f '$PUR_ANCHOR' && grep -q '\"version\"' '$PUR_ANCHOR'"
assert "PUR-1.1 AC-PUR-01.2: anchor carries repo_slug" "test -f '$PUR_ANCHOR' && grep -q '\"repo_slug\"' '$PUR_ANCHOR'"
assert "PUR-1.1 AC-PUR-01.1: anchor carries source_commit" "test -f '$PUR_ANCHOR' && grep -q '\"source_commit\"' '$PUR_ANCHOR'"
assert "PUR-1.1 AC-PUR-01.1: anchor carries installed_at" "test -f '$PUR_ANCHOR' && grep -q '\"installed_at\"' '$PUR_ANCHOR'"

# AC-PUR-02.1 -- installed `version` from a NEUTRAL cwd (/tmp), no --root, must
# print the installed version and never error. RED now: errors "VERSION not found".
pur_ver_neutral="$(cd /tmp && "$PUR_CLI" version 2>&1)"
assert_eq "PUR-1.1 AC-PUR-02.1: installed version from /tmp is the installed version" "$INSTALLED_VERSION" "$pur_ver_neutral"

# AC-PUR-02.2 -- installed `version` from a FOREIGN repo (own VERSION=9.9.9), no
# --root, must print the installed version, NEVER 9.9.9. RED now: prints 9.9.9.
pur_ver_foreign="$(cd "$FAKEREPO" && "$PUR_CLI" version 2>&1)"
assert_eq "PUR-1.1 AC-PUR-02.2: installed version from foreign repo is the installed version" "$INSTALLED_VERSION" "$pur_ver_foreign"
assert "PUR-1.1 AC-PUR-02.2: installed version from foreign repo is NEVER the foreign 9.9.9" "test '$pur_ver_foreign' != '9.9.9'"

# AC-PUR-02.2 -- installed `update --check` from the FOREIGN repo must query the
# INSTALLED slug (DYAI2025/Plumbline), NOT the foreign origin. Offline: a local
# recording http stub records the requested /repos/<owner>/<repo>/... path; we
# assert which slug was queried. RED now: queries EVILFORK/NotPlumbline (foreign).
PUR_STUB_DIR="$TMP_ROOT/pur-slug-stub"
mkdir -p "$PUR_STUB_DIR"
PUR_REC="$PUR_STUB_DIR/requested-path.txt"
PUR_PORT_FILE="$PUR_STUB_DIR/port.txt"
PUR_STUB_PY="$PUR_STUB_DIR/stub.py"
# Write the stub as a standalone file (NOT a $()-wrapped heredoc -- bash 3.2 / macOS
# CI mis-parses those; the shell-portability guard flags them). It records every
# requested path and returns a valid release JSON so --check completes offline.
cat > "$PUR_STUB_PY" <<'PYEOF'
import sys, json, http.server
recfile, portfile = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(recfile, "a") as f:
            f.write(self.path + "\n")
        body = json.dumps({"tag_name": "v0.0.1", "draft": False, "prerelease": False}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(portfile, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PYEOF
python3 "$PUR_STUB_PY" "$PUR_REC" "$PUR_PORT_FILE" >"$PUR_STUB_DIR/stub.log" 2>&1 &
PUR_STUB_PID=$!
# Poll for the port file (bash-3.2-safe loop; no sleep-via-$()).
pur_wait=0
while [ ! -s "$PUR_PORT_FILE" ] && [ "$pur_wait" -lt 50 ]; do
  sleep 0.1
  pur_wait=$((pur_wait + 1))
done
PUR_PORT="$(cat "$PUR_PORT_FILE" 2>/dev/null || true)"
PUR_MARK="STUB_NOT_READY"
if [ -n "$PUR_PORT" ]; then
  # Connectivity probe BEFORE the run so the macOS skip keys off whether the
  # loopback socket is connectable, NOT off the assertion outcome.
  PUR_MARK="$(pur_stub_reachable 127.0.0.1 "$PUR_PORT")"
  ( cd "$FAKEREPO" && PLUMBLINE_GITHUB_API="http://127.0.0.1:$PUR_PORT" "$PUR_CLI" update --check >"$TMP_ROOT/pur-check.log" 2>&1 ) || true
fi
kill "$PUR_STUB_PID" 2>/dev/null || true
wait "$PUR_STUB_PID" 2>/dev/null || true
# macOS-CI loopback skip (NARROW / LOUD / Linux stays HARD): the slug the `--check`
# fetch queries can only be recorded if the run reached the 127.0.0.1 stub. On the
# macOS runner the stub is unconnectable (PUR_MARK=STUB_NOT_READY) -> SKIP tallied;
# Linux/local reach it -> run HARD. Keyed off connectivity, never the outcome.
if pur_macos_stub_skip_active "$PUR_MARK"; then
  pur_stub_skip_notice "PUR-1.1 AC-PUR-02.2 --check installed-slug block (2 assertions)"
else
  assert "PUR-1.1 AC-PUR-02.2: --check from foreign repo queries installed slug DYAI2025/Plumbline" "test -f '$PUR_REC' && grep -q '/repos/DYAI2025/Plumbline/' '$PUR_REC'"
  assert "PUR-1.1 AC-PUR-02.2: --check from foreign repo does NOT query the foreign slug" "! { test -f '$PUR_REC' && grep -q '/repos/EVILFORK/NotPlumbline/' '$PUR_REC'; }"
fi


# Review #83 P1 -- installed COPY-mode natural `plumbline update` from the
# FOREIGN repo must use the same anchor-aware slug resolution as `update --check`.
# This intentionally lets the later apply fail (the stub release has no real
# tarball); the regression being killed is the FIRST network request slug.
PUR_APPLY_STUB_DIR="$TMP_ROOT/pur-apply-slug-stub"
mkdir -p "$PUR_APPLY_STUB_DIR"
PUR_APPLY_REC="$PUR_APPLY_STUB_DIR/requested-path.txt"
PUR_APPLY_PORT_FILE="$PUR_APPLY_STUB_DIR/port.txt"
PUR_APPLY_STUB_PY="$PUR_APPLY_STUB_DIR/stub.py"
cat > "$PUR_APPLY_STUB_PY" <<'PYEOF'
import sys, json, http.server
recfile, portfile = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(recfile, "a") as f:
            f.write(self.path + "\n")
        body = json.dumps({
            "tag_name": "v999.0.0",
            "draft": False,
            "prerelease": False,
            "tarball_url": "http://127.0.0.1:%s/missing.tar.gz" % self.server.server_address[1],
        }).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(portfile, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PYEOF
python3 "$PUR_APPLY_STUB_PY" "$PUR_APPLY_REC" "$PUR_APPLY_PORT_FILE" >"$PUR_APPLY_STUB_DIR/stub.log" 2>&1 &
PUR_APPLY_STUB_PID=$!
pur_apply_wait=0
while [ ! -s "$PUR_APPLY_PORT_FILE" ] && [ "$pur_apply_wait" -lt 50 ]; do
  sleep 0.1
  pur_apply_wait=$((pur_apply_wait + 1))
done
PUR_APPLY_PORT="$(cat "$PUR_APPLY_PORT_FILE" 2>/dev/null || true)"
PUR_APPLY_MARK="STUB_NOT_READY"
if [ -n "$PUR_APPLY_PORT" ]; then
  PUR_APPLY_MARK="$(pur_stub_reachable 127.0.0.1 "$PUR_APPLY_PORT")"
  ( cd "$FAKEREPO" && PLUMBLINE_GITHUB_API="http://127.0.0.1:$PUR_APPLY_PORT" "$PUR_CLI" update >"$TMP_ROOT/pur-apply.log" 2>&1 ) || true
fi
kill "$PUR_APPLY_STUB_PID" 2>/dev/null || true
wait "$PUR_APPLY_STUB_PID" 2>/dev/null || true
# macOS-CI loopback skip: the natural-update FIRST fetch slug is only recorded if
# the run reached the stub; macOS-unconnectable -> SKIP tallied, Linux/local HARD.
if pur_macos_stub_skip_active "$PUR_APPLY_MARK"; then
  pur_stub_skip_notice "PUR-1.1 review P1 natural-update installed-slug block (2 assertions)"
else
  assert "PUR-1.1 review P1: natural update from foreign repo queries installed slug DYAI2025/Plumbline" "test -f '$PUR_APPLY_REC' && grep -q '/repos/DYAI2025/Plumbline/' '$PUR_APPLY_REC'"
  assert "PUR-1.1 review P1: natural update from foreign repo does NOT query the foreign slug" "! { test -f '$PUR_APPLY_REC' && grep -q '/repos/EVILFORK/NotPlumbline/' '$PUR_APPLY_REC'; }"
fi

# --- SPRINT 1 review findings: C2 (symlink cwd-independence), I1 (malformed-
# --- version anchor must fail loud), I2 (exotic origin must stay valid JSON) ---
# Three additions for the Sprint-1 code-review findings. The user confirmed a
# TWO-MODE identity model:
#   * COPY installs read the install-identity anchor ($CLAUDE_HOME/.plumbline-install.json).
#   * SYMLINK installs (the default) track the symlinked CHECKOUT: the symlink fixes
#     the lib's path to the source tree, so identity resolves from the checkout's
#     VERSION/origin -- cwd-INDEPENDENT, regardless of where the user runs it from.
# SANDBOX-ONLY: every path below lives under $TMP_ROOT (mktemp); the real ~/.claude
# is NEVER touched. Offline (0 network). bash-3.2-safe (no $()-wrapped heredocs),
# ASCII-only, eval-free (JSON validity is checked by handing the file PATH to
# python3 as argv[1], never by interpolating payload into shell/python code).

# ====================================================================
# C2 -- SYMLINK-mode cwd-independence (CONFIRMING test; PASSES with current code).
# The copy-pinned PUR-1.1 block above only exercised --copy mode; this closes the
# coverage gap for the DEFAULT (symlink) install. Install in symlink mode, then run
# the INSTALLED `version` with NO --root from a NEUTRAL cwd (/tmp) and from a FOREIGN
# repo (own VERSION=9.9.9) -> MUST return the CHECKOUT's version (cwd-independent),
# never the cwd's VERSION, never an error.
# ====================================================================
C2_HOME="$TMP_ROOT/c2-symlink-home"
CLAUDE_HOME="$C2_HOME" "$REPO_DIR/config/claude/install.sh" --no-agents --no-commands --no-skills --no-hook --force >"$TMP_ROOT/c2-install.log" 2>&1
C2_CLI="$C2_HOME/bin/plumbline"
assert_file "C2 install: symlink-mode plumbline wrapper exists in sandbox" "$C2_CLI"
# Safety belt: prove this never wrote to the operator's real ~/.claude.
assert "C2 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$C2_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
# Confirm it is genuinely the DEFAULT symlink mode (the lib is a symlink, not a copy);
# if a future install.sh flipped the default to copies, this assertion makes the mode
# regression LOUD rather than letting C2 silently re-test copy mode.
assert "C2: default install symlinks the installed library (not a copy)" "test -L '$C2_HOME/lib/plumbline_update.py'"

# A foreign repo with its OWN VERSION=9.9.9 and its OWN git origin -- the installed
# symlink CLI must ignore ALL of it (identity is the symlinked checkout's, not cwd's).
C2_FAKEREPO="$TMP_ROOT/c2-fakerepo"
mkdir -p "$C2_FAKEREPO"
printf '9.9.9\n' > "$C2_FAKEREPO/VERSION"
git -C "$C2_FAKEREPO" init -q
git -C "$C2_FAKEREPO" remote add origin "https://github.com/EVILFORK/NotPlumbline.git"

# C2.a -- installed `version` from a NEUTRAL cwd (/tmp), no --root, MUST be the
# checkout version and exit cleanly (never "VERSION not found").
c2_ver_neutral="$(cd /tmp && "$C2_CLI" version 2>&1)"
assert_eq "C2.a: symlink-mode version from /tmp is the checkout version (cwd-independent)" "$REPO_VERSION" "$c2_ver_neutral"

# C2.b -- installed `version` from a FOREIGN repo (own VERSION=9.9.9), no --root,
# MUST be the checkout version, NEVER 9.9.9, NEVER an error.
c2_ver_foreign="$(cd "$C2_FAKEREPO" && "$C2_CLI" version 2>&1)"
assert_eq "C2.b: symlink-mode version from foreign repo is the checkout version" "$REPO_VERSION" "$c2_ver_foreign"
assert "C2.b: symlink-mode version from foreign repo is NEVER the foreign 9.9.9" "test '$c2_ver_foreign' != '9.9.9'"

# ====================================================================
# C2.5 -- AC-PUR-02.5: SYMLINK install tracks the ADVANCED checkout after a git pull
# (the DISCRIMINATOR the C2 block above lacks). CONFIRMING test; PASSES with current
# code. The C2 assertions only check `version == $REPO_VERSION`, which at install time
# equals BOTH the checkout VERSION and any frozen install-time/anchor value -- so a
# regression to "symlink reads the frozen install-time value" would stay GREEN there
# ("a test that still passes with the branch deleted does not cover it"). This block
# closes that gap: install in symlink mode from a THROWAWAY source checkout at version
# vN (the anchor, if any, captures vN), then ADVANCE that checkout's VERSION to vN+1
# (simulating a `git pull`/version bump), and assert the installed CLI -- run with NO
# --root from a foreign cwd -- reports vN+1, explicitly NOT vN (the frozen value) and
# NOT the cwd's VERSION. This FAILS the instant symlink mode regresses to reading a
# frozen anchor instead of the live symlinked checkout.
# SANDBOX-ONLY: the VERSION bump is on a THROWAWAY checkout under $TMP_ROOT (mktemp);
# the real repo's VERSION and the operator's real ~/.claude are NEVER touched. Offline
# (0 network). bash-3.2-safe (no $()-wrapped heredocs), ASCII-only, eval-free.
# ====================================================================
# vN = the install-time/frozen value; vN+1 = the advanced ("after git pull") value.
C25_VN="$REPO_VERSION"
C25_VN1="$(awk -F. -v OFS=. '{print $1, $2+1, 0}' <<<"$REPO_VERSION")"

# A THROWAWAY source checkout (install-capable subset) at vN, with the canonical
# Plumbline origin. install.sh derives its REPO_DIR from its own location, so a symlink
# install from here pins the installed lib's symlink to THIS checkout -- whose VERSION we
# then advance. (Same throwaway-source mechanism the I2 block below relies on.)
C25_SRC="$TMP_ROOT/c25-src"
mkdir -p "$C25_SRC/config/claude/lib" "$C25_SRC/config/claude/bin"
printf '%s\n' "$C25_VN" > "$C25_SRC/VERSION"
cp "$REPO_DIR/config/claude/install.sh" "$C25_SRC/config/claude/install.sh"
cp "$REPO_DIR/config/claude/lib/plumbline_update.py" "$C25_SRC/config/claude/lib/plumbline_update.py"
cp "$REPO_DIR/config/claude/bin/plumbline" "$C25_SRC/config/claude/bin/plumbline" 2>/dev/null || true
chmod +x "$C25_SRC/config/claude/install.sh" "$C25_SRC/config/claude/bin/plumbline" 2>/dev/null || true
git -C "$C25_SRC" init -q
git -C "$C25_SRC" remote add origin "https://github.com/DYAI2025/Plumbline.git"

# Symlink-install (default mode) the throwaway checkout into a sandbox HOME at vN.
C25_HOME="$TMP_ROOT/c25-symlink-home"
CLAUDE_HOME="$C25_HOME" "$C25_SRC/config/claude/install.sh" --no-agents --no-commands --no-skills --no-hook --force >"$TMP_ROOT/c25-install.log" 2>&1
C25_CLI="$C25_HOME/bin/plumbline"
assert_file "C2.5 install: symlink-mode plumbline wrapper exists in sandbox" "$C25_CLI"
assert "C2.5 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$C25_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
assert "C2.5 safety: throwaway source is under TMP_ROOT (real repo VERSION untouched)" "case '$C25_SRC' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
# Confirm it really is the DEFAULT symlink mode (lib is a symlink into the throwaway src).
assert "C2.5: default install symlinks the installed library into the throwaway checkout" "test -L '$C25_HOME/lib/plumbline_update.py'"
# Sanity: at install time the installed CLI reports vN (anchor/checkout agree here).
c25_ver_preadvance="$(cd /tmp && "$C25_CLI" version 2>&1)"
assert_eq "C2.5 precondition: symlink-mode version at install time is vN" "$C25_VN" "$c25_ver_preadvance"

# ADVANCE the throwaway checkout's VERSION to vN+1 -- simulate `git pull`/version bump.
printf '%s\n' "$C25_VN1" > "$C25_SRC/VERSION"

# THE DISCRIMINATOR: installed `version`, NO --root, from a FOREIGN cwd (own VERSION)
# must now report vN+1 (the ADVANCED checkout value the live symlink tracks), and
# explicitly NOT vN (the frozen install-time/anchor value) and NOT the cwd's VERSION.
C25_FAKEREPO="$TMP_ROOT/c25-fakerepo"
mkdir -p "$C25_FAKEREPO"
printf '7.7.7\n' > "$C25_FAKEREPO/VERSION"
git -C "$C25_FAKEREPO" init -q
git -C "$C25_FAKEREPO" remote add origin "https://github.com/EVILFORK/NotPlumbline.git"
c25_ver_advanced="$(cd "$C25_FAKEREPO" && "$C25_CLI" version 2>&1)"
assert_eq "C2.5 AC-PUR-02.5: symlink-mode version tracks the ADVANCED checkout (vN+1)" "$C25_VN1" "$c25_ver_advanced"
assert "C2.5 AC-PUR-02.5: symlink-mode version is NOT the frozen install-time value (vN)" "test '$c25_ver_advanced' != '$C25_VN'"
assert "C2.5 AC-PUR-02.5: symlink-mode version is NOT the foreign cwd's VERSION (7.7.7)" "test '$c25_ver_advanced' != '7.7.7'"
# And from a NEUTRAL cwd (/tmp) too: still the advanced value, never an error.
c25_ver_advanced_neutral="$(cd /tmp && "$C25_CLI" version 2>&1)"
assert_eq "C2.5 AC-PUR-02.5: symlink-mode version from /tmp also tracks the ADVANCED checkout (vN+1)" "$C25_VN1" "$c25_ver_advanced_neutral"

# ====================================================================
# I1 -- present-but-malformed (no usable version) anchor must FAIL LOUD, not fall
# through to the cwd's VERSION. RED-FOR-THE-RIGHT-REASON TODAY: read_version()
# treats a no-`version` anchor as "fall through to root/VERSION", so an installed
# COPY run from a dir that happens to carry a VERSION silently reports THAT dir's
# version. Copy-install into a sandbox, corrupt the anchor to a valid-JSON dict
# WITHOUT a usable version, plant a cwd VERSION=8.8.8, run installed `version` from
# that cwd (no --root) -> MUST fail loud (non-zero, "re-run install.sh"-style
# notice), NOT print 8.8.8.
# ====================================================================
I1_HOME="$TMP_ROOT/i1-copy-home"
CLAUDE_HOME="$I1_HOME" "$REPO_DIR/config/claude/install.sh" --copy --no-agents --no-commands --no-skills --no-hook --force >"$TMP_ROOT/i1-install.log" 2>&1
I1_CLI="$I1_HOME/bin/plumbline"
assert_file "I1 install: copy-mode plumbline wrapper exists in sandbox" "$I1_CLI"
assert "I1 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$I1_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
I1_ANCHOR="$I1_HOME/.plumbline-install.json"
assert_file "I1 precondition: copy install wrote the identity anchor" "$I1_ANCHOR"
# Corrupt to a valid-JSON dict WITHOUT a usable `version` field.
printf '%s\n' '{"repo_slug":"a/b"}' > "$I1_ANCHOR"
# Plant a cwd whose VERSION the buggy fall-through would wrongly report.
I1_PLANT="$TMP_ROOT/i1-plant-cwd"
mkdir -p "$I1_PLANT"
printf '8.8.8\n' > "$I1_PLANT/VERSION"
if i1_out="$(cd "$I1_PLANT" && "$I1_CLI" version 2>&1)"; then
  i1_status=0
else
  i1_status=$?
fi
# RED now: today the fall-through prints 8.8.8 and exits 0. After the fix the
# malformed anchor must be a loud failure, never the cwd's version.
assert_eq "I1: malformed-version anchor fails loud (non-zero exit)" "1" "$i1_status"
assert "I1: malformed-version anchor NEVER reports the cwd's planted 8.8.8" "test '$i1_out' != '8.8.8'"
assert_contains "I1: malformed-version anchor advises re-running install.sh" "$i1_out" "install.sh"

# ====================================================================
# I2 -- a source git origin containing a double-quote must NOT break the anchor
# JSON. RED-FOR-THE-RIGHT-REASON TODAY: write_install_anchor printf-interpolates
# repo_slug into the JSON without escaping, so an origin like
# https://github.com/EVIL"X/repo.git yields  "repo_slug": "EVIL"X/repo"  -> the
# .plumbline-install.json is INVALID JSON. The fix must keep the file valid JSON
# (slug escaped, or rejected to the safe charset and replaced by the
# DYAI2025/Plumbline fallback). All sandboxed: a throwaway SOURCE checkout under
# $TMP_ROOT supplies install.sh + the lib so install.sh runs, and its git origin
# carries the exotic double-quote.
# ====================================================================
I2_SRC="$TMP_ROOT/i2-src"
mkdir -p "$I2_SRC/config/claude/lib" "$I2_SRC/config/claude/bin"
printf '%s\n' "$REPO_VERSION" > "$I2_SRC/VERSION"
cp "$REPO_DIR/config/claude/install.sh" "$I2_SRC/config/claude/install.sh"
cp "$REPO_DIR/config/claude/lib/plumbline_update.py" "$I2_SRC/config/claude/lib/plumbline_update.py"
cp "$REPO_DIR/config/claude/bin/plumbline" "$I2_SRC/config/claude/bin/plumbline" 2>/dev/null || true
chmod +x "$I2_SRC/config/claude/install.sh" "$I2_SRC/config/claude/bin/plumbline" 2>/dev/null || true
git -C "$I2_SRC" init -q
git -C "$I2_SRC" -c user.email=t@t -c user.name=t add -A >/dev/null 2>&1 || true
git -C "$I2_SRC" -c user.email=t@t -c user.name=t commit -q -m init >/dev/null 2>&1 || true
# Exotic origin: a literal double-quote in the owner segment.
git -C "$I2_SRC" remote add origin 'https://github.com/EVIL"X/repo.git'
I2_HOME="$TMP_ROOT/i2-home"
CLAUDE_HOME="$I2_HOME" "$I2_SRC/config/claude/install.sh" --copy --no-agents --no-commands --no-skills --no-hook --force >"$TMP_ROOT/i2-install.log" 2>&1
assert "I2 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$I2_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
I2_ANCHOR="$I2_HOME/.plumbline-install.json"
assert_file "I2 precondition: install wrote an anchor from the exotic-origin source" "$I2_ANCHOR"
# RED now: the unescaped double-quote makes this file invalid JSON. Validate by
# handing the FILE PATH to python3 as argv[1] (eval-free, no payload interpolation).
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$I2_ANCHOR" >/dev/null 2>&1; then
  i2_json_status=0
else
  i2_json_status=$?
fi
assert_eq "I2: anchor stays valid parseable JSON despite a double-quote in origin" "0" "$i2_json_status"
# And the recorded slug must be safe: either the escaped exotic value re-parses to a
# string, or it was rejected to the DYAI2025/Plumbline fallback. A raw unescaped
# double-quote inside the repo_slug VALUE is the defect -- forbid it.
assert "I2: anchor repo_slug is not a raw unescaped double-quote injection" "! grep -q '\"repo_slug\": \"EVIL\"X/repo\"' '$I2_ANCHOR'"

# ====================================================================
# SPRINT 2 (REQ-PUR-03): token-aware, rate-limit-resilient release fetch.
# AC-PUR-03.1 token sent | .2 unauth still works | .3 403-rate-limit vs 404
# classified distinctly | .4 token NEVER printed (success AND error paths).
#
# Driven entirely through the injectable PLUMBLINE_GITHUB_API seam against a
# local recording http stub -- 0 real network, 0 touch of the real ~/.claude.
# The stub RECORDS the bytes it actually received (method, path, and the
# Authorization header value) to a file, and returns a CONFIGURABLE status
# (200 / 403+rate-limit-headers / 404) so each branch is exercised for real.
# We assert on what the stub RECORDED -- never on the env var the test set --
# so the test measures the request the code emitted, not a value we typed in.
#
# A unique SENTINEL token value is used so the never-leaked assertions (.4) are
# unambiguous: the literal sentinel must be ABSENT from stdout/stderr on every
# path. bash-3.2-safe (the stub is a standalone .py file, NOT a $()-wrapped
# heredoc), ASCII-only, eval-free (assert_not_contains passes args as params).
#
# RED-for-the-right-reason TODAY (current fetch_latest_release :292-310):
#   * .1 sends NO Authorization header at all  -> RED (header absent in record).
#   * .3 every HTTP error re-raises the SAME "could not reach GitHub release
#     API" string -> 403 and 404 are NOT distinct -> RED.
#   * .2 already works unauthenticated         -> CONFIRMING-GREEN.
#   * .4 today's code never prints the token (it sends none) -> CONFIRMING-GREEN
#     now; it stays a guard once .1 makes the code start sending one, ensuring
#     the new header/token is never logged on any path.
# ====================================================================

# A unique, easily-greppable sentinel token. The never-leaked assertions check
# this exact literal is absent from all output.
PUR3_TOKEN="ghp_PUR3SENTINEL_do_not_log_0123456789ABCDEF"

# --- The recording / configurable stub (standalone file; NOT a $()-heredoc) ---
PUR3_DIR="$TMP_ROOT/pur3-fetch-stub"
mkdir -p "$PUR3_DIR"
PUR3_STUB_PY="$PUR3_DIR/stub.py"
cat > "$PUR3_STUB_PY" <<'PYEOF'
import sys, json, http.server
# argv: <record-file> <port-file> <mode>
# mode in {ok, ratelimit, notfound}: selects the response the stub returns.
recfile, portfile, mode = sys.argv[1], sys.argv[2], sys.argv[3]

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization", "<none>")
        with open(recfile, "a") as f:
            f.write("METHOD GET\n")
            f.write("PATH " + self.path + "\n")
            f.write("AUTH " + auth + "\n")
        if mode == "ratelimit":
            body = json.dumps({"message": "API rate limit exceeded",
                               "documentation_url": "https://docs.github.com/"}).encode()
            self.send_response(403)
            self.send_header("Content-Type", "application/json")
            self.send_header("X-RateLimit-Limit", "60")
            self.send_header("X-RateLimit-Remaining", "0")
            self.send_header("X-RateLimit-Reset", "9999999999")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        elif mode == "notfound":
            body = json.dumps({"message": "Not Found",
                               "documentation_url": "https://docs.github.com/"}).encode()
            self.send_response(404)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)
        else:  # ok
            body = json.dumps({"tag_name": "v0.0.1",
                               "draft": False, "prerelease": False}).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

    def log_message(self, *a):
        pass

srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(portfile, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PYEOF

# pur3_run_check <mode> <record-file> <stdout+stderr-log-file> [env-assignment ...]
# Boots the stub in <mode>, runs `update --check` against it via the seam with
# any extra leading ENV assignments, captures combined stdout+stderr to the log,
# then tears the stub down. bash-3.2-safe port polling; no $()-wrapped heredocs.
#
# Sets PUR3_MARK to a CONNECTIVITY-ONLY marker for the macOS-CI loopback skip:
#   STUB_REACHABLE -- the stub's loopback socket actually accepted a TCP connect
#                     (the run reached the stub; assertions run HARD on every OS).
#   STUB_NOT_READY -- the stub bound a port but its loopback socket was never
#                     connectable (the diagnosed macOS-CI-runner limitation), or
#                     no port file appeared. Linux/local NEVER produce this when
#                     the stub is up, so they always run HARD. The marker is
#                     derived from CONNECTIVITY, never from the assertion outcome.
PUR3_MARK=""
pur3_run_check() {
  pur3_mode="$1"; pur3_rec="$2"; pur3_log="$3"; shift 3
  : > "$pur3_rec"
  pur3_portfile="$PUR3_DIR/port-$pur3_mode.txt"
  rm -f "$pur3_portfile"
  python3 "$PUR3_STUB_PY" "$pur3_rec" "$pur3_portfile" "$pur3_mode" >"$PUR3_DIR/stub-$pur3_mode.log" 2>&1 &
  pur3_pid=$!
  pur3_wait=0
  while [ ! -s "$pur3_portfile" ] && [ "$pur3_wait" -lt 50 ]; do
    sleep 0.1
    pur3_wait=$((pur3_wait + 1))
  done
  pur3_port="$(cat "$pur3_portfile" 2>/dev/null || true)"
  PUR3_MARK="STUB_NOT_READY"
  if [ -n "$pur3_port" ]; then
    # Probe real TCP connectivity BEFORE the run so the skip can key off whether
    # the loopback socket is actually connectable (NOT off the assertion outcome).
    PUR3_MARK="$(pur_stub_reachable 127.0.0.1 "$pur3_port")"
    # Run with the canonical slug pinned (--repo) so the recorded path is
    # deterministic regardless of this repo's own origin, against the stub seam.
    env "$@" PLUMBLINE_GITHUB_API="http://127.0.0.1:$pur3_port" \
      "$PLUMBLINE" --root "$REPO_DIR" update --check --repo DYAI2025/Plumbline \
      >"$pur3_log" 2>&1 || true
  else
    printf 'STUB_NOT_READY\n' > "$pur3_log"
  fi
  kill "$pur3_pid" 2>/dev/null || true
  wait "$pur3_pid" 2>/dev/null || true
}

# --- SECURITY (CRITICAL-1, Sprint 2 remediation): the prod-honored
# --- PLUMBLINE_GITHUB_API seam must NOT exfiltrate the token to an arbitrary
# --- host. -----------------------------------------------------------------
# require_safe_url only validates the SCHEME, not the HOST, so today
# fetch_latest_release attaches `Authorization: Bearer <token>` to WHATEVER host
# PLUMBLINE_GITHUB_API resolves to -- including an attacker's. Captured
# empirically: token-set + PLUMBLINE_GITHUB_API=http://127.0.0.1:<stub> ships the
# token straight to 127.0.0.1 (here standing in for an attacker host).
#
# Remediation contract (coordinated with the coder brief): the Authorization
# header is sent ONLY when the resolved base host is api.github.com (the real
# GitHub API / configured GHE host), UNLESS an explicit, default-OFF test gate env
# PLUMBLINE_GITHUB_API_ALLOW_INSECURE_TOKEN=1 is set (so the offline tests can
# still exercise the header path against the 127.0.0.1 stub).
#
# The header-sent ACs below therefore now set that explicit gate so they keep
# exercising the real header path against the local stub WITHOUT weakening the
# prod invariant; the exfil falsifier directly below them runs WITHOUT the gate
# and proves the token never reaches the insecure host.
PUR3_INSECURE_GATE="PLUMBLINE_GITHUB_API_ALLOW_INSECURE_TOKEN=1"

# --- CRITICAL-1 exfil falsifier (RED NOW): with the SENTINEL token set and the
# seam pointed at the 127.0.0.1 stub (an attacker host) and the insecure-token
# gate NOT set, the stub MUST receive NO Authorization header at all, and the
# sentinel literal MUST be absent from the captured request bytes. RED today:
# the code attaches the header unconditionally, so 127.0.0.1 receives the token.
# Asserted on what the stub RECORDED, never on the env var the test set.
PUR3_REC_EXFIL="$PUR3_DIR/rec-exfil.txt"
PUR3_LOG_EXFIL="$PUR3_DIR/log-exfil.txt"
pur3_run_check ok "$PUR3_REC_EXFIL" "$PUR3_LOG_EXFIL" "GITHUB_TOKEN=$PUR3_TOKEN"
# macOS-CI loopback skip (NARROW / LOUD / Linux stays HARD): these assertions all
# depend on the run reaching the 127.0.0.1 stub. On the macOS CI runner the stub
# binds but its loopback socket is unconnectable (PUR3_MARK=STUB_NOT_READY), so we
# SKIP with a tallied PUR_STUB_SKIP notice; on Linux/local the stub IS reachable
# (PUR3_MARK=STUB_REACHABLE) so they run HARD. The skip keys off CONNECTIVITY only
# -- a reachable-but-WRONG response is never skipped.
PUR3_MARK_EXFIL="$PUR3_MARK"
if pur_macos_stub_skip_active "$PUR3_MARK_EXFIL"; then
  pur_stub_skip_notice "PUR-3 CRITICAL-1 token-exfil block (5 assertions)"
else
  assert "PUR-3 CRITICAL-1: token NOT sent to insecure host (no Authorization header) when the insecure-token gate is OFF" "grep -q 'AUTH <none>' '$PUR3_REC_EXFIL'"
  assert "PUR-3 CRITICAL-1: stub on the insecure host received NO Bearer header" "! grep -q 'AUTH Bearer' '$PUR3_REC_EXFIL'"
  # The sentinel token literal must be ABSENT from the whole captured request
  # record (method/path/auth) -- it must never reach the attacker host on any line.
  PUR3_REC_EXFIL_BODY="$(cat "$PUR3_REC_EXFIL" 2>/dev/null || true)"
  assert_not_contains "PUR-3 CRITICAL-1: sentinel token literal NEVER captured at the insecure-host stub" "$PUR3_REC_EXFIL_BODY" "$PUR3_TOKEN"
  # Belt: the unauthenticated --check against the insecure host still SUCCEEDS
  # (withholding the header must not break the offline fetch -- value preserved).
  assert "PUR-3 CRITICAL-1: --check against insecure host still succeeds with the header withheld" "grep -q 'status:' '$PUR3_LOG_EXFIL'"
  assert "PUR-3 CRITICAL-1: insecure-host --check produced no traceback" "! grep -q 'Traceback' '$PUR3_LOG_EXFIL'"
fi

# --- CRITICAL-1 gate-is-OFF-by-default: a SECOND record file confirms that the
# header-path-against-the-stub ONLY appears once the explicit gate is set. This is
# the path-specific falsifier for the gate branch: if a regression made the gate
# default-ON (or ignored it), the exfil run above would already RED; if a
# regression hardwired the header OFF even under the gate, the gated header-sent
# AC below would RED. The two together pin "OFF by default, ON only when gated".
PUR3_REC_GATEOFF="$PUR3_DIR/rec-gate-off.txt"
PUR3_LOG_GATEOFF="$PUR3_DIR/log-gate-off.txt"
pur3_run_check ok "$PUR3_REC_GATEOFF" "$PUR3_LOG_GATEOFF" "GITHUB_TOKEN=$PUR3_TOKEN"
PUR3_MARK_GATEOFF="$PUR3_MARK"
if pur_macos_stub_skip_active "$PUR3_MARK_GATEOFF"; then
  pur_stub_skip_notice "PUR-3 CRITICAL-1 gate-off-by-default assertion"
else
  assert "PUR-3 CRITICAL-1: insecure-token gate is OFF by default (no header to the stub absent the gate)" "! grep -q 'AUTH Bearer' '$PUR3_REC_GATEOFF'"
fi

# --- AC-PUR-03.1: with GITHUB_TOKEN set AND the explicit insecure-token gate ON,
# the request carries Authorization: Bearer <token> to the 127.0.0.1 stub. This
# keeps the real header path under test without weakening the prod invariant
# (the gate is the ONLY reason the header is allowed to a non-github host here).
# RED now ONLY for the gate semantics is not required: today the header is sent
# regardless, so this stays GREEN today and remains correct after the fix (the
# gate is honored). We assert on the RECORDED header bytes, not the env var.
PUR3_REC_TOK="$PUR3_DIR/rec-token.txt"
PUR3_LOG_TOK="$PUR3_DIR/log-token.txt"
pur3_run_check ok "$PUR3_REC_TOK" "$PUR3_LOG_TOK" "GITHUB_TOKEN=$PUR3_TOKEN" "$PUR3_INSECURE_GATE"
PUR3_MARK_TOK="$PUR3_MARK"
if pur_macos_stub_skip_active "$PUR3_MARK_TOK"; then
  pur_stub_skip_notice "PUR-3 AC-PUR-03.1/.4 GITHUB_TOKEN header block (2 assertions)"
else
  assert "PUR-3 AC-PUR-03.1: GITHUB_TOKEN + insecure-token gate sends Authorization: Bearer <token> to the stub" "grep -qF 'AUTH Bearer $PUR3_TOKEN' '$PUR3_REC_TOK'"
  # And the success path printed no leak of the token literal (success-path .4).
  PUR3_LOG_TOK_BODY="$(cat "$PUR3_LOG_TOK" 2>/dev/null || true)"
  assert_not_contains "PUR-3 AC-PUR-03.4: token NEVER printed on the authenticated success path" "$PUR3_LOG_TOK_BODY" "$PUR3_TOKEN"
fi

# --- AC-PUR-03.1 (GH_TOKEN fallback): with GITHUB_TOKEN ABSENT but GH_TOKEN set
# AND the insecure-token gate ON, the same Authorization: Bearer <token> is sent
# to the stub. We clear GITHUB_TOKEN explicitly so only GH_TOKEN can provide the
# value.
PUR3_REC_GH="$PUR3_DIR/rec-ghtoken.txt"
PUR3_LOG_GH="$PUR3_DIR/log-ghtoken.txt"
pur3_run_check ok "$PUR3_REC_GH" "$PUR3_LOG_GH" "GITHUB_TOKEN=" "GH_TOKEN=$PUR3_TOKEN" "$PUR3_INSECURE_GATE"
PUR3_MARK_GH="$PUR3_MARK"
if pur_macos_stub_skip_active "$PUR3_MARK_GH"; then
  pur_stub_skip_notice "PUR-3 AC-PUR-03.1/.4 GH_TOKEN fallback header block (2 assertions)"
else
  assert "PUR-3 AC-PUR-03.1: GH_TOKEN (no GITHUB_TOKEN) + insecure-token gate sends Authorization: Bearer <token>" "grep -qF 'AUTH Bearer $PUR3_TOKEN' '$PUR3_REC_GH'"
  PUR3_LOG_GH_BODY="$(cat "$PUR3_LOG_GH" 2>/dev/null || true)"
  assert_not_contains "PUR-3 AC-PUR-03.4: GH_TOKEN value NEVER printed on success" "$PUR3_LOG_GH_BODY" "$PUR3_TOKEN"
fi

# --- NOTE-1: a whitespace-only GITHUB_TOKEN must NOT produce a garbage
# Authorization header (no `Bearer    ` / `Bearer` with empty/blank credential).
# The insecure-token gate is ON so that IF the code wrongly treated "   " as a
# real token it WOULD send the header to the stub -- making the absence a real
# signal, not masked by the host gate. RED-or-confirming: today _github_token()
# returns a non-empty "   " (it only checks truthiness), so this would send a
# blank-credential `Bearer    ` header -> RED until the token is treated as empty
# after stripping. We require the stub to record NO Bearer header at all.
PUR3_REC_WS="$PUR3_DIR/rec-whitespace.txt"
PUR3_LOG_WS="$PUR3_DIR/log-whitespace.txt"
pur3_run_check ok "$PUR3_REC_WS" "$PUR3_LOG_WS" "GITHUB_TOKEN=   " "$PUR3_INSECURE_GATE"
PUR3_MARK_WS="$PUR3_MARK"
if pur_macos_stub_skip_active "$PUR3_MARK_WS"; then
  pur_stub_skip_notice "PUR-3 NOTE-1 whitespace-token block (3 assertions)"
else
  assert "PUR-3 NOTE-1: whitespace-only GITHUB_TOKEN sends NO Authorization header" "grep -q 'AUTH <none>' '$PUR3_REC_WS'"
  assert "PUR-3 NOTE-1: whitespace-only GITHUB_TOKEN never produces a garbage Bearer header" "! grep -q 'AUTH Bearer' '$PUR3_REC_WS'"
  assert "PUR-3 NOTE-1: whitespace-token --check still succeeds unauthenticated" "grep -q 'status:' '$PUR3_LOG_WS'"
fi

# --- AC-PUR-03.2: with NO token, the fetch still SUCCEEDS unauthenticated -- no
# crash, and the recorded request carried NO Authorization header. CONFIRMING:
# likely GREEN with today's code (it sends no header and reads the 200). We
# clear BOTH token env vars so the run is genuinely unauthenticated.
PUR3_REC_NOAUTH="$PUR3_DIR/rec-noauth.txt"
PUR3_LOG_NOAUTH="$PUR3_DIR/log-noauth.txt"
pur3_run_check ok "$PUR3_REC_NOAUTH" "$PUR3_LOG_NOAUTH" "GITHUB_TOKEN=" "GH_TOKEN="
PUR3_MARK_NOAUTH="$PUR3_MARK"
if pur_macos_stub_skip_active "$PUR3_MARK_NOAUTH"; then
  pur_stub_skip_notice "PUR-3 AC-PUR-03.2 unauthenticated block (3 assertions)"
else
  assert "PUR-3 AC-PUR-03.2: unauthenticated --check still succeeds (reports a status)" "grep -q 'status:' '$PUR3_LOG_NOAUTH'"
  assert "PUR-3 AC-PUR-03.2: unauthenticated --check produced no traceback" "! grep -q 'Traceback' '$PUR3_LOG_NOAUTH'"
  assert "PUR-3 AC-PUR-03.2: unauthenticated request carried NO Authorization header" "grep -q 'AUTH <none>' '$PUR3_REC_NOAUTH'"
fi

# --- AC-PUR-03.3: 403 rate-limit vs 404 not-found are CLASSIFIED DISTINCTLY.
# RED now: both collapse to the identical "could not reach GitHub release API"
# string. We require (a) the 403 message is a classified "rate"-limited message,
# (b) the 404 message is a "not found" message, and (c) the two messages DIFFER.
PUR3_REC_403="$PUR3_DIR/rec-403.txt"
PUR3_LOG_403="$PUR3_DIR/log-403.txt"
pur3_run_check ratelimit "$PUR3_REC_403" "$PUR3_LOG_403" "GITHUB_TOKEN=" "GH_TOKEN="
PUR3_MARK_403="$PUR3_MARK"
PUR3_REC_404="$PUR3_DIR/rec-404.txt"
PUR3_LOG_404="$PUR3_DIR/log-404.txt"
pur3_run_check notfound "$PUR3_REC_404" "$PUR3_LOG_404" "GITHUB_TOKEN=" "GH_TOKEN="
PUR3_MARK_404="$PUR3_MARK"
# The classification block depends on BOTH the 403 and 404 runs reaching the stub.
# If EITHER was unconnectable on macOS, mark the whole block STUB_NOT_READY (skip);
# any STUB_REACHABLE-on-both means it runs HARD (Linux/local).
if [ "$PUR3_MARK_403" = "STUB_REACHABLE" ] && [ "$PUR3_MARK_404" = "STUB_REACHABLE" ]; then
  PUR3_MARK_CLASS="STUB_REACHABLE"
else
  PUR3_MARK_CLASS="STUB_NOT_READY"
fi
PUR3_BODY_403="$(cat "$PUR3_LOG_403" 2>/dev/null || true)"
PUR3_BODY_404="$(cat "$PUR3_LOG_404" 2>/dev/null || true)"
# Today BOTH errors collapse to the SAME generic wrapper:
#   "could not reach GitHub release API: HTTP Error <code>: <reason>"
# That generic wrapper happens to embed urllib's reason phrase ("Not Found",
# "Forbidden"), so a naive `grep 'not found'` would FALSE-PASS against the
# unclassified string. To stay RED-for-the-right-reason we require the message
# to be a real CLASSIFICATION -- i.e. it must NOT be the generic "could not
# reach GitHub release API" passthrough. After the fix, 403 -> a rate-limit
# message and 404 -> a release/repo-not-found message, NEITHER of which is the
# generic "could not reach" wrapper.
PUR3_GENERIC="could not reach GitHub release API"
# .3a 403 is classified as rate-limited. The classification must REPLACE the
# generic wrapper (not merely be a substring inside it): we require a "rate"
# message AND that it is not the generic "could not reach" passthrough. Both
# halves combined are RED today (the message is the generic wrapper, no "rate").
# Computed as a single derived outcome so the assertion is RED-for-the-right-
# reason: it cannot pass while the message is still the unclassified passthrough.
if grep -qi 'rate' "$PUR3_LOG_403" && ! grep -qF "$PUR3_GENERIC" "$PUR3_LOG_403"; then
  pur3_403_class=ratelimited
else
  pur3_403_class=unclassified
fi
# macOS-CI loopback skip for the classification block (keys off CONNECTIVITY of
# the 403+404 runs, never off the classification outcome): on macOS-unconnectable
# the fetch never reaches the stub so classification is necessarily 'unclassified'
# -- SKIP with a tallied notice; on Linux/local both runs reach the stub and the
# classification assertions run HARD (a wrong classification is still a hard fail).
if pur_macos_stub_skip_active "$PUR3_MARK_CLASS"; then
  pur_stub_skip_notice "PUR-3 AC-PUR-03.3 403/404 classification block (4 assertions)"
else
  assert_eq "PUR-3 AC-PUR-03.3: 403 is classified as rate-limited (not the generic passthrough)" "ratelimited" "$pur3_403_class"
  # .3b 404 is classified as release/repo-not-found. Same shape: a not-found
  # phrase AND escaping the generic wrapper. RED today: the 404 string IS the
  # generic "could not reach ... HTTP Error 404: Not Found" wrapper, so the
  # not-generic half fails even though urllib's bare "Not Found" reason matches
  # the phrase -- this is exactly why the not-generic guard is ANDed in (a lone
  # phrase grep would FALSE-PASS against the unclassified urllib reason).
  if grep -qiE 'not found|not be found|no release|does not exist' "$PUR3_LOG_404" && ! grep -qF "$PUR3_GENERIC" "$PUR3_LOG_404"; then
    pur3_404_class=notfound
  else
    pur3_404_class=unclassified
  fi
  assert_eq "PUR-3 AC-PUR-03.3: 404 is classified as release/repo-not-found (not the generic passthrough)" "notfound" "$pur3_404_class"
  assert "PUR-3 AC-PUR-03.3: the 404 message is NOT a rate-limit message" "! grep -qi 'rate' '$PUR3_LOG_404'"
  # The discriminator: the two error strings must be DISTINCT *and* neither may be
  # the generic passthrough. Today they differ only by urllib's reason phrase
  # INSIDE the same generic wrapper, so a byte-compare ALONE would FALSE-PASS;
  # requiring both classified (above) AND distinct here makes it a real
  # "distinct classification" check, RED until classification actually splits them.
  if [ "$PUR3_BODY_403" != "$PUR3_BODY_404" ] && [ "$pur3_403_class" = "ratelimited" ] && [ "$pur3_404_class" = "notfound" ]; then
    pur3_distinct=distinct
  else
    pur3_distinct=not-distinct
  fi
  assert_eq "PUR-3 AC-PUR-03.3: 403 and 404 are DISTINCT classified messages (not collapsed)" "distinct" "$pur3_distinct"
fi

# --- AC-PUR-03.4 (error paths): the token is NEVER printed on the 403 or 404
# error path either. Re-run both error modes WITH the token set, and assert the
# sentinel is absent from the combined output. RED-or-confirming: today no token
# is sent so it cannot leak (confirming); it becomes a real guard once .1 lands.
# The insecure-token gate is set on these error runs so the token is genuinely
# sent to the 127.0.0.1 stub (otherwise the post-fix host gate would withhold it
# and the "guard is meaningful" belt below would be vacuous). With the token in
# play on the error paths, we then prove it is NEVER printed.
PUR3_REC_403T="$PUR3_DIR/rec-403-tok.txt"
PUR3_LOG_403T="$PUR3_DIR/log-403-tok.txt"
pur3_run_check ratelimit "$PUR3_REC_403T" "$PUR3_LOG_403T" "GITHUB_TOKEN=$PUR3_TOKEN" "$PUR3_INSECURE_GATE"
PUR3_MARK_403T="$PUR3_MARK"
PUR3_REC_404T="$PUR3_DIR/rec-404-tok.txt"
PUR3_LOG_404T="$PUR3_DIR/log-404-tok.txt"
pur3_run_check notfound "$PUR3_REC_404T" "$PUR3_LOG_404T" "GITHUB_TOKEN=$PUR3_TOKEN" "$PUR3_INSECURE_GATE"
PUR3_MARK_404T="$PUR3_MARK"
PUR3_BODY_403T="$(cat "$PUR3_LOG_403T" 2>/dev/null || true)"
PUR3_BODY_404T="$(cat "$PUR3_LOG_404T" 2>/dev/null || true)"
# The .4 error-path block depends on BOTH token-error runs reaching the stub: the
# "token actually sent" belt (and thus the meaningfulness of the leak guards) needs
# the request to have reached the 127.0.0.1 stub. Skip the whole block only when an
# error run was macOS-unconnectable; Linux/local run it HARD.
if [ "$PUR3_MARK_403T" = "STUB_REACHABLE" ] && [ "$PUR3_MARK_404T" = "STUB_REACHABLE" ]; then
  PUR3_MARK_ERRTOK="STUB_REACHABLE"
else
  PUR3_MARK_ERRTOK="STUB_NOT_READY"
fi
if pur_macos_stub_skip_active "$PUR3_MARK_ERRTOK"; then
  pur_stub_skip_notice "PUR-3 AC-PUR-03.4 error-path token-leak block (3 assertions)"
else
  assert_not_contains "PUR-3 AC-PUR-03.4: token NEVER printed on the 403 rate-limit error path" "$PUR3_BODY_403T" "$PUR3_TOKEN"
  assert_not_contains "PUR-3 AC-PUR-03.4: token NEVER printed on the 404 not-found error path" "$PUR3_BODY_404T" "$PUR3_TOKEN"
  # Belt: prove these error runs actually carried the token to the stub (so the
  # "never printed" guard is meaningful -- the token WAS in play, yet absent from
  # output). Asserted on the RECORDED header, not the env var.
  assert "PUR-3 AC-PUR-03.4: the 403 error run actually sent the token (guard is meaningful)" "grep -qF 'AUTH Bearer $PUR3_TOKEN' '$PUR3_REC_403T'"
fi

# --- PUR-3 safety belt: every path above lived under $TMP_ROOT; no real network
# (the seam pointed at a 127.0.0.1 ephemeral-port stub) and no real ~/.claude.
assert "PUR-3 safety: fetch stub dir is under TMP_ROOT (offline, sandboxed)" "case '$PUR3_DIR' in '$TMP_ROOT'/*) true ;; *) false ;; esac"

# ====================================================================
# SPRINT 2 review finding NOTE-2 -- FETCH-SIDE slug guard (CONFIRMING test;
# PASSES with current code). fetch_latest_release() validates the slug against
# REPO_SLUG_RE (^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$) BEFORE it is interpolated into
# the request path, so a malicious slug is refused with a classified error and
# NEVER touches the network. The existing I2 block (~:555) covers the anchor-WRITE
# side of slug handling; this closes the missing coverage for the FETCH-side guard
# ("a claim needs a test per branch").
#
# Driven through `update --check --repo <slug>` (no --source -> the real
# fetch_latest_release path) against a RECORDING http stub on 127.0.0.1: a refused
# slug must record ZERO hits at the stub (the guard fires before any request), and
# a VALID slug must reach the stub (proving the guard is not a blanket block).
# SANDBOX-ONLY: the stub + record files live under $TMP_ROOT (mktemp); the seam
# (PLUMBLINE_GITHUB_API) points at the local stub -> 0 real network, real ~/.claude
# never touched. bash-3.2-safe (standalone .py stub, no $()-wrapped heredocs),
# ASCII-only, eval-free.
# ====================================================================
NOTE2_DIR="$TMP_ROOT/note2-slug-stub"
mkdir -p "$NOTE2_DIR"
NOTE2_STUB_PY="$NOTE2_DIR/stub.py"
# Recording stub: appends every requested path to <record-file> and returns a
# valid release JSON so a VALID-slug --check completes offline. Standalone file
# (NOT a $()-wrapped heredoc -- bash 3.2 / macOS CI mis-parses those).
cat > "$NOTE2_STUB_PY" <<'PYEOF'
import sys, json, http.server
recfile, portfile = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(recfile, "a") as f:
            f.write("PATH " + self.path + "\n")
        body = json.dumps({"tag_name": "v0.0.1", "draft": False, "prerelease": False}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(portfile, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PYEOF

# note2_check <slug> <record-file> <stdout+stderr-log-file>
# Boots the recording stub, runs `update --check --repo <slug>` against it via the
# seam, captures combined output + exit status, then tears the stub down. Sets
# NOTE2_STATUS to the CLI exit code. bash-3.2-safe port polling; no $()-heredocs.
#
# Sets NOTE2_MARK to a CONNECTIVITY-ONLY marker (STUB_REACHABLE / STUB_NOT_READY)
# for the macOS-CI loopback skip: STUB_NOT_READY when no port file appeared OR the
# bound port was unconnectable (the macOS-CI-runner limitation). Linux/local reach
# the stub -> STUB_REACHABLE -> assertions run HARD. Never keyed off the outcome.
NOTE2_MARK=""
note2_check() {
  note2_slug="$1"; note2_rec="$2"; note2_log="$3"
  : > "$note2_rec"
  note2_portfile="$NOTE2_DIR/port.txt"
  rm -f "$note2_portfile"
  python3 "$NOTE2_STUB_PY" "$note2_rec" "$note2_portfile" >"$NOTE2_DIR/stub.log" 2>&1 &
  note2_pid=$!
  note2_wait=0
  while [ ! -s "$note2_portfile" ] && [ "$note2_wait" -lt 50 ]; do
    sleep 0.1
    note2_wait=$((note2_wait + 1))
  done
  note2_port="$(cat "$note2_portfile" 2>/dev/null || true)"
  NOTE2_STATUS=0
  NOTE2_MARK="STUB_NOT_READY"
  if [ -n "$note2_port" ]; then
    NOTE2_MARK="$(pur_stub_reachable 127.0.0.1 "$note2_port")"
    if PLUMBLINE_GITHUB_API="http://127.0.0.1:$note2_port" \
      "$PLUMBLINE" --root "$REPO_DIR" update --check --repo "$note2_slug" \
      >"$note2_log" 2>&1; then
      NOTE2_STATUS=0
    else
      NOTE2_STATUS=$?
    fi
  else
    printf 'STUB_NOT_READY\n' > "$note2_log"
    NOTE2_STATUS=127
  fi
  kill "$note2_pid" 2>/dev/null || true
  wait "$note2_pid" 2>/dev/null || true
}

# Malicious slugs -- each must be REFUSED (non-zero), classified as an invalid
# slug, and record ZERO hits at the stub (the guard fires before any request).
for note2_evil in '../../etc/passwd' 'owner/repo/extra' 'owner/repo?x=1'; do
  note2_rec="$NOTE2_DIR/rec-evil.txt"
  note2_logf="$NOTE2_DIR/log-evil.txt"
  note2_check "$note2_evil" "$note2_rec" "$note2_logf"
  # macOS-CI loopback skip: the slug guard is verified offline (it refuses BEFORE
  # any fetch), but `note2_check` can only run the CLI once the stub is usable;
  # when the macOS runner cannot boot/connect the stub (NOTE2_MARK=STUB_NOT_READY)
  # the CLI never runs (exit 127) so we SKIP with a tallied notice. Linux/local
  # reach the stub -> the guard assertions run HARD. Keyed off connectivity only.
  if pur_macos_stub_skip_active "$NOTE2_MARK"; then
    pur_stub_skip_notice "PUR-3 NOTE-2 malicious slug '$note2_evil' guard block (4 assertions)"
  else
    assert_eq "PUR-3 NOTE-2: malicious slug '$note2_evil' is refused (non-zero exit)" "1" "$NOTE2_STATUS"
    assert "PUR-3 NOTE-2: malicious slug '$note2_evil' reports a classified invalid-slug error" "grep -qi 'invalid GitHub repo slug' '$note2_logf'"
    # ZERO network: the recording stub must have logged no requested path at all.
    assert "PUR-3 NOTE-2: malicious slug '$note2_evil' triggers NO network request (stub records zero hits)" "test ! -s '$note2_rec'"
    # And the classified refusal is not the generic transport wrapper (it never reached the network).
    assert "PUR-3 NOTE-2: malicious slug '$note2_evil' is NOT a generic could-not-reach error" "! grep -qF 'could not reach GitHub release API' '$note2_logf'"
  fi
done

# A VALID slug (exercising the full permitted charset: dots, dashes, digits) must
# PASS the guard and actually reach the stub -- proving the guard is a real filter,
# not a blanket block ("a test that still passes with the branch deleted does not
# cover it": this VALID-slug leg fails if the regex were tightened to reject it).
NOTE2_REC_OK="$NOTE2_DIR/rec-ok.txt"
NOTE2_LOG_OK="$NOTE2_DIR/log-ok.txt"
note2_check 'owner/repo.name-1' "$NOTE2_REC_OK" "$NOTE2_LOG_OK"
if pur_macos_stub_skip_active "$NOTE2_MARK"; then
  pur_stub_skip_notice "PUR-3 NOTE-2 valid-slug-reaches-stub block (4 assertions)"
else
  assert_eq "PUR-3 NOTE-2: valid slug 'owner/repo.name-1' passes the guard (exit 0)" "0" "$NOTE2_STATUS"
  assert "PUR-3 NOTE-2: valid slug 'owner/repo.name-1' DOES reach the stub (request recorded)" "test -s '$NOTE2_REC_OK'"
  assert "PUR-3 NOTE-2: valid slug request path carries the slug to the GitHub releases endpoint" "grep -q '/repos/owner/repo.name-1/releases/latest' '$NOTE2_REC_OK'"
  assert "PUR-3 NOTE-2: valid slug --check produced no traceback" "! grep -q 'Traceback' '$NOTE2_LOG_OK'"
fi

# ====================================================================
# SPRINT 2 review finding (gh-fallback branch) -- _github_token() resolves
# GITHUB_TOKEN -> GH_TOKEN -> `gh auth token`, and the subtle UNDEFINED-vs-empty
# rule: the `gh` fallback is consulted ONLY when NEITHER token env var is defined;
# a DEFINED-but-empty value is an explicit "unauthenticated" opt-out that
# SUPPRESSES the `gh` fallback. This branch was only manually verified -- this
# CONFIRMING test pins both halves (PASSES with current code).
#
# Driven against a STUB `gh` on a temp PATH (a tiny script that prints a sentinel
# token) plus the RECORDING http stub, with the insecure-token gate ON so the
# Authorization header is allowed to reach the 127.0.0.1 stub (otherwise the prod
# host gate would withhold it and these branch assertions would be vacuous). We
# assert on the header the stub RECORDED, never on any env var the test set.
# SANDBOX-ONLY: the stub gh, temp PATH, stub, and record files all live under
# $TMP_ROOT (mktemp); the real `gh` is NEVER invoked and real ~/.claude is never
# touched. bash-3.2-safe (standalone .py stub, no $()-wrapped heredocs),
# ASCII-only, eval-free.
# ====================================================================
GHFB_DIR="$TMP_ROOT/ghfallback"
GHFB_BIN="$GHFB_DIR/bin"
mkdir -p "$GHFB_BIN"
# A UNIQUE, easily-greppable sentinel so the header assertion is unambiguous.
GHFB_TOKEN="ghp_GHFB_STUB_SENTINEL_0123456789abcdefXYZ"
# Stub `gh`: only `gh auth token` prints the sentinel; everything else exits 1.
cat > "$GHFB_BIN/gh" <<'GHEOF'
#!/usr/bin/env bash
if [ "$1" = "auth" ] && [ "$2" = "token" ]; then
  printf '%s\n' "ghp_GHFB_STUB_SENTINEL_0123456789abcdefXYZ"
  exit 0
fi
exit 1
GHEOF
chmod +x "$GHFB_BIN/gh"
# Safety belt: the stub gh + temp PATH live under $TMP_ROOT (real gh untouched).
assert "GH-FALLBACK safety: stub gh + temp PATH are under TMP_ROOT (real gh never invoked)" "case '$GHFB_BIN' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
assert_file "GH-FALLBACK precondition: stub gh exists and is executable" "$GHFB_BIN/gh"

# Recording stub: appends the Authorization header value it received to a record
# file, returns valid release JSON. Standalone .py (no $()-wrapped heredoc).
GHFB_STUB_PY="$GHFB_DIR/stub.py"
cat > "$GHFB_STUB_PY" <<'PYEOF'
import sys, json, http.server
recfile, portfile = sys.argv[1], sys.argv[2]
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        auth = self.headers.get("Authorization", "<none>")
        with open(recfile, "a") as f:
            f.write("AUTH " + auth + "\n")
        body = json.dumps({"tag_name": "v0.0.1", "draft": False, "prerelease": False}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
    def log_message(self, *a):
        pass
srv = http.server.HTTPServer(("127.0.0.1", 0), H)
with open(portfile, "w") as f:
    f.write(str(srv.server_address[1]))
srv.serve_forever()
PYEOF

# ghfb_run_check <record-file> <log-file> <env-assignment ...>
# Boots the recording stub, runs `update --check` against it via the seam with the
# stub gh PREPENDED to PATH and the supplied leading ENV assignments, captures
# combined output, tears the stub down. The insecure-token gate is always set so
# the header (if the code resolves one) reaches the 127.0.0.1 stub. We use `env`
# with explicit -u to make GITHUB_TOKEN / GH_TOKEN genuinely UNDEFINED when asked.
#
# Sets GHFB_MARK to a CONNECTIVITY-ONLY marker (STUB_REACHABLE / STUB_NOT_READY)
# for the macOS-CI loopback skip; STUB_NOT_READY when no port file appeared OR the
# bound port is unconnectable. Linux/local reach the stub -> HARD. Never the outcome.
GHFB_MARK=""
ghfb_run_check() {
  ghfb_rec="$1"; ghfb_log="$2"; shift 2
  : > "$ghfb_rec"
  ghfb_portfile="$GHFB_DIR/port.txt"
  rm -f "$ghfb_portfile"
  python3 "$GHFB_STUB_PY" "$ghfb_rec" "$ghfb_portfile" >"$GHFB_DIR/stub.log" 2>&1 &
  ghfb_pid=$!
  ghfb_wait=0
  while [ ! -s "$ghfb_portfile" ] && [ "$ghfb_wait" -lt 50 ]; do
    sleep 0.1
    ghfb_wait=$((ghfb_wait + 1))
  done
  ghfb_port="$(cat "$ghfb_portfile" 2>/dev/null || true)"
  GHFB_MARK="STUB_NOT_READY"
  if [ -n "$ghfb_port" ]; then
    GHFB_MARK="$(pur_stub_reachable 127.0.0.1 "$ghfb_port")"
    env "$@" PATH="$GHFB_BIN:$PATH" \
      PLUMBLINE_GITHUB_API_ALLOW_INSECURE_TOKEN=1 \
      PLUMBLINE_GITHUB_API="http://127.0.0.1:$ghfb_port" \
      "$PLUMBLINE" --root "$REPO_DIR" update --check --repo DYAI2025/Plumbline \
      >"$ghfb_log" 2>&1 || true
  else
    printf 'STUB_NOT_READY\n' > "$ghfb_log"
  fi
  kill "$ghfb_pid" 2>/dev/null || true
  wait "$ghfb_pid" 2>/dev/null || true
}

# (a) BOTH GITHUB_TOKEN and GH_TOKEN UNDEFINED -> the stub gh IS consulted and its
# sentinel token is used: the stub records `Authorization: Bearer <gh-sentinel>`.
GHFB_REC_A="$GHFB_DIR/rec-a.txt"
GHFB_LOG_A="$GHFB_DIR/log-a.txt"
ghfb_run_check "$GHFB_REC_A" "$GHFB_LOG_A" -u GITHUB_TOKEN -u GH_TOKEN
GHFB_MARK_A="$GHFB_MARK"
if pur_macos_stub_skip_active "$GHFB_MARK_A"; then
  pur_stub_skip_notice "GH-FALLBACK (a) gh-token-sent block (4 assertions)"
else
  assert "GH-FALLBACK (a): both token env vars UNDEFINED -> stub gh token is sent as Bearer <sentinel>" "grep -qF 'AUTH Bearer $GHFB_TOKEN' '$GHFB_REC_A'"
  assert "GH-FALLBACK (a): unauthenticated-marker is absent (the gh fallback DID supply a token)" "! grep -q 'AUTH <none>' '$GHFB_REC_A'"
  GHFB_BODY_A="$(cat "$GHFB_LOG_A" 2>/dev/null || true)"
  assert_not_contains "GH-FALLBACK (a): gh sentinel token is NEVER printed on the success path" "$GHFB_BODY_A" "$GHFB_TOKEN"
  assert "GH-FALLBACK (a): --check via gh-fallback still succeeds (reports a status)" "grep -q 'status:' '$GHFB_LOG_A'"
fi

# (b) GITHUB_TOKEN="" (DEFINED-but-empty) -> explicit unauthenticated opt-out: the
# `gh` fallback is SUPPRESSED, so NO Authorization header / gh sentinel is sent.
# (GH_TOKEN left undefined so only the GITHUB_TOKEN-empty path governs.) This is
# the path-specific falsifier for the undefined-vs-empty branch: it FAILS the
# instant the code regresses to consulting `gh` despite a deliberately-cleared var.
GHFB_REC_B="$GHFB_DIR/rec-b.txt"
GHFB_LOG_B="$GHFB_DIR/log-b.txt"
ghfb_run_check "$GHFB_REC_B" "$GHFB_LOG_B" -u GH_TOKEN GITHUB_TOKEN=""
GHFB_MARK_B="$GHFB_MARK"
if pur_macos_stub_skip_active "$GHFB_MARK_B"; then
  pur_stub_skip_notice "GH-FALLBACK (b) suppress-fallback block (4 assertions)"
else
  assert "GH-FALLBACK (b): defined-but-empty GITHUB_TOKEN SUPPRESSES the gh fallback (no Authorization header)" "grep -q 'AUTH <none>' '$GHFB_REC_B'"
  assert "GH-FALLBACK (b): defined-but-empty GITHUB_TOKEN sends NO Bearer header at all" "! grep -q 'AUTH Bearer' '$GHFB_REC_B'"
  assert "GH-FALLBACK (b): the gh sentinel token is absent from the recorded request" "! grep -qF '$GHFB_TOKEN' '$GHFB_REC_B'"
  assert "GH-FALLBACK (b): opted-out --check still succeeds unauthenticated (reports a status)" "grep -q 'status:' '$GHFB_LOG_B'"
fi

# Safety belt: every path in the two blocks above lived under $TMP_ROOT; the seam
# pointed at a 127.0.0.1 ephemeral-port stub (0 real network) and the real gh /
# real ~/.claude were never touched.
assert "PUR-3 NOTE-2 + GH-FALLBACK safety: stub dirs are under TMP_ROOT (offline, sandboxed)" "case '$NOTE2_DIR' in '$TMP_ROOT'/*) case '$GHFB_DIR' in '$TMP_ROOT'/*) true ;; *) false ;; esac ;; *) false ;; esac"

# ====================================================================
# SPRINT 3 (PUR-3.1): the HEADLINE RED acceptance contract --
# `plumbline update` ACTUALLY installs all new content into $CLAUDE_HOME,
# verified-or-reverted. REQ-PUR-04 (real apply into $CLAUDE_HOME via the REAL
# installer) + REQ-PUR-05 (install update-mode REFRESHES changed targets, no
# stale skip; adds new files) + REQ-PUR-06 (snapshot + verify-or-revert) +
# REQ-PUR-01 (anchor re-stamp on apply). ACs: AC-PUR-04.1/.2/.4, AC-PUR-05.1/.2,
# AC-PUR-06.1.
#
# This is the value falsifier the existing 142 assertions DO NOT cover: every
# apply test above uses an explicit `--target <fixture-checkout>` (checkout-patch
# mode) and never an actual INSTALLED $CLAUDE_HOME. The Gegenthese this kills:
# "the apply flow is green, yet a real user's ~/.claude is never refreshed" --
# because today (a) the no-`--target` apply resolves target = root = cwd (NEVER
# $CLAUDE_HOME), (b) install.sh transfer() SKIPS existing targets without --force
# (so a stale installed file is never overwritten), and (c) update_apply only
# runs `install.sh --dry-run` against the checkout -- nothing is written into the
# installed home. So the assertions below are RED-for-the-right-reason today and
# go GREEN only when PUR-3.2 (install.sh --update content-compare+overwrite) and
# PUR-3.3 (no-`--target` apply runs the REAL install.sh --update into
# $CLAUDE_HOME, verify-or-revert) land.
#
# DRIVEN THROUGH THE PRODUCTION COMPOSITION PATH: the INSTALLED CLI
# ($CLAUDE_HOME/bin/plumbline) drives the REAL install.sh into a real (sandbox)
# $CLAUDE_HOME -- not a hand-built harness. Offline only: the vN+1 payload is
# staged via the OFFLINE `--source` seam (a throwaway checkout under $TMP_ROOT),
# never the network.
#
# SANDBOX-ONLY (NFR-PUR-01, binding): every path lives under $TMP_ROOT (mktemp);
# CLAUDE_HOME is a sandbox dir under $TMP_ROOT; a safety belt asserts the real
# ~/.claude is NEVER written (its pre-test mtime/listing is captured and required
# unchanged). bash-3.2-safe (NO $()-wrapped heredocs anywhere in this block;
# every heredoc is redirected to a file then read back), ASCII-only, eval-free.
# ====================================================================

# vN (install-time) and vN+1 (the staged payload) -- synthesized relative to the
# repo version so the block survives every release bump (no hardcoded literal).
PUR3S_VN="$REPO_VERSION"
PUR3S_VN1="$(awk -F. -v OFS=. '{print $1, $2+1, 0}' <<<"$REPO_VERSION")"

# Safety belt #1: capture the REAL ~/.claude state BEFORE anything runs, so we can
# prove at the end that this whole block never wrote to it. We snapshot a sorted
# listing + the dir's own mtime. If ~/.claude does not exist, both markers are the
# empty/absent string and must STAY that way.
PUR3S_REAL_HOME="$HOME/.claude"
PUR3S_REAL_LIST_BEFORE="$TMP_ROOT/pur3s-real-list-before.txt"
PUR3S_REAL_LIST_AFTER="$TMP_ROOT/pur3s-real-list-after.txt"
if [ -d "$PUR3S_REAL_HOME" ]; then
  # shellcheck disable=SC2012  # a sorted name listing is exactly the change-detector we want
  ( ls -A "$PUR3S_REAL_HOME" 2>/dev/null | sort ) > "$PUR3S_REAL_LIST_BEFORE" 2>/dev/null || : > "$PUR3S_REAL_LIST_BEFORE"
  # shellcheck disable=SC2012  # capturing the dir's own stat line (mtime) as a tamper marker
  PUR3S_REAL_MTIME_BEFORE="$(ls -ld "$PUR3S_REAL_HOME" 2>/dev/null || true)"
else
  : > "$PUR3S_REAL_LIST_BEFORE"
  PUR3S_REAL_MTIME_BEFORE="<absent>"
fi

# build_pur3s_source <src-dir> <version> <agent-marker> <command-marker> <lib-extra-marker> <new-file-rel-or-empty>
# Assemble an install-capable Plumbline source tree at <src-dir>: the REAL
# install.sh + lib + bin (so the installed CLI and the apply path are the prod
# code), plus a controllable AGENT (markdown with a `name:` key so install.sh
# mounts it), a controllable COMMAND, and a controllable extra LIB file carrying
# <lib-extra-marker>. VERSION + compatibility.json are stamped to <version>. When
# <new-file-rel-or-empty> is non-empty, an extra agent file is added at that path
# (the "NEW file added on update" case). A git origin (canonical Plumbline) is
# set so the anchor slug is well-formed. No $()-wrapped heredocs.
build_pur3s_source() {
  pur3s_src="$1"; pur3s_ver="$2"; pur3s_agentmark="$3"
  pur3s_cmdmark="$4"; pur3s_libmark="$5"; pur3s_newrel="$6"
  mkdir -p "$pur3s_src/config/claude/lib" "$pur3s_src/config/claude/bin" \
           "$pur3s_src/config/claude/commands" \
           "$pur3s_src/config/claude/tests" \
           "$pur3s_src/agents"
  printf '%s\n' "$pur3s_ver" > "$pur3s_src/VERSION"
  printf '{\n  "version": "%s",\n  "schema": 1,\n  "verifyCommand": "true",\n  "frozenContracts": ["VERSION"],\n  "migrations": []\n}\n' "$pur3s_ver" > "$pur3s_src/compatibility.json"
  # The REAL prod code: installed CLI + apply lib + the installer under test.
  cp "$REPO_DIR/config/claude/install.sh" "$pur3s_src/config/claude/install.sh"
  cp "$REPO_DIR/config/claude/lib/plumbline_update.py" "$pur3s_src/config/claude/lib/plumbline_update.py"
  cp "$REPO_DIR/config/claude/bin/plumbline" "$pur3s_src/config/claude/bin/plumbline" 2>/dev/null || true
  chmod +x "$pur3s_src/config/claude/install.sh" "$pur3s_src/config/claude/bin/plumbline" 2>/dev/null || true
  # A controllable agent (the `name:` frontmatter key is what makes install.sh
  # mount it under $CLAUDE_HOME/agents/...). Its body carries the version marker.
  printf '%s\n%s\n%s\n\n%s\n' '---' 'name: pur3s-stale-agent' '---' "MARKER $pur3s_agentmark" \
    > "$pur3s_src/agents/pur3s-stale-agent.md"
  # A controllable command + an extra lib file, both carrying their markers.
  printf '%s\n%s\n' '# pur3s command' "MARKER $pur3s_cmdmark" \
    > "$pur3s_src/config/claude/commands/pur3s-stale-command.md"
  printf '%s\n%s\n' '# pur3s extra lib' "MARKER = '$pur3s_libmark'" \
    > "$pur3s_src/config/claude/lib/pur3s_extra.py"
  # A stub run_all.sh so the payload's tree is self-consistent (never executed by
  # these assertions; the apply uses --verify-cmd or DEFAULT_VERIFY explicitly).
  printf '%s\n%s\n' '#!/usr/bin/env bash' 'exit 0' > "$pur3s_src/config/claude/tests/run_all.sh"
  chmod +x "$pur3s_src/config/claude/tests/run_all.sh"
  # Optional NEW file (absent from the vN install; appears only in the vN+1 payload).
  # An agent (it carries a `name:` key) so install.sh's --update path would mount it.
  if [ -n "$pur3s_newrel" ]; then
    mkdir -p "$pur3s_src/$(dirname "$pur3s_newrel")"
    printf '%s\n%s\n%s\n\n%s\n' '---' 'name: pur3s-new-agent' '---' "MARKER NEWFILE $pur3s_ver" \
      > "$pur3s_src/$pur3s_newrel"
  fi
  git -C "$pur3s_src" init -q
  git -C "$pur3s_src" remote add origin "https://github.com/DYAI2025/Plumbline.git"
}

# pur3s_installed_paths -- the relative paths install.sh writes for our controlled
# artifacts (agents keep their repo-relative path; commands/libs are basename'd).
PUR3S_AGENT_REL="agents/agents/pur3s-stale-agent.md"   # $CLAUDE_HOME/agents/<repo-rel>
PUR3S_CMD_REL="commands/pur3s-stale-command.md"
PUR3S_LIB_REL="lib/pur3s_extra.py"
PUR3S_NEW_SRC_REL="agents/pur3s-new-agent.md"          # path inside the payload tree
PUR3S_NEW_INSTALLED_REL="agents/agents/pur3s-new-agent.md"

# run_pur3s_scenario <mode-flag> <label> -- install a sandbox $CLAUDE_HOME at vN
# from a throwaway vN source, make it stale, stage a vN+1 payload, run the natural
# `plumbline update` (no --target, no --root, from a neutral cwd) through the
# INSTALLED CLI, and assert refresh + add + re-stamp. <mode-flag> is "" for the
# DEFAULT symlink mode or "--copy" for copy mode (REQ-PUR-05: both modes refresh).
run_pur3s_scenario() {
  pur3s_modeflag="$1"; pur3s_label="$2"
  pur3s_base="$TMP_ROOT/pur3s-$pur3s_label"
  pur3s_vnsrc="$pur3s_base/vN-src"
  pur3s_home="$pur3s_base/home"
  pur3s_pay="$pur3s_base/vN1-payload"

  # vN source: agent/command/lib carry the "vN" marker; NO new file yet.
  build_pur3s_source "$pur3s_vnsrc" "$PUR3S_VN" "vN-AGENT" "vN-COMMAND" "vN-LIB" ""
  # Install it into the sandbox HOME through the REAL install.sh (prod path). The
  # whole install (agents + commands + bin/lib + anchor) lands at vN. Hooks off
  # (no jq/settings churn); agents/commands/skills ON so our controlled artifacts
  # actually get mounted.
  # shellcheck disable=SC2086
  CLAUDE_HOME="$pur3s_home" "$pur3s_vnsrc/config/claude/install.sh" $pur3s_modeflag --no-hook --no-skills --force \
    >"$pur3s_base/install.log" 2>&1
  pur3s_cli="$pur3s_home/bin/plumbline"
  assert_file "PUR-3.1 ($pur3s_label): installed plumbline wrapper exists in sandbox HOME" "$pur3s_cli"
  assert "PUR-3.1 ($pur3s_label) safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$pur3s_home' in '$TMP_ROOT'/*) true ;; *) false ;; esac"

  # Preconditions: the vN content is actually installed and marked vN (so a later
  # "refreshed to vN+1" assertion has a real stale state to overwrite -- this is
  # what makes the refresh assertion RED-for-the-right-reason, not vacuous).
  pur3s_agent_inst="$pur3s_home/$PUR3S_AGENT_REL"
  pur3s_cmd_inst="$pur3s_home/$PUR3S_CMD_REL"
  pur3s_lib_inst="$pur3s_home/$PUR3S_LIB_REL"
  pur3s_new_inst="$pur3s_home/$PUR3S_NEW_INSTALLED_REL"
  assert_file "PUR-3.1 ($pur3s_label) precondition: vN agent is installed in HOME" "$pur3s_agent_inst"
  assert "PUR-3.1 ($pur3s_label) precondition: installed agent carries the STALE vN marker" "grep -q 'MARKER vN-AGENT' '$pur3s_agent_inst'"
  assert_file "PUR-3.1 ($pur3s_label) precondition: vN command is installed in HOME" "$pur3s_cmd_inst"
  assert "PUR-3.1 ($pur3s_label) precondition: installed command carries the STALE vN marker" "grep -q 'MARKER vN-COMMAND' '$pur3s_cmd_inst'"
  assert_file "PUR-3.1 ($pur3s_label) precondition: vN extra lib is installed in HOME" "$pur3s_lib_inst"
  assert "PUR-3.1 ($pur3s_label) precondition: installed lib carries the STALE vN marker" "grep -q 'vN-LIB' '$pur3s_lib_inst'"
  assert "PUR-3.1 ($pur3s_label) precondition: NEW agent is ABSENT before update" "test ! -e '$pur3s_new_inst'"
  pur3s_anchor="$pur3s_home/.plumbline-install.json"
  assert_file "PUR-3.1 ($pur3s_label) precondition: anchor written at install (vN)" "$pur3s_anchor"
  assert "PUR-3.1 ($pur3s_label) precondition: anchor reads vN before update" "grep -q '\"$PUR3S_VN\"' '$pur3s_anchor'"

  # CRITICAL anti-false-green guard. In SYMLINK mode the installed agent is a
  # symlink INTO the vN source checkout. Today's no-`--target` apply resolves its
  # target via repo_root() to the SYMLINKED SOURCE (it finds install.sh there),
  # so it POLLUTES the source (copies the vN+1 payload over $pur3s_vnsrc) -- and
  # the installed symlink then reads vN+1 by accident, NOT via a real apply into
  # $CLAUDE_HOME. That would FALSE-PASS the refresh content assertions. To keep
  # them RED-for-the-right-reason we (1) snapshot the vN source state now and
  # assert below it is LEFT UNTOUCHED by the update (the apply must write HOME, not
  # the source -- RED today: the source IS mutated vN->vN+1), and (2) require the
  # refresh content assertions AND source-immutability together, so the only
  # honest way content can be vN+1 at the installed path is a genuine HOME apply.
  pur3s_src_ver_before="$(cat "$pur3s_vnsrc/VERSION" 2>/dev/null || true)"
  pur3s_src_agent_before="$pur3s_base/src-agent-before.md"
  cp "$pur3s_vnsrc/agents/pur3s-stale-agent.md" "$pur3s_src_agent_before"

  # Stage the vN+1 payload (offline --source seam): SAME agent/command/lib paths
  # with the vN+1 marker, PLUS a NEW agent file absent at vN.
  build_pur3s_source "$pur3s_pay" "$PUR3S_VN1" "vN1-AGENT" "vN1-COMMAND" "vN1-LIB" "$PUR3S_NEW_SRC_REL"
  assert "PUR-3.1 ($pur3s_label) safety: vN+1 payload is under TMP_ROOT (offline staging)" "case '$pur3s_pay' in '$TMP_ROOT'/*) true ;; *) false ;; esac"

  # THE NATURAL UPDATE: installed CLI, NO --target, NO --root, from a NEUTRAL cwd
  # (/tmp), CLAUDE_HOME = the sandbox HOME, payload via the offline --source seam,
  # verify forced to `true` so refresh/add/re-stamp are isolated from verify here
  # (the revert path is exercised separately below). This is the production
  # composition path: $CLAUDE_HOME/bin/plumbline -> plumbline_update.py ->
  # install.sh into $CLAUDE_HOME.
  ( cd /tmp && CLAUDE_HOME="$pur3s_home" "$pur3s_cli" update --source "$pur3s_pay" --verify-cmd true \
      >"$pur3s_base/update.log" 2>&1 ) || true

  # ANTI-FALSE-GREEN: the apply must NOT mutate the throwaway vN SOURCE checkout --
  # it must write into $CLAUDE_HOME. RED today: the no-`--target` apply targets the
  # symlinked SOURCE (repo_root finds install.sh there) and pollutes it
  # (VERSION + agent flipped vN->vN+1). These assertions are what keep the symlink
  # refresh assertions below from false-passing via source pollution.
  assert_eq "PUR-3.1 ($pur3s_label) anti-false-green: vN SOURCE VERSION UNTOUCHED by the apply (apply writes HOME, not the source)" "$pur3s_src_ver_before" "$(cat "$pur3s_vnsrc/VERSION" 2>/dev/null || true)"
  assert "PUR-3.1 ($pur3s_label) anti-false-green: vN SOURCE agent content UNTOUCHED by the apply" "diff '$pur3s_src_agent_before' '$pur3s_vnsrc/agents/pur3s-stale-agent.md' >/dev/null 2>&1"

  # AC-PUR-04.1 / AC-PUR-05.1 -- the STALE installed files are REFRESHED to vN+1
  # content (content-compare + overwrite), proving a REAL apply into $CLAUDE_HOME
  # (not a dry-run of a checkout, and not source pollution). RED today: transfer()
  # skips existing targets AND the no-target apply targets the source/cwd, so the
  # installed files stay vN (copy mode) or only change via source pollution
  # (symlink mode) -- which the anti-false-green guards above redden.
  assert "PUR-3.1 ($pur3s_label) AC-PUR-05.1: STALE agent REFRESHED to vN+1 in HOME" "grep -q 'MARKER vN1-AGENT' '$pur3s_agent_inst'"
  assert "PUR-3.1 ($pur3s_label) AC-PUR-05.1: STALE agent no longer carries the vN marker" "! grep -q 'MARKER vN-AGENT' '$pur3s_agent_inst'"
  assert "PUR-3.1 ($pur3s_label) AC-PUR-05.1: STALE command REFRESHED to vN+1 in HOME" "grep -q 'MARKER vN1-COMMAND' '$pur3s_cmd_inst'"
  assert "PUR-3.1 ($pur3s_label) AC-PUR-05.1: STALE extra lib REFRESHED to vN+1 in HOME" "grep -q 'vN1-LIB' '$pur3s_lib_inst'"

  # AC-PUR-05.2 -- a NEW file in the payload now EXISTS in $CLAUDE_HOME.
  assert "PUR-3.1 ($pur3s_label) AC-PUR-05.2: NEW agent from the payload is ADDED to HOME" "test -e '$pur3s_new_inst'"
  assert "PUR-3.1 ($pur3s_label) AC-PUR-05.2: added NEW agent carries the vN+1 NEWFILE marker" "grep -q 'MARKER NEWFILE $PUR3S_VN1' '$pur3s_new_inst' 2>/dev/null || false"

  # AC-PUR-01 / REQ-PUR-01 re-stamp -- the anchor now reads vN+1 (apply re-stamps
  # install identity). RED today: the apply never re-runs the installer into HOME,
  # so the anchor stays vN.
  assert "PUR-3.1 ($pur3s_label) AC-PUR-04.2 / REQ-PUR-01: anchor RE-STAMPED to vN+1 after update" "grep -q '\"$PUR3S_VN1\"' '$pur3s_anchor'"
  assert "PUR-3.1 ($pur3s_label) AC-PUR-04.2: anchor no longer reads the stale vN" "! grep -q '\"$PUR3S_VN\"' '$pur3s_anchor'"

  # AC-PUR-04.4 sandbox belt for THIS scenario: the apply wrote into the sandbox
  # HOME (it changed) AND the sandbox HOME is the only home touched.
  assert "PUR-3.1 ($pur3s_label) AC-PUR-04.1: the update actually WROTE into the sandbox HOME (content changed)" "grep -q 'MARKER vN1-AGENT' '$pur3s_agent_inst'"
}

# The natural `plumbline update` headline (refresh + add + anchor re-stamp, and the
# verify-or-revert block below) runs for the COPY install ONLY. The confirmed two-mode
# model (PRD :124-125) is: COPY installs update via `plumbline update`; SYMLINK installs
# update via `git pull`. CR-1 (below) is authoritative and asserts `plumbline update` on
# a SYMLINK install is REFUSED -> git pull, install unchanged, still tracks the live
# checkout. A symlink arm here that asserted `plumbline update` REFRESHES (copy-converts)
# a symlink install would directly CONTRADICT CR-1 and destroy the live-checkout tracking
# the two-mode decision exists to preserve -- so it was REMOVED as superseded (and is
# redundant: the symlink-via-`plumbline update` REFUSAL is fully covered by CR-1).
#
# REQ-PUR-05's "content-compare + overwrite in BOTH modes" claim (OQ-PUR-01) is preserved
# HONESTLY at the layer it actually applies: NOT the CLI's two-mode gating, but the
# install.sh --update MECHANISM, which handles BOTH symlink and copy TARGETS. That is
# covered by the direct `install.sh --update` against a SYMLINK-target $CLAUDE_HOME below
# (run_inst_update_symlink_target), distinct from the CLI's `plumbline update` gating.
run_pur3s_scenario "--copy" "copy"

# ====================================================================
# PUR-3.1 (c') -- REQ-PUR-05 / OQ-PUR-01: the install.sh --update MECHANISM
# content-compares + overwrites a CHANGED target, idempotently SKIPS an unchanged
# one, and ADDS a new file against a SYMLINK-mode $CLAUDE_HOME too. This is the
# HONEST "both modes" coverage at the layer the claim actually applies: install.sh
# --update handles BOTH symlink and copy TARGETS, which is DISTINCT from the CLI's
# two-mode gating (`plumbline update` = copy installs only; symlink installs =
# `git pull`, enforced by CR-1 below).
#
# Deliberately NOT driven through `plumbline update` (which CR-1 requires to REFUSE
# a symlink install): this exercises the installer MECHANISM directly -- the REAL
# install.sh --update run against a symlink-mode $CLAUDE_HOME -- so it neither
# contradicts CR-1 nor re-tests the now-removed symlink-via-`plumbline update`
# refresh. The copy-TARGET half of OQ-PUR-01 is already proven by the copy headline
# scenario above (which DOES route through the natural `plumbline update`); this
# block closes the symlink-TARGET half of the MECHANISM without touching the CLI gate.
#
# CONSTRUCTION (so the assertions reach the content-compare branch they intend to
# test -- not a different branch that vacuously passes). The home is a real
# symlink-mode install (CLI + lib are symlinks into the source -> proves the mode).
# install.sh's symlink-mode update treats an EXISTING SYMLINK target as a live link
# and keeps it (that is the symlink semantic the two-mode model preserves), so to
# exercise content-compare we plant TWO REAL-FILE targets at install-paths in the
# symlink-mode home: (1) a STALE real file (different content from the source) which
# --update MUST content-compare, find changed, and OVERWRITE to vN+1 content; and
# (2) an UP-TO-DATE real file (byte-identical to the source) which --update MUST
# content-compare and SKIP (proving compare, not blind overwrite). The vN+1 source
# also carries a NEW agent absent before, which --update MUST ADD.
# RED-if-the-mechanism-regressed: if --update reverted to the old "skip if exists"
# behavior, the STALE real file would stay vN and the NEW agent would be absent;
# if it blindly overwrote everything, the UP-TO-DATE file would be needlessly rewritten.
# SANDBOX-ONLY: every path under $TMP_ROOT; the real ~/.claude is NEVER written
# (the GLOBAL real-HOME-unchanged belt below brackets this block too; a per-block
# belt is added here). Offline. bash-3.2-safe (no $()-wrapped heredocs), ASCII-only,
# eval-free.
# ====================================================================
INSTU_BASE="$TMP_ROOT/pur3s-instupd-symlink-target"
INSTU_SRC_VN="$INSTU_BASE/src-vN"      # install source: NO new agent, NO instu_* lib files
INSTU_SRC_VN1="$INSTU_BASE/src-vN1"    # update source: ADDS the new agent + the instu_* lib files
INSTU_HOME="$INSTU_BASE/home"
mkdir -p "$INSTU_BASE"

# vN install source -- WITHOUT the NEW agent (so "NEW agent added by --update" is real,
# not added by the first install) and WITHOUT the instu_* lib files (those are planted
# below as real-file targets so they reach the content-compare branch, not the symlink one).
build_pur3s_source "$INSTU_SRC_VN" "$PUR3S_VN" "vN-AGENT" "vN-COMMAND" "vN-LIB" ""

# DEFAULT (symlink) install into the sandbox HOME -> the CLI/lib are symlinks INTO the
# source. This is genuinely a SYMLINK-mode $CLAUDE_HOME.
CLAUDE_HOME="$INSTU_HOME" "$INSTU_SRC_VN/config/claude/install.sh" --no-hook --no-skills --force \
  >"$INSTU_BASE/install.log" 2>&1
INSTU_LIB="$INSTU_HOME/lib/plumbline_update.py"
INSTU_NEW="$INSTU_HOME/$PUR3S_NEW_INSTALLED_REL"
assert "PUR-3.1 (c') safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$INSTU_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
assert "PUR-3.1 (c') safety: both throwaway sources are under TMP_ROOT (real repo untouched)" "case '$INSTU_SRC_VN' in '$TMP_ROOT'/*) case '$INSTU_SRC_VN1' in '$TMP_ROOT'/*) true ;; *) false ;; esac ;; *) false ;; esac"
# Precondition: it really IS symlink mode (the installed lib is a symlink into the src),
# so a future install.sh that flipped the default to copies makes this block LOUD rather
# than silently re-testing copy mode (the "test that still passes with the branch deleted"
# guard) -- this is the symlink-MODE context for the mechanism under test.
assert "PUR-3.1 (c') precondition: default install symlinks the installed library (symlink-MODE home)" "test -L '$INSTU_LIB'"

# vN+1 update source -- ADDS the NEW agent, and carries the instu_* lib files (vN+1
# content) at the same install-paths as the planted targets below.
build_pur3s_source "$INSTU_SRC_VN1" "$PUR3S_VN1" "vN1-AGENT" "vN1-COMMAND" "vN1-LIB" "$PUR3S_NEW_SRC_REL"
INSTU_SRC_STALE="$INSTU_SRC_VN1/config/claude/lib/instu_stale.py"
INSTU_SRC_FRESH="$INSTU_SRC_VN1/config/claude/lib/instu_fresh.py"
printf '%s\n' "STALE = 'vN1-CONTENT'" > "$INSTU_SRC_STALE"
printf '%s\n' "FRESH = 'vN1-CONTENT'" > "$INSTU_SRC_FRESH"

# Plant the two REAL-FILE targets in the home that exercise content-compare (these reach
# the content_current FILE branch -- cmp -s -- NOT the symlink branch, which keeps live
# links). rm -f FIRST so we replace any install-time symlink with a genuine real file
# (a plain `>` redirect would otherwise WRITE THROUGH the symlink into the source).
#   (1) a STALE real file (content DIFFERS from the vN+1 source) -> --update must OVERWRITE it.
#   (2) an UP-TO-DATE real file (byte-identical to the vN+1 source) -> --update must SKIP it.
INSTU_STALE="$INSTU_HOME/lib/instu_stale.py"
INSTU_FRESH="$INSTU_HOME/lib/instu_fresh.py"
mkdir -p "$INSTU_HOME/lib"
rm -f "$INSTU_STALE" "$INSTU_FRESH"
printf '%s\n' "STALE = 'vN-OLD-CONTENT'" > "$INSTU_STALE"
printf '%s\n' "FRESH = 'vN1-CONTENT'" > "$INSTU_FRESH"
# Preconditions: the planted targets are genuine REAL FILES (NOT symlinks), so the
# overwrite/skip assertions below truly exercise the content-compare branch; the stale
# one carries OLD content; the up-to-date one is byte-identical to the source; and the
# NEW agent is ABSENT before the --update (so its appearance is caused by --update).
assert "PUR-3.1 (c') precondition: planted STALE target is a real file, not a symlink (reaches content-compare)" "test -f '$INSTU_STALE' && test ! -L '$INSTU_STALE'"
assert "PUR-3.1 (c') precondition: planted STALE target carries the OLD content" "grep -q 'vN-OLD-CONTENT' '$INSTU_STALE'"
assert "PUR-3.1 (c') precondition: planted UP-TO-DATE target is a real file byte-identical to the source" "test ! -L '$INSTU_FRESH' && cmp -s '$INSTU_FRESH' '$INSTU_SRC_FRESH'"
assert "PUR-3.1 (c') precondition: the NEW agent is ABSENT before the --update" "test ! -e '$INSTU_NEW'"

# THE MECHANISM under test: install.sh --update run DIRECTLY (NOT via `plumbline
# update`) from the vN+1 source against the SAME symlink-mode $CLAUDE_HOME. Default
# (symlink) mode preserved (no --copy).
CLAUDE_HOME="$INSTU_HOME" "$INSTU_SRC_VN1/config/claude/install.sh" --update --no-hook --no-skills --force \
  >"$INSTU_BASE/update.log" 2>&1

# AC-PUR-05.1 (symlink mode) -- the STALE real-file target is content-compared, found
# CHANGED, and OVERWRITTEN to vN+1 content. RED if --update reverted to "skip if exists".
assert "PUR-3.1 (c') AC-PUR-05.1: install.sh --update content-compares + OVERWRITES a STALE target in symlink mode (vN+1 content)" "grep -q 'vN1-CONTENT' '$INSTU_STALE'"
assert "PUR-3.1 (c') AC-PUR-05.1: the overwritten target no longer carries the OLD content" "! grep -q 'vN-OLD-CONTENT' '$INSTU_STALE'"
# AC-PUR-05.1 (idempotency) -- the UP-TO-DATE real-file target is content-compared and
# SKIPPED (proving COMPARE, not blind overwrite): its content is unchanged AND the
# installer reported it `up-to-date` (the deterministic, platform-portable skip proof --
# no GNU-only `ls --time-style` / stat that breaks macOS BSD `ls`).
assert "PUR-3.1 (c') AC-PUR-05.1: the UP-TO-DATE target still carries its content (skipped, not corrupted)" "grep -q 'vN1-CONTENT' '$INSTU_FRESH'"
assert "PUR-3.1 (c') AC-PUR-05.1: install.sh --update reports the up-to-date target as skipped (content-compare, not blind overwrite)" "grep -q 'up-to-date: $INSTU_FRESH' '$INSTU_BASE/update.log'"
# AC-PUR-05.2 (symlink mode) -- a NEW file in the source is now ADDED to the home.
assert "PUR-3.1 (c') AC-PUR-05.2: install.sh --update ADDS a NEW agent to the symlink-mode home" "test -e '$INSTU_NEW'"
assert "PUR-3.1 (c') AC-PUR-05.2: the added NEW agent carries the vN+1 NEWFILE marker" "grep -q 'MARKER NEWFILE $PUR3S_VN1' '$INSTU_NEW' 2>/dev/null || false"
# Per-block sandbox belt.
assert "PUR-3.1 (c') safety: install.sh --update sandbox root is under TMP_ROOT" "case '$INSTU_BASE' in '$TMP_ROOT'/*) true ;; *) false ;; esac"

# ====================================================================
# PUR-3.1 (d) -- REQ-PUR-06 / AC-PUR-06.1: verify-or-revert. With an INJECTED
# verify-FAILURE during a vN->vN+1 apply into a sandbox $CLAUDE_HOME, the WHOLE
# $CLAUDE_HOME must be REVERTED to the vN snapshot: the stale-but-vN state is
# restored (agent marker back to vN), the anchor is back to vN, and the NEW file
# is gone. A failed update must NEVER leave a broken/half-updated install.
# RED today: the no-`--target` apply does not snapshot+install into $CLAUDE_HOME
# at all, so there is nothing to revert in the home (it stays vN by accident, or
# the apply errors against cwd). After the fix this proves the home is restored
# byte-for-byte on a verify-fail.
# ====================================================================
PUR3R_BASE="$TMP_ROOT/pur3s-revert"
PUR3R_VNSRC="$PUR3R_BASE/vN-src"
PUR3R_HOME="$PUR3R_BASE/home"
PUR3R_PAY="$PUR3R_BASE/vN1-payload"

build_pur3s_source "$PUR3R_VNSRC" "$PUR3S_VN" "vN-AGENT" "vN-COMMAND" "vN-LIB" ""
CLAUDE_HOME="$PUR3R_HOME" "$PUR3R_VNSRC/config/claude/install.sh" --copy --no-hook --no-skills --force \
  >"$PUR3R_BASE/install.log" 2>&1
PUR3R_CLI="$PUR3R_HOME/bin/plumbline"
PUR3R_AGENT="$PUR3R_HOME/$PUR3S_AGENT_REL"
PUR3R_NEW="$PUR3R_HOME/$PUR3S_NEW_INSTALLED_REL"
PUR3R_ANCHOR="$PUR3R_HOME/.plumbline-install.json"
assert_file "PUR-3.1 (revert): installed CLI exists in sandbox HOME" "$PUR3R_CLI"
assert "PUR-3.1 (revert) safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$PUR3R_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
assert "PUR-3.1 (revert) precondition: installed agent is vN before the failed update" "grep -q 'MARKER vN-AGENT' '$PUR3R_AGENT'"
assert "PUR-3.1 (revert) precondition: anchor reads vN before the failed update" "grep -q '\"$PUR3S_VN\"' '$PUR3R_ANCHOR'"
assert "PUR-3.1 (revert) precondition: NEW agent absent before the failed update" "test ! -e '$PUR3R_NEW'"

# Stage the vN+1 payload (new file + changed content) and run the natural update
# with an INJECTED verify-FAILURE (a verify-cmd that exits non-zero). The apply
# must snapshot $CLAUDE_HOME, attempt the install, fail verification, and REVERT.
build_pur3s_source "$PUR3R_PAY" "$PUR3S_VN1" "vN1-AGENT" "vN1-COMMAND" "vN1-LIB" "$PUR3S_NEW_SRC_REL"
if ( cd /tmp && CLAUDE_HOME="$PUR3R_HOME" "$PUR3R_CLI" update --source "$PUR3R_PAY" --verify-cmd 'exit 7' \
      >"$PUR3R_BASE/update.log" 2>&1 ); then
  pur3r_status=0
else
  pur3r_status=$?
fi

# The failed update exits non-zero (a broken update is a failure, not a success).
# (Confirming: today it already exits 1 -- "VERSION not found at /tmp/VERSION" --
# because the no-`--target` apply wrongly targets cwd; the RED FALSIFIER for the
# verify-or-revert path is the HOME-snapshot assertion immediately below, which
# proves the snapshot+revert actually ran AGAINST $CLAUDE_HOME.)
assert_eq "PUR-3.1 (revert) AC-PUR-06.1: injected verify-failure exits non-zero" "1" "$pur3r_status"
# RED FALSIFIER (AC-PUR-06.1 / NFR-PUR-02): the snapshot+verify+revert path must
# run AGAINST $CLAUDE_HOME -- so a snapshot is taken UNDER the sandbox HOME before
# the install attempt. RED today: the apply targets cwd/the source and never
# snapshots HOME, so $CLAUDE_HOME/.plumbline/update/snapshots/ is never created.
# After the fix, a verify-failure leaves exactly this evidence: HOME was snapshotted
# (then restored), proving the revert exercised the real HOME, not a no-op.
# Precompute whether HOME carries any snapshot (avoid $() inside the assert string).
if [ -d "$PUR3R_HOME/.plumbline/update/snapshots" ]; then
  # shellcheck disable=SC2012  # snapshot dirs are timestamp-named under a sandbox path; a name probe is fine
  pur3r_home_snaps="$(ls -A "$PUR3R_HOME/.plumbline/update/snapshots" 2>/dev/null | head -n1)"
else
  pur3r_home_snaps=""
fi
assert "PUR-3.1 (revert) AC-PUR-06.1 FALSIFIER: a snapshot was taken UNDER the sandbox HOME (snapshot+revert ran against the home, not cwd/source)" "test -n '$pur3r_home_snaps'"
# AC-PUR-06.1 -- the WHOLE $CLAUDE_HOME is reverted to the vN snapshot:
#   * the agent marker is back to vN (the vN+1 refresh was rolled back),
assert "PUR-3.1 (revert) AC-PUR-06.1: agent reverted to the vN content after the failed update" "grep -q 'MARKER vN-AGENT' '$PUR3R_AGENT'"
assert "PUR-3.1 (revert) AC-PUR-06.1: agent does NOT carry the half-applied vN+1 content" "! grep -q 'MARKER vN1-AGENT' '$PUR3R_AGENT'"
#   * the anchor is back to vN (no half-applied re-stamp survives),
assert "PUR-3.1 (revert) AC-PUR-06.1: anchor reverted to vN after the failed update" "grep -q '\"$PUR3S_VN\"' '$PUR3R_ANCHOR'"
assert "PUR-3.1 (revert) AC-PUR-06.1: anchor does NOT read the half-applied vN+1" "! grep -q '\"$PUR3S_VN1\"' '$PUR3R_ANCHOR'"
#   * the NEW file the payload would have added is GONE (no half-updated debris).
assert "PUR-3.1 (revert) AC-PUR-06.1: the NEW payload file is absent after revert (no half-update debris)" "test ! -e '$PUR3R_NEW'"

# ====================================================================
# CR-4 (CONFIRMING falsifier) -- the home-apply revert prints the exact
# `recover: plumbline rollback <snapshot>` recovery command (plumbline_update.py
# ~:896). The revert prints a `recover:` line naming the snapshot path so a crash
# MID-revert is still recoverable by hand (the snapshot survives -- re-run rollback
# against it). No existing assertion checks this line, so it is "deletable with the
# suite staying green" -- this confirms the branch.
#
# Reuses the PUR-3.1 (revert) scenario directly above: the injected verify-failure
# already drove _apply_into_home through the snapshot -> install -> verify-fail ->
# REVERT path against the sandbox $CLAUDE_HOME, capturing combined output to
# $PUR3R_BASE/update.log. We assert on that captured output (never on an env var).
# The snapshot path is recomputed from the snapshot dir recorded UNDER the sandbox
# HOME (proving the named snapshot is the real one the revert used), eval-free.
# CONFIRMING-GREEN against current code; RED-if-the-recover-line-is-deleted.
# ====================================================================
# Recompute the exact snapshot path the revert used (the single timestamp-named
# dir under the sandbox HOME's snapshots). Avoid $() inside the assert string.
# CANONICALIZE the home the SAME way the lib does: resolve_install_home() returns
# `parent.resolve()` and snapshot_target() builds the snapshot path under that
# resolved home -- so the printed `recover:` path is canonicalized (on macOS the
# mktemp `/var/folders/...` HOME dereferences to `/private/var/...`). We rebuild
# the expected snapshot path from the canonical home (`cd ... && pwd -P` mirrors
# Python's `.resolve()`) so the fixed-string grep matches on macOS as well as on
# Linux/local (where there is no /var -> /private/var symlink, so it is a no-op).
PUR3R_HOME_CANON="$PUR3R_HOME"
if [ -d "$PUR3R_HOME" ]; then
  PUR3R_HOME_CANON="$( cd "$PUR3R_HOME" && pwd -P )"
fi
PUR3R_SNAP_DIR="$PUR3R_HOME_CANON/.plumbline/update/snapshots"
if [ -d "$PUR3R_SNAP_DIR" ]; then
  # shellcheck disable=SC2012  # one timestamp-named snapshot dir under a sandbox path; a name probe is fine
  pur3r_snap_name="$(ls -A "$PUR3R_SNAP_DIR" 2>/dev/null | head -n1)"
else
  pur3r_snap_name=""
fi
PUR3R_SNAP_PATH="$PUR3R_SNAP_DIR/$pur3r_snap_name"
# Precondition: the revert ran and produced exactly one snapshot to recover from
# (so the recover-line assertions below are not vacuous against an empty path).
assert "CR-4 precondition: the revert produced a snapshot under the sandbox HOME (recover target exists)" "test -n '$pur3r_snap_name' && test -d '$PUR3R_SNAP_PATH'"
# THE CONFIRMING FALSIFIER (a) -- the revert output carries a `recover:` line that
# names `plumbline rollback` (the recovery command). Deleting plumbline_update.py
# ~:896 would drop this line and redden the assertion.
assert "CR-4: the home-apply revert prints a 'recover:' line naming 'plumbline rollback'" "grep -q 'recover: plumbline rollback' '$PUR3R_BASE/update.log'"
# (b) -- that recover line names the REAL snapshot path the revert created (so the
# operator can copy-paste it). We grep for the exact `recover: plumbline rollback
# <snapshot>` line, fixed-string on the recomputed snapshot path.
assert "CR-4: the recover line names the exact snapshot path the revert used" "grep -qF 'recover: plumbline rollback $PUR3R_SNAP_PATH' '$PUR3R_BASE/update.log'"
# (c) -- ordering belt: the recover line follows the `status: reverted to snapshot`
# line (it is part of the revert path, not some unrelated output), proving the two
# lines belong to the same revert event.
assert "CR-4: the revert reports 'status: reverted to snapshot' alongside the recover line" "grep -q 'status: reverted to snapshot' '$PUR3R_BASE/update.log'"

# ====================================================================
# CR-4 (cont.) -- the CHECKOUT-apply --target revert path also prints the recover
# line, with the `--target <path>` suffix (plumbline_update.py ~:943). This is the
# _apply_from_source revert (a `--target` apply), distinct from the home-apply
# above. The existing failed-verification revert (FAIL_TARGET, lines ~73-83)
# already drove _apply_from_source through a verify-fail revert, but it asserted
# only on the version/payload/`status: reverted` -- NOT on the recover line. We add
# a fresh, self-contained --target verify-fail revert and assert the recover line
# names BOTH `plumbline rollback <snapshot>` AND `--target <target>`.
# CONFIRMING-GREEN against current code; RED-if-the-checkout-recover-line-is-deleted.
# ====================================================================
CR4T_TARGET="$TMP_ROOT/cr4-target"
cp -R "$BASELINE_FIXTURE" "$CR4T_TARGET"
# A natural --target apply with an INJECTED verify-FAILURE forces _apply_from_source
# through snapshot -> copy -> verify-fail -> REVERT (the checkout-apply revert path).
( "$PLUMBLINE" --root "$REPO_DIR" update --target "$CR4T_TARGET" --source "$UPDATE_FIXTURE" --verify-cmd 'exit 7' \
    >"$TMP_ROOT/cr4-target.log" 2>&1 ) || true
assert "CR-4 (--target) safety: the --target tree is under TMP_ROOT (sandbox)" "case '$CR4T_TARGET' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
# Precondition: the checkout-apply revert actually ran (status: reverted present).
assert "CR-4 (--target) precondition: the --target verify-fail reverted (revert path ran)" "grep -q 'status: reverted to snapshot' '$TMP_ROOT/cr4-target.log'"
# Recompute the snapshot path the --target revert created (under the TARGET tree).
# CANONICALIZE the target the SAME way the lib does: _apply_from_source receives
# `Path(args.target).resolve()` (plumbline_update.py ~:799) and snapshot_target()
# builds the snapshot under it -- so BOTH the printed snapshot path AND the
# `--target <target>` suffix are canonicalized (macOS `/var/folders/...` ->
# `/private/var/...`). We rebuild the expected snapshot dir AND the expected
# --target value from the canonical target (`cd ... && pwd -P` mirrors `.resolve()`)
# so the fixed-string grep matches on macOS as well as Linux/local (a no-op where
# there is no /var -> /private/var symlink). The sandbox belt above keeps using the
# raw $CR4T_TARGET (it shares the un-canonicalized $TMP_ROOT prefix).
CR4T_TARGET_CANON="$CR4T_TARGET"
if [ -d "$CR4T_TARGET" ]; then
  CR4T_TARGET_CANON="$( cd "$CR4T_TARGET" && pwd -P )"
fi
CR4T_SNAP_DIR="$CR4T_TARGET_CANON/.plumbline/update/snapshots"
if [ -d "$CR4T_SNAP_DIR" ]; then
  # shellcheck disable=SC2012  # one timestamp-named snapshot dir under a sandbox path; a name probe is fine
  cr4t_snap_name="$(ls -A "$CR4T_SNAP_DIR" 2>/dev/null | head -n1)"
else
  cr4t_snap_name=""
fi
CR4T_SNAP_PATH="$CR4T_SNAP_DIR/$cr4t_snap_name"
assert "CR-4 (--target) precondition: the --target revert produced a snapshot (recover target exists)" "test -n '$cr4t_snap_name' && test -d '$CR4T_SNAP_PATH'"
# THE CONFIRMING FALSIFIER -- the checkout-apply revert prints the recover line
# naming `plumbline rollback <snapshot> --target <target>` (the full hand-recovery
# command for a --target apply). Deleting plumbline_update.py ~:943 reddens this.
assert "CR-4 (--target): the checkout-apply revert prints a 'recover: plumbline rollback' line" "grep -q 'recover: plumbline rollback' '$TMP_ROOT/cr4-target.log'"
assert "CR-4 (--target): the recover line names the exact snapshot path AND --target" "grep -qF 'recover: plumbline rollback $CR4T_SNAP_PATH --target $CR4T_TARGET_CANON' '$TMP_ROOT/cr4-target.log'"

# ====================================================================
# PUR-3.1 (e) -- AC-PUR-04.4 GLOBAL sandbox belt: across ALL of the Sprint-3
# scenarios above (copy refresh, install.sh --update symlink-TARGET mechanism, revert),
# the operator's REAL
# ~/.claude was NEVER written. Compare the post-test listing + dir mtime to the
# pre-test capture; any change is a hard failure (a Sprint-3 test that wrote the
# real HOME is itself the defect this whole feature exists to prevent).
# ====================================================================
if [ -d "$PUR3S_REAL_HOME" ]; then
  # shellcheck disable=SC2012  # a sorted name listing is exactly the change-detector we want
  ( ls -A "$PUR3S_REAL_HOME" 2>/dev/null | sort ) > "$PUR3S_REAL_LIST_AFTER" 2>/dev/null || : > "$PUR3S_REAL_LIST_AFTER"
  # shellcheck disable=SC2012  # capturing the dir's own stat line (mtime) as a tamper marker
  PUR3S_REAL_MTIME_AFTER="$(ls -ld "$PUR3S_REAL_HOME" 2>/dev/null || true)"
else
  : > "$PUR3S_REAL_LIST_AFTER"
  PUR3S_REAL_MTIME_AFTER="<absent>"
fi
assert "PUR-3.1 (e) AC-PUR-04.4: real ~/.claude listing UNCHANGED by the Sprint-3 apply tests" "diff '$PUR3S_REAL_LIST_BEFORE' '$PUR3S_REAL_LIST_AFTER' >/dev/null 2>&1"
assert_eq "PUR-3.1 (e) AC-PUR-04.4: real ~/.claude dir mtime UNCHANGED by the Sprint-3 apply tests" "$PUR3S_REAL_MTIME_BEFORE" "$PUR3S_REAL_MTIME_AFTER"
# And belt-on-belt: the Sprint-3 anchor the tests re-stamped lives ONLY in the
# sandbox -- there is no .plumbline-install.json freshly written into the real HOME
# by this block (it either pre-existed unchanged, captured above, or is absent).
assert "PUR-3.1 (e) AC-PUR-04.4: Sprint-3 sandbox roots are all under TMP_ROOT" "case '$TMP_ROOT/pur3s-copy' in '$TMP_ROOT'/*) case '$INSTU_BASE' in '$TMP_ROOT'/*) case '$TMP_ROOT/pur3s-revert' in '$TMP_ROOT'/*) true ;; *) false ;; esac ;; *) false ;; esac ;; *) false ;; esac"

# ====================================================================
# SPRINT 3 REMEDIATION -- RED falsifiers for the Sprint-3 code-review findings
# (CR-1, CR-2, CR-3, CR-5, SEC-2). Each is RED-for-the-right-reason against TODAY's
# code (or marked CONFIRMING where today's code already holds).
#
# All blocks below are SANDBOX-ONLY (NFR-PUR-01): every path lives under $TMP_ROOT
# (mktemp), CLAUDE_HOME is always a sandbox dir under $TMP_ROOT; the operator's REAL
# ~/.claude is NEVER written (the GLOBAL real-HOME-unchanged belt above ALREADY
# brackets the whole Sprint-3 surface; a per-block belt is added here too). Offline
# only (no network: payloads are staged via the OFFLINE --source seam). bash-3.2-safe
# (NO $()-wrapped heredocs anywhere; heredocs are redirected to files then read back),
# ASCII-only, eval-free.
#
# DRIVEN THROUGH THE PRODUCTION COMPOSITION PATH: where a finding is about apply
# behavior, the INSTALLED CLI ($CLAUDE_HOME/bin/plumbline) drives the REAL install.sh
# into a real (sandbox) $CLAUDE_HOME -- never a hand-built harness.
# ====================================================================

# Shared vN/vN+1/vN+2 versions (synthesized off $REPO_VERSION so the blocks survive
# every release bump -- no hardcoded literal). vN+2 is used by CR-1 to prove the
# symlinked checkout is still LIVE-tracked after a refused update.
REMED_VN="$REPO_VERSION"
REMED_VN1="$(awk -F. -v OFS=. '{print $1, $2+1, 0}' <<<"$REPO_VERSION")"
REMED_VN2="$(awk -F. -v OFS=. '{print $1, $2+2, 0}' <<<"$REPO_VERSION")"

# build_remed_source <src-dir> <version> -- assemble a MINIMAL install-capable
# Plumbline source tree (REAL install.sh + lib + bin + a stub run_all.sh) at
# <src-dir>, stamped to <version>, with the canonical Plumbline git origin (so the
# anchor slug is well-formed). No agents/commands/skills here (callers that need a
# controlled skill add it explicitly). No $()-wrapped heredocs.
build_remed_source() {
  remed_src="$1"; remed_ver="$2"
  mkdir -p "$remed_src/config/claude/lib" "$remed_src/config/claude/bin" \
           "$remed_src/config/claude/tests"
  printf '%s\n' "$remed_ver" > "$remed_src/VERSION"
  printf '{\n  "version": "%s",\n  "schema": 1,\n  "verifyCommand": "true",\n  "frozenContracts": ["VERSION"],\n  "migrations": []\n}\n' "$remed_ver" > "$remed_src/compatibility.json"
  cp "$REPO_DIR/config/claude/install.sh" "$remed_src/config/claude/install.sh"
  cp "$REPO_DIR/config/claude/lib/plumbline_update.py" "$remed_src/config/claude/lib/plumbline_update.py"
  cp "$REPO_DIR/config/claude/bin/plumbline" "$remed_src/config/claude/bin/plumbline" 2>/dev/null || true
  printf '%s\n%s\n' '#!/usr/bin/env bash' 'exit 0' > "$remed_src/config/claude/tests/run_all.sh"
  chmod +x "$remed_src/config/claude/install.sh" "$remed_src/config/claude/bin/plumbline" "$remed_src/config/claude/tests/run_all.sh" 2>/dev/null || true
  git -C "$remed_src" init -q
  git -C "$remed_src" remote add origin "https://github.com/DYAI2025/Plumbline.git"
}

# ====================================================================
# CR-1 (HIGH) -- `plumbline update` must REFUSE to silently copy-convert a SYMLINK
# install. The confirmed two-mode model (PRD :124-125): COPY installs update via
# `plumbline update`; SYMLINK installs update via `git pull`. Today _apply_into_home
# runs `install.sh --copy --update`, which converts a symlinked install to a frozen
# copy in place and reports "changed and verified" -- the user's `git pull` workflow
# is silently destroyed.
#
# Gegenthese this kills: the update is "green" yet it broke the user's install mode.
# The falsifier drives the INSTALLED symlink CLI through a REAL `plumbline update`
# and requires: (a) it is REFUSED (non-zero), (b) the message names `git pull`
# (actionable, mode-aware), (c) the payload is NOT applied (anchor / report do NOT
# say changed-and-verified), and (d) the install mode is UNCHANGED -- the lib is
# STILL a symlink AND STILL tracks the live checkout (advance the source VERSION to
# vN+2 post-attempt and require the installed `version` to report vN+2, proving it
# was never frozen to a copy).
# RED today: the update succeeds, converts the symlink to a copy, and the post-attempt
# advance is therefore NOT tracked.
# ====================================================================
CR1_BASE="$TMP_ROOT/remed-cr1"
CR1_SRC="$CR1_BASE/src"
CR1_HOME="$CR1_BASE/home"
CR1_PAY="$CR1_BASE/payload"
mkdir -p "$CR1_BASE"
build_remed_source "$CR1_SRC" "$REMED_VN"
# DEFAULT (symlink) install into the sandbox HOME from the throwaway vN source.
CLAUDE_HOME="$CR1_HOME" "$CR1_SRC/config/claude/install.sh" --no-agents --no-commands --no-skills --no-hook --force \
  >"$CR1_BASE/install.log" 2>&1
CR1_CLI="$CR1_HOME/bin/plumbline"
CR1_LIB="$CR1_HOME/lib/plumbline_update.py"
assert_file "CR-1: symlink-mode installed CLI exists in sandbox HOME" "$CR1_CLI"
assert "CR-1 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$CR1_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
assert "CR-1 safety: throwaway source is under TMP_ROOT (real repo untouched)" "case '$CR1_SRC' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
# Precondition: it really is the DEFAULT symlink mode (lib is a symlink into the src).
assert "CR-1 precondition: default install symlinks the installed library" "test -L '$CR1_LIB'"
# Stage a vN+1 payload via the offline --source seam.
build_remed_source "$CR1_PAY" "$REMED_VN1"
assert "CR-1 safety: vN+1 payload is under TMP_ROOT (offline staging)" "case '$CR1_PAY' in '$TMP_ROOT'/*) true ;; *) false ;; esac"

# THE NATURAL UPDATE on a SYMLINK install: installed CLI, NO --target, NO --root,
# from a NEUTRAL cwd (/tmp), CLAUDE_HOME = the sandbox HOME, payload via --source.
if ( cd /tmp && CLAUDE_HOME="$CR1_HOME" "$CR1_CLI" update --source "$CR1_PAY" --verify-cmd true \
      >"$CR1_BASE/update.log" 2>&1 ); then
  cr1_status=0
else
  cr1_status=$?
fi
# (a) REFUSED -- a symlink install must not be updated via `plumbline update`.
assert_eq "CR-1: plumbline update on a SYMLINK install is REFUSED (non-zero exit)" "1" "$cr1_status"
# (b) the refusal NAMES `git pull` (the actionable, mode-correct path).
assert "CR-1: the refusal message names 'git pull' (the symlink-mode update path)" "grep -qi 'git pull' '$CR1_BASE/update.log'"
# (c) NOT applied -- the success line must be ABSENT (no changed-and-verified).
assert "CR-1: the symlink update did NOT report 'changed and verified' (not applied)" "! grep -q 'status: changed and verified' '$CR1_BASE/update.log'"
# (d.1) the install MODE is UNCHANGED -- the lib is STILL a symlink (never frozen to a copy).
assert "CR-1: after the refused update the installed library is STILL a symlink (not copy-converted)" "test -L '$CR1_LIB'"
# (d.2) and it STILL tracks the LIVE checkout: advance the throwaway source to vN+2
# (simulating the `git pull` the user is told to run) and require the installed CLI
# to report vN+2 -- impossible if it had been frozen into a copy of vN/vN+1.
printf '%s\n' "$REMED_VN2" > "$CR1_SRC/VERSION"
cr1_ver_after="$(cd /tmp && "$CR1_CLI" version 2>&1)"
assert_eq "CR-1: symlink install still tracks the LIVE checkout after the refused update (reports advanced vN+2)" "$REMED_VN2" "$cr1_ver_after"
assert "CR-1: symlink install version is NOT frozen to the payload vN+1 (proves no copy-conversion)" "test '$cr1_ver_after' != '$REMED_VN1'"

# ====================================================================
# CR-2 (HIGH) -- `plumbline update` must REFRESH SKILLS (REQ-PUR-05). Today
# _apply_into_home passes `--no-skills` to install.sh, so an existing skill stays
# STALE and a new skill is never added, while the apply reports "changed and
# verified".
#
# Gegenthese this kills: the update is "green" yet the user is running a stale skill
# (and is missing a shipped one) without knowing. The falsifier COPY-installs a
# sandbox HOME WITH skills (a controlled skill at vN-STALE), stages a vN+1 payload
# that CHANGES that skill AND ADDS a new skill, runs the natural `plumbline update`,
# and requires: the existing skill is REFRESHED to vN+1 content AND the new skill is
# ADDED AND the report is the honest changed-and-verified.
# RED today: the skill stays vN-STALE and the new skill is absent.
# COPY mode is used (the mode whose natural update path IS `plumbline update`).
# ====================================================================
CR2_BASE="$TMP_ROOT/remed-cr2"
CR2_SRC="$CR2_BASE/src"
CR2_HOME="$CR2_BASE/home"
CR2_PAY="$CR2_BASE/payload"
mkdir -p "$CR2_BASE"
# vN source WITH a controlled skill carrying the STALE marker.
build_remed_source "$CR2_SRC" "$REMED_VN"
mkdir -p "$CR2_SRC/config/claude/skills/remed-skill"
printf '%s\n%s\n' '# remed skill' 'MARKER vN-SKILL' > "$CR2_SRC/config/claude/skills/remed-skill/SKILL.md"
# COPY install WITH skills (omit --no-skills so the controlled skill is mounted).
CLAUDE_HOME="$CR2_HOME" "$CR2_SRC/config/claude/install.sh" --copy --no-agents --no-commands --no-hook --force \
  >"$CR2_BASE/install.log" 2>&1
CR2_CLI="$CR2_HOME/bin/plumbline"
CR2_SKILL_INST="$CR2_HOME/skills/remed-skill/SKILL.md"
CR2_NEWSKILL_INST="$CR2_HOME/skills/remed-newskill/SKILL.md"
assert_file "CR-2: copy-mode installed CLI exists in sandbox HOME" "$CR2_CLI"
assert "CR-2 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$CR2_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
# Precondition: the STALE skill is actually installed and carries the vN marker (so
# the refresh assertion has a real stale state to overwrite -- not vacuous).
assert_file "CR-2 precondition: the controlled skill is installed in HOME" "$CR2_SKILL_INST"
assert "CR-2 precondition: installed skill carries the STALE vN marker" "grep -q 'MARKER vN-SKILL' '$CR2_SKILL_INST'"
assert "CR-2 precondition: the NEW skill is ABSENT before update" "test ! -e '$CR2_NEWSKILL_INST'"
# Stage a vN+1 payload: SAME skill path with the vN+1 marker, PLUS a NEW skill.
build_remed_source "$CR2_PAY" "$REMED_VN1"
mkdir -p "$CR2_PAY/config/claude/skills/remed-skill" "$CR2_PAY/config/claude/skills/remed-newskill"
printf '%s\n%s\n' '# remed skill' 'MARKER vN1-SKILL' > "$CR2_PAY/config/claude/skills/remed-skill/SKILL.md"
printf '%s\n%s\n' '# remed new skill' 'MARKER NEWSKILL vN1' > "$CR2_PAY/config/claude/skills/remed-newskill/SKILL.md"
assert "CR-2 safety: vN+1 payload is under TMP_ROOT (offline staging)" "case '$CR2_PAY' in '$TMP_ROOT'/*) true ;; *) false ;; esac"

# THE NATURAL UPDATE (copy mode): installed CLI, NO --target/--root, neutral cwd.
( cd /tmp && CLAUDE_HOME="$CR2_HOME" "$CR2_CLI" update --source "$CR2_PAY" --verify-cmd true \
    >"$CR2_BASE/update.log" 2>&1 ) || true
# The existing skill is REFRESHED to vN+1 content (REQ-PUR-05).
assert "CR-2 REQ-PUR-05: existing skill is REFRESHED to vN+1 content" "grep -q 'MARKER vN1-SKILL' '$CR2_SKILL_INST'"
assert "CR-2 REQ-PUR-05: existing skill no longer carries the STALE vN marker" "! grep -q 'MARKER vN-SKILL' '$CR2_SKILL_INST'"
# The NEW skill is ADDED.
assert "CR-2 REQ-PUR-05: the NEW skill is ADDED to HOME" "test -e '$CR2_NEWSKILL_INST'"
assert "CR-2 REQ-PUR-05: the added NEW skill carries the vN+1 NEWSKILL marker" "grep -q 'MARKER NEWSKILL vN1' '$CR2_NEWSKILL_INST' 2>/dev/null || false"
# The success report is honest (the apply actually completed AND refreshed skills).
assert "CR-2 REQ-PUR-05: the update reports an honest changed-and-verified once skills are refreshed" "grep -q 'status: changed and verified' '$CR2_BASE/update.log'"

# ====================================================================
# CR-3 (MEDIUM) -- revert must not DESTROY ignored-but-present entries it never
# snapshotted. Today snapshot_target ignores {.git,.plumbline,__pycache__}, but
# restore_snapshot DELETES everything in the home except `.plumbline`. So a user's
# `$CLAUDE_HOME/__pycache__/user.pyc` is WIPED on a revert and never restored --
# silent data loss masquerading as a safe rollback.
#
# Gegenthese this kills: the revert "succeeds" and looks safe, yet it destroyed a
# user file it never backed up. The falsifier COPY-installs a sandbox HOME, plants
# BOTH a legit snapshotted user file AND `$CLAUDE_HOME/__pycache__/user.pyc`, runs an
# update with an INJECTED verify-FAILURE, and requires that AFTER the revert: the
# snapshotted user file is RESTORED (proves the revert ran) AND the __pycache__ user
# file STILL EXISTS (not wiped).
# RED today: the __pycache__ user file is deleted by restore_snapshot and never
# restored (it was never in the snapshot).
# ====================================================================
CR3_BASE="$TMP_ROOT/remed-cr3"
CR3_SRC="$CR3_BASE/src"
CR3_HOME="$CR3_BASE/home"
CR3_PAY="$CR3_BASE/payload"
mkdir -p "$CR3_BASE"
build_remed_source "$CR3_SRC" "$REMED_VN"
CLAUDE_HOME="$CR3_HOME" "$CR3_SRC/config/claude/install.sh" --copy --no-agents --no-commands --no-skills --no-hook --force \
  >"$CR3_BASE/install.log" 2>&1
CR3_CLI="$CR3_HOME/bin/plumbline"
assert_file "CR-3: copy-mode installed CLI exists in sandbox HOME" "$CR3_CLI"
assert "CR-3 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$CR3_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
# Plant (1) a legit user file that WILL be snapshotted (top-level, not ignored) and
# (2) the ignored-but-present __pycache__ user file that snapshot_target SKIPS.
CR3_LEGIT="$CR3_HOME/user-keepme.txt"
CR3_PYC="$CR3_HOME/__pycache__/user.pyc"
printf '%s\n' 'USER-LEGIT-CONTENT' > "$CR3_LEGIT"
mkdir -p "$CR3_HOME/__pycache__"
printf '%s\n' 'USER-PYC-CONTENT' > "$CR3_PYC"
assert_file "CR-3 precondition: legit (snapshotted) user file exists before update" "$CR3_LEGIT"
assert_file "CR-3 precondition: ignored-but-present __pycache__ user file exists before update" "$CR3_PYC"
# Stage a vN+1 payload and run the natural update with an INJECTED verify-FAILURE,
# forcing the snapshot -> install -> verify-fail -> REVERT path against $CLAUDE_HOME.
build_remed_source "$CR3_PAY" "$REMED_VN1"
( cd /tmp && CLAUDE_HOME="$CR3_HOME" "$CR3_CLI" update --source "$CR3_PAY" --verify-cmd 'exit 7' \
    >"$CR3_BASE/update.log" 2>&1 ) || true
# Confirm the revert path actually ran against HOME (a snapshot was taken under HOME).
if [ -d "$CR3_HOME/.plumbline/update/snapshots" ]; then
  # shellcheck disable=SC2012  # snapshot dirs are timestamp-named under a sandbox path; a name probe is fine
  cr3_snaps="$(ls -A "$CR3_HOME/.plumbline/update/snapshots" 2>/dev/null | head -n1)"
else
  cr3_snaps=""
fi
assert "CR-3 precondition: a snapshot was taken under the sandbox HOME (revert path ran against the home)" "test -n '$cr3_snaps'"
# AFTER the revert: the snapshotted user file is RESTORED (proves the revert worked).
assert_file "CR-3: the legit snapshotted user file is RESTORED after the failed update" "$CR3_LEGIT"
assert "CR-3: the restored legit user file still carries its content" "grep -q 'USER-LEGIT-CONTENT' '$CR3_LEGIT'"
# THE FALSIFIER: the ignored-but-present __pycache__ user file STILL EXISTS (not wiped).
assert_file "CR-3: ignored-but-present __pycache__ user file STILL EXISTS after revert (not wiped)" "$CR3_PYC"
assert "CR-3: the surviving __pycache__ user file still carries its content" "grep -q 'USER-PYC-CONTENT' '$CR3_PYC' 2>/dev/null || false"

# ====================================================================
# CR-5 (LOW) -- the anchor `source_commit` must NEVER be the literal string 'HEAD'.
# Today write_install_anchor runs `git rev-parse HEAD 2>/dev/null || true`; on a
# git-init'd checkout with NO commit, `git rev-parse HEAD` prints the literal `HEAD`
# to stdout (fatal path) and the `|| true` swallows the non-zero exit, so the anchor
# records  "source_commit": "HEAD"  -- useless provenance that LOOKS recorded.
#
# Gegenthese this kills: the anchor "has a source_commit" yet it is the placeholder
# `HEAD`, not a real sha. The falsifier installs from a throwaway source that is
# `git init`'d but has NO commit, then requires the anchor's source_commit to be
# either EMPTY or a 40-hex sha, NEVER the literal `HEAD`.
# RED today: source_commit == "HEAD".
# Validated eval-free by handing the FILE PATH to python3 as argv[1] (no payload
# interpolation into shell/python code).
# ====================================================================
CR5_BASE="$TMP_ROOT/remed-cr5"
CR5_SRC="$CR5_BASE/src"
CR5_HOME="$CR5_BASE/home"
mkdir -p "$CR5_BASE/config/claude/lib" "$CR5_SRC/config/claude/lib" "$CR5_SRC/config/claude/bin"
# A throwaway source: git init'd but deliberately NO commit (so HEAD is unborn).
printf '%s\n' "$REMED_VN" > "$CR5_SRC/VERSION"
cp "$REPO_DIR/config/claude/install.sh" "$CR5_SRC/config/claude/install.sh"
cp "$REPO_DIR/config/claude/lib/plumbline_update.py" "$CR5_SRC/config/claude/lib/plumbline_update.py"
cp "$REPO_DIR/config/claude/bin/plumbline" "$CR5_SRC/config/claude/bin/plumbline" 2>/dev/null || true
chmod +x "$CR5_SRC/config/claude/install.sh" "$CR5_SRC/config/claude/bin/plumbline" 2>/dev/null || true
git -C "$CR5_SRC" init -q
git -C "$CR5_SRC" remote add origin "https://github.com/DYAI2025/Plumbline.git"
# NOTE: deliberately NO `git add`/`git commit` here -- HEAD is unborn.
CLAUDE_HOME="$CR5_HOME" "$CR5_SRC/config/claude/install.sh" --copy --no-agents --no-commands --no-skills --no-hook --force \
  >"$CR5_BASE/install.log" 2>&1
assert "CR-5 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$CR5_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
assert "CR-5 safety: throwaway commitless source is under TMP_ROOT" "case '$CR5_SRC' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
CR5_ANCHOR="$CR5_HOME/.plumbline-install.json"
assert_file "CR-5 precondition: install wrote the identity anchor from the commitless source" "$CR5_ANCHOR"
# Extract source_commit eval-free (file path as argv[1]) and classify it.
CR5_COMMIT="$(python3 -c 'import json,sys
d=json.load(open(sys.argv[1]))
print(d.get("source_commit",""))' "$CR5_ANCHOR" 2>/dev/null || true)"
# THE FALSIFIER: source_commit must NEVER be the literal 'HEAD'.
assert "CR-5: anchor source_commit is NOT the literal 'HEAD'" "test '$CR5_COMMIT' != 'HEAD'"
# And it must be a VALID value: empty OR a 40-hex sha (nothing else).
if [ -z "$CR5_COMMIT" ] || printf '%s' "$CR5_COMMIT" | grep -Eq '^[0-9a-f]{40}$'; then
  cr5_commit_class=valid
else
  cr5_commit_class=invalid
fi
assert_eq "CR-5: anchor source_commit is empty or a 40-hex sha (never a placeholder)" "valid" "$cr5_commit_class"
# Belt: the anchor stays valid parseable JSON regardless.
if python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$CR5_ANCHOR" >/dev/null 2>&1; then
  cr5_json_status=0
else
  cr5_json_status=$?
fi
assert_eq "CR-5: anchor from a commitless source stays valid parseable JSON" "0" "$cr5_json_status"

# ====================================================================
# SEC-2 (NOTE, hardening) -- the apply subprocess env must NOT carry the operator's
# GITHUB_TOKEN/GH_TOKEN into the (possibly untrusted) downloaded payload's install.sh
# / verify subprocess. Today _apply_into_home does `env = dict(os.environ)` then runs
# the payload's install.sh with that env -- so a malicious payload installer can read
# the token straight out of its environment.
#
# Gegenthese this kills: the apply "works" yet it hands the user's token to attacker-
# controlled payload code. The falsifier stages a vN+1 payload whose install.sh ECHOES
# its own environment, runs `plumbline update` with a unique SENTINEL GITHUB_TOKEN set,
# and requires the sentinel to be ABSENT from the apply output (the apply must scrub
# GITHUB_TOKEN/GH_TOKEN from the staged install.sh/verify subprocess env).
# RED today: the env is inherited, so the payload installer echoes the sentinel.
# We assert on the apply OUTPUT (what the payload installer actually saw), never on the
# env var the test set. eval-free (assert_not_contains passes args as params).
# ====================================================================
SEC2_BASE="$TMP_ROOT/remed-sec2"
SEC2_SRC="$SEC2_BASE/src"
SEC2_HOME="$SEC2_BASE/home"
SEC2_PAY="$SEC2_BASE/payload"
mkdir -p "$SEC2_BASE"
SEC2_TOKEN="ghp_SEC2SENTINEL_must_not_reach_payload_0123456789ABCDEF"
# A clean vN COPY install (the mode whose update path is `plumbline update`).
build_remed_source "$SEC2_SRC" "$REMED_VN"
CLAUDE_HOME="$SEC2_HOME" "$SEC2_SRC/config/claude/install.sh" --copy --no-agents --no-commands --no-skills --no-hook --force \
  >"$SEC2_BASE/install.log" 2>&1
SEC2_CLI="$SEC2_HOME/bin/plumbline"
assert_file "SEC-2: copy-mode installed CLI exists in sandbox HOME" "$SEC2_CLI"
assert "SEC-2 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$SEC2_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
# Stage a vN+1 payload whose install.sh ECHOES its environment (the probe). It still
# exits 0 so the apply reaches verify; the echoed env is what we inspect.
build_remed_source "$SEC2_PAY" "$REMED_VN1"
printf '%s\n%s\n%s\n' '#!/usr/bin/env bash' 'env' 'exit 0' > "$SEC2_PAY/config/claude/install.sh"
chmod +x "$SEC2_PAY/config/claude/install.sh"
assert "SEC-2 safety: vN+1 probe payload is under TMP_ROOT (offline staging)" "case '$SEC2_PAY' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
# Run the natural update with the SENTINEL token set in the apply caller's env.
( cd /tmp && CLAUDE_HOME="$SEC2_HOME" GITHUB_TOKEN="$SEC2_TOKEN" "$SEC2_CLI" update --source "$SEC2_PAY" --verify-cmd true \
    >"$SEC2_BASE/update.log" 2>&1 ) || true
SEC2_OUT="$(cat "$SEC2_BASE/update.log" 2>/dev/null || true)"
# THE FALSIFIER: the sentinel token must be ABSENT from the apply output (the payload
# installer's echoed env must not contain it -- it must be scrubbed before the subprocess).
assert_not_contains "SEC-2: GITHUB_TOKEN sentinel is ABSENT from the apply subprocess output (token scrubbed from payload install.sh env)" "$SEC2_OUT" "$SEC2_TOKEN"
# Belt that the probe was meaningful: the payload installer DID run and echoed SOME env
# (so an empty/never-ran output cannot vacuously pass the absence check above).
assert "SEC-2: the probe payload installer actually ran and echoed its env (guard is meaningful)" "grep -q 'PATH=' '$SEC2_BASE/update.log'"

# ====================================================================
# SEC-3 (CONFIRMING falsifier) -- a non-https `tarball_url` is REFUSED when the
# resolved API base host is the REAL GitHub host (api.github.com), with the
# insecure-token gate OFF (plumbline_update.py resolve_payload_source :553-560).
# A plain-http release tarball from the real GitHub API is a downgrade / MITM
# surface and must be refused with a classified error BEFORE any download. No
# existing assertion exercises this branch (the MEDIUM-2 test above covers a
# non-http(s) API *base* scheme, not the *tarball_url* https-on-real-host gate),
# so the branch is "deletable with the suite staying green" -- this confirms it.
#
# Forcing base_host == api.github.com WHILE staying fully offline is done by
# driving resolve_payload_source DIRECTLY in-process (like the setuid/redirect
# Python tests above): PLUMBLINE_GITHUB_API is set to https://api.github.com so
# base_host resolves to the real host and the insecure-token gate is OFF, and
# fetch_latest_release is REPLACED with a stub that returns a release whose
# tarball_url is plain `http://...` -- so ZERO real network happens (the stub
# returns the metadata; the refusal fires before download_tarball is ever
# reached). download_tarball is ALSO replaced with a tripwire that fails the test
# loudly if the refused http tarball is ever actually fetched.
# CONFIRMING-GREEN against current code; RED-if-the-host+scheme-gate is removed.
# eval-free (the JSON-free Python program is a quoted heredoc redirected to a
# temp file, NOT a $()-wrapped heredoc -- bash-3.2-safe), ASCII-only.
# ====================================================================
SEC3_LOG="$TMP_ROOT/sec3.log"
SEC3_PY="$TMP_ROOT/sec3_refuse_http_tarball.py"
cat > "$SEC3_PY" <<'PYEOF'
import argparse
import os
import sys
from pathlib import Path

repo = sys.argv[1]
sys.path.insert(0, str(Path(repo) / "config" / "claude" / "lib"))
import plumbline_update as P  # noqa: E402

# Force the resolved API base to the REAL GitHub host so base_host == api.github.com,
# and ensure the insecure-token gate is OFF (so the https-only gate is ACTIVE).
os.environ["PLUMBLINE_GITHUB_API"] = "https://api.github.com"
os.environ.pop("PLUMBLINE_GITHUB_API_ALLOW_INSECURE_TOKEN", None)

# Stub the network: fetch_latest_release returns a release whose tarball_url is
# PLAIN HTTP. No real request leaves the process.
def _fake_fetch_latest_release(slug):
    return {
        "tag_name": "v99.0.0",
        "draft": False,
        "prerelease": False,
        "tarball_url": "http://api.github.com/repos/DYAI2025/Plumbline/tarball/v99.0.0",
    }

# Tripwire: download_tarball must NEVER run for a refused http tarball. If it does,
# the gate failed open and we fail the test loudly.
def _tripwire_download_tarball(url, dest):
    print("SEC3-TRIPWIRE: download_tarball was called -- gate failed OPEN: " + str(url))
    raise AssertionError("download_tarball must not run when the http tarball is refused")

P.fetch_latest_release = _fake_fetch_latest_release
P.download_tarball = _tripwire_download_tarball

# No --source -> resolve_payload_source takes the network branch and hits the gate.
args = argparse.Namespace(source=None, repo="DYAI2025/Plumbline")
try:
    P.resolve_payload_source(args, Path(repo))
    print("SEC3-FAIL: http tarball was NOT refused (resolve_payload_source returned)")
    sys.exit(2)
except P.PlumblineError as exc:
    msg = str(exc)
    if "refus" in msg.lower():
        print("SEC3-OK: non-https tarball refused on the real GitHub host")
        print("SEC3-MSG: " + msg)
        sys.exit(0)
    print("SEC3-FAIL: raised PlumblineError but not a refusal: " + msg)
    sys.exit(3)
PYEOF
if python3 "$SEC3_PY" "$REPO_DIR" >"$SEC3_LOG" 2>&1; then
  sec3_status=0
else
  sec3_status=$?
fi
# THE CONFIRMING FALSIFIER -- the gate refuses the http tarball (exit 0 = refused),
# names the refusal, NEVER downloads, and leaves no traceback. Removing the
# host+scheme gate (resolve_payload_source :555-560) flips exit to 2 (returned) or
# trips the download tripwire -> RED.
assert_eq "SEC-3: non-https tarball on the real GitHub host is REFUSED (gate active)" "0" "$sec3_status"
assert "SEC-3: the refusal is reported by name (classified error)" "grep -q 'SEC3-OK: non-https tarball refused' '$SEC3_LOG'"
assert "SEC-3: the refusal message names the non-https release tarball" "grep -q 'refusing non-https release tarball' '$SEC3_LOG'"
assert "SEC-3: the http tarball was NEVER downloaded (download_tarball tripwire did not fire)" "! grep -q 'SEC3-TRIPWIRE' '$SEC3_LOG'"
assert "SEC-3: the gate did NOT fail open (resolve_payload_source did not return)" "! grep -q 'SEC3-FAIL' '$SEC3_LOG'"
assert "SEC-3: the refusal path produced no traceback" "! grep -q 'Traceback' '$SEC3_LOG'"
assert "SEC-3 safety: the SEC-3 probe is offline + sandboxed (under TMP_ROOT, no real network)" "case '$SEC3_PY' in '$TMP_ROOT'/*) true ;; *) false ;; esac"

# ====================================================================
# CR-2 (CONFIRMING falsifier) -- `plumbline update` keeps `--no-hook`: the GLOBAL
# settings.json Stop-hook registration is DELIBERATELY NOT re-written on a
# self-update (a named scope decision -- plumbline_update.py :844-846,857). The
# confirmed refresh set is agents/commands/skills/libs/bin; re-registering the
# hooks on every update is intrusive jq/settings churn the team chose to exclude.
# No existing assertion proves the hook is NOT re-registered, so dropping
# `--no-hook` from the staged install.sh invocation would pass the suite silently
# -- this confirms the branch.
#
# Gegenthese this kills: the update is "green" yet it silently mutated the user's
# settings.json (re-registering the Stop hook) without asking. The falsifier
# COPY-installs a sandbox HOME, seeds a SENTINEL settings.json that carries the
# user's own marker AND has NO Stop hook (so IF --no-hook were dropped,
# register_stop_hook WOULD add a .hooks.Stop entry -- a real, detectable mutation,
# not a vacuous no-op), runs the natural `plumbline update`, and requires the
# settings.json to be BYTE-UNCHANGED by the update (no Stop hook added, sentinel
# intact). jq is present (asserted), so register_stop_hook WOULD genuinely mutate.
# CONFIRMING-GREEN against current code; RED-if-`--no-hook`-is-dropped.
# ====================================================================
CR2H_BASE="$TMP_ROOT/remed-cr2-nohook"
CR2H_SRC="$CR2H_BASE/src"
CR2H_HOME="$CR2H_BASE/home"
CR2H_PAY="$CR2H_BASE/payload"
mkdir -p "$CR2H_BASE"
# A clean vN COPY install (the mode whose update path is `plumbline update`).
build_remed_source "$CR2H_SRC" "$REMED_VN"
CLAUDE_HOME="$CR2H_HOME" "$CR2H_SRC/config/claude/install.sh" --copy --no-agents --no-commands --no-skills --no-hook --force \
  >"$CR2H_BASE/install.log" 2>&1
CR2H_CLI="$CR2H_HOME/bin/plumbline"
CR2H_SETTINGS="$CR2H_HOME/settings.json"
assert_file "CR-2 (--no-hook): copy-mode installed CLI exists in sandbox HOME" "$CR2H_CLI"
assert "CR-2 (--no-hook) safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$CR2H_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
# Seed a SENTINEL settings.json with NO Stop hook and a recognizable user marker.
# (The --no-hook install above did not write settings.json, so we author the
# operator's pre-existing settings here.) Valid JSON so register_stop_hook would
# actually run (it bails on invalid JSON); NO .hooks.Stop so a dropped --no-hook
# would genuinely ADD one (a detectable mutation -- not a dedup no-op).
printf '%s\n' '{ "_cr2h_user_marker": "DO_NOT_REWRITE_ON_UPDATE", "model": "inherit" }' > "$CR2H_SETTINGS"
assert_file "CR-2 (--no-hook) precondition: a sentinel settings.json exists in HOME" "$CR2H_SETTINGS"
assert "CR-2 (--no-hook) precondition: sentinel settings.json is valid JSON (register_stop_hook would run)" "python3 -c 'import json,sys; json.load(open(sys.argv[1]))' '$CR2H_SETTINGS'"
assert "CR-2 (--no-hook) precondition: sentinel settings.json carries NO Stop hook (a dropped --no-hook would ADD one)" "! grep -q 'stop-learning-loop' '$CR2H_SETTINGS'"
assert "CR-2 (--no-hook) precondition: jq is present (register_stop_hook would genuinely mutate, not skip)" "command -v jq"
# Capture the exact bytes of the sentinel settings.json BEFORE the update.
CR2H_SETTINGS_BEFORE="$CR2H_BASE/settings.before.json"
cp "$CR2H_SETTINGS" "$CR2H_SETTINGS_BEFORE"
# Stage a vN+1 payload and run the NATURAL update (copy mode): installed CLI, NO
# --target/--root, neutral cwd. This drives _apply_into_home, which runs the staged
# install.sh with --no-hook -- so settings.json must be left untouched.
build_remed_source "$CR2H_PAY" "$REMED_VN1"
assert "CR-2 (--no-hook) safety: vN+1 payload is under TMP_ROOT (offline staging)" "case '$CR2H_PAY' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
( cd /tmp && CLAUDE_HOME="$CR2H_HOME" "$CR2H_CLI" update --source "$CR2H_PAY" --verify-cmd true \
    >"$CR2H_BASE/update.log" 2>&1 ) || true
# Belt that the update actually applied (so the no-mutation assertion is not vacuous
# against an update that never ran).
assert "CR-2 (--no-hook) belt: the update actually applied (changed and verified)" "grep -q 'status: changed and verified' '$CR2H_BASE/update.log'"
# THE CONFIRMING FALSIFIER (a) -- the Stop-hook was NOT (re)registered: settings.json
# carries no learning-loop Stop-hook command after the update.
assert "CR-2 (--no-hook): the global Stop-hook is NOT registered by the update (no learning-loop hook in settings.json)" "! grep -q 'stop-learning-loop' '$CR2H_SETTINGS'"
assert "CR-2 (--no-hook): the enforce Stop-hook is NOT registered by the update either" "! grep -q 'plumbline-enforce' '$CR2H_SETTINGS'"
# (b) -- the settings.json is BYTE-UNCHANGED by the update (the user's file is not
# rewritten at all: no hook added, sentinel marker + content intact).
assert "CR-2 (--no-hook): settings.json is BYTE-UNCHANGED by the update (not rewritten)" "cmp -s '$CR2H_SETTINGS_BEFORE' '$CR2H_SETTINGS'"
assert "CR-2 (--no-hook): the user's sentinel marker survives the update untouched" "grep -q 'DO_NOT_REWRITE_ON_UPDATE' '$CR2H_SETTINGS'"

# ====================================================================
# SPRINT 3 REMEDIATION (belt) -- the REAL ~/.claude was NEVER written by ANY of the
# remediation blocks above. Re-capture the post-test listing + dir mtime and compare
# to the SAME pre-test markers the Sprint-3 block captured (PUR3S_REAL_*_BEFORE).
# A remediation test that wrote the real HOME is itself the defect this feature
# exists to prevent.
# ====================================================================
if [ -d "$PUR3S_REAL_HOME" ]; then
  # shellcheck disable=SC2012  # a sorted name listing is exactly the change-detector we want
  ( ls -A "$PUR3S_REAL_HOME" 2>/dev/null | sort ) > "$TMP_ROOT/remed-real-list-after.txt" 2>/dev/null || : > "$TMP_ROOT/remed-real-list-after.txt"
  # shellcheck disable=SC2012  # capturing the dir's own stat line (mtime) as a tamper marker
  REMED_REAL_MTIME_AFTER="$(ls -ld "$PUR3S_REAL_HOME" 2>/dev/null || true)"
else
  : > "$TMP_ROOT/remed-real-list-after.txt"
  REMED_REAL_MTIME_AFTER="<absent>"
fi
assert "SPRINT-3 REMED belt: real ~/.claude listing UNCHANGED by the remediation tests" "diff '$PUR3S_REAL_LIST_BEFORE' '$TMP_ROOT/remed-real-list-after.txt' >/dev/null 2>&1"
assert_eq "SPRINT-3 REMED belt: real ~/.claude dir mtime UNCHANGED by the remediation tests" "$PUR3S_REAL_MTIME_BEFORE" "$REMED_REAL_MTIME_AFTER"
assert "SPRINT-3 REMED belt: all remediation sandbox roots are under TMP_ROOT" "case '$CR1_BASE' in '$TMP_ROOT'/*) case '$CR2_BASE' in '$TMP_ROOT'/*) case '$CR2H_BASE' in '$TMP_ROOT'/*) case '$CR3_BASE' in '$TMP_ROOT'/*) case '$CR5_BASE' in '$TMP_ROOT'/*) case '$SEC2_BASE' in '$TMP_ROOT'/*) true ;; *) false ;; esac ;; *) false ;; esac ;; *) false ;; esac ;; *) false ;; esac ;; *) false ;; esac ;; *) false ;; esac"

# ====================================================================
# REQ-PUR-FOLLOWUP-DOCTOR -- `doctor` + `honest-status` resolve identity (version +
# update slug) from the install-identity ANCHOR, exactly like `version` and
# `update --check` already do. Code-review follow-up, now in-scope by user request.
#
# THE GAP (RED-FOR-THE-RIGHT-REASON TODAY): in plumbline_update.py, doctor() calls
# read_version(root) + default_repo_slug(root), and honest_status() calls
# read_version(root) -- ALL with the DEFAULT explicit_root=True. So an INSTALLED
# doctor/honest-status run from a FOREIGN cwd (no --root) reads the cwd's
# VERSION/git-origin instead of the install anchor. `version` and `update --check`
# already thread explicit_root=bool(args.root) and resolve from the anchor; these
# two do not. Confirmed current behavior off-tree:
#   * doctor from a foreign repo  -> dies "compatibility.json not found" (exit 1):
#       it never reaches a correct version/slug line at all.
#   * doctor from /tmp            -> dies "VERSION not found at /tmp/VERSION".
#   * honest-status from a foreign repo -> prints "version: 9.9.9" (the cwd's VERSION).
# After the fix doctor/honest-status MUST report the INSTALLED identity (the anchor's
# version + slug) regardless of cwd, never the cwd's value, never a VERSION-not-found
# error. (The doctor file-existence checks install.sh/run_all.sh/compatibility.json
# stay root-relative and may read "fail" off-tree -- that is expected and NOT what
# this block contracts; we contract only the reported version + update slug lines.)
#
# OFFLINE (NFR): doctor/honest-status read version+slug from the LOCAL anchor file
# and make NO network call -- there is no http.server stub and no PLUMBLINE_GITHUB_API
# seam here. So every assertion below stays HARD on EVERY OS (no macOS skip needed:
# nothing depends on loopback connectivity).
# SANDBOX-ONLY: every path is under $TMP_ROOT (mktemp); the real ~/.claude is NEVER
# touched. bash-3.2-safe (no $()-wrapped heredocs -- in fact no heredocs at all in
# this block), ASCII-only, eval-free (doctor/honest-status output is captured to a
# log FILE and grepped; no payload is interpolated into shell or python code).
# ====================================================================
DOC_INSTALLED_VERSION="$REPO_VERSION"

# COPY-install Plumbline into a sandbox HOME so the installed lib runs from
# $CLAUDE_HOME/lib and resolves identity from the install anchor (the C2.5/PUR-1.1
# pattern). The anchor carries the installed version + slug DYAI2025/Plumbline.
DOC_HOME="$TMP_ROOT/doctor-anchor-home"
CLAUDE_HOME="$DOC_HOME" "$REPO_DIR/config/claude/install.sh" --copy --no-agents --no-commands --no-skills --no-hook --force >"$TMP_ROOT/doctor-install.log" 2>&1
DOC_CLI="$DOC_HOME/bin/plumbline"
assert_file "DOCTOR install: copy-mode plumbline wrapper exists in sandbox" "$DOC_CLI"
# Safety belt: prove this block never wrote to the operator's real ~/.claude.
assert "DOCTOR safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$DOC_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
DOC_ANCHOR="$DOC_HOME/.plumbline-install.json"
assert_file "DOCTOR precondition: copy install wrote the identity anchor" "$DOC_ANCHOR"
assert "DOCTOR precondition: anchor carries the installed slug DYAI2025/Plumbline" "grep -q 'DYAI2025/Plumbline' '$DOC_ANCHOR'"

# A foreign repo with its OWN VERSION=9.9.9 and its OWN git origin. The installed
# doctor/honest-status must ignore ALL of it (identity is the install's anchor, not cwd).
DOC_FAKEREPO="$TMP_ROOT/doctor-fakerepo"
mkdir -p "$DOC_FAKEREPO"
printf '9.9.9\n' > "$DOC_FAKEREPO/VERSION"
git -C "$DOC_FAKEREPO" init -q
git -C "$DOC_FAKEREPO" remote add origin "https://github.com/EVILFORK/NotPlumbline.git"

# --- 1) doctor version, FOREIGN cwd (own VERSION=9.9.9), no --root --------------
# doctor exits non-zero off-tree (root-relative file checks fail) -- that is expected
# and NOT contracted here -- so capture combined output to a log with `|| true` and
# assert on the PRINTED version line. RED now: doctor dies "compatibility.json not
# found" before any version line, so DOC_VER_FOREIGN is empty (mismatch) AND the
# error log carries no "version: <installed>" line.
( cd "$DOC_FAKEREPO" && "$DOC_CLI" doctor >"$TMP_ROOT/doctor-foreign.log" 2>&1 ) || true
DOC_VER_FOREIGN="$(grep -E '^version: ' "$TMP_ROOT/doctor-foreign.log" 2>/dev/null | head -1 | sed 's/^version: //')"
assert_eq "REQ-PUR-FOLLOWUP-DOCTOR 1: doctor version from foreign repo is the INSTALLED version" "$DOC_INSTALLED_VERSION" "$DOC_VER_FOREIGN"
assert "REQ-PUR-FOLLOWUP-DOCTOR 1: doctor version from foreign repo is NEVER the foreign 9.9.9" "! grep -Eq '^version: 9\.9\.9$' '$TMP_ROOT/doctor-foreign.log'"
assert "REQ-PUR-FOLLOWUP-DOCTOR 1: doctor from foreign repo never errors VERSION not found" "! grep -q 'VERSION not found' '$TMP_ROOT/doctor-foreign.log'"

# --- 2) doctor update-slug, FOREIGN cwd, no --root ------------------------------
# doctor prints "update slug: <slug>" (the resolved upstream). From the foreign repo
# it MUST report the anchor slug DYAI2025/Plumbline, NOT the foreign origin
# EVILFORK/NotPlumbline. RED now: doctor dies before the slug line (no "update slug:"
# printed at all), and were it to reach it, default_repo_slug(root) with the default
# explicit_root=True would consult the foreign git origin.
DOC_SLUG_FOREIGN="$(grep -E '^update slug: ' "$TMP_ROOT/doctor-foreign.log" 2>/dev/null | head -1 | sed 's/^update slug: //')"
assert_eq "REQ-PUR-FOLLOWUP-DOCTOR 2: doctor update slug from foreign repo is the anchor slug DYAI2025/Plumbline" "DYAI2025/Plumbline" "$DOC_SLUG_FOREIGN"
assert "REQ-PUR-FOLLOWUP-DOCTOR 2: doctor update slug from foreign repo is NEVER the foreign EVILFORK/NotPlumbline" "! grep -Eq '^update slug: .*EVILFORK/NotPlumbline' '$TMP_ROOT/doctor-foreign.log'"

# --- 3) doctor version, NEUTRAL cwd (/tmp), no --root ---------------------------
# RED now: doctor dies "VERSION not found at /tmp/VERSION".
( cd /tmp && "$DOC_CLI" doctor >"$TMP_ROOT/doctor-neutral.log" 2>&1 ) || true
DOC_VER_NEUTRAL="$(grep -E '^version: ' "$TMP_ROOT/doctor-neutral.log" 2>/dev/null | head -1 | sed 's/^version: //')"
assert_eq "REQ-PUR-FOLLOWUP-DOCTOR 3: doctor version from /tmp is the INSTALLED version" "$DOC_INSTALLED_VERSION" "$DOC_VER_NEUTRAL"
assert "REQ-PUR-FOLLOWUP-DOCTOR 3: doctor from /tmp never errors VERSION not found" "! grep -q 'VERSION not found' '$TMP_ROOT/doctor-neutral.log'"

# --- 4) honest-status version, FOREIGN cwd (own VERSION=9.9.9), no --root -------
# honest-status prints "version: <V>". From the foreign repo it MUST report the
# INSTALLED version, NEVER 9.9.9. RED now: honest_status() calls read_version(root)
# with the default explicit_root=True -> reads the cwd's VERSION -> prints
# "version: 9.9.9".
( cd "$DOC_FAKEREPO" && "$DOC_CLI" honest-status >"$TMP_ROOT/honest-foreign.log" 2>&1 ) || true
DOC_HS_VER_FOREIGN="$(grep -E '^version: ' "$TMP_ROOT/honest-foreign.log" 2>/dev/null | head -1 | sed 's/^version: //')"
assert_eq "REQ-PUR-FOLLOWUP-DOCTOR 4: honest-status version from foreign repo is the INSTALLED version" "$DOC_INSTALLED_VERSION" "$DOC_HS_VER_FOREIGN"
assert "REQ-PUR-FOLLOWUP-DOCTOR 4: honest-status version from foreign repo is NEVER the foreign 9.9.9" "! grep -Eq '^version: 9\.9\.9$' '$TMP_ROOT/honest-foreign.log'"
assert "REQ-PUR-FOLLOWUP-DOCTOR 4: honest-status keeps its Plumbline language from foreign repo" "grep -q 'changed, not yet verified' '$TMP_ROOT/honest-foreign.log'"

finish "update layer tests"
