# shellcheck shell=bash
# Minimal assertion helpers for the bash test scripts. Source this file.
# Pure POSIX-ish bash, no external deps beyond coreutils.

TESTS_RUN=0
TESTS_FAILED=0
TESTS_SKIPPED=0

_pass() { printf '  ok   %s\n' "$1"; }
_fail() { printf '  FAIL %s\n' "$1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }
# A LOUD, counted, never-silent SKIP. Per the repo "no silent caps -- log what was
# dropped" rule: a skipped assertion is tallied and announced, never a hidden pass.
_skip() { printf '  SKIP %s\n' "$1"; TESTS_SKIPPED=$((TESTS_SKIPPED + 1)); }

# gui_macos_skip_active <server-output-marker>
# Returns 0 (skip IS active) ONLY when BOTH hold:
#   (1) the OS is macOS (`uname` = Darwin), AND
#   (2) the server-output marker is exactly "SERVER_NOT_READY" -- i.e. the spawned
#       `serve` process was alive but its loopback socket was never connectable within
#       the FULL retry budget (the diagnosed macOS-CI-runner limitation).
# Returns 1 (skip NOT active) on EVERY non-Darwin OS (Linux stays HARD: SERVER_NOT_READY
# remains a real failure there), AND whenever the server WAS reachable (any other marker:
# a real status code or DISCONNECTED) -- so a wrong response is ALWAYS a HARD fail.
# This NEVER skips a real assertion failure; it skips ONLY the connectivity-blocked macOS
# case. eval-free, bash-3.2-safe, ASCII-only.
gui_macos_skip_active() { # gui_macos_skip_active <marker>
  [ "$(uname)" = "Darwin" ] || return 1
  [ "$1" = "SERVER_NOT_READY" ] || return 1
  return 0
}

# gui_srv_skip_notice <assertion-label>
# Emit the unmistakable, CI-grep-able skip notice for one macOS-skipped socket assertion.
gui_srv_skip_notice() { # gui_srv_skip_notice <assertion-label>
  _skip "GUI_SRV_SKIP: $1 skipped: macOS CI runner cannot accept loopback http.server (server alive, unconnectable); same logic proven by the in-process render/config seams here + the real socket on Linux CI"
}

# ----------------------------------------------------------------------------
# PUR stub-reachability helpers (the SAME diagnosed macOS-CI-runner limitation
# the GUI socket tests already handle, applied to the update-layer / session
# update-check tests). Those tests drive `plumbline update --check` against a
# 127.0.0.1 `PLUMBLINE_GITHUB_API` http.server stub; on the macOS CI runner the
# spawned stub is ALIVE (port bound, port-file written) but its loopback socket
# is never CONNECTABLE, so the CLI's fetch never reaches the stub -> empty record
# / 'unclassified' / exit 127. That is a runner network limitation, NOT a product
# defect: the SAME logic is verified HARD on Linux CI (and locally, where the
# stub IS reachable). Linux/local stay a HARD verifier; only the unconnectable
# macOS case is skipped, with a LOUD tallied notice.
#
# pur_stub_reachable <host> <port> -- prints exactly ONE marker on stdout:
#   "STUB_REACHABLE"  -- a TCP connect to <host>:<port> succeeded.
#   "STUB_NOT_READY"  -- the connect failed within the budget (port bound by the
#                        spawned server -- the caller only probes once a port file
#                        exists -- but the loopback socket is not connectable).
# The marker keys off CONNECTIVITY ONLY; it never inspects any assertion outcome,
# so a reachable-but-WRONG response is never skipped (it always runs HARD). The
# probe uses python3 (already a hard dep of these tests) -- eval-free,
# bash-3.2-safe (no $()-wrapped heredocs in the caller), ASCII-only.
pur_stub_reachable() { # pur_stub_reachable <host> <port>
  PUR_PROBE_HOST="$1" PUR_PROBE_PORT="$2" python3 - <<'PY'
import os, socket
host = os.environ["PUR_PROBE_HOST"]
try:
    port = int(os.environ["PUR_PROBE_PORT"])
except (TypeError, ValueError):
    print("STUB_NOT_READY")
    raise SystemExit(0)
# A short budget of connect attempts: the caller already waited for the port file,
# so the server is bound; this confirms the loopback socket actually accepts.
import time
deadline = time.time() + 5.0
while time.time() < deadline:
    try:
        s = socket.create_connection((host, port), timeout=0.5)
        s.close()
        print("STUB_REACHABLE")
        raise SystemExit(0)
    except OSError:
        time.sleep(0.1)
print("STUB_NOT_READY")
PY
}

# pur_macos_stub_skip_active <marker>
# Returns 0 (skip IS active) ONLY when BOTH hold:
#   (1) the OS is macOS (`uname` = Darwin), AND
#   (2) <marker> is exactly "STUB_NOT_READY" -- the spawned stub was bound but its
#       loopback socket was never connectable (the diagnosed macOS-CI limitation).
# Returns 1 (skip NOT active) on EVERY non-Darwin OS (Linux stays HARD), AND
# whenever the stub WAS reachable ("STUB_REACHABLE") -- so a wrong response is
# ALWAYS a HARD fail on every OS. This NEVER skips a real assertion failure; it
# skips ONLY the connectivity-blocked macOS case. eval-free, bash-3.2-safe, ASCII.
pur_macos_stub_skip_active() { # pur_macos_stub_skip_active <marker>
  [ "$(uname)" = "Darwin" ] || return 1
  [ "$1" = "STUB_NOT_READY" ] || return 1
  return 0
}

# pur_stub_skip_notice <assertion-label>
# Emit the unmistakable, CI-grep-able skip notice for one macOS-skipped stub assertion.
pur_stub_skip_notice() { # pur_stub_skip_notice <assertion-label>
  _skip "PUR_STUB_SKIP: $1 skipped: macOS CI runner cannot connect to the loopback PLUMBLINE_GITHUB_API stub (server bound, socket unconnectable); same logic verified HARD on Linux CI + locally"
}

assert() { # assert <description> <condition-exit-status-via-eval-string>
  TESTS_RUN=$((TESTS_RUN + 1))
  if eval "$2" >/dev/null 2>&1; then _pass "$1"; else _fail "$1"; fi
}

assert_file() { # assert_file <description> <path>
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ -f "$2" ]; then _pass "$1"; else _fail "$1 (missing: $2)"; fi
}

