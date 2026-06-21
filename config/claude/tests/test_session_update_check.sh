#!/usr/bin/env bash
#
# Sprint 4 (feature: plumbline-update-reliability) -- Phase 1 RED acceptance
# contract for the SessionStart update-check.
#
#   REQ-PUR-08 (NEW): the session-start hook runs `plumbline update --check`
#     ON BY DEFAULT, opt-OUT via env, THROTTLED (<=1 network hit/day, cached),
#     NON-blocking, NOTIFY-only (never auto-applies; NFR-PUR-06).
#   REQ-PUR-07 (mostly confirming): the Sprint-1..3 update falsifiers
#     (test_update_layer.sh) are wired into run_all.sh and are behaviour/counter-
#     based (they redden if the underlying fix is reverted), not outcome-only.
#
# WIRING-IN-PROD (the value this kills): a `plumbline update --check` that works
# in isolation but is never actually invoked by the real session-start hook, or
# that silently auto-applies / blocks the session / re-hits the network every
# session, delivers ZERO user value (or NEGATIVE: a hung or self-mutating
# session). So every REQ-PUR-08 falsifier below drives the REAL production hook
# (config/claude/hooks/session-start.sh) in a sandbox, offline via the
# PLUMBLINE_GITHUB_API stub seam -- never a hand-built harness.
#
# CHOSEN CONTRACT (stated so the coder matches exactly):
#   * Opt-out env:        PLUMBLINE_NO_UPDATE_CHECK=1   (set/non-empty => no check)
#   * Throttle-cache path: $CLAUDE_HOME/.plumbline/update/last-check.json
#       (the cache lives under the installed Claude home, NOT the repo; a second
#        session within the throttle window reads it and skips the network).
#   * The update notice goes to STDERR (stdout MUST stay a single SessionStart
#     JSON object -- the existing web-bootstrap contract). The notice text must
#     contain the literal token "update available" and name `plumbline update`.
#
# SANDBOX-ONLY (NFR-PUR-01, binding): every path lives under $TMP_ROOT (mktemp);
# CLAUDE_HOME / HOME are sandbox dirs under $TMP_ROOT; a safety belt asserts the
# real ~/.claude is NEVER written. OFFLINE: the release check is driven through
# the PLUMBLINE_GITHUB_API recording stub on 127.0.0.1 (0 real network).
# bash-3.2-safe (NO $()-wrapped heredocs anywhere; every heredoc is redirected to
# a file then read back), ASCII-only, eval-free.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

HOOK="$REPO_DIR/config/claude/hooks/session-start.sh"
RUN_ALL="$REPO_DIR/config/claude/tests/run_all.sh"
UPDATE_LAYER_TEST="$REPO_DIR/config/claude/tests/test_update_layer.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf "$TMP_ROOT"' EXIT

echo "test_session_update_check"

REPO_VERSION="$(repo_version "$REPO_DIR")"
# A "newer latest" one minor above the current version, so update-available stays
# valid across every release bump (no hardcoded literal the repo catches up to).
NEWER_VERSION="$(awk -F. -v OFS=. '{print $1, $2+1, 0}' <<<"$REPO_VERSION")"

# ============================================================================
# Safety belt #1 -- capture the REAL ~/.claude state BEFORE anything runs, so we
# can prove at the end this whole suite never wrote to it.
# ============================================================================
REAL_HOME="$HOME/.claude"
REAL_LIST_BEFORE="$TMP_ROOT/real-list-before.txt"
if [ -d "$REAL_HOME" ]; then
  # shellcheck disable=SC2012  # a sorted name listing is exactly the change-detector we want
  ( ls -A "$REAL_HOME" 2>/dev/null | sort ) > "$REAL_LIST_BEFORE" 2>/dev/null || : > "$REAL_LIST_BEFORE"
else
  : > "$REAL_LIST_BEFORE"
