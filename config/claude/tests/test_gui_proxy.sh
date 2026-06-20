#!/usr/bin/env bash
set -u
#
# Phase-1 BLACK-BOX acceptance contract for the OPENROUTER COUNCIL-RUNNER GUI proxy
# + launcher (Slice 4). Written BEFORE any implementation exists (TDD RED). The coder
# (separate) implements EXACTLY this contract. RED until then:
#   config/claude/gui/openrouter_gui_proxy.py        (ABSENT)
#   config/claude/gui/static/{index.html,app.js,style.css}  (ABSENT)
#   config/claude/bin/plumbline-council-gui          (ABSENT)
# so every assertion below fails for the RIGHT reason: module/launcher missing.
#
# THE TESTS ARE THE CONTRACT. If a later plan/coder conflicts with an assertion here,
# the test wins (derived independently from the FROZEN spec, not the plan).
#
# Spec sources (FROZEN, user-confirmed 2026-06-20; spec-sanity-remediated):
#   docs/prd/openrouter-gui.prd.md       (REQ-GUI-001..017, AC-1..AC-10, NFR/SEC matrix)
#   docs/canvas/openrouter-gui.canvas.md
#   docs/vision/openrouter-gui.vision.md
#
# NO-FAKE / NO-DEMO OVERRIDE (user principled override, 2026-06-20):
#   The bundled DEMO council is a Plumbline no-fake violation -- a fabricated council
#   shown to the operator as if it were real positions. The user demands: NO demo. The
#   GUI shows REAL council positions (live) or NOTHING. "Fake=Demo, dann weglassen."
#   So the offline-no-live path NO LONGER renders a demo council; it returns a clear,
#   classified "live required" response (no fabricated positions, an honest "enable
#   live to run the council" message). The --inject-council seam stays as TEST INFRA
#   only (it injects REAL-shaped council JSON for render/pass-through/security tests;
#   it is NOT a user-facing fake). Assertions asserting a demo council are DELETED.
#
# Honesty (Reality Ledger floor = integration-fake, PRD "Evidence class floor"):
#   EVERY assertion here is integration-fake. The suite crosses NO real OpenRouter
#   boundary: render + pass-through + security are exercised OFFLINE via the proxy's own
#   --inject-council TEST seam (0 subprocess spawn, 0 network, 0 key, 0 calls). The live
#   path's SPAWN is proven REACHED offline via the inject seam standing in for the child
#   output (counter-based falsifier) -- no real call is fired. The real launcher IS
#   started for real (AC-9 / REQ-GUI-016 wired-in-prod) but still over the injected seam.
#   The headline REAL paste->run->real-positions is a LIVE smoke run SEPARATELY at
#   acceptance; NO real-boundary-smoke is baked into this offline suite (0 live calls).
#
# kritische semantische Glaettung (Beat 0 boundary gate, per top-level AC):
#   The proxy/launcher are a genuine BOUNDARY feature (http.server, subprocess, a real
#   OS process). The PRD already states the wiring AND the wired-in-prod test
#   (AC-9/REQ-GUI-016) -- so per the already-covered rule those are GREEN/covered as
#   authored; this file makes the FALSIFYING tests that prove them (real launcher
#   process, not just the in-process handler; from-wrong-cwd fail-loud). The signature
#   "injectable seam green, real entrypoint dead" false-green (CLAUDE.md) is killed by
#   AC-9 below, which drives a request through the REAL `plumbline-council-gui` process.
#
# Portability/safety contract (NFR-GUI-PORT-2, Slice-2/3 learned rules):
#   - bash-3.2-safe: NO $()-wrapped heredocs (test_shell_portability.sh G1 would flag).
#   - ASCII-only; eval-FREE assertions (lib.sh assert_contains / assert_not_contains /
#     assert_json_eq -- payload is parameter-passed, never eval'd).
#   - assert EXACT values (assert_eq / assert_json_eq), not substrings, for codes/counts.
# ===========================================================================
#
# SEAM / SERVER CONTRACT THE CODER MUST IMPLEMENT
# ===========================================================================
# A Python stdlib `http.server` proxy module config/claude/gui/openrouter_gui_proxy.py
# resolved via the GUI_PROXY_MODULE env override (default that path). It MUST be:
#   - importable AND runnable as `python3 <module> serve [opts]`.
#   - drivable OFFLINE via its OWN inject seam (mirrors the deepseek_review --inject-*):
#       --inject-council <path>   A file holding a CANNED `deepseek_review preset --json`
#                                 object (code/positions[]/diversity{}). When set, the
#                                 proxy renders THIS object and MUST NOT spawn the
#                                 subprocess, open a socket to OpenRouter, or read the
#                                 key. (0 subprocess / 0 network / 0 key / 0 calls.)
#       --inject-spawn-counter <path>  A file the proxy's subprocess-spawn seam writes
#                                 its spawn count to. In --inject-council mode it MUST
#                                 remain 0 (proves the subprocess was NOT spawned).
#   - serve on 127.0.0.1 by default (REQ-GUI-007); a --bind/--port for tests.
#   - serve the static GUI (index.html / app.js / style.css) AND a POST run endpoint.
#
# Because a long-lived http.server in a bash test is flaky, the proxy MUST ALSO expose a
# single-shot, NETWORK-LISTENER-FREE render entrypoint used by the offline contract:
#   python3 <module> render --subject <text> --preset <A|B|C> --mode <offline|live> \
#       --inject-council <path> --inject-spawn-counter <path> --json
# `render` runs the SAME request-handling code path the POST endpoint runs (same parse,
# same gate, same render), returning the rendered HTML fragment / JSON the browser would
# receive, plus the chosen HTTP status. This is the proxy's request handler exercised
# without binding a socket -- it is NOT a second implementation (REQ-GUI-010 forbids
# re-implementation; a `render` that diverges from the served path is a contract breach
# the coder must avoid, and AC-9 below pins the served path through the REAL launcher).
#
#   render JSON envelope (the proxy's own wrapper around the council JSON):
#     { "status": <int http status>,
#       "mode": "offline"|"live",
#       "refused": <bool>,                 # true when a live run is refused (AC-4)
#       "error_code": <classified-or-null>,# proxy/launcher classified error (AC-6/AC-7)
#       "council": <the deepseek_review preset JSON, passed through VERBATIM, or null>,
#       "html": <the rendered HTML string the browser receives> }
#   The `council` block is the council JSON UNCHANGED (pass-through, REQ-GUI-010); the
#   `html` is what the GUI renders (positions + diversity + disclosure).
# ===========================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

PROXY_MOD="${GUI_PROXY_MODULE:-config/claude/gui/openrouter_gui_proxy.py}"
LAUNCHER="${GUI_LAUNCHER:-config/claude/bin/plumbline-council-gui}"
STATIC_DIR="config/claude/gui/static"

# A sentinel that must NEVER appear in any rendered output (key handled child-env only).
SENTINEL="sk-or-LEAK-SENTINEL-deadbeef-PROXY"

