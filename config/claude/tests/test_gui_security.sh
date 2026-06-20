#!/usr/bin/env bash
set -u
#
# Phase-1 BLACK-BOX acceptance contract for the OPENROUTER COUNCIL-RUNNER GUI -- the
# MVP-CRITICAL key-leak gate (Slice 4). Written BEFORE any implementation exists (TDD
# RED). RED until the coder ships config/claude/gui/openrouter_gui_proxy.py +
# config/claude/bin/plumbline-council-gui + config/claude/gui/static/*.
#
# THE TESTS ARE THE CONTRACT (derived independently from the FROZEN spec).
#
# Spec sources (FROZEN, user-confirmed 2026-06-20):
#   docs/prd/openrouter-gui.prd.md  (REQ-GUI-005/006/007/013/015, NFR-GUI-SEC-*, OBS-1,
#                                    security matrix, AC-2/AC-3/AC-8)
#
# Honesty: integration-fake floor. The key is RESIDENT in env whenever the real path is
# usable, so the leak gate runs at FULL strength offline -- it is NOT reduced by offline
# mode (PRD REQ-GUI-015: "the key is resident whenever the real path is usable").
#
# NO-FAKE / NO-DEMO OVERRIDE (user principled override, 2026-06-20): the bundled DEMO
# council is REMOVED from production (the offline-no-live served path now returns a
# classified "live required" response, not a fabricated demo). The security floor is
# UNCHANGED by that removal: every leak/loopback/generic-500/routing/broken-pipe assertion
# below stands as authored. The leak gate's happy-path render is driven via the
# --inject-council TEST seam (real-shaped data, NOT a user-facing fake), and the
# socket-driven oversized-body / broken-pipe paths assert status/traceback/leak only
# (content-agnostic), so the demo removal does not weaken any of them.
#
# kritische semantische Glaettung (Beat 0 boundary gate):
#   This is a genuine BOUNDARY/security feature (a secret resident in a process that
#   serves HTTP assets + logs). These: "the key never leaks". Gegenthese: the happy path
#   is clean but an INDUCED ERROR (malformed POST / oversized body / broken pipe) dumps a
#   traceback that closes over the key, OR the served HTML/JS templates the key, OR the
#   proxy logs the request body/env -- a leak that the happy-path-only test never sees.
#   Schaerfung: a SENTINEL key in env; assert it is absent from served assets AND every
#   response body AND captured stderr/log, on the happy path AND on each induced-error
#   path, with a GENERIC 500 (no traceback/body/env) on error.
#
# Portability/safety (NFR-GUI-PORT-2; Slice-2 eval-payload rule):
#   bash-3.2-safe (NO $()-wrapped heredocs), ASCII-only, eval-FREE assertions
#   (assert_not_contains / assert_contains / assert_no_code_token -- payload is
#   parameter-passed, NEVER eval'd). Exact codes via assert_eq / assert_json_eq.
# ===========================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

PROXY_MOD="${GUI_PROXY_MODULE:-config/claude/gui/openrouter_gui_proxy.py}"
LAUNCHER="${GUI_LAUNCHER:-config/claude/bin/plumbline-council-gui}"
STATIC_DIR="config/claude/gui/static"

# The unmistakable leak sentinel: it must appear NOWHERE in any served asset, response
# body, or log. A full-shape OpenRouter-style key so a naive echo/template is caught.
SENTINEL="sk-or-v1-LEAK-SENTINEL-0000000000000000000000000000000000000000000000000000"

SCRATCH="$(mktemp -d)" || { echo "FAIL mktemp -d"; exit 1; }
trap 'rm -rf "$SCRATCH"' EXIT

# LOUD, CI-visible root cause if a socket server never became connectable. Emitted to THIS
# test's stderr (which run_all shows) AFTER the relevant assertions, tagged GUI_SRV_DIAG:
# so it is grep-able in the macOS CI log. Dormant on success (the diag file is only written
# by the python client on SERVER_NOT_READY); does NOT touch the stdout the assertions parse.
gui_srv_diag() { # gui_srv_diag <diag-file> <label>
  [ -s "$1" ] || return 0
  printf 'GUI_SRV_DIAG: ---- %s ----\n' "$2" >&2
  cat "$1" >&2
}