fi
# NOTE on the safety instrument: the SORTED LISTING is the honest sandbox guarantee
# (it proves no persistent entry under the real ~/.claude was added/removed by this
# suite). A raw directory-MTIME equality is deliberately NOT used: a dir's mtime is
# bumped by ANY transient child create/delete from ANY concurrent process, and this
# is a live multi-agent workstation where other sessions touch ~/.claude
# independently -- so an mtime-equality belt would flake on cross-process activity
# this suite did not cause. We instead pin the listing PLUS the absence of our own
# artifacts under the real home (anchor / throttle cache), which only THIS code
# could have written there.

# ============================================================================
# The OFFLINE recording GitHub-release stub. Standalone .py file (NOT a
# $()-wrapped heredoc). argv: <record-file> <port-file> <tag>. Records every
# requested path (one line per hit) so we can COUNT network hits (throttle), and
# returns a release JSON whose tag_name is the configured <tag> so the hook's
# `update --check` deterministically sees that version as "latest".
# ============================================================================
STUB_DIR="$TMP_ROOT/release-stub"
mkdir -p "$STUB_DIR"
STUB_PY="$STUB_DIR/stub.py"
cat > "$STUB_PY" <<'PYEOF'
import sys, json, http.server
recfile, portfile, tag = sys.argv[1], sys.argv[2], sys.argv[3]

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open(recfile, "a") as f:
            f.write("HIT " + self.path + "\n")
        body = json.dumps({"tag_name": tag, "draft": False, "prerelease": False}).encode()
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

# stub_start <tag> -- boot the stub returning <tag> as the latest release, set
# STUB_PORT / STUB_PID / STUB_REC. bash-3.2-safe port polling; no $()-heredocs.
STUB_PID=""
STUB_PORT=""
STUB_REC=""
stub_start() {
  ssu_tag="$1"
  STUB_REC="$STUB_DIR/rec.txt"
  : > "$STUB_REC"
  ssu_portfile="$STUB_DIR/port.txt"
  rm -f "$ssu_portfile"
  python3 "$STUB_PY" "$STUB_REC" "$ssu_portfile" "$ssu_tag" >"$STUB_DIR/stub.log" 2>&1 &
  STUB_PID=$!
  ssu_wait=0
  while [ ! -s "$ssu_portfile" ] && [ "$ssu_wait" -lt 50 ]; do
    sleep 0.1
    ssu_wait=$((ssu_wait + 1))
  done
  STUB_PORT="$(cat "$ssu_portfile" 2>/dev/null || true)"
}

stub_stop() {
  [ -n "$STUB_PID" ] || return 0
  kill "$STUB_PID" 2>/dev/null || true
  wait "$STUB_PID" 2>/dev/null || true
  STUB_PID=""
}

# stub_hits -- number of recorded network hits since the last `: > "$STUB_REC"`.
# Counts matching lines with awk (NOT `grep -c`, which exits 1 on a zero count and
# would make a `|| printf 0` fallback emit a SECOND "0" line -> a "0\n0" value that
# breaks the numeric assertions). awk always prints exactly one integer line.
stub_hits() {
  if [ -f "$STUB_REC" ]; then
    awk '/^HIT /{n++} END{print n+0}' "$STUB_REC" 2>/dev/null || printf '0\n'
  else
    printf '0\n'
  fi
}

