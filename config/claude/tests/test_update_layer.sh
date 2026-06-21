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
if [ -n "$PUR_PORT" ]; then
  ( cd "$FAKEREPO" && PLUMBLINE_GITHUB_API="http://127.0.0.1:$PUR_PORT" "$PUR_CLI" update --check >"$TMP_ROOT/pur-check.log" 2>&1 ) || true
fi
kill "$PUR_STUB_PID" 2>/dev/null || true
wait "$PUR_STUB_PID" 2>/dev/null || true
assert "PUR-1.1 AC-PUR-02.2: --check from foreign repo queries installed slug DYAI2025/Plumbline" "test -f '$PUR_REC' && grep -q '/repos/DYAI2025/Plumbline/' '$PUR_REC'"
assert "PUR-1.1 AC-PUR-02.2: --check from foreign repo does NOT query the foreign slug" "! { test -f '$PUR_REC' && grep -q '/repos/EVILFORK/NotPlumbline/' '$PUR_REC'; }"

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

finish "update layer tests"