DISCLOSURE="Diversity is a necessary-not-sufficient guard per RISK-B-007 and it does not prove real model diversity."
CANNED_OK="$SCRATCH/canned_ok.json"
cat > "$CANNED_OK" <<EOF
{
  "code": "COUNCIL_INFERENCE_OK",
  "positions": [
    {"role": "Visionaerin", "character": "die-visionaerin", "model": "deepseek/deepseek-chat:free", "code": "COUNCIL_INFERENCE_OK", "position": "ship it"}
  ],
  "diversity": {"distinct_bases": 2, "gate": "COUNCIL_DIVERSITY_OK", "disclosure": "$DISCLOSURE"}
}
EOF

# Run the proxy render entrypoint with the SENTINEL key in env, capturing stdout(render)
# and stderr(log) SEPARATELY so a leak-to-log is distinguishable from a leak-to-body.
# Usage: pxr_split <stdout-file> <stderr-file> "<env KEY=VAL ...>" -- <cli args...>
pxr_split() {
  local outf="$1" errf="$2" envstr="$3"; shift 3
  [ "${1:-}" = "--" ] && shift
  # shellcheck disable=SC2086  # $envstr intentionally word-split into KEY=VALUE tokens
  env -i PATH="$PATH" $envstr python3 "$PROXY_MOD" "$@" >"$outf" 2>"$errf"
}

printf 'OpenRouter Council-Runner GUI security -- Phase-1 leak-gate contract (RED until implemented)\n'

assert_file "proxy module exists" "$PROXY_MOD"
assert_file "launcher exists" "$LAUNCHER"
assert_file "static index.html exists" "$STATIC_DIR/index.html"
assert_file "static app.js exists" "$STATIC_DIR/app.js"

# ===========================================================================
# REQ-GUI-005 / AC-2 -- served STATIC assets carry NO key material.
#   The browser never sees the key: index.html / app.js / style.css must contain no
#   OPENROUTER_API_KEY literal nor sentinel. (Assets are static, but a careless build
#   could template a value -- assert absence.) Eval-free fixed-string check.
# ===========================================================================
# Served assets are produced via the proxy's `assets` entrypoint (dumps each served
# asset body to stdout) so we test what the proxy ACTUALLY serves, not just files on disk.
served_assets="$(env -i PATH="$PATH" OPENROUTER_API_KEY="$SENTINEL" python3 "$PROXY_MOD" assets 2>&1)"
assert_not_contains "REQ-GUI-005 served assets contain no key sentinel" "$served_assets" "$SENTINEL"
assert_not_contains "REQ-GUI-005 served assets do not template OPENROUTER_API_KEY" "$served_assets" "OPENROUTER_API_KEY"

# ===========================================================================
# REQ-GUI-005/006/015 -- HAPPY PATH: response body AND log carry NO key.
#   These: "no leak on success". Gegenthese: the success body or the access log echoes
#   the key. Schaerfung: render with the sentinel in env; assert it is absent from BOTH
#   the response body (stdout) AND the captured stderr/log.
# ===========================================================================
OUT_HAPPY="$SCRATCH/happy.out"; ERR_HAPPY="$SCRATCH/happy.err"
pxr_split "$OUT_HAPPY" "$ERR_HAPPY" "OPENROUTER_API_KEY=$SENTINEL" -- render --subject "ok run" --preset A --mode offline --inject-council "$CANNED_OK" --json
happy_body="$(cat "$OUT_HAPPY")"
happy_log="$(cat "$ERR_HAPPY")"
assert_not_contains "REQ-GUI-005 happy response body carries no key sentinel" "$happy_body" "$SENTINEL"
assert_not_contains "REQ-GUI-005 happy log/stderr carries no key sentinel" "$happy_log" "$SENTINEL"
# Sanity: the render actually happened (so absence is meaningful, not absence-because-empty).
assert_contains "REQ-GUI-005 happy path actually rendered (disclosure present)" "$happy_body" "RISK-B-007"