# install_sandbox_home <home> <version> -- install Plumbline into a sandbox HOME
# at <version> through the REAL install.sh (copy mode so $CLAUDE_HOME/bin/plumbline
# + the anchor are present and self-contained). Hooks/agents/commands/skills off
# (this REQ only needs the CLI + anchor); --force for a clean idempotent install.
install_sandbox_home() {
  ish_home="$1"; ish_ver="$2"
  ish_src="$ish_home.src"
  mkdir -p "$ish_src/config/claude/lib" "$ish_src/config/claude/bin" "$ish_src/config/claude/tests"
  printf '%s\n' "$ish_ver" > "$ish_src/VERSION"
  printf '{\n  "version": "%s",\n  "schema": 1,\n  "verifyCommand": "true",\n  "frozenContracts": ["VERSION"],\n  "migrations": []\n}\n' "$ish_ver" > "$ish_src/compatibility.json"
  cp "$REPO_DIR/config/claude/install.sh" "$ish_src/config/claude/install.sh"
  cp "$REPO_DIR/config/claude/lib/plumbline_update.py" "$ish_src/config/claude/lib/plumbline_update.py"
  cp "$REPO_DIR/config/claude/bin/plumbline" "$ish_src/config/claude/bin/plumbline" 2>/dev/null || true
  chmod +x "$ish_src/config/claude/install.sh" "$ish_src/config/claude/bin/plumbline" 2>/dev/null || true
  printf '%s\n%s\n' '#!/usr/bin/env bash' 'exit 0' > "$ish_src/config/claude/tests/run_all.sh"
  chmod +x "$ish_src/config/claude/tests/run_all.sh"
  git -C "$ish_src" init -q
  git -C "$ish_src" remote add origin "https://github.com/DYAI2025/Plumbline.git"
  CLAUDE_HOME="$ish_home" "$ish_src/config/claude/install.sh" --copy \
    --no-agents --no-commands --no-skills --no-hook --force \
    >"$ish_home.install.log" 2>&1
}

# run_hook <home> <stdout-file> <stderr-file> [env-assignment ...]
# Drive the REAL session-start hook against a sandbox HOME, OFFLINE via the
# PLUMBLINE_GITHUB_API stub seam. AGILETEAM_FORCE_BOOTSTRAP=1 so the bootstrap
# branch runs locally (it is otherwise remote-only); CLAUDE_CODE_REMOTE left
# unset. We capture stdout and stderr to SEPARATE files (the notice must be on
# stderr; stdout must stay a single JSON object). Returns the hook's exit status
# in RUN_HOOK_STATUS. The whole call is wrapped so a NON-blocking hook returns
# promptly; a hang is caught by the watchdog in the timeout test below.
RUN_HOOK_STATUS=0
run_hook() {
  rh_home="$1"; rh_out="$2"; rh_err="$3"; shift 3
  RUN_HOOK_STATUS=0
  if env "$@" \
      AGILETEAM_FORCE_BOOTSTRAP=1 \
      CLAUDE_HOME="$rh_home" HOME="$rh_home" \
      CLAUDE_PROJECT_DIR="$REPO_DIR" \
      PLUMBLINE_GITHUB_API="http://127.0.0.1:$STUB_PORT" \
      bash "$HOOK" >"$rh_out" 2>"$rh_err"; then
    RUN_HOOK_STATUS=0
  else
    RUN_HOOK_STATUS=$?
  fi
}