assert_eq() { # assert_eq <description> <expected> <actual>
  TESTS_RUN=$((TESTS_RUN + 1))
  if [ "$2" = "$3" ]; then _pass "$1"; else _fail "$1 (expected '$2', got '$3')"; fi
}

assert_contains() { # assert_contains <description> <haystack> <needle>
  TESTS_RUN=$((TESTS_RUN + 1))
  if printf '%s\n' "$2" | grep -qF -- "$3"; then
    _pass "$1"
  else
    _fail "$1 (missing '$3')"
  fi
}

assert_not_contains() { # assert_not_contains <description> <haystack> <needle>
  # Passes when <needle> is ABSENT from <haystack>. Both args are passed as
  # ordinary parameters (NOT eval'd), so shell-meta characters in the haystack
  # (e.g. '(', ')', ';', backticks) can never break parsing or change the
  # assertion's meaning. The needle is matched fixed-string via grep -F.
  TESTS_RUN=$((TESTS_RUN + 1))
  if printf '%s\n' "$2" | grep -qF -- "$3"; then
    _fail "$1 (found forbidden '$3')"
  else
    _pass "$1"
  fi
}

assert_json_eq() { # assert_json_eq <description> <json-string> <python-extractor-expr> <expected>
  # Eval-FREE JSON-field assertion. The JSON payload is written to a temp file and
  # handed to python3 as argv[1] (NEVER eval'd / re-parsed by the shell), so the
  # payload's own double-quotes can never close/reopen shell quoting or word-split
  # it into invalid JSON. <python-extractor-expr> is a Python expression evaluated
  # with `d` bound to json.load(open(argv[1])); its value is printed and compared
  # to <expected> with a plain string compare. Meaning is identical to the old
  # `assert "..." "printf %s \"$JSON\" | python3 -c 'sys.exit(0 if EXPR==X)'"`,
  # but without the eval-over-payload defect.
  #   e.g. assert_json_eq "desc" "$JSON" 'd["k"]["catch"]' 1
  #        assert_json_eq "desc" "$JSON" 'len(d["flags"])' 2
  #        assert_json_eq "desc" "$JSON" 'all(v.get("ok") for v in d.values())' True
  TESTS_RUN=$((TESTS_RUN + 1))
  local desc="$1" json="$2" expr="$3" expected="$4"
  local tmp got rc
  tmp="$(mktemp)" || { _fail "$desc (mktemp failed)"; return; }
  printf '%s' "$json" > "$tmp"
  # The extractor reads the file by path (argv[1]); no payload is interpolated into code.
  got="$(EXPR="$expr" python3 - "$tmp" <<'PY' 2>/dev/null
import json, os, sys
with open(sys.argv[1]) as fh:
    d = json.load(fh)
print(eval(os.environ["EXPR"]))  # EXPR is the test-author extractor, NOT payload data
PY
)"
  rc=$?
  rm -f "$tmp"
  if [ "$rc" -eq 0 ] && [ "$got" = "$expected" ]; then
    _pass "$desc"
  else
    _fail "$desc (expected '$expected', got '$got')"
  fi
}