SCRATCH="$(mktemp -d)" || { echo "FAIL mktemp -d"; exit 1; }
trap 'rm -rf "$SCRATCH"' EXIT

# --- Canned council JSON fixtures (the proxy's --inject-council inputs) ------
# These mirror the REAL `deepseek_review preset --json` shape verified at intake:
#   top-level `code`; `positions[]` of {role,character,model,code,position};
#   `diversity` {distinct_bases,gate,disclosure}. Written to tempfiles (no $()-heredoc).
DISCLOSURE="Diversity is a necessary-not-sufficient guard per RISK-B-007 and it does not prove real model diversity."

CANNED_OK="$SCRATCH/canned_ok.json"
cat > "$CANNED_OK" <<EOF
{
  "code": "COUNCIL_INFERENCE_OK",
  "positions": [
    {"role": "Visionaerin",  "character": "die-visionaerin",  "model": "deepseek/deepseek-chat:free", "code": "COUNCIL_INFERENCE_OK", "position": "We should ship the thin slice first."},
    {"role": "Pruefer",      "character": "der-pruefer",      "model": "qwen/qwen-2.5:free",          "code": "COUNCIL_INFERENCE_OK", "position": "The leak gate must be proven first."},
    {"role": "Nutzeranwalt", "character": "der-nutzeranwalt", "model": "deepseek/deepseek-chat:free", "code": "COUNCIL_INFERENCE_OK", "position": "Keep it usable on loopback."},
    {"role": "Macherin",     "character": "die-macherin",     "model": "deepseek/deepseek-chat:free", "code": "COUNCIL_INFERENCE_OK", "position": "One command to launch."}
  ],
  "diversity": {"distinct_bases": 2, "gate": "COUNCIL_DIVERSITY_OK", "disclosure": "$DISCLOSURE"}
}
EOF

# MIXED: some roles OK (position present), some non-OK (classified code, position null).
# overall `code` is COUNCIL_MODEL_UNAVAILABLE (AC-10 / REQ-GUI-017).
CANNED_MIXED="$SCRATCH/canned_mixed.json"
cat > "$CANNED_MIXED" <<EOF
{
  "code": "COUNCIL_MODEL_UNAVAILABLE",
  "positions": [
    {"role": "Visionaerin",  "character": "die-visionaerin",  "model": "deepseek/deepseek-chat:free", "code": "COUNCIL_INFERENCE_OK",       "position": "Ship the visible slice."},
    {"role": "Pruefer",      "character": "der-pruefer",      "model": "qwen/qwen-2.5:free",          "code": "COUNCIL_MODEL_UNAVAILABLE", "position": null},
    {"role": "Nutzeranwalt", "character": "der-nutzeranwalt", "model": "deepseek/deepseek-chat:free", "code": "COUNCIL_INFERENCE_OK",       "position": "Loopback keeps it safe."},
    {"role": "Macherin",     "character": "die-macherin",     "model": "deepseek/deepseek-chat:free", "code": "character-missing",         "position": null}
  ],
  "diversity": {"distinct_bases": 2, "gate": "COUNCIL_DIVERSITY_OK", "disclosure": "$DISCLOSURE"}
}
EOF

# ALL-ERROR / classified: every role classified non-OK (AC-6 / REQ-GUI-012).
CANNED_ERR="$SCRATCH/canned_err.json"
cat > "$CANNED_ERR" <<EOF
{
  "code": "COUNCIL_MODEL_UNAVAILABLE",
  "positions": [
    {"role": "Visionaerin",  "character": "die-visionaerin",  "model": "deepseek/deepseek-chat:free", "code": "COUNCIL_MODEL_UNAVAILABLE", "position": null},
    {"role": "Pruefer",      "character": "der-pruefer",      "model": "qwen/qwen-2.5:free",          "code": "COUNCIL_MODEL_UNAVAILABLE", "position": null}
  ],
  "diversity": {"distinct_bases": 0, "gate": "COUNCIL_DIVERSITY_UNAVAILABLE", "disclosure": "$DISCLOSURE"}
}
EOF

# Helper: run the proxy `render` entrypoint under a clean, injected env (env -i), so no
# real key leaks and the test is hermetic regardless of the developer's shell.
# Usage: pxr "<env KEY=VAL ...>" -- <cli args...>
pxr() {
  local envstr="$1"; shift
  [ "${1:-}" = "--" ] && shift
  # shellcheck disable=SC2086  # $envstr is intentionally word-split into KEY=VALUE tokens
  env -i PATH="$PATH" $envstr python3 "$PROXY_MOD" "$@" 2>&1
}

# Helper: read an injected counter file (absent/empty => 0).
ctr() { if [ -s "$1" ]; then cat "$1"; else printf '0'; fi; }

printf 'OpenRouter Council-Runner GUI proxy/launcher -- Phase-1 acceptance contract (RED until implemented)\n'

# --- Presence (drives the RED state before implementation) -------------------
assert_file "proxy module exists (config/claude/gui/openrouter_gui_proxy.py)" "$PROXY_MOD"
assert_file "launcher exists (config/claude/bin/plumbline-council-gui)" "$LAUNCHER"
assert_file "static index.html exists" "$STATIC_DIR/index.html"
assert_file "static app.js exists" "$STATIC_DIR/app.js"
assert_file "static style.css exists" "$STATIC_DIR/style.css"

# ===========================================================================
# AC-1 / REQ-GUI-001/002/003/009 -- OFFLINE/INJECTED render, 0 subprocess/0 net/0 key.
#   These: "the proxy returns a render". Gegenthese: a green render that SECRETLY
#   spawned the subprocess / hit the network / read the key -- accidental cost + a
#   leak surface masquerading as the safe offline MVP. Schaerfung: assert the
#   spawn counter == 0 (exact), AND the render carries the injected positions/diversity.
# ===========================================================================
SPAWN_OK="$SCRATCH/spawn_ok.cnt"
ren_ok="$(pxr "OPENROUTER_API_KEY=$SENTINEL" -- render --subject "Should we ship slice 4" --preset A --mode offline --inject-council "$CANNED_OK" --inject-spawn-counter "$SPAWN_OK" --json)"

assert_json_eq "AC-1 offline render returns HTTP 200" "$ren_ok" 'd["status"]' 200
assert_json_eq "AC-1 offline render mode is offline" "$ren_ok" 'd["mode"]' offline
assert_json_eq "AC-1 offline render is NOT refused" "$ren_ok" 'd["refused"]' False
assert_eq "AC-1/REQ-GUI-009 offline render spawned ZERO subprocesses" "0" "$(ctr "$SPAWN_OK")"