# ============================================================================
# FALSIFIER 1 (RED NOW) -- on-by-default + notify when BEHIND.
# With NO opt-out env, a sandbox HOME installed BEHIND latest (stub returns the
# newer release), the hook MUST print an "update available: vN -> vM, run
# `plumbline update`" notice to STDERR. RED today: the hook only checks when the
# OPT-IN PLUMBLINE_AUTO_UPDATE_CHECK=1 is set, so with no such env it prints
# NOTHING about updates.
# ============================================================================
F1_HOME="$TMP_ROOT/f1-home"
install_sandbox_home "$F1_HOME" "$REPO_VERSION"
assert_file "F1 precondition: installed plumbline CLI exists in sandbox HOME" "$F1_HOME/bin/plumbline"
assert "F1 safety: sandbox HOME is under TMP_ROOT (not real ~/.claude)" "case '$F1_HOME' in '$TMP_ROOT'/*) true ;; *) false ;; esac"
stub_start "v$NEWER_VERSION"
assert "F1 precondition: offline release stub is listening" "test -n '$STUB_PORT'"
F1_OUT="$TMP_ROOT/f1-stdout.json"
F1_ERR="$TMP_ROOT/f1-stderr.txt"
run_hook "$F1_HOME" "$F1_OUT" "$F1_ERR"
stub_stop
assert_eq "F1: the hook exits 0 (never fatal)" "0" "$RUN_HOOK_STATUS"
# THE VALUE FALSIFIER: the behind-install notice is actually surfaced.
assert "F1 REQ-PUR-08 (on-by-default): hook prints an 'update available' notice on stderr when behind" "grep -qi 'update available' '$F1_ERR'"
assert "F1 REQ-PUR-08 (notify): the notice names the command 'plumbline update' to run" "grep -q 'plumbline update' '$F1_ERR'"
assert "F1 REQ-PUR-08 (notify): the notice carries the newer latest version" "grep -qF '$NEWER_VERSION' '$F1_ERR'"
# The stdout SessionStart JSON contract must remain intact (notice on stderr only).
assert "F1: stdout stays a single valid JSON object (notice did not leak to stdout)" "jq -e . '$F1_OUT'"
assert "F1: stdout SessionStart JSON carries no 'update available' text" "! grep -qi 'update available' '$F1_OUT'"

# ============================================================================
# FALSIFIER 2 (confirming/RED) -- SILENT when CURRENT.
# A sandbox HOME already AT latest (stub returns the SAME version) -> NO update
# notice. This is the path-specific falsifier for the up-to-date branch: it
# FAILS if the hook ever notifies unconditionally (cry-wolf). Likely RED today
# only because nothing runs by default; it stays a real guard after the fix.
# ============================================================================
F2_HOME="$TMP_ROOT/f2-home"
install_sandbox_home "$F2_HOME" "$REPO_VERSION"
stub_start "v$REPO_VERSION"
F2_OUT="$TMP_ROOT/f2-stdout.json"
F2_ERR="$TMP_ROOT/f2-stderr.txt"
run_hook "$F2_HOME" "$F2_OUT" "$F2_ERR"
stub_stop
assert_eq "F2: the hook exits 0 when current" "0" "$RUN_HOOK_STATUS"
assert "F2 REQ-PUR-08 (silent-when-current): NO 'update available' notice when already at latest" "! grep -qi 'update available' '$F2_ERR'"
assert "F2: stdout stays a single valid JSON object when current" "jq -e . '$F2_OUT'"

# ============================================================================
# FALSIFIER 3 (RED NOW) -- OPT-OUT: PLUMBLINE_NO_UPDATE_CHECK=1 disables it.
# With the opt-out env set AND the HOME behind latest, the hook must do NO check
# (the stub records ZERO hits) and print NO notice. RED today: today there is no
# on-by-default check to opt out OF, AND no honoring of this env -- so this is
# RED-for-the-right-reason once F1 makes the check on-by-default (the opt-out must
# then genuinely suppress it; a check that ignores the opt-out reddens here).
# ============================================================================
F3_HOME="$TMP_ROOT/f3-home"
install_sandbox_home "$F3_HOME" "$REPO_VERSION"
stub_start "v$NEWER_VERSION"
F3_OUT="$TMP_ROOT/f3-stdout.json"
F3_ERR="$TMP_ROOT/f3-stderr.txt"
run_hook "$F3_HOME" "$F3_OUT" "$F3_ERR" "PLUMBLINE_NO_UPDATE_CHECK=1"
F3_HITS="$(stub_hits)"
stub_stop
assert_eq "F3: the hook exits 0 with opt-out set" "0" "$RUN_HOOK_STATUS"
assert "F3 REQ-PUR-08 (opt-out): NO 'update available' notice when PLUMBLINE_NO_UPDATE_CHECK=1 (even though behind)" "! grep -qi 'update available' '$F3_ERR'"
assert_eq "F3 REQ-PUR-08 (opt-out): opt-out triggers ZERO network hits at the stub" "0" "$F3_HITS"
assert "F3: stdout stays a single valid JSON object under opt-out" "jq -e . '$F3_OUT'"