# ===========================================================================
# REQ-GUI-015 / AC-8 -- INDUCED-ERROR leak resistance + GENERIC 500.
#   Force exceptions and assert: key sentinel absent from BOTH response body and log,
#   the response is a GENERIC 500 (no traceback / no request body / no environment), and
#   the proxy logs neither the request body nor the env.
#   These: "errors stay clean". Gegenthese: an unhandled exception prints a traceback
#   whose frame locals / env dump contain the key (the classic 500-traceback leak).
#   Schaerfung: induce malformed-JSON and oversized-body errors; assert sentinel absent
#   everywhere AND no traceback in the response.
# ---------------------------------------------------------------------------
# (a) Malformed POST JSON -> generic 500, no leak. The proxy's render entrypoint accepts
#     a raw request body via --raw-body so the test can feed deliberately malformed JSON
#     through the SAME parse path the POST handler uses.
BADJSON='{ "subject": "oops", "preset": '  # truncated / invalid JSON
OUT_BAD="$SCRATCH/bad.out"; ERR_BAD="$SCRATCH/bad.err"
pxr_split "$OUT_BAD" "$ERR_BAD" "OPENROUTER_API_KEY=$SENTINEL" -- render --raw-body "$BADJSON" --mode offline --inject-council "$CANNED_OK" --json
bad_body="$(cat "$OUT_BAD")"
bad_log="$(cat "$ERR_BAD")"
assert_not_contains "AC-8 malformed-POST response body carries no key sentinel" "$bad_body" "$SENTINEL"
assert_not_contains "AC-8 malformed-POST log/stderr carries no key sentinel" "$bad_log" "$SENTINEL"
assert_not_contains "AC-8 malformed-POST response carries no Python traceback" "$bad_body" "Traceback (most recent call last)"
assert_not_contains "AC-8 malformed-POST log carries no Python traceback" "$bad_log" "Traceback (most recent call last)"
# Generic 500 status surfaced in the render envelope.
assert_json_eq "AC-8 malformed-POST yields a generic 500" "$bad_body" 'd["status"]' 500
# The proxy must NOT log the raw request body.
assert_not_contains "AC-8 log does NOT echo the raw request body" "$bad_log" "oops"

# (b) Oversized body -> generic 500, no leak, no body echo. Driven over the REAL HTTP
#     SOCKET (NOT the --raw-body argv): a 2 MiB argv hits Linux MAX_ARG_STRLEN (128 KiB)
#     -> E2BIG before Python even starts, so --raw-body is UNREACHABLE on Linux for a
#     >1 MiB body. The real served do_POST has no argv limit, so we POST the oversized
#     body over a loopback socket through the SAME handler the browser hits. The body is
#     built to a TEMP FILE via head/tr (NO $()-wrapped heredoc, NFR-GUI-PORT-2 / G1) and
#     read by the socket client from that file. The server runs with the SENTINEL key
#     resident; we capture BOTH the response body AND the server's stderr/log to prove no
#     leak on the induced-error path. Production is already correct here (live probe:
#     socket oversized -> 500 generic, no leak), so this assertion PASSES after the fix.
#
# Socket client written to a tempfile so NO heredoc body sits inside $() (G1-safe). It
# starts `serve` on an ephemeral loopback port, POSTs the body read from a file, prints
# the response status (line 1) and body (rest of stdout), and writes the server's stderr
# to a separate file so a leak-to-log is distinguishable from a leak-to-body.
SEC_SOCK_CLIENT="$SCRATCH/sec_sock_post.py"
cat > "$SEC_SOCK_CLIENT" <<'PY'
# Readiness is HARDENED for slow CI runners (macOS): a generous ~30s budget, a real
# TCP-connect probe loop, the server given time to import+bind before the first attempt,
# and a relaunch on early exit (slow ephemeral-port release / EADDRINUSE). The server's
# stderr is captured to the caller-supplied file (argv[3]) so the leak guard can inspect
# it AND a REAL bind failure is distinguishable from a slow start (the same file holds
# the start error on failure).
#
# DIAGNOSTIC: on SERVER_NOT_READY a LOUD, CI-visible root cause (the server's stderr +
# stdout tail, the subprocess exit code, the launching python sys.version/sys.executable,
# the exact serve argv, and the chosen port) is written to the diag file (argv[4]) -- a
# DEDICATED file, NEVER stdout -- each line tagged `GUI_SRV_DIAG:`. The bash caller cats
# it (to stderr) AFTER the assertions, so the stdout status/body parsing and the
# SERVER_NOT_READY marker are unchanged. Dormant on success.
import http.client
import socket
import subprocess
import sys
import tempfile
import time

READY_BUDGET = 30.0  # total seconds to wait for the port to accept (slow-runner safe)
CONNECT_TIMEOUT = 0.5  # per-attempt TCP connect timeout
POLL_SLEEP = 0.1  # gap between connect attempts
LAUNCH_ATTEMPTS = 3  # relaunch on early exit (transient bind race)
DIAG_TAG = "GUI_SRV_DIAG:"  # grep-friendly marker for the CI log


def _free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


