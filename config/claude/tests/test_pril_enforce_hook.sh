#!/usr/bin/env bash
# Contract tests for the fail-closed PRIL enforcement Stop hook
# (config/claude/hooks/plumbline-enforce.sh).
#
# These tests prove the binding M0-gate amendments are actually true at runtime:
#   C1 — activation is driven by the ground-truth marker file
#        docs/context/.active-feature (the orchestrator writes it), NOT by an
#        env var the runtime never sets. No marker -> no-op exit 0.
#   C2 — the changed-file surface is read from git ground-truth
#        (merge-base(HEAD,main)..HEAD UNION working UNION staged), so a real
#        out-of-scope change that no agent listed is still caught -> fail closed.
#   I1 — sub-command stderr never lands in the repo (mktemp -d + trap).
#   I2 — the reality gate mirrors the feature's boundary class: a pure-logic
#        feature (no docs/context/.feature-boundary marker) is NOT blocked.
#   Safety — never exits non-zero, honors stop_hook_active, fails CLOSED.
#
# Self-contained: every git-ground-truth case builds its own throwaway repo.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_pril_enforce_hook"

HOOK="$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"
CMD="$REPO_DIR/config/claude/commands/agileteam.md"
BIN_SRC="$REPO_DIR/config/claude/bin"
LIB_SRC="$REPO_DIR/config/claude/lib"

# Workspace for all temp git repos; cleaned on exit.
WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# Run the hook against a given project dir with a given stdin payload.
# Captures stdout, stderr, and exit code separately. Uses CLAUDE_PROJECT_DIR
# (the hook's project anchor) and a clean PATH-independent invocation.
# Sets globals: HOOK_OUT HOOK_ERR HOOK_RC
run_hook() {
  local project="$1" stdin_payload="$2"
  local outf errf
  outf="$(mktemp -p "$WORK")"
  errf="$(mktemp -p "$WORK")"
  CLAUDE_PROJECT_DIR="$project" bash "$HOOK" >"$outf" 2>"$errf" <<<"$stdin_payload"
  HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"
  HOOK_ERR="$(cat "$errf")"
  rm -f "$outf" "$errf"
}