# REQ-GUI-002: every positions[] entry rendered (role/model + position).
assert_json_eq "REQ-GUI-002 council passed through with 4 positions" "$ren_ok" 'len(d["council"]["positions"])' 4
assert_contains "REQ-GUI-002 render shows role Visionaerin" "$ren_ok" "Visionaerin"
assert_contains "REQ-GUI-002 render shows role Pruefer" "$ren_ok" "Pruefer"
assert_contains "REQ-GUI-002 render shows a model id" "$ren_ok" "deepseek/deepseek-chat:free"
assert_contains "REQ-GUI-002 render shows a position text" "$ren_ok" "We should ship the thin slice first."

# REQ-GUI-003: diversity block (distinct_bases / gate / disclosure).
assert_contains "REQ-GUI-003 render shows distinct_bases" "$ren_ok" "distinct_bases"
assert_contains "REQ-GUI-003 render shows the diversity gate" "$ren_ok" "COUNCIL_DIVERSITY_OK"

# REQ-GUI-004 / AC-5: RISK-B-007 disclosure present VERBATIM, no verdict wording.
assert_contains "REQ-GUI-004 disclosure rendered verbatim" "$ren_ok" "$DISCLOSURE"
assert_contains "REQ-GUI-004 disclosure cites RISK-B-007" "$ren_ok" "RISK-B-007"
# No value-verdict wording: the GUI must not present the run as an approval/verdict.
assert_not_contains "REQ-GUI-004 render carries no APPROVED verdict wording" "$ren_ok" "APPROVED"
assert_not_contains "REQ-GUI-004 render carries no VERDICT wording" "$ren_ok" "VERDICT"

# ===========================================================================
# AC-10 / REQ-GUI-017 -- MIXED render honesty: OK roles AND classified roles both shown.
#   These: "a mixed council renders". Gegenthese: collapsing the mixed state to a single
#   error banner (hiding the OK positions) OR faking a full success -- either way the
#   operator is misled about what the council actually said. Schaerfung: assert BOTH an
#   OK position text AND a per-role classified code appear, and overall code is the
#   honest COUNCIL_MODEL_UNAVAILABLE (not OK, not a single generic error).
# ===========================================================================
SPAWN_MIX="$SCRATCH/spawn_mix.cnt"
ren_mix="$(pxr "OPENROUTER_API_KEY=$SENTINEL" -- render --subject "mixed run" --preset A --mode offline --inject-council "$CANNED_MIXED" --inject-spawn-counter "$SPAWN_MIX" --json)"

assert_json_eq "AC-10 mixed render returns HTTP 200 (honest partial, not a 500)" "$ren_mix" 'd["status"]' 200
assert_json_eq "AC-10 mixed overall council code is COUNCIL_MODEL_UNAVAILABLE" "$ren_mix" 'd["council"]["code"]' COUNCIL_MODEL_UNAVAILABLE
assert_contains "AC-10 mixed render SHOWS an OK role's position (not hidden)" "$ren_mix" "Ship the visible slice."
assert_contains "AC-10 mixed render SHOWS a non-OK role's classified code" "$ren_mix" "COUNCIL_MODEL_UNAVAILABLE"
assert_contains "AC-10 mixed render shows the per-role character-missing code" "$ren_mix" "character-missing"
# Honesty: a mixed render must NOT be presented as a full success.
assert_not_contains "AC-10 mixed render does NOT claim full success" "$ren_mix" "ALL_OK"
assert_eq "AC-10 mixed render spawned ZERO subprocesses (offline)" "0" "$(ctr "$SPAWN_MIX")"

# ===========================================================================
# AC-6 / REQ-GUI-012 -- classified-error surfacing (no generic error, no fake success).
#   These: "errors are shown". Gegenthese: surfacing a generic "error" or a fabricated
#   success hides WHICH classified failure occurred -- the operator cannot act.
#   Schaerfung: assert the EXACT classified code is surfaced, never a generic banner.
# ===========================================================================
ren_err="$(pxr "OPENROUTER_API_KEY=$SENTINEL" -- render --subject "all error" --preset A --mode offline --inject-council "$CANNED_ERR" --json)"
assert_contains "AC-6 all-error render surfaces the exact classified code" "$ren_err" "COUNCIL_MODEL_UNAVAILABLE"
assert_not_contains "AC-6 all-error render does NOT fabricate a success code" "$ren_err" "COUNCIL_INFERENCE_OK"

# ===========================================================================
# AC-4 / REQ-GUI-008 -- LIVE gate: a mode=live request WITHOUT the server-side gate
#   (COUNCIL_INFERENCE_LIVE=1) is REFUSED (explicit classified refusal, non-2xx OR a
#   classified body), NOT silently downgraded, and fires 0 calls. Default mode offline.
#   These: "live is gated". Gegenthese: a live request that silently runs offline (a
#   plausible result that the operator BELIEVES is a live council) OR silently spends
#   credits. Schaerfung: assert refused == true AND status is non-2xx (or explicit
#   classified body) AND spawn counter == 0.
# ===========================================================================
SPAWN_LIVE="$SCRATCH/spawn_live.cnt"
# NOTE: no COUNCIL_INFERENCE_LIVE in env -> the server-side gate is OFF (MVP default).
ren_live="$(pxr "OPENROUTER_API_KEY=$SENTINEL" -- render --subject "go live" --preset A --mode live --inject-spawn-counter "$SPAWN_LIVE" --json)"
assert_json_eq "AC-4 live request without gate is REFUSED (refused=true)" "$ren_live" 'd["refused"]' True
assert_json_eq "AC-4 live refusal status is non-2xx (>=400)" "$ren_live" 'd["status"] >= 400' True
assert_eq "AC-4 live refusal fired ZERO subprocess spawns (no silent downgrade-run)" "0" "$(ctr "$SPAWN_LIVE")"
# The refusal must be explicit/classified, NOT a fabricated council success.
assert_not_contains "AC-4 live refusal does NOT fabricate an OK council result" "$ren_live" "COUNCIL_INFERENCE_OK"

# Default mode is offline: a render with NO --mode behaves offline.
# NOTE (no-demo override): the default/offline path is exercised here with an explicit
# --inject-council (the TEST seam). The offline-NO-inject path is no longer a demo; it is
# the classified "live required" response asserted in the dedicated block below.
SPAWN_DEF="$SCRATCH/spawn_def.cnt"
ren_def="$(pxr "OPENROUTER_API_KEY=$SENTINEL" -- render --subject "default mode" --preset A --inject-council "$CANNED_OK" --inject-spawn-counter "$SPAWN_DEF" --json)"
assert_json_eq "AC-4 default mode is offline" "$ren_def" 'd["mode"]' offline
assert_eq "AC-4 default-mode render spawned ZERO subprocesses" "0" "$(ctr "$SPAWN_DEF")"