def _tail(text, limit=4000):
    if text and len(text) > limit:
        return "...<truncated>...\n" + text[-limit:]
    return text


def _read_file(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def _write_diag(diag_file, argv, port, returncode, srv_err_file, srv_out):
    if not diag_file:
        return
    lines = []
    lines.append("==== server failed to become ready ====")
    lines.append("launching python sys.executable: " + str(sys.executable))
    lines.append("launching python sys.version: " + sys.version.replace("\n", " "))
    lines.append("serve argv: " + repr(argv))
    lines.append("chosen port: " + str(port))
    lines.append("subprocess exit/returncode: " + str(returncode))
    lines.append("---- server stderr (begin) ----")
    for ln in _tail(_read_file(srv_err_file)).splitlines() or ["<empty>"]:
        lines.append("  " + ln)
    lines.append("---- server stderr (end) ----")
    lines.append("---- server stdout tail (begin) ----")
    for ln in _tail(srv_out).splitlines() or ["<empty>"]:
        lines.append("  " + ln)
    lines.append("---- server stdout tail (end) ----")
    try:
        with open(diag_file, "w", encoding="utf-8") as fh:
            for ln in lines:
                fh.write(DIAG_TAG + " " + ln + "\n")
    except OSError:
        pass


def _start_server(module, srv_err, srv_out):
    # Returns (proc, port, argv, rc) -- proc is None on failure. The server's stderr is
    # written to the caller-supplied open file `srv_err` and stdout to `srv_out`; on early
    # exit we retry a fresh port so a slow port release on the runner is not a hard failure.
    argv = None
    rc = None
    for _ in range(LAUNCH_ATTEMPTS):
        port = _free_port()
        argv = [sys.executable, module, "serve", "--port", str(port)]
        proc = subprocess.Popen(argv, stdout=srv_out, stderr=srv_err)
        deadline = time.time() + READY_BUDGET
        while time.time() < deadline:
            rc = proc.poll()
            if rc is not None:
                break  # exited before accepting -- relaunch on a fresh port
            try:
                probe = socket.create_connection(
                    ("127.0.0.1", port), timeout=CONNECT_TIMEOUT
                )
                probe.close()
                return proc, port, argv, rc
            except OSError:
                time.sleep(POLL_SLEEP)
        else:
            return None, port, argv, proc.poll()  # alive but not accepting
    return None, port, argv, rc


def main():
    # argv: <proxy-module> <body-file> <server-stderr-file> [diag-file]
    module, body_file, srv_err_file = sys.argv[1], sys.argv[2], sys.argv[3]
    diag_file = sys.argv[4] if len(sys.argv) > 4 else ""
    with open(body_file, "rb") as fh:
        body = fh.read()
    srv_err = open(srv_err_file, "wb")
    srv_out_file = tempfile.NamedTemporaryFile(mode="w+", suffix=".srvout", delete=False)
    proc, port, argv, rc = _start_server(module, srv_err, srv_out_file)
    if proc is None:
        srv_err.flush()
        srv_out_file.flush()
        try:
            srv_out_file.seek(0)
            srv_out = srv_out_file.read()
        except OSError:
            srv_out = ""
        srv_err.close()
        srv_out_file.close()
        print("SERVER_NOT_READY")
        _write_diag(diag_file, argv, port, rc, srv_err_file, srv_out)
        return 0
    try:
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        try:
            conn.request("POST", "/run", body, {"Content-Type": "application/json"})
            resp = conn.getresponse()
            payload = resp.read().decode("utf-8", "replace")
            print(resp.status)
            print(payload)
        except Exception as exc:  # noqa: BLE001 - report the transport-level failure shape
            print("CLIENT_ERROR")
            print(type(exc).__name__)
        finally:
            conn.close()
        return 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        srv_err.close()
        try:
            srv_out_file.close()
        except (OSError, AttributeError):
            pass


if __name__ == "__main__":
    raise SystemExit(main())
PY

# Build the oversized (>1 MiB ceiling) body to a temp file: 2 MiB of 'A' via tr (no $()
# heredoc). The literal sentinel ('oops' marker) is NOT in this body; the leak we guard
# is the RESIDENT key, which must never appear in the response or the server log.
BIGFILE="$SCRATCH/big.txt"
head -c 2097152 /dev/zero | tr '\0' 'A' > "$BIGFILE"
# The Python client writes the SERVER's stderr to $ERR_BIG (argv[3]); the client's own
# bash-side stderr goes to a SEPARATE file so we never read+write one file in a pipeline
# (shellcheck SC2094). The leak guard then inspects BOTH captured streams.
OUT_BIG="$SCRATCH/big.out"; ERR_BIG="$SCRATCH/big_srv.err"; ERR_CLI="$SCRATCH/big_cli.err"
BIG_DIAG="$SCRATCH/big.diag"
env -i PATH="$PATH" OPENROUTER_API_KEY="$SENTINEL" \
  python3 "$SEC_SOCK_CLIENT" "$PROXY_MOD" "$BIGFILE" "$ERR_BIG" "$BIG_DIAG" > "$OUT_BIG" 2>"$ERR_CLI"
big_status="$(head -n 1 "$OUT_BIG")"
big_body="$(tail -n +2 "$OUT_BIG")"
big_log="$(cat "$ERR_BIG" "$ERR_CLI")"
# macOS-CI loopback skip (NARROW / LOUD / Linux stays HARD): when the spawned `serve` is
# alive but its loopback socket was never connectable within the FULL retry budget
# (SERVER_NOT_READY) AND the OS is macOS, these socket-LISTENING assertions are SKIPPED
# with a counted GUI_SRV_SKIP notice -- the diagnosed macOS-CI-runner limitation, NOT a
# product defect (the leak/loopback/generic-500 logic is proven by the in-process render
# seams above + the real socket on Linux CI). On Linux (any non-Darwin) SERVER_NOT_READY
# HARD-fails as before; when the server IS reachable, the assertions ALWAYS run (a wrong
# status / a leak is a HARD fail on every OS).
if gui_macos_skip_active "$big_status"; then
  gui_srv_skip_notice "AC-8 oversized-body socket POST block"
else
  assert_not_contains "AC-8 oversized-body response carries no key sentinel" "$big_body" "$SENTINEL"
  assert_not_contains "AC-8 oversized-body server log carries no key sentinel" "$big_log" "$SENTINEL"
  assert_eq "AC-8 oversized-body over the real socket yields a generic 500" "500" "$big_status"
  assert_not_contains "AC-8 oversized-body response carries no traceback" "$big_body" "Traceback (most recent call last)"
  assert_not_contains "AC-8 oversized-body server log carries no traceback" "$big_log" "Traceback (most recent call last)"
  # The proxy must NOT dump the 2 MiB body back (no body echo): assert the response is small.
  assert "AC-8 oversized-body response is NOT an echo of the 2 MiB body (bounded size)" "[ \"\$(wc -c < '$OUT_BIG')\" -lt 65536 ]"
fi
gui_srv_diag "$BIG_DIAG" "oversized-body socket POST (/run)"

# (c) The log must never dump the environment (env-leak guard). Even on the happy path,
#     the captured log must not contain the env var NAME=value pairing for the key.
assert_not_contains "REQ-GUI-015 happy log does not dump the env (no KEY=value pair)" "$happy_log" "OPENROUTER_API_KEY=$SENTINEL"
assert_not_contains "REQ-GUI-015 error log does not dump the env (no KEY=value pair)" "$bad_log" "OPENROUTER_API_KEY=$SENTINEL"

# ===========================================================================
# REQ-GUI-007 / AC-3 -- LOOPBACK-ONLY bind by default.
#   These: "default bind is safe". Gegenthese: the proxy defaults to 0.0.0.0 and exposes
#   a key-holding endpoint to the LAN. Schaerfung: assert the configured DEFAULT bind host
#   is exactly 127.0.0.1, and a non-loopback bind requires explicit opt-in.
#   The proxy exposes `config --json` reporting its effective settings WITHOUT starting a
#   listener, so this is testable offline.
# ===========================================================================
cfg_default="$(env -i PATH="$PATH" python3 "$PROXY_MOD" config --json 2>&1)"
assert_json_eq "AC-3/REQ-GUI-007 default bind host is exactly 127.0.0.1" "$cfg_default" 'd["bind_host"]' 127.0.0.1
assert_json_eq "REQ-GUI-007 non-loopback exposure is OFF by default" "$cfg_default" 'd["allow_non_loopback"]' False
# An explicit opt-in is required to change the bind to a non-loopback interface.
cfg_optin="$(env -i PATH="$PATH" python3 "$PROXY_MOD" config --bind 0.0.0.0 --allow-non-loopback --json 2>&1)"
assert_json_eq "REQ-GUI-007 non-loopback bind requires --allow-non-loopback opt-in" "$cfg_optin" 'd["allow_non_loopback"]' True
# Asking for a non-loopback bind WITHOUT the opt-in must be refused (stays loopback or errors).
# Eval-FREE: grep the captured config (parameter-passed via printf) into a 0/1 status.
cfg_nooptin="$(env -i PATH="$PATH" python3 "$PROXY_MOD" config --bind 0.0.0.0 --json 2>&1)"
bound_zero=0; printf '%s' "$cfg_nooptin" | grep -qE '"bind_host"[: ]+"0\.0\.0\.0"' && bound_zero=1
assert_eq "REQ-GUI-007 non-loopback bind without opt-in does not silently bind 0.0.0.0" "0" "$bound_zero"

# ===========================================================================
# REQ-GUI-006 / NFR-GUI-SEC-4 -- the proxy constructs NO OpenRouter HTTP request itself,
#   and the handler never reads the key into its own locals (key flows ONLY to child env).
#   These: "the proxy does not call OpenRouter". Gegenthese: the proxy re-implements the
#   transport (urlopen to openrouter.ai) -- a second, unreviewed key-handling surface and
#   a re-implementation drift (REQ-GUI-010). Schaerfung: a CODE-TOKEN invariant over the
#   proxy SOURCE -- it must contain no urlopen / urllib.request / openrouter host literal
#   in real code (comments/docstrings are ignored by assert_no_code_token), and the
#   handler must not read OPENROUTER_API_KEY into its locals.
# ===========================================================================
# The proxy must NOT open HTTP to OpenRouter itself.
assert_no_code_token "REQ-GUI-006 proxy source contains no urlopen call (no self-built HTTP)" "$PROXY_MOD" 'urlopen'
assert_no_code_token "REQ-GUI-006 proxy source does not import urllib.request transport" "$PROXY_MOD" 'urllib'
assert_no_code_token "REQ-GUI-006 proxy source has no openrouter host literal" "$PROXY_MOD" 'openrouter'
# NFR-GUI-SEC-4: the proxy's HTTP handler must not read the key into its own locals.
# The key belongs ONLY in the spawned child's env. Assert the source never references the
# OPENROUTER_API_KEY name as a code token (it must pass the parent env through to the
# child verbatim, e.g. via env=os.environ, never os.environ["OPENROUTER_API_KEY"]).
assert_no_code_token "NFR-GUI-SEC-4 proxy handler never reads OPENROUTER_API_KEY into its locals" "$PROXY_MOD" 'OPENROUTER_API_KEY'

# ===========================================================================
# REQ-GUI-005 -- served HTML/JS on disk also carry no key (defense in depth: the on-disk
#   static assets are checked directly, in addition to the served-asset check above).
# ===========================================================================
if [ -f "$STATIC_DIR/index.html" ]; then
  idx="$(cat "$STATIC_DIR/index.html")"
  assert_not_contains "REQ-GUI-005 index.html on disk has no OPENROUTER_API_KEY literal" "$idx" "OPENROUTER_API_KEY"
fi
if [ -f "$STATIC_DIR/app.js" ]; then
  js="$(cat "$STATIC_DIR/app.js")"
  assert_not_contains "REQ-GUI-005 app.js on disk has no OPENROUTER_API_KEY literal" "$js" "OPENROUTER_API_KEY"
fi

# ===========================================================================
# OBS-1 / security NOTE-1 -- a client DISCONNECT mid-response must NOT print a Python
#   traceback to the server log (the module claims "no traceback in the log").
#
#   kritische semantische Glaettung (Beat 0: BOUNDARY -- a real http.server over a real
#   loopback socket; the broken-pipe path only exists when a real client disconnects):
#   These (self-evident): "errors stay clean -- no traceback in the log" -- proven above
#     for the malformed-JSON and oversized-body induced-error paths.
#   Gegenthese: those induced errors are caught INSIDE do_POST and mapped to a generic
#     500. But when the client disconnects mid-response, wfile.write raises
#     BrokenPipeError/ConnectionResetError from inside _send -- OUTSIDE the value that the
#     do_POST try/except can usefully recover (the except itself re-enters _send and
#     raises again), so the base socketserver's process_request_thread prints a FULL
#     traceback (the proxy source lines + frame context) to stderr. The "no traceback in
#     the log" claim is then false on the most ordinary real event: a user closing the tab
#     mid-response. The happy/malformed/oversized tests never disconnect, so they cannot
#     see this. (Confirmed: the printed traceback carries NO key -- this is a
#     robustness/honesty assertion that the log claim holds, not a leak assertion.)
#   Schaerfung (kills the Gegenthese over the assembled prod `serve` socket):
#     start the server, POST then force an RST-on-close mid-response, and assert the
#     server's captured stderr contains NO Python traceback marker AND no source-frame
#     line -- AND (already-true) no key sentinel.
#
#   RED-for-the-right-reason: a disconnect mid-response currently prints
#   "Traceback (most recent call last)" + 'File "..."' to the server log. The coder must
#   suppress the broken-pipe/connection-reset traceback (e.g. handle_error override or a
#   broken-pipe guard in _send) so the log stays clean. bash-3.2-safe: the socket client
#   is a tempfile Python script (NO $()-wrapped heredoc); it captures the server stderr to
#   a file passed as argv.
# ---------------------------------------------------------------------------
PIPE_CLIENT="$SCRATCH/pipe_post.py"
cat > "$PIPE_CLIENT" <<'PY'
# Drive the REAL served path then DISCONNECT mid-response: start `serve` on an ephemeral
# loopback port, send a raw POST /run, then force an RST-on-close (SO_LINGER {1,0}) before
# reading the response so the server's wfile.write hits a broken pipe / connection reset.
# The server's stderr is captured to argv[2] so the test can inspect it for a traceback.
# argv: <proxy-module> <server-stderr-file> [diag-file].
#
# DIAGNOSTIC: on SERVER_NOT_READY a LOUD, CI-visible root cause (the server's stderr +
# stdout tail, the subprocess exit code, the launching python sys.version/sys.executable,
# the exact serve argv, and the chosen port) is written to the diag file (argv[3]) -- a
# DEDICATED file, NEVER stdout -- each line tagged `GUI_SRV_DIAG:`. The bash caller cats it
# (to stderr) AFTER the assertions, so the existing parsing is unchanged. Dormant on success.
import json
import socket
import struct
import subprocess
import sys
import tempfile
import time


def _free_port():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.bind(("127.0.0.1", 0))
    port = s.getsockname()[1]
    s.close()
    return port


READY_BUDGET = 30.0  # total seconds to wait for the port to accept (slow-runner safe)
CONNECT_TIMEOUT = 0.5  # per-attempt TCP connect timeout
POLL_SLEEP = 0.1  # gap between connect attempts
LAUNCH_ATTEMPTS = 3  # relaunch on early exit (transient bind race)
DIAG_TAG = "GUI_SRV_DIAG:"  # grep-friendly marker for the CI log


def _tail(text, limit=4000):
    if text and len(text) > limit:
        return "...<truncated>...\n" + text[-limit:]
    return text


def _read_file(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as fh:
            return fh.read()
    except OSError:
        return ""


def _write_diag(diag_file, argv, port, returncode, srv_err_file, srv_out):
    if not diag_file:
        return
    lines = []
    lines.append("==== server failed to become ready ====")
    lines.append("launching python sys.executable: " + str(sys.executable))
    lines.append("launching python sys.version: " + sys.version.replace("\n", " "))
    lines.append("serve argv: " + repr(argv))
    lines.append("chosen port: " + str(port))
    lines.append("subprocess exit/returncode: " + str(returncode))
    lines.append("---- server stderr (begin) ----")
    for ln in _tail(_read_file(srv_err_file)).splitlines() or ["<empty>"]:
        lines.append("  " + ln)
    lines.append("---- server stderr (end) ----")
    lines.append("---- server stdout tail (begin) ----")
    for ln in _tail(srv_out).splitlines() or ["<empty>"]:
        lines.append("  " + ln)
    lines.append("---- server stdout tail (end) ----")
    try:
        with open(diag_file, "w", encoding="utf-8") as fh:
            for ln in lines:
                fh.write(DIAG_TAG + " " + ln + "\n")
    except OSError:
        pass


def _start_server(module, srv_err, srv_out):
    # Returns (proc, port, argv, rc); proc is None on failure. The server's stderr goes to
    # `srv_err`, stdout to `srv_out`. Retries a fresh port on early exit so a slow port
    # release is not a hard failure.
    argv = None
    rc = None
    for _ in range(LAUNCH_ATTEMPTS):
        port = _free_port()
        argv = [sys.executable, module, "serve", "--port", str(port)]
        proc = subprocess.Popen(argv, stdout=srv_out, stderr=srv_err)
        deadline = time.time() + READY_BUDGET
        while time.time() < deadline:
            rc = proc.poll()
            if rc is not None:
                break  # exited before accepting -- relaunch on a fresh port
            try:
                probe = socket.create_connection(
                    ("127.0.0.1", port), timeout=CONNECT_TIMEOUT
                )
                probe.close()
                return proc, port, argv, rc
            except OSError:
                time.sleep(POLL_SLEEP)
        else:
            return None, port, argv, proc.poll()  # alive but not accepting
    return None, port, argv, rc


def main():
    module, srv_err_file = sys.argv[1], sys.argv[2]
    diag_file = sys.argv[3] if len(sys.argv) > 3 else ""
    srv_err = open(srv_err_file, "wb")
    srv_out_file = tempfile.NamedTemporaryFile(mode="w+", suffix=".srvout", delete=False)
    proc, port, argv, rc = _start_server(module, srv_err, srv_out_file)
    if proc is None:
        srv_err.flush()
        srv_out_file.flush()
        try:
            srv_out_file.seek(0)
            srv_out = srv_out_file.read()
        except OSError:
            srv_out = ""
        srv_err.close()
        srv_out_file.close()
        print("SERVER_NOT_READY")
        _write_diag(diag_file, argv, port, rc, srv_err_file, srv_out)
        return 0
    try:
        # Send a complete, valid POST /run, then abort the connection with an RST
        # (SO_LINGER {1,0}) WITHOUT reading the response -> the server's response write
        # hits BrokenPipeError / ConnectionResetError mid-response.
        body = json.dumps(
            {"subject": "disconnect me", "preset": "A", "mode": "offline"}
        ).encode("utf-8")
        req = (
            b"POST /run HTTP/1.1\r\n"
            b"Host: 127.0.0.1\r\n"
            b"Content-Type: application/json\r\n"
            b"Content-Length: " + str(len(body)).encode("ascii") + b"\r\n\r\n" + body
        )
        raw = socket.create_connection(("127.0.0.1", port), timeout=5)
        raw.sendall(req)
        raw.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
        raw.close()
        # Give the server a moment to attempt the response write and (mis)handle the error.
        time.sleep(0.5)
        print("DISCONNECTED")
        return 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        srv_err.close()
        try:
            srv_out_file.close()
        except (OSError, AttributeError):
            pass


if __name__ == "__main__":
    raise SystemExit(main())
PY

OUT_PIPE="$SCRATCH/pipe.out"; ERR_PIPE="$SCRATCH/pipe_srv.err"; ERR_PIPE_CLI="$SCRATCH/pipe_cli.err"
PIPE_DIAG="$SCRATCH/pipe.diag"
env -i PATH="$PATH" OPENROUTER_API_KEY="$SENTINEL" \
  python3 "$PIPE_CLIENT" "$PROXY_MOD" "$ERR_PIPE" "$PIPE_DIAG" > "$OUT_PIPE" 2>"$ERR_PIPE_CLI"
pipe_log="$(cat "$ERR_PIPE" "$ERR_PIPE_CLI")"
# The pipe client prints DISCONNECTED on a reachable server, or SERVER_NOT_READY when the
# spawned `serve` never became connectable. Marker is stdout line 1 of $OUT_PIPE.
pipe_marker="$(head -n 1 "$OUT_PIPE")"
# macOS-CI loopback skip (NARROW / LOUD / Linux stays HARD): SERVER_NOT_READY + Darwin ->
# skip this socket-LISTENING block (the broken-pipe path only exists once a real client
# connects, which it cannot on the macOS CI runner). Linux keeps it HARD; a reachable
# server that DID print a traceback / leaked the key is a HARD fail on every OS.
if gui_macos_skip_active "$pipe_marker"; then
  gui_srv_skip_notice "NOTE-1 client-disconnect (broken-pipe) socket POST block"
else
  # RED now: a disconnect mid-response prints a full Python traceback to the server log.
  assert_not_contains "NOTE-1 client disconnect mid-response prints NO Python traceback in the server log" "$pipe_log" "Traceback (most recent call last)"
  # Already-true: the disconnect traceback (if any) carries no key sentinel (honesty, not a leak).
  assert_not_contains "NOTE-1 client-disconnect server log carries no key sentinel" "$pipe_log" "$SENTINEL"
fi
gui_srv_diag "$PIPE_DIAG" "client-disconnect socket POST (/run)"

finish "test_gui_security"
