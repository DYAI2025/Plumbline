# shellcheck shell=bash
# Minimal assertion helpers for the bash test scripts. Source this file.
# Pure POSIX-ish bash, no external deps beyond coreutils.

TESTS_RUN=0
TESTS_FAILED=0

_pass() { printf '  ok   %s\n' "$1"; }
_fail() { printf '  FAIL %s\n' "$1"; TESTS_FAILED=$((TESTS_FAILED + 1)); }

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
print(eval(os.environ["EXPR"]))  # EXPR is the test-author's extractor, NOT payload data
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
  # false-fail it. <regex> is a fixed test-author literal, never payload — no eval of
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
  printf '\n%s: %d run, %d failed\n' "${1:-tests}" "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