# Build a self-contained git repo that vendors the PRIL CLIs + libs so the hook
# can shell out to them with --repo pointed at this repo. Echoes the repo path.
# Arg1: feature slug. Sets up a confirmed canvas + full context + traceability.
make_feature_repo() {
  local feat="$1" repo
  repo="$(mktemp -d -p "$WORK")"

  # Vendor the real PRIL CLIs + lib so the hook's "$repo/config/claude/bin/..."
  # resolves inside this throwaway repo (the hook anchors bin on the project dir).
  mkdir -p "$repo/config/claude/bin" "$repo/config/claude/lib"
  cp "$BIN_SRC"/plumbline-context-check "$BIN_SRC"/plumbline-reality-check \
     "$BIN_SRC"/plumbline-scope-check "$repo/config/claude/bin/"
  cp "$LIB_SRC"/plumbline_context.py "$LIB_SRC"/plumbline_reality.py \
     "$LIB_SRC"/plumbline_scope.py "$repo/config/claude/lib/"
  chmod +x "$repo/config/claude/bin/"*

  # Confirmed product-context artifacts (context-check passes) + an Allowed
  # change scope section limiting changes to src/feature/** and docs/.
  mkdir -p "$repo/docs/canvas" "$repo/docs/prd" "$repo/docs/vision" \
           "$repo/docs/context" "$repo/src/feature"
  cat >"$repo/docs/canvas/$feat.canvas.md" <<EOF
# $feat Canvas

Status: user-confirmed
Confirmed by user: yes

## Allowed change scope
- src/feature/**
- docs/
EOF
  printf 'Status: user-confirmed\nPRD body.\n' >"$repo/docs/prd/$feat.prd.md"
  printf 'Status: user-confirmed\nVision body.\n' >"$repo/docs/vision/$feat.vision.md"
  printf 'Status: user-confirmed\nTraceability.\n' >"$repo/docs/traceability.md"

  # Initialize a real git repo with a main branch (merge-base needs main).
  git -C "$repo" init -q
  git -C "$repo" config user.email pril-test@example.com
  git -C "$repo" config user.name "PRIL Test"
  git -C "$repo" checkout -q -b main
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "baseline confirmed context"
  git -C "$repo" checkout -q -b "feat/$feat"

  printf '%s' "$repo"
}

# --- 1. No marker -> empty stdout, exit 0 (normal session untouched). ---------
plain_repo="$(mktemp -d -p "$WORK")"
git -C "$plain_repo" init -q
run_hook "$plain_repo" '{}'
assert_eq "no marker: exit 0" "0" "$HOOK_RC"
assert_eq "no marker: empty stdout" "" "$HOOK_OUT"

# --- 2. stop_hook_active:true -> exit 0, empty stdout (no infinite loop). ------
# Use a fully-armed feature repo so we prove the short-circuit happens BEFORE any
# enforcement (i.e. it is honored even when a marker is present).
loop_repo="$(make_feature_repo loopfeat)"
printf 'loopfeat' >"$loop_repo/docs/context/.active-feature"
run_hook "$loop_repo" '{"stop_hook_active":true}'
assert_eq "stop_hook_active: exit 0" "0" "$HOOK_RC"
assert_eq "stop_hook_active: empty stdout" "" "$HOOK_OUT"

# --- 3. Garbage / empty stdin -> exit 0 (never crashes the session). ----------
run_hook "$plain_repo" 'not json at all {{{'
assert_eq "garbage stdin: exit 0" "0" "$HOOK_RC"
run_hook "$plain_repo" ''
assert_eq "empty stdin: exit 0" "0" "$HOOK_RC"

# --- 4. Marker + planted OUT-OF-SCOPE change (git ground-truth) -> block -------
# The out-of-scope file (src/billing/charge.py) is a real staged git change that
# appears in NO agent-authored list — only in `git diff --name-only --cached`,
# part of the C2 surface. This proves C2 reads git ground-truth AND fails closed.
scope_repo="$(make_feature_repo scopefeat)"
printf 'scopefeat' >"$scope_repo/docs/context/.active-feature"
# In-scope committed change on the feature branch.
printf 'def f():\n    return 1\n' >"$scope_repo/src/feature/impl.py"
git -C "$scope_repo" add src/feature/impl.py
git -C "$scope_repo" commit -q -m "in-scope feature work"
# Out-of-scope staged change (no agent listed it; git ground-truth via --cached).
mkdir -p "$scope_repo/src/billing"
printf 'def charge():\n    return 0\n' >"$scope_repo/src/billing/charge.py"
git -C "$scope_repo" add src/billing/charge.py
run_hook "$scope_repo" '{}'
assert_eq "out-of-scope: exit 0 (never non-zero)" "0" "$HOOK_RC"

# stdout must be exactly ONE valid JSON object.
TESTS_RUN=$((TESTS_RUN + 1))
decision="$(printf '%s' "$HOOK_OUT" | jq -r '.decision' 2>/dev/null)"
djq=$?
if [ "$djq" -eq 0 ] && [ "$decision" = "block" ]; then
  _pass "out-of-scope: stdout is one JSON object with .decision==block"
else
  _fail "out-of-scope: expected .decision==block (jq rc=$djq, out: $HOOK_OUT)"
fi

TESTS_RUN=$((TESTS_RUN + 1))
reason="$(printf '%s' "$HOOK_OUT" | jq -r '.reason' 2>/dev/null)"
if printf '%s' "$reason" | grep -Fq 'scope'; then
  _pass "out-of-scope: reason names the failing 'scope' check"
else
  _fail "out-of-scope: reason should name 'scope' (reason: $reason)"
fi

# stderr must NOT have leaked err.* files into the project repo (I1).
TESTS_RUN=$((TESTS_RUN + 1))
leaked="$(find "$scope_repo" -maxdepth 2 -name 'err.*' 2>/dev/null)"
if [ -z "$leaked" ]; then
  _pass "I1: no err.* files leaked into the repo"
else
  _fail "I1: stderr leaked into repo: $leaked"
fi

# --- 5. Marker + everything in scope + NO boundary marker -> exit 0 (I2). ------
# Pure-logic feature: no docs/context/.feature-boundary, so the reality gate is
# skipped (no integration boundary to evidence). Must NOT be blocked.
ok_repo="$(make_feature_repo okfeat)"
printf 'okfeat' >"$ok_repo/docs/context/.active-feature"
printf 'def g():\n    return 2\n' >"$ok_repo/src/feature/logic.py"
git -C "$ok_repo" add src/feature/logic.py
git -C "$ok_repo" commit -q -m "in-scope pure-logic work"
run_hook "$ok_repo" '{}'
assert_eq "pure-logic in-scope: exit 0" "0" "$HOOK_RC"
assert_eq "pure-logic in-scope: empty stdout (not blocked)" "" "$HOOK_OUT"

# --- 6. bash -n valid; hook does NOT contain the old guard filename. ----------
TESTS_RUN=$((TESTS_RUN + 1))
if bash -n "$HOOK" 2>/dev/null; then
  _pass "hook has valid bash syntax"
else
  _fail "hook failed bash -n"
fi

TESTS_RUN=$((TESTS_RUN + 1))
if grep -Fq 'pretool-plumbline-guard.sh' "$HOOK"; then
  _fail "hook must NOT reference pretool-plumbline-guard.sh"
else
  _pass "hook does not reference pretool-plumbline-guard.sh"
fi

# --- 7. agileteam.md wires the C1 prod activation path (marker write). --------
# The orchestrator must write the confirmed slug to docs/context/.active-feature
# at development start, so the hook actually fires in production.
has_marker_write() {
  TESTS_RUN=$((TESTS_RUN + 1))
  if grep -Fq -- 'docs/context/.active-feature' "$CMD"; then
    _pass "agileteam.md writes docs/context/.active-feature (C1 prod path)"
  else
    _fail "agileteam.md missing docs/context/.active-feature marker-write wiring"
  fi
}
has_marker_write

finish "test_pril_enforce_hook"