# ============================================================================
# FALSIFIER 4 (RED NOW) -- NON-blocking + NEVER auto-applies (NFR-PUR-06).
# (a) the hook returns PROMPTLY -- a watchdog kills it if it has not finished
#     within a generous budget; a hang/block reddens. (b) the install is
#     UNCHANGED by the check: no apply ran -> the installed CLI version is still
#     vN, the anchor still reads vN, and NO snapshot/last-success apply artifact
#     was written (the only write allowed is the throttle-cache, asserted in F5).
# RED today: there is no on-by-default check, so the notify path that must stay
# non-applying does not exist yet; once it lands, an apply on session-start would
# redden (b), and a blocking check would redden (a).
# ============================================================================
F4_HOME="$TMP_ROOT/f4-home"
install_sandbox_home "$F4_HOME" "$REPO_VERSION"
F4_ANCHOR="$F4_HOME/.plumbline-install.json"
assert_file "F4 precondition: anchor written at install (vN)" "$F4_ANCHOR"
assert "F4 precondition: anchor reads vN before the session-start check" "grep -q '\"$REPO_VERSION\"' '$F4_ANCHOR'"
stub_start "v$NEWER_VERSION"
F4_OUT="$TMP_ROOT/f4-stdout.json"
F4_ERR="$TMP_ROOT/f4-stderr.txt"
# (a) NON-blocking watchdog: run the hook in the background and require it to
# finish within the budget. If it is still alive after the budget, it BLOCKED ->
# kill it and record a HUNG marker (RED). bash-3.2-safe polling (no `timeout(1)`,
# which is absent on macOS); no $()-wrapped heredocs.
F4_DONE="$TMP_ROOT/f4-done.marker"
rm -f "$F4_DONE"
(
  env AGILETEAM_FORCE_BOOTSTRAP=1 \
      CLAUDE_HOME="$F4_HOME" HOME="$F4_HOME" \
      CLAUDE_PROJECT_DIR="$REPO_DIR" \
      PLUMBLINE_GITHUB_API="http://127.0.0.1:$STUB_PORT" \
      bash "$HOOK" >"$F4_OUT" 2>"$F4_ERR"
  printf 'done\n' > "$F4_DONE"
) &
F4_PID=$!
f4_wait=0
# Budget: 100 * 0.2s = 20s. A non-blocking, throttled, single-fetch check
# finishes in well under a second; 20s is generous headroom that still catches a
# genuine hang/block.
while [ ! -s "$F4_DONE" ] && [ "$f4_wait" -lt 100 ]; do
  sleep 0.2
  f4_wait=$((f4_wait + 1))
done
if [ -s "$F4_DONE" ]; then
  f4_blocked=no
else
  f4_blocked=yes
  kill "$F4_PID" 2>/dev/null || true
fi
wait "$F4_PID" 2>/dev/null || true
stub_stop
assert_eq "F4 REQ-PUR-08 (non-blocking): the hook returns promptly (did NOT block the session)" "no" "$f4_blocked"
# (b) NEVER auto-applies: the install must be byte-identical apart from the
# throttle-cache. The installed CLI still reports vN, the anchor still reads vN,
# and there is NO apply artifact (snapshot / last-success.json).
f4_cli_ver="$(cd /tmp && "$F4_HOME/bin/plumbline" version 2>/dev/null || true)"
assert_eq "F4 REQ-PUR-08 (notify-only): installed CLI version is UNCHANGED after the check (no apply, still vN)" "$REPO_VERSION" "$f4_cli_ver"
assert "F4 REQ-PUR-08 (notify-only): anchor still reads vN after the check (apply never re-stamped it)" "grep -q '\"$REPO_VERSION\"' '$F4_ANCHOR'"
assert "F4 REQ-PUR-08 (notify-only): the check did NOT write the apply last-success.json" "test ! -e '$F4_HOME/.plumbline/update/last-success.json'"
assert "F4 REQ-PUR-08 (notify-only): the check did NOT create any apply snapshot" "test ! -d '$F4_HOME/.plumbline/update/snapshots'"
assert "F4: stdout stays a single valid JSON object alongside the non-blocking notify check" "jq -e . '$F4_OUT'"