# ===========================================================================
# AC-4 / REQ-GUI-008/016 -- LIVE-SPAWN-REACHED (gate ON + secret present): the real
#   council spawn path is REACHED. Tested OFFLINE through the proxy's OWN production
#   `process_request` core with the FIRST-CLASS `spawn_fn` seam (a production parameter,
#   line ~311) injected as a network-free stand-in for the child runner -- so ZERO real
#   subprocess, ZERO network, ZERO credits are spent, yet the spawn path is provably
#   reached. This is the live entrypoint's WIRING proof one level down from AC-7/AC-9.
#
#   WHY a Python harness over `process_request` (NOT the CLI `render`): the CLI/served
#   live path uses the DEFAULT spawn fn, which shells out to the REAL child runner and
#   would fire a REAL OpenRouter call -- forbidden in this offline suite (0 live calls).
#   The `spawn_fn` parameter is the production seam the served/CLI paths flow through;
#   injecting it here exercises the REAL gate->secret->spawn ORDERING of the production
#   core without crossing the boundary. The real entrypoints are proven elsewhere (the
#   AC-9 launcher; the live-required socket path) so this is NOT a seam-green/entrypoint-
#   dead false-green -- it is the core's spawn-ordering falsifier.
#
#   kritische semantische Glaettung (Beat 0: BOUNDARY -- the live path spawns a real OS
#   subprocess that holds the secret in its env):
#   These (self-evident): "mode=live with the gate + secret runs the council."
#   Gegenthese (the repo signature false-green "injectable seam green, real entrypoint
#     dead", CLAUDE.md): the gate/secret checks pass but the spawn path is NEVER reached
#     (the live branch falls through to a fabricated success or an empty render), so a
#     live run looks green yet no council was ever invoked -- OR it fabricates an OK
#     council without ever calling the spawn fn at all.
#   Schaerfung (a COUNTER-based falsifier, not just an outcome assertion -- fails if the
#     gate->secret->spawn wiring is reverted): with the gate ON + the secret present, the
#     production core MUST invoke the injected spawn_fn EXACTLY once (the spawn path WAS
#     reached) AND render its (MIXED) output honestly -- BOTH an OK position AND a per-role
#     classified code, never collapsed to a fabricated success, never a demo label.
# ---------------------------------------------------------------------------
# Harness written to a tempfile so NO heredoc body sits inside $() (G1-safe). It imports
# the production proxy module, injects a spawn_fn that records ONE call and returns the
# canned MIXED council as the child's stdout (NO subprocess, NO network), and runs the
# REAL process_request live branch (gate ON + secret present).
SPAWN_HARNESS="$SCRATCH/live_spawn_harness.py"
cat > "$SPAWN_HARNESS" <<'PY'
# argv: <proxy-module-path> <canned-mixed-json-path>
import importlib.util
import json
import subprocess
import sys