assert_no_code_token() { # assert_no_code_token <description> <py-file> <regex>
  # Passes when <regex> does NOT match any ACTUAL Python CODE token in <py-file>
  # (comments and string/docstring literals are ignored via the tokenizer). This is
  # the precise form of "the module has no <seam>": a seam in real code reddens it,
  # but documenting that the module avoids the seam (in a comment/docstring) does not
  # false-fail it. <regex> is a fixed test-author literal, never payload -- no eval of
  # file content. A tokenizer/parse error fails closed (treated as a hit).
  TESTS_RUN=$((TESTS_RUN + 1))
  local desc="$1" file="$2" rx="$3" hits rc
  hits="$(RX="$rx" python3 - "$file" <<'PY' 2>/dev/null
import tokenize, sys, re, os
pat = re.compile(os.environ["RX"])
out = []
with open(sys.argv[1], "rb") as f:
    for tok in tokenize.tokenize(f.readline):
        if tok.type in (tokenize.COMMENT, tokenize.STRING):
            continue
        if pat.search(tok.string):
            out.append(f"{tok.start[0]}:{tok.string}")
print("\n".join(out))
PY
)"
  rc=$?
  if [ "$rc" -ne 0 ]; then
    _fail "$desc (tokenizer failed on $file)"
  elif [ -z "$hits" ]; then
    _pass "$desc"
  else
    _fail "$desc (code-token match: $hits)"
  fi
}

repo_version() { # repo_version <repo-root>
  # VERSION is release-please-managed and may contain marker comments. Return
  # the first non-comment, non-empty semver so release tests follow each bump.
  local version_file="${1:-.}/VERSION"
  local version
  [ -f "$version_file" ] || return 1
  version="$(awk 'NF && $0 !~ /^#/ {print; exit}' "$version_file")" || return 1
  printf '%s\n' "$version" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$' || return 1
  printf '%s\n' "$version"
}

finish() { # print summary and exit non-zero if anything failed
  if [ "$TESTS_SKIPPED" -gt 0 ]; then
    # Skips come from the macOS-CI loopback limitation only (GUI_SRV_SKIP for the
    # spawned http.server socket tests; PUR_STUB_SKIP for the update-layer /
    # session update-check loopback stub tests). Linux/local never skip.
    printf '\n%s: %d run, %d failed, %d skipped (macOS-loopback: GUI_SRV_SKIP / PUR_STUB_SKIP)\n' \
      "${1:-tests}" "$TESTS_RUN" "$TESTS_FAILED" "$TESTS_SKIPPED"
  else
    printf '\n%s: %d run, %d failed\n' "${1:-tests}" "$TESTS_RUN" "$TESTS_FAILED"
  fi
  [ "$TESTS_FAILED" -eq 0 ]
}