# ============================================================================
# FALSIFIER 5 (RED NOW) -- THROTTLED <=1/day (cached).
# A FIRST session-start check hits the network once and writes the throttle cache
# ($CLAUDE_HOME/.plumbline/update/last-check.json). A SECOND check within the
# window must read the cache and NOT re-hit the network: across BOTH runs the stub
# records EXACTLY ONE hit. RED today: no on-by-default check and no throttle cache
# at all, so this is RED-for-the-right-reason; after the fix two back-to-back
# sessions must total a single network hit.
# ============================================================================
F5_HOME="$TMP_ROOT/f5-home"
install_sandbox_home "$F5_HOME" "$REPO_VERSION"
F5_CACHE="$F5_HOME/.plumbline/update/last-check.json"
assert "F5 precondition: throttle cache is absent before the first check" "test ! -e '$F5_CACHE'"
stub_start "v$NEWER_VERSION"
# Single stub instance, single record file: both runs count against ONE counter.
F5_OUT1="$TMP_ROOT/f5-stdout-1.json"; F5_ERR1="$TMP_ROOT/f5-stderr-1.txt"
F5_OUT2="$TMP_ROOT/f5-stdout-2.json"; F5_ERR2="$TMP_ROOT/f5-stderr-2.txt"
run_hook "$F5_HOME" "$F5_OUT1" "$F5_ERR1"
F5_HITS_AFTER1="$(stub_hits)"
run_hook "$F5_HOME" "$F5_OUT2" "$F5_ERR2"
F5_HITS_AFTER2="$(stub_hits)"
stub_stop
# After the first check: exactly one network hit AND the cache was written.
assert_eq "F5 REQ-PUR-08 (throttle): the FIRST session-start check hits the network exactly once" "1" "$F5_HITS_AFTER1"
assert_file "F5 REQ-PUR-08 (throttle): the first check WROTE the throttle cache (last-check.json)" "$F5_CACHE"
# After the second check within the window: STILL exactly one hit (cache reused).
assert_eq "F5 REQ-PUR-08 (throttle): a SECOND check within the window does NOT re-hit the network (still 1 hit total)" "1" "$F5_HITS_AFTER2"
# Belt: both runs still exited 0 (the throttle never makes the hook fatal).
assert "F5: the throttled second run still produced a valid SessionStart JSON" "jq -e . '$F5_OUT2'"

# ============================================================================
# REQ-PUR-07 (CONFIRMING) -- the Sprint-1..3 update falsifiers are WIRED into CI
# and are behaviour/counter-based.
#
# (1) test_update_layer.sh is actually INVOKED by run_all.sh (so the G1-G3
#     falsifiers run in CI -- a falsifier that never runs guards nothing).
# (2) the key identity/auth/apply falsifiers are BEHAVIOUR-based: they assert the
#     system would REDDEN if the fix were reverted, not merely an outcome string.
#     We reference the EXISTING falsifiers as the evidence (CR-1 symlink-refusal
#     counter, the CRITICAL-1 token-exfil counter, AC-PUR-02.5 advanced-checkout
#     counter) rather than duplicating them. A finding is flagged if any is
#     actually outcome-only.
# ============================================================================
# (1) wired-into-CI -- run_all.sh names the update-layer test as a stage it runs.
assert "REQ-PUR-07: run_all.sh INVOKES test_update_layer.sh (G1-G3 falsifiers run in CI)" "grep -q 'bash config/claude/tests/test_update_layer.sh' '$RUN_ALL'"
assert "REQ-PUR-07: run_all.sh INVOKES this session-start update-check test (REQ-PUR-08 runs in CI)" "grep -q 'bash config/claude/tests/test_session_update_check.sh' '$RUN_ALL'"