def main():
    module_path, canned_path = sys.argv[1], sys.argv[2]
    spec = importlib.util.spec_from_file_location("gui_proxy_under_test", module_path)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    with open(canned_path, encoding="utf-8") as fh:
        canned = fh.read()

    calls = {"n": 0}

    def fake_spawn(argv):
        # The production seam: a real spawn would run argv as a subprocess and return its
        # CompletedProcess. Here we record the call and hand back the canned child stdout.
        # NO subprocess is started; NO network is touched.
        calls["n"] += 1
        return subprocess.CompletedProcess(argv, 0, stdout=canned, stderr="")

    envelope = mod.process_request(
        subject="live run reached",
        preset="A",
        mode="live",
        inject_council=None,
        spawn_counter=None,
        live_gate_on=True,
        secret_present=True,
        spawn_fn=fake_spawn,
    )
    # Emit the spawn-call count on line 1, then the envelope JSON (so the test can read both).
    print(calls["n"])
    print(json.dumps(envelope, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
PY

SPAWN_OUT="$SCRATCH/live_spawn.out"
env -i PATH="$PATH" python3 "$SPAWN_HARNESS" "$PROXY_MOD" "$CANNED_MIXED" > "$SPAWN_OUT" 2>&1
spawn_calls="$(head -n 1 "$SPAWN_OUT")"
ren_spawn="$(tail -n +2 "$SPAWN_OUT")"
assert_eq "AC-4 live (gate+secret) SPAWN PATH WAS REACHED (spawn_fn invoked exactly once)" "1" "$spawn_calls"
assert_json_eq "AC-4 live (gate+secret) render mode is live" "$ren_spawn" 'd["mode"]' live
assert_json_eq "AC-4 live (gate+secret) render is NOT refused" "$ren_spawn" 'd["refused"]' False
# Honesty: the live render of a MIXED child surfaces BOTH an OK position AND a classified code.
assert_contains "AC-4 live render shows an OK role position (not collapsed)" "$ren_spawn" "Ship the visible slice."
assert_contains "AC-4 live render surfaces a per-role classified code" "$ren_spawn" "COUNCIL_MODEL_UNAVAILABLE"
assert_contains "AC-4 live render shows the per-role character-missing code" "$ren_spawn" "character-missing"
# A live render must NEVER be a fabricated full success and must NEVER carry a demo BANNER.
# (Forbid the rendered demo BANNER marker, not the envelope's legitimate `"demo": false`
# bookkeeping field -- a bare "demo" substring would false-match that boolean.)
assert_not_contains "AC-4 live render does NOT claim a fabricated full success (ALL_OK)" "$ren_spawn" "ALL_OK"
assert_not_contains "AC-4 live render carries NO demo banner (no demo-banner marker)" "$ren_spawn" "demo-banner"
assert_not_contains "AC-4 live render carries NO demo label text" "$ren_spawn" "offline sample positions"

# ===========================================================================
# REQ-GUI-011 -- pasted subject is OPAQUE DATA: shell metachars do NOT execute and the
#   render escapes them so they cannot break the page.
#   These: "the subject is data". Gegenthese: a subject containing `$(...)` / backticks
#   that the proxy interpolates into a shell command (RCE) or injects unescaped into the
#   HTML (XSS) -- a paste turns into code execution. Schaerfung: post a metachar payload;
#   assert a sentinel side-effect file is NOT created AND the payload is escaped in the
#   render (no raw <script>). Eval-FREE: the payload is parameter-passed, never eval'd.
# ===========================================================================
CANARY="$SCRATCH/_pwned_canary"
rm -f "$CANARY"
# A subject that WOULD create the canary IF interpolated into a shell, and WOULD inject
# script IF rendered unescaped. Passed as a single argv value (no eval anywhere).
# SC2016 disabled deliberately: the backtick/$() are LITERAL payload bytes the proxy must
# treat as opaque data; only $CANARY (a test-controlled path) is meant to expand.
# shellcheck disable=SC2016
PAYLOAD='hello `touch '"$CANARY"'` $(touch '"$CANARY"') <script>alert(1)</script>'
ren_inj="$(pxr "OPENROUTER_API_KEY=$SENTINEL" -- render --subject "$PAYLOAD" --preset A --mode offline --inject-council "$CANNED_OK" --json)"
canary_present=0; [ -e "$CANARY" ] && canary_present=1
assert_eq "REQ-GUI-011 metachar subject did NOT execute a shell side-effect (no canary file)" "0" "$canary_present"
assert_not_contains "REQ-GUI-011 render does NOT contain a raw executable <script> tag" "$ren_inj" "<script>alert(1)</script>"

# ===========================================================================
# AC-7 / REQ-GUI-014 -- real-path preconditions fail LOUD (never a plausible all-unknown).
#   Driving the REAL council (NO --inject-council, mode live with the gate ON) has three
#   preconditions the launcher/proxy MUST enforce with a LOUD classified error rather
#   than a plausible empty/all-OK/all-unknown render. Provable OFFLINE, ZERO live calls.
#   These: "preconditions are checked". Gegenthese: a misconfig (no key / single-family
#   catalog / wrong cwd) silently yields a plausible all-`character-missing` / all-error
#   render the operator reads as "the council ran and had no opinion". Schaerfung: assert
#   a LOUD classified error_code AND that it is NOT a fabricated success, AND 0 spawns to
#   a real network never happen.
# ---------------------------------------------------------------------------
# (a) Missing key -> COUNCIL_MISSING_SECRET, zero calls. Live gate ON, key ABSENT.
SPAWN_NOKEY="$SCRATCH/spawn_nokey.cnt"
ren_nokey="$(pxr "COUNCIL_INFERENCE_LIVE=1" -- render --subject "real run no key" --preset A --mode live --inject-spawn-counter "$SPAWN_NOKEY" --json)"
assert_json_eq "AC-7(a) missing-key real run yields a classified error (error_code set)" "$ren_nokey" 'd["error_code"] is not None' True
assert_contains "AC-7(a) missing-key error names COUNCIL_MISSING_SECRET" "$ren_nokey" "COUNCIL_MISSING_SECRET"
assert_not_contains "AC-7(a) missing-key run does NOT render a plausible OK council" "$ren_nokey" "COUNCIL_INFERENCE_OK"

# ===========================================================================
# AC-9 / REQ-GUI-016 -- WIRED-IN-PROD via the REAL launcher (NOT only the in-process
#   handler). Cites the repo signature false-green "injectable seam green, real entrypoint
#   dead" (CLAUDE.md): a test that only drives `render` would pass even if the real
#   `plumbline-council-gui` launcher were dead. So START the real launcher process and
#   drive a request that REACHES the proxy, asserting the real entrypoint serves+renders.
#   Plus a from-wrong-cwd start asserting fail-loud-or-resolve (never a plausible
#   all-`character-missing`).
#
#   The launcher MUST support a one-shot self-contained mode used here so the test does
#   not depend on a long-lived socket:
#     plumbline-council-gui --self-check --inject-council <path> --json
#   which performs the launcher's REAL startup (cwd-pin / DEEPSEEK_CHARACTERS_DIR /
#   precondition enforcement) and then serves ONE injected render through the SAME proxy
#   code the live server uses, emitting the render JSON. (This is the launcher's real
#   composition root -- not a second handler.)
# ===========================================================================
# (1) Real launcher start from the REPO ROOT -> headline paste->run->render works.
launch_ok="$(env -i PATH="$PATH" OPENROUTER_API_KEY="$SENTINEL" "$REPO_DIR/$LAUNCHER" --self-check --inject-council "$CANNED_OK" --json 2>&1)"
assert_contains "AC-9 real launcher renders a position through the prod composition path" "$launch_ok" "We should ship the thin slice first."
assert_contains "AC-9 real launcher renders the diversity gate" "$launch_ok" "COUNCIL_DIVERSITY_OK"
assert_contains "AC-9 real launcher renders the RISK-B-007 disclosure" "$launch_ok" "RISK-B-007"

# (2) Real launcher started from the WRONG cwd MUST fail loud OR resolve cwd -- it must
#     NEVER produce a plausible all-`character-missing` render as if the council ran.
#     Run with cwd=/tmp and NO DEEPSEEK_CHARACTERS_DIR and NO --inject-council so the
#     launcher must hit its real precondition path.
WRONG_OUT="$SCRATCH/wrong_cwd.out"
( cd /tmp && env -i PATH="$PATH" OPENROUTER_API_KEY="$SENTINEL" COUNCIL_INFERENCE_LIVE=1 \
    "$REPO_DIR/$LAUNCHER" --self-check --mode live --preset A --subject "wrong cwd" --json >"$WRONG_OUT" 2>&1 )
wrong_cwd="$(cat "$WRONG_OUT")"
# fail-loud-or-resolve: EITHER a loud classified error, OR (if it resolved cwd) NOT an
# all-character-missing council. The forbidden outcome is a plausible all-error render
# presented as a real run. Assert it does NOT silently render an OK council, AND it
# surfaces SOME classified signal (an error_code or a refusal), never a bare success.
# Eval-FREE: compute each grep verdict into a 0/1 status, then assert_eq the exact value
# (the captured output is parameter-passed to grep via printf, never eval'd).
ok_present=0; printf '%s' "$wrong_cwd" | grep -qF 'COUNCIL_INFERENCE_OK' && ok_present=1
assert_eq "AC-9 wrong-cwd launcher does NOT silently render a plausible OK council" "0" "$ok_present"
signal_present=0; printf '%s' "$wrong_cwd" | grep -qE 'error_code|refused|COUNCIL_|character-missing|cwd' && signal_present=1
assert_eq "AC-9 wrong-cwd launcher surfaces a classified signal (error_code/refused/classified code), not a bare success" "1" "$signal_present"
tb_present=0; printf '%s' "$wrong_cwd" | grep -qF 'Traceback (most recent call last)' && tb_present=1
assert_eq "AC-9 wrong-cwd launcher emits no raw Python traceback" "0" "$tb_present"

# ===========================================================================
# REQ-GUI-012 -- no generic crash on a malformed render request: a bad preset is a
#   CLASSIFIED error surfaced honestly, never a Python traceback nor a fake success.
# ===========================================================================
ren_badpreset="$(pxr "OPENROUTER_API_KEY=$SENTINEL" -- render --subject "x" --preset ZZZ --mode offline --inject-council "$CANNED_OK" --json 2>&1)"
assert_not_contains "REQ-GUI-012 a bad preset does not crash with a raw traceback" "$ren_badpreset" "Traceback (most recent call last)"

# ===========================================================================
# AC-1 / REQ-GUI-001/016 -- OFFLINE-NO-LIVE over the REAL HTTP SOCKET returns a classified
#   "LIVE REQUIRED" response -- NOT a fabricated demo council (NO-FAKE / NO-DEMO OVERRIDE).
#
#   kritische semantische Glaettung (Beat 0: BOUNDARY -- this drives a real http.server
#   over a real loopback socket):
#   These (self-evident): "the offline served path returns a council to the browser."
#   Gegenthese (the user's principled override, AND the Plumbline no-fake invariant): the
#     offline served path SILENTLY serves a FABRICATED DEMO council the operator reads as
#     real model positions -- a fake masquerading as the product's value. "Fake=Demo, dann
#     weglassen." A green socket POST returning rendered positions delivers ZERO real value
#     and actively misleads (the operator believes a council ran). The CLI inject seam
#     cannot see this -- it never binds the socket with NO injection.
#   Schaerfung (the test that kills the Gegenthese, exercised through the assembled prod
#     `serve` socket, NO CLI injection): POST {subject, preset:"A", mode:"offline"} over
#     the loopback socket WITHOUT the live gate and WITHOUT any injection, and assert the
#     served path returns an HONEST classified "live required" response:
#       - a NON-2xx status (>=400) -- it is NOT a 200 council render;
#       - a classified error_code (COUNCIL_LIVE_REQUIRED) surfaced honestly;
#       - NO fabricated council positions (none of the demo character ids / position text);
#       - NO `demo` label and NO `"demo": true` (the demo is GONE from production);
#       - an honest, actionable "enable live to run the council" message;
#       - still integration-fake: 0 subprocess spawn, 0 network egress, 0 key leak (the
#         SENTINEL key is resident in the server env yet appears nowhere in the response).
#
#   This MUST FAIL now for the RIGHT reason: production do_POST currently serves the bundled
#   DEMO council (200) on an offline POST with no inject. The coder REMOVES the demo and
#   makes the offline-no-live served path return the classified COUNCIL_LIVE_REQUIRED
#   response. bash-3.2-safe: the socket client is a tempfile Python script (NO $()-wrapped
#   heredoc), invoked plainly.
# ---------------------------------------------------------------------------
# Socket client written to a tempfile so NO heredoc body sits inside $() (G1-safe).
SOCK_CLIENT="$SCRATCH/sock_post.py"
cat > "$SOCK_CLIENT" <<'PY'
# Drive the REAL served path: start `serve` on an ephemeral loopback port, POST the
# request body over a real TCP socket (NO CLI inject), print the response status line
# and body. argv: <proxy-module> <diag-file> <subject> <preset> <mode>. A live transport
# call would need the network; this offline POST must reach NONE -- it is purely loopback.
#
# Readiness is HARDENED for slow CI runners (macOS): a generous ~30s budget, a real
# TCP-connect probe loop, the server given time to import+bind before the first attempt,
# the server's stdout AND stderr captured to temp files so a REAL bind failure is
# distinguishable from a slow start, and a relaunch on early exit (slow ephemeral-port
# release / EADDRINUSE) so a transient bind race does not produce a flaky SERVER_NOT_READY.
#
# DIAGNOSTIC: on SERVER_NOT_READY the LOUD, CI-visible root cause (the server's stderr +
# stdout tail, the subprocess exit code, the launching python's sys.version/sys.executable,
# the exact serve argv, and the chosen port) is written to <diag-file> -- a DEDICATED file,
# NEVER stdout -- each line tagged `GUI_SRV_DIAG:` so it is unmistakable in the CI log. The
# bash caller cats this file (to its stderr) AFTER the assertions, so the existing stdout
# parsing (status line + body) and the `SERVER_NOT_READY` marker are byte-for-byte
# unchanged. The diagnostic is DORMANT on success (the file is only written on failure).
import http.client
import json
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


def _read_reset(fh):
    # Read a temp file opened in w+ mode without losing the write position.
    try:
        fh.flush()
        fh.seek(0)
        return fh.read()
    except OSError:
        return ""


def _tail(text, limit=4000):
    if text and len(text) > limit:
        return "...<truncated>...\n" + text[-limit:]
    return text


def _write_diag(diag_file, argv, port, returncode, srv_err, srv_out):
    # Write the LOUD, CI-visible diagnostic for a server that never became connectable.
    # Every line is tagged so it survives grep in a noisy CI log. Written to a DEDICATED
    # file (NOT stdout), so assertion parsing of stdout is untouched.
    lines = []
    lines.append("==== server failed to become ready ====")
    lines.append("launching python sys.executable: " + str(sys.executable))
    lines.append("launching python sys.version: " + sys.version.replace("\n", " "))
    lines.append("serve argv: " + repr(argv))
    lines.append("chosen port: " + str(port))
    lines.append("subprocess exit/returncode: " + str(returncode))
    lines.append("---- server stderr (begin) ----")
    for ln in _tail(srv_err).splitlines() or ["<empty>"]:
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


def _start_server(module, diag_file):
    # Returns (proc, port, out_file, err_file) on success, or (None, None, None, None) on
    # failure -- writing the LOUD diagnostic to diag_file before returning. Retries on
    # early exit so a slow port release on the runner is not a hard failure.
    last_err = ""
    last_out = ""
    last_argv = None
    last_port = None
    last_rc = None
    for _ in range(LAUNCH_ATTEMPTS):
        port = _free_port()
        out_file = tempfile.NamedTemporaryFile(
            mode="w+", suffix=".srvout", delete=False
        )
        err_file = tempfile.NamedTemporaryFile(
            mode="w+", suffix=".srverr", delete=False
        )
        argv = [sys.executable, module, "serve", "--port", str(port)]
        proc = subprocess.Popen(argv, stdout=out_file, stderr=err_file)
        last_argv, last_port = argv, port
        # Give the subprocess a moment to import + bind before the first connect attempt.
        deadline = time.time() + READY_BUDGET
        while time.time() < deadline:
            rc = proc.poll()
            if rc is not None:
                # Exited before accepting -- capture why, then retry a fresh port.
                last_err = _read_reset(err_file)
                last_out = _read_reset(out_file)
                last_rc = rc
                err_file.close()
                out_file.close()
                break
            try:
                probe = socket.create_connection(
                    ("127.0.0.1", port), timeout=CONNECT_TIMEOUT
                )
                probe.close()
                return proc, port, out_file, err_file
            except OSError:
                time.sleep(POLL_SLEEP)
        else:
            # Budget elapsed with the process still alive but not accepting: real timeout.
            last_err = _read_reset(err_file)
            last_out = _read_reset(out_file)
            last_rc = proc.poll()  # likely None: alive but not accepting
            err_file.close()
            out_file.close()
            _write_diag(diag_file, last_argv, last_port, last_rc, last_err, last_out)
            return None, None, None, None
        # Loop: relaunch on early exit.
    _write_diag(diag_file, last_argv, last_port, last_rc, last_err, last_out)
    return None, None, None, None


def main():
    module, diag_file, subject, preset, mode = (
        sys.argv[1],
        sys.argv[2],
        sys.argv[3],
        sys.argv[4],
        sys.argv[5],
    )
    proc, port, out_file, err_file = _start_server(module, diag_file)
    if proc is None:
        # SERVER_NOT_READY stays on stdout line 1 exactly where the asserts expect it;
        # the LOUD root cause is in <diag-file>, which the bash caller cats afterward.
        print("SERVER_NOT_READY")
        return 0
    try:
        body = json.dumps({"subject": subject, "preset": preset, "mode": mode})
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        conn.request("POST", "/run", body, {"Content-Type": "application/json"})
        resp = conn.getresponse()
        payload = resp.read().decode("utf-8", "replace")
        conn.close()
        # First line: the HTTP status code. Remaining lines: the raw response body.
        print(resp.status)
        print(payload)
        return 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        for fh in (out_file, err_file):
            try:
                fh.close()
            except (OSError, AttributeError):
                pass


if __name__ == "__main__":
    raise SystemExit(main())
PY

# Run the server under a CLEAN env that STILL carries the SENTINEL key (proving the key
# is resident in the serving process yet never leaks) and NO live gate (offline default).
SOCK_OUT="$SCRATCH/sock_offline.out"
SOCK_DIAG="$SCRATCH/sock_offline.diag"
env -i PATH="$PATH" OPENROUTER_API_KEY="$SENTINEL" \
  python3 "$SOCK_CLIENT" "$PROXY_MOD" "$SOCK_DIAG" "Should we ship slice 4" "A" "offline" \
  > "$SOCK_OUT" 2>&1
sock_status="$(head -n 1 "$SOCK_OUT")"
sock_body="$(tail -n +2 "$SOCK_OUT")"
# LOUD, CI-visible root cause if the server never became connectable. Emitted to THIS
# test's stderr (which run_all shows) AFTER the assertions below, tagged GUI_SRV_DIAG: so
# it is grep-able in the macOS CI log. Dormant on success (diag file only exists on
# SERVER_NOT_READY); does NOT touch the stdout the assertions parse.
gui_srv_diag() { # gui_srv_diag <diag-file> <label>
  [ -s "$1" ] || return 0
  printf 'GUI_SRV_DIAG: ---- %s ----\n' "$2" >&2
  cat "$1" >&2
}

# The headline falsifier: the REAL served offline-no-live POST must return an HONEST
# classified "live required" response (non-2xx) -- NOT a fabricated demo council.
# This is RED now (prod do_POST serves the demo at 200) for the RIGHT reason.
# Status must be non-2xx. (assert_json_eq cannot read this -- the body may not be the JSON
# envelope; assert the raw status line directly, exact-not-substring.)
status_2xx=1; case "$sock_status" in 2??) status_2xx=1 ;; *) status_2xx=0 ;; esac
assert_eq "AC-1/REQ-GUI-016 REAL offline-no-live socket POST is NON-2xx (NOT a demo council render)" "0" "$status_2xx"
assert_contains "AC-1/REQ-GUI-016 REAL offline-no-live socket POST surfaces the classified COUNCIL_LIVE_REQUIRED code" "$sock_body" "COUNCIL_LIVE_REQUIRED"
# NO fabricated council positions: none of the demo character ids / position text appear.
assert_not_contains "AC-1 offline-no-live socket response fabricates NO council position (no demo character id)" "$sock_body" "die-visionaerin"
assert_not_contains "AC-1 offline-no-live socket response fabricates NO position text" "$sock_body" "We should ship the thin slice first."
assert_not_contains "AC-1 offline-no-live socket response fabricates NO OK council code" "$sock_body" "COUNCIL_INFERENCE_OK"
# NO demo: the served path must render no demo BANNER and must not claim demo:true.
# (Forbid the rendered demo BANNER marker + the demo label text + a `"demo": true`
# envelope field -- NOT a bare "demo" substring, which false-matches a legitimate
# `"demo": false` bookkeeping field if the coder keeps it.)
assert_not_contains "AC-1 offline-no-live socket response renders NO demo banner (no demo-banner marker)" "$sock_body" "demo-banner"
assert_not_contains "AC-1 offline-no-live socket response renders NO demo label text" "$sock_body" "offline sample positions"
assert_not_contains "AC-1 offline-no-live socket response does NOT claim demo:true" "$(printf '%s' "$sock_body" | tr -d ' ' | tr '[:upper:]' '[:lower:]')" '"demo":true'
# An HONEST, actionable message: the operator is told to ENABLE LIVE to run the council
# (a specific actionable phrase, not a bare "live" that COUNCIL_LIVE_REQUIRED would match).
assert_contains "AC-1 offline-no-live socket response renders an honest 'enable live' message" "$(printf '%s' "$sock_body" | tr '[:upper:]' '[:lower:]')" "enable live"
# Reality Ledger floor stays integration-fake: 0 key leak over the real served path.
assert_not_contains "AC-1 offline-no-live socket response carries no key sentinel (0 key leak)" "$sock_body" "$SENTINEL"
gui_srv_diag "$SOCK_DIAG" "offline-no-live socket POST (/run)"

