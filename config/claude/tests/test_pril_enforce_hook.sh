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
  rm -f "$outf" "$errf"
}

# Install just enough Plumbline CLI surface under a fake Claude home to exercise
# the production install path: target repos do NOT vendor config/claude/bin, but
# install.sh does place these commands under $CLAUDE_HOME/bin.
make_installed_cli_home() {
  local home
  home="$(mktemp -d -p "$WORK")"
  mkdir -p "$home/bin" "$home/lib"
  cp "$BIN_SRC"/plumbline-context-check "$BIN_SRC"/plumbline-reality-check \
     "$BIN_SRC"/plumbline-scope-check "$home/bin/"
  cp "$LIB_SRC"/plumbline_context.py "$LIB_SRC"/plumbline_reality.py \
     "$LIB_SRC"/plumbline_scope.py "$home/lib/"
  chmod +x "$home/bin/"*
  printf '%s' "$home"
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

# --- 4b. Installed hook path: CLIs resolve from $CLAUDE_HOME/bin. --------------
# Production installs register the hook from the Claude installation while
# CLAUDE_PROJECT_DIR remains the target repo. A normal target repo with an active
# marker/canvas should not need to vendor config/claude/bin for enforcement to run.
installed_repo="$(make_feature_repo installedfeat)"
rm -rf "$installed_repo/config/claude/bin" "$installed_repo/config/claude/lib"
printf 'installedfeat' >"$installed_repo/docs/context/.active-feature"
mkdir -p "$installed_repo/src/billing"
printf 'def installed_escape():\n    return 1\n' >"$installed_repo/src/billing/escape.py"
git -C "$installed_repo" add src/billing/escape.py
installed_home="$(make_installed_cli_home)"
outf="$(mktemp -p "$WORK")"
errf="$(mktemp -p "$WORK")"
CLAUDE_HOME="$installed_home" CLAUDE_PROJECT_DIR="$installed_repo" \
  bash "$HOOK" >"$outf" 2>"$errf" <<<'{}'
installed_rc=$?
installed_out="$(cat "$outf")"
rm -f "$outf" "$errf"
assert_eq "installed CLI path: exit 0 (never non-zero)" "0" "$installed_rc"
TESTS_RUN=$((TESTS_RUN + 1))
installed_decision="$(printf '%s' "$installed_out" | jq -r '.decision' 2>/dev/null)"
installed_reason="$(printf '%s' "$installed_out" | jq -r '.reason' 2>/dev/null)"
if [ "$installed_decision" = "block" ] && printf '%s' "$installed_reason" | grep -Fq 'scope'; then
  _pass "installed CLI path: target repo without vendored CLIs still enforces via CLAUDE_HOME/bin"
else
  _fail "installed CLI path: expected scope block via CLAUDE_HOME/bin (out: $installed_out)"
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

# --- 8. install.sh registers the enforce hook (closes Critical C-1). -----------
# C-1: a fail-closed hook that is never wired into settings.json is inert. After
# install into an isolated CLAUDE_HOME, plumbline-enforce.sh must be registered in
# Stop EXACTLY ONCE, the existing stop-learning-loop.sh must STILL be registered
# exactly once, and the deliberately-inert pretool guard must STILL be absent.
INSTALL="$REPO_DIR/config/claude/install.sh"
assert_file "install.sh exists" "$INSTALL"

CH="$(mktemp -d -p "$WORK")"
# --copy so the agent repo path the hook prefers resolves inside CH (no symlink
# back into the live repo); --no-skills/--no-bin keep the install fast.
CLAUDE_HOME="$CH" HOME="$CH" bash "$INSTALL" --copy --no-skills --no-bin \
  >/dev/null 2>&1
SETTINGS_OUT="$CH/settings.json"

assert_file "install produced settings.json" "$SETTINGS_OUT"

count_cmd() { # count_cmd <regex> -> count of Stop-hook commands matching it
  jq "[.hooks.Stop[]?.hooks[]?.command? // \"\" | select(test(\"$1\"))] | length" \
     "$SETTINGS_OUT" 2>/dev/null
}

assert_eq "enforce hook registered in Stop exactly once" "1" \
  "$(count_cmd 'plumbline-enforce\\.sh')"
assert_eq "stop-learning-loop hook still registered exactly once" "1" \
  "$(count_cmd 'stop-learning-loop\\.sh')"
assert_eq "pretool-plumbline-guard.sh is NOT registered" "0" \
  "$(count_cmd 'pretool-plumbline-guard\\.sh')"

# Idempotency: a second install must NOT double-register the enforce hook.
CLAUDE_HOME="$CH" HOME="$CH" bash "$INSTALL" --copy --no-skills --no-bin \
  >/dev/null 2>&1
assert_eq "second install: enforce hook still registered exactly once" "1" \
  "$(count_cmd 'plumbline-enforce\\.sh')"

# --- 9. H-1 marker laundering: present-but-EMPTY marker must BLOCK. ------------
# An armed-then-blanked marker is suspicious — silently disabling enforcement by
# emptying the marker must not be possible. A truly ABSENT marker stays a no-op.
empty_repo="$(make_feature_repo emptyfeat)"
: > "$empty_repo/docs/context/.active-feature"          # present but empty
run_hook "$empty_repo" '{}'
assert_eq "empty marker: exit 0 (never non-zero)" "0" "$HOOK_RC"
TESTS_RUN=$((TESTS_RUN + 1))
edecision="$(printf '%s' "$HOOK_OUT" | jq -r '.decision' 2>/dev/null)"
if [ "$edecision" = "block" ]; then
  _pass "empty marker: blocks (enforcement cannot be silently disabled)"
else
  _fail "empty marker: expected .decision==block (out: $HOOK_OUT)"
fi
TESTS_RUN=$((TESTS_RUN + 1))
ereason="$(printf '%s' "$HOOK_OUT" | jq -r '.reason' 2>/dev/null)"
if printf '%s' "$ereason" | grep -Fq 'empty'; then
  _pass "empty marker: reason explains the empty marker is rejected"
else
  _fail "empty marker: reason should mention 'empty' (reason: $ereason)"
fi

# Whitespace-only marker is equally a blanked marker -> block.
ws_repo="$(make_feature_repo wsfeat)"
printf '   \n\t\n' > "$ws_repo/docs/context/.active-feature"
run_hook "$ws_repo" '{}'
TESTS_RUN=$((TESTS_RUN + 1))
wdecision="$(printf '%s' "$HOOK_OUT" | jq -r '.decision' 2>/dev/null)"
if [ "$wdecision" = "block" ]; then
  _pass "whitespace-only marker: blocks"
else
  _fail "whitespace-only marker: expected .decision==block (out: $HOOK_OUT)"
fi

# Absent marker stays a clean no-op (the normal-session contract is preserved).
absent_repo="$(make_feature_repo absentfeat)"
rm -f "$absent_repo/docs/context/.active-feature"      # ensure absent
run_hook "$absent_repo" '{}'
assert_eq "absent marker: exit 0" "0" "$HOOK_RC"
assert_eq "absent marker: empty stdout (no-op)" "" "$HOOK_OUT"

# --- 10. M-1 jq-less loop guard: stop_hook_active honored without jq. ----------
# If jq is unavailable the hook must still short-circuit on stop_hook_active via a
# grep fallback — otherwise the loop guard silently fails and the hook re-fires.
# We build a sandbox PATH that contains the tools the hook needs (cat, tr, grep,
# git, sort, mktemp, find, rm) but NOT jq, so `command -v jq` genuinely fails and
# the grep branch is exercised. (A non-executable jq stub would NOT work: command
# -v finds the next real jq further down PATH.)
nojq_repo="$(make_feature_repo nojqfeat)"
printf 'nojqfeat' > "$nojq_repo/docs/context/.active-feature"
NOJQ_BIN="$(mktemp -d -p "$WORK")"
for t in cat tr grep git sort mktemp find rm sed bash; do
  src="$(command -v "$t" 2>/dev/null)" && [ -n "$src" ] && ln -sf "$src" "$NOJQ_BIN/$t"
done
TESTS_RUN=$((TESTS_RUN + 1))
# Guard the test itself: the sandbox PATH must actually hide jq.
if PATH="$NOJQ_BIN" command -v jq >/dev/null 2>&1; then
  _fail "M-1: sandbox PATH still exposes jq (test setup invalid)"
else
  nojq_outf="$(mktemp -p "$WORK")"
  PATH="$NOJQ_BIN" CLAUDE_PROJECT_DIR="$nojq_repo" \
    bash "$HOOK" >"$nojq_outf" 2>/dev/null <<<'{"stop_hook_active":true}'
  nojq_rc=$?
  nojq_out="$(cat "$nojq_outf")"; rm -f "$nojq_outf"
  if [ "$nojq_rc" -eq 0 ] && [ -z "$nojq_out" ]; then
    _pass "M-1: stop_hook_active short-circuits via grep fallback when jq absent"
  else
    _fail "M-1: jq-less stop_hook_active (rc=$nojq_rc, out: $nojq_out)"
  fi
fi

# --- 11. Untracked scope-evasion: untracked out-of-scope file -> block. --------
# "Write malware, never git add" must be caught: the C2 surface unions
# `git ls-files --others --exclude-standard` so untracked, non-ignored files are
# checked against scope too.
untracked_repo="$(make_feature_repo untrackedfeat)"
printf 'untrackedfeat' > "$untracked_repo/docs/context/.active-feature"
# Untracked (never added) out-of-scope file under an active feature.
mkdir -p "$untracked_repo/src/billing"
printf 'def exfil():\n    return 1\n' > "$untracked_repo/src/billing/secret.py"
run_hook "$untracked_repo" '{}'
assert_eq "untracked out-of-scope: exit 0 (never non-zero)" "0" "$HOOK_RC"
TESTS_RUN=$((TESTS_RUN + 1))
udecision="$(printf '%s' "$HOOK_OUT" | jq -r '.decision' 2>/dev/null)"
ureason="$(printf '%s' "$HOOK_OUT" | jq -r '.reason' 2>/dev/null)"
if [ "$udecision" = "block" ] && printf '%s' "$ureason" | grep -Fq 'scope'; then
  _pass "untracked out-of-scope file blocks on scope (ls-files --others in C2)"
else
  _fail "untracked out-of-scope: expected block naming scope (out: $HOOK_OUT)"
fi
# A .gitignore'd untracked file must NOT count (exclude-standard honored): the
# ignore rule is committed on main (in baseline) so it is not itself an
# out-of-scope feature change, isolating the ls-files --exclude-standard behavior.
ignore_repo="$(make_feature_repo ignorefeat)"
printf 'ignorefeat' > "$ignore_repo/docs/context/.active-feature"
git -C "$ignore_repo" checkout -q main
printf 'src/billing/\n' > "$ignore_repo/.gitignore"
git -C "$ignore_repo" add .gitignore
git -C "$ignore_repo" commit -q -m "ignore billing"
git -C "$ignore_repo" checkout -q "feat/ignorefeat"
git -C "$ignore_repo" merge -q --no-edit main
mkdir -p "$ignore_repo/src/billing"
printf 'junk\n' > "$ignore_repo/src/billing/ignored.py"   # untracked AND ignored
run_hook "$ignore_repo" '{}'
assert_eq "ignored untracked file: exit 0 (no-op, not in C2 surface)" "0" "$HOOK_RC"
assert_eq "ignored untracked file: empty stdout (not blocked)" "" "$HOOK_OUT"

finish "test_pril_enforce_hook"
