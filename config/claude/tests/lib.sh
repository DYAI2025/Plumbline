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

repo_version() { # repo_version <repo-root>
  # VERSION is release-please-managed and may contain marker comments. Return
  # the first non-comment, non-empty line so release tests follow each bump.
  awk 'NF && $0 !~ /^#/ {print; exit}' "${1:-.}/VERSION"
}

finish() { # print summary and exit non-zero if anything failed
  printf '\n%s: %d run, %d failed\n' "${1:-tests}" "$TESTS_RUN" "$TESTS_FAILED"
  [ "$TESTS_FAILED" -eq 0 ]
}