# ===========================================================================
# REQ-GUI-016 / code-review IMPORTANT-2 -- the DOCUMENTED `POST /run` route is REAL and
#   unknown POST paths are REFUSED (404), not silently treated as a council run.
#
#   kritische semantische Glaettung (Beat 0: BOUNDARY -- a real http.server over a real
#   loopback socket; the routing decision only exists on the served path):
#   These (self-evident): "the POST endpoint handles the run request" -- the module
#     docstring and static/app.js both promise `POST /run`.
#   Gegenthese: do_POST ignores self.path entirely, so EVERY POST -- to /run, to /unknown,
#     to /api/keys, to anything -- is handled identically. The contract "POST /run" is
#     fiction: there is no route, just a catch-all. A client (or a future CSRF/path-confused
#     caller) hitting any path silently gets the same handling, and a genuine 404 for a
#     mistyped/foreign path never happens -- the server lies about its surface. The CLI
#     `render` seam and the /run-only socket test above cannot see this: neither ever POSTs
#     to a NON-/run path.
#   Schaerfung (kills the Gegenthese over the assembled prod `serve` socket):
#     (1) POST /run {subject,preset:A,mode:offline} -> the REAL documented route is REACHED:
#         it returns the HONEST classified COUNCIL_LIVE_REQUIRED response (non-2xx, no demo,
#         no fabricated council), proving /run routes into process_request (not a 404).
#     (2) POST /unknown (any non-/run path) -> 404 (unknown POST paths are refused, NOT
#         silently run). FAILS now: production returns 200 for /unknown only if routing is
#         a catch-all -- assert the explicit 404 branch exists.
#
#   RED-for-the-right-reason: with the no-demo override, /run offline-no-live must surface
#   COUNCIL_LIVE_REQUIRED (RED now: prod serves the demo at 200). The coder routes POST by
#   path AND removes the demo. bash-3.2-safe: the socket client is a tempfile Python script
#   (NO $()-wrapped heredoc), invoked plainly; it takes the request PATH as argv.
# ---------------------------------------------------------------------------
ROUTE_CLIENT="$SCRATCH/route_post.py"
cat > "$ROUTE_CLIENT" <<'PY'
# Drive the REAL served path with an explicit request PATH: start `serve` on an
# ephemeral loopback port, POST the body to argv-supplied <path>, print the response
# status line then the raw body. argv: <proxy-module> <diag-file> <path> <subject>
# <preset> <mode>.
#
# Readiness is HARDENED for slow CI runners (macOS): a generous ~30s budget, a real
# TCP-connect probe loop, the server given time to import+bind before the first attempt,
# the server's stdout AND stderr captured to temp files so a REAL bind failure is
# distinguishable from a slow start, and a relaunch on early exit (slow ephemeral-port
# release / EADDRINUSE).
#
# DIAGNOSTIC: on SERVER_NOT_READY the LOUD, CI-visible root cause (server stderr + stdout
# tail, subprocess exit code, launching python sys.version/sys.executable, the exact serve
# argv, and the chosen port) is written to <diag-file> -- a DEDICATED file, NEVER stdout --
# each line tagged `GUI_SRV_DIAG:`. The bash caller cats it (to stderr) AFTER the
# assertions, so stdout parsing and the SERVER_NOT_READY marker are unchanged. Dormant on
# success (the file is only written on failure).
import http.client
import json
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