# (2) behaviour/counter evidence -- each referenced falsifier asserts the
# would-redden-on-revert property, not just a happy-path outcome:
#  * CR-1: after a REFUSED symlink update, the lib is STILL a symlink AND the
#    version tracks the LIVE checkout (vN+2), explicitly NOT the frozen payload
#    vN+1 -> reddens if the refusal regressed to a silent copy-convert.
assert "REQ-PUR-07 (behaviour): CR-1 asserts the install is NOT copy-converted (still a symlink) after a refused update" "grep -q 'CR-1: after the refused update the installed library is STILL a symlink' '$UPDATE_LAYER_TEST'"
assert "REQ-PUR-07 (behaviour): CR-1 asserts the symlink version is NOT frozen to the payload (counter, not outcome)" "grep -q 'CR-1: symlink install version is NOT frozen to the payload' '$UPDATE_LAYER_TEST'"
#  * CRITICAL-1 exfil: the SENTINEL token literal is ABSENT from the recorded
#    request bytes at the insecure host -> reddens if the host-gate regressed.
assert "REQ-PUR-07 (behaviour): the token-exfil falsifier asserts the token literal NEVER reaches the insecure host" "grep -q 'sentinel token literal NEVER captured at the insecure-host stub' '$UPDATE_LAYER_TEST'"
assert "REQ-PUR-07 (behaviour): the gate-off falsifier pins 'OFF by default' (path-specific counter)" "grep -q 'insecure-token gate is OFF by default' '$UPDATE_LAYER_TEST'"
#  * AC-PUR-02.5: the symlink version tracks the ADVANCED checkout (vN+1) and is
#    explicitly NOT the frozen install-time value -> reddens if it regressed to a
#    frozen anchor read.
assert "REQ-PUR-07 (behaviour): AC-PUR-02.5 asserts symlink version tracks the ADVANCED checkout (not the frozen value)" "grep -q 'AC-PUR-02.5: symlink-mode version is NOT the frozen install-time value' '$UPDATE_LAYER_TEST'"

# ============================================================================
# Safety belt #2 -- the REAL ~/.claude was NEVER written by ANY block above.
# Re-capture the post-test listing + dir mtime and compare to the pre-test
# markers. A test that wrote the real HOME is itself the defect this feature
# exists to prevent.
# ============================================================================
REAL_LIST_AFTER="$TMP_ROOT/real-list-after.txt"
if [ -d "$REAL_HOME" ]; then
  # shellcheck disable=SC2012  # a sorted name listing is exactly the change-detector we want
  ( ls -A "$REAL_HOME" 2>/dev/null | sort ) > "$REAL_LIST_AFTER" 2>/dev/null || : > "$REAL_LIST_AFTER"
else
  : > "$REAL_LIST_AFTER"
fi
assert "SAFETY: real ~/.claude listing UNCHANGED by this suite (no persistent entry added/removed)" "diff '$REAL_LIST_BEFORE' '$REAL_LIST_AFTER' >/dev/null 2>&1"
# This suite must never write its OWN apply/throttle artifacts under the REAL home.
# (The throttle cache + apply markers it tests for must land under the SANDBOX home
# only; their absence under the real home is a write-tamper detector this code, and
# only this code, could trip.)
assert "SAFETY: this suite wrote NO throttle cache under the real ~/.claude" "test ! -e '$REAL_HOME/.plumbline/update/last-check.json' || diff '$REAL_LIST_BEFORE' '$REAL_LIST_AFTER' >/dev/null 2>&1"
assert "SAFETY: every sandbox path is under TMP_ROOT" "case '$STUB_DIR' in '$TMP_ROOT'/*) true ;; *) false ;; esac"

finish "session-start update-check tests"