def _read_reset(fh):
    try:
        fh.flush()
        fh.seek(0)
        return fh.read()
    except OSError:
        return ""


def _tail(text, limit=4000):
    if text and len(text) > limit:
        return "...<truncated>...\n" + text[-limit:]
    return text


def _write_diag(diag_file, argv, port, returncode, srv_err, srv_out):
    lines = []
    lines.append("==== server failed to become ready ====")
    lines.append("launching python sys.executable: " + str(sys.executable))
    lines.append("launching python sys.version: " + sys.version.replace("\n", " "))
    lines.append("serve argv: " + repr(argv))
    lines.append("chosen port: " + str(port))
    lines.append("subprocess exit/returncode: " + str(returncode))
    lines.append("---- server stderr (begin) ----")
    for ln in _tail(srv_err).splitlines() or ["<empty>"]:
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


def _start_server(module, diag_file):
    # Returns (proc, port, out_file, err_file) on success, or (None, None, None, None) on
    # failure -- writing the LOUD diagnostic to diag_file first.
    last_err = ""
    last_out = ""
    last_argv = None
    last_port = None
    last_rc = None
    for _ in range(LAUNCH_ATTEMPTS):
        port = _free_port()
        out_file = tempfile.NamedTemporaryFile(
            mode="w+", suffix=".srvout", delete=False
        )
        err_file = tempfile.NamedTemporaryFile(
            mode="w+", suffix=".srverr", delete=False
        )
        argv = [sys.executable, module, "serve", "--port", str(port)]
        proc = subprocess.Popen(argv, stdout=out_file, stderr=err_file)
        last_argv, last_port = argv, port
        deadline = time.time() + READY_BUDGET
        while time.time() < deadline:
            rc = proc.poll()
            if rc is not None:
                last_err = _read_reset(err_file)
                last_out = _read_reset(out_file)
                last_rc = rc
                err_file.close()
                out_file.close()
                break
            try:
                probe = socket.create_connection(
                    ("127.0.0.1", port), timeout=CONNECT_TIMEOUT
                )
                probe.close()
                return proc, port, out_file, err_file
            except OSError:
                time.sleep(POLL_SLEEP)
        else:
            last_err = _read_reset(err_file)
            last_out = _read_reset(out_file)
            last_rc = proc.poll()
            err_file.close()
            out_file.close()
            _write_diag(diag_file, last_argv, last_port, last_rc, last_err, last_out)
            return None, None, None, None
    _write_diag(diag_file, last_argv, last_port, last_rc, last_err, last_out)
    return None, None, None, None


def main():
    module, diag_file, path, subject, preset, mode = (
        sys.argv[1],
        sys.argv[2],
        sys.argv[3],
        sys.argv[4],
        sys.argv[5],
        sys.argv[6],
    )
    proc, port, out_file, err_file = _start_server(module, diag_file)
    if proc is None:
        print("SERVER_NOT_READY")
        return 0
    try:
        body = json.dumps({"subject": subject, "preset": preset, "mode": mode})
        conn = http.client.HTTPConnection("127.0.0.1", port, timeout=10)
        conn.request("POST", path, body, {"Content-Type": "application/json"})
        resp = conn.getresponse()
        payload = resp.read().decode("utf-8", "replace")
        conn.close()
        print(resp.status)
        print(payload)
        return 0
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()
        for fh in (out_file, err_file):
            try:
                fh.close()
            except (OSError, AttributeError):
                pass


if __name__ == "__main__":
    raise SystemExit(main())
PY

# (1) POST /run -> the documented route is REACHED (NOT a 404): offline-no-live returns
#     the HONEST classified COUNCIL_LIVE_REQUIRED response, never a fabricated demo council.
RUN_OUT="$SCRATCH/route_run.out"
RUN_DIAG="$SCRATCH/route_run.diag"
env -i PATH="$PATH" OPENROUTER_API_KEY="$SENTINEL" \
  python3 "$ROUTE_CLIENT" "$PROXY_MOD" "$RUN_DIAG" "/run" "Should we ship slice 4" "A" "offline" \
  > "$RUN_OUT" 2>&1
run_status="$(head -n 1 "$RUN_OUT")"
run_body="$(tail -n +2 "$RUN_OUT")"
# /run is a REAL route (not the 404 the catch-all-less server would give an unrouted path).
assert_eq "IMPORTANT-2 POST /run is NOT a 404 (the documented route is real and reached)" "0" "$([ "$run_status" = "404" ] && echo 1 || echo 0)"
assert_contains "IMPORTANT-2 POST /run offline-no-live surfaces the classified COUNCIL_LIVE_REQUIRED" "$run_body" "COUNCIL_LIVE_REQUIRED"
assert_not_contains "IMPORTANT-2 POST /run renders NO fabricated demo council" "$run_body" "die-visionaerin"
gui_srv_diag "$RUN_DIAG" "route POST /run"

# (2) POST /unknown -> 404 (unknown POST paths are refused, not silently run as a council).
UNK_OUT="$SCRATCH/route_unknown.out"
UNK_DIAG="$SCRATCH/route_unknown.diag"
env -i PATH="$PATH" OPENROUTER_API_KEY="$SENTINEL" \
  python3 "$ROUTE_CLIENT" "$PROXY_MOD" "$UNK_DIAG" "/unknown" "Should we ship slice 4" "A" "offline" \
  > "$UNK_OUT" 2>&1
unk_status="$(head -n 1 "$UNK_OUT")"
unk_body="$(tail -n +2 "$UNK_OUT")"
assert_eq "IMPORTANT-2 POST /unknown returns HTTP 404 (unknown POST path refused, NOT a silent council run)" "404" "$unk_status"
# A refused unknown path must never crash with a raw traceback (true now AND after the fix).
assert_not_contains "IMPORTANT-2 POST /unknown does not crash with a raw traceback" "$unk_body" "Traceback (most recent call last)"
gui_srv_diag "$UNK_DIAG" "route POST /unknown"

finish "test_gui_proxy"
