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

# Run the hook against a given project dir with a given stdin payload. Remaining
# arguments are optional NAME=value environment entries for the hook process.
# Captures stdout, stderr, and exit code separately. Uses CLAUDE_PROJECT_DIR
# (the hook's project anchor) and a clean PATH-independent invocation.
# Sets globals: HOOK_OUT HOOK_ERR HOOK_RC.
run_hook_with_env() {
  local project="$1" stdin_payload="$2"
  shift 2
  local outf errf
  outf="$(mktemp -p "$WORK")"
  errf="$(mktemp -p "$WORK")"
  env "$@" CLAUDE_PROJECT_DIR="$project" bash "$HOOK" \
    >"$outf" 2>"$errf" <<<"$stdin_payload"
  HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"
  HOOK_ERR="$(cat "$errf")"
  rm -f "$outf" "$errf"
}

run_hook() {
  run_hook_with_env "$1" "$2"
}

# Build a self-contained git repo that vendors the PRIL CLIs + libs so the hook
# can shell out to them with --repo pointed at this repo. Echoes the repo path.
# Arg1: feature slug. Arg2: baseline branch (default: main). Arg3: set to
# "no-vendor" for a real foreign product repository with no Plumbline payload.
# Sets up a confirmed canvas + full context + traceability.
make_feature_repo() {
  local feat="$1" baseline_branch="${2:-main}" vendor="${3:-vendor}" repo
  repo="$(mktemp -d -p "$WORK")"

  if [ "$vendor" != "no-vendor" ]; then
    # Legacy/repo-local layout remains supported, but is no longer required.
    mkdir -p "$repo/config/claude/bin" "$repo/config/claude/lib"
    cp "$BIN_SRC"/plumbline-context-check "$BIN_SRC"/plumbline-reality-check \
       "$BIN_SRC"/plumbline-scope-check "$repo/config/claude/bin/"
    cp "$LIB_SRC"/plumbline_context.py "$LIB_SRC"/plumbline_reality.py \
       "$LIB_SRC"/plumbline_scope.py "$LIB_SRC"/plumbline_python.sh \
       "$repo/config/claude/lib/"
    chmod +x "$repo/config/claude/bin/"*
  fi

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

  # Initialize a real git repo with the requested baseline branch.
  git -C "$repo" init -q
  git -C "$repo" config user.email pril-test@example.com
  git -C "$repo" config user.name "PRIL Test"
  git -C "$repo" checkout -q -b "$baseline_branch"
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

# --- 12. PLUM-7: CLIs resolve outside the governed product repository. --------
# The operator-facing order and stack override must remain documented.
setup_text="$(cat "$REPO_DIR/SETUP.md")"
assert_contains "PLUM-7 docs: explicit CLI directory is documented" \
  "$setup_text" 'PLUMBLINE_BIN_DIR'
assert_contains "PLUM-7 docs: per-user CLI fallback is documented" \
  "$setup_text" "\$HOME/.claude/bin"
assert_contains "PLUM-9 docs: stack baseline override is documented" \
  "$setup_text" 'PLUMBLINE_STACK_BASE'

# This is the real deployment topology: the product repo has no vendored
# config/claude/bin payload, while the Plumbline installation is elsewhere.
foreign_repo="$(make_feature_repo foreignfeat master no-vendor)"
printf 'foreignfeat' >"$foreign_repo/docs/context/.active-feature"
printf 'def external():\n    return 1\n' >"$foreign_repo/src/feature/external.py"
git -C "$foreign_repo" add src/feature/external.py
git -C "$foreign_repo" commit -q -m "foreign product change"
run_hook_with_env "$foreign_repo" '{}' "PLUMBLINE_BIN_DIR=$BIN_SRC"
assert_eq "PLUM-7 foreign repo: exit 0" "0" "$HOOK_RC"
assert_eq "PLUM-7 foreign repo: real external CLIs pass" "" "$HOOK_OUT"
assert_contains "PLUM-7 audit: scope CLI path is visible" "$HOOK_ERR" \
  "plumbline-scope-check"
assert_contains "PLUM-7 audit: explicit install source is visible" "$HOOK_ERR" \
  "source=PLUMBLINE_BIN_DIR"

# Every CLI is resolved independently in the documented order. Deliberately
# distribute the three executables across explicit-dir, repo-local, and PATH;
# resolving one shared bin directory would fail this case.
split_repo="$(make_feature_repo splitfeat main no-vendor)"
printf 'splitfeat' >"$split_repo/docs/context/.active-feature"
split_explicit="$WORK/split-explicit"
split_path="$WORK/split-path"
mkdir -p "$split_explicit" "$split_path" "$split_repo/config/claude/bin"
printf '#!/usr/bin/env bash\nexit 0\n' >"$split_explicit/plumbline-scope-check"
printf '#!/usr/bin/env bash\nexit 0\n' >"$split_repo/config/claude/bin/plumbline-context-check"
printf '#!/usr/bin/env bash\nexit 0\n' >"$split_path/plumbline-reality-check"
chmod +x "$split_explicit/plumbline-scope-check" \
  "$split_repo/config/claude/bin/plumbline-context-check" \
  "$split_path/plumbline-reality-check"
run_hook_with_env "$split_repo" '{}' \
  "PLUMBLINE_BIN_DIR=$split_explicit" "PATH=$split_path:$PATH"
assert_eq "PLUM-7 per-CLI resolution: distributed executables pass" "" "$HOOK_OUT"
assert_contains "PLUM-7 order: scope uses explicit dir" "$HOOK_ERR" \
  "plumbline-scope-check source=PLUMBLINE_BIN_DIR"
assert_contains "PLUM-7 order: context uses repo-local" "$HOOK_ERR" \
  "plumbline-context-check source=project-local"
assert_contains "PLUM-7 order: reality uses PATH" "$HOOK_ERR" \
  "plumbline-reality-check source=PATH"

# Final fallback: the conventional per-user install. The directory contains a
# space so quoting/canonicalization is exercised on both Linux and macOS CI.
home_repo="$(make_feature_repo homefeat main no-vendor)"
printf 'homefeat' >"$home_repo/docs/context/.active-feature"
fake_home="$WORK/home with space"
mkdir -p "$fake_home/.claude/bin"
for cli in plumbline-scope-check plumbline-context-check plumbline-reality-check; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$fake_home/.claude/bin/$cli"
  chmod +x "$fake_home/.claude/bin/$cli"
done
run_hook_with_env "$home_repo" '{}' "HOME=$fake_home"
assert_eq "PLUM-7 HOME fallback: quoted portable path passes" "" "$HOOK_OUT"
assert_contains "PLUM-7 HOME fallback: source is audited" "$HOOK_ERR" \
  "source=HOME/.claude/bin"
assert_contains "PLUM-7 HOME fallback: path with spaces survives" "$HOOK_ERR" \
  "$fake_home/.claude/bin/plumbline-scope-check"

# A partially installed runtime must block with a stable classification and the
# exact missing executable, never degrade to a no-op.
missing_repo="$(make_feature_repo missingcli main no-vendor)"
printf 'missingcli' >"$missing_repo/docs/context/.active-feature"
missing_bin="$WORK/missing-bin"
missing_home="$WORK/missing-home"
mkdir -p "$missing_bin" "$missing_home"
for cli in plumbline-scope-check plumbline-context-check; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$missing_bin/$cli"
  chmod +x "$missing_bin/$cli"
done
run_hook_with_env "$missing_repo" '{}' \
  "PLUMBLINE_BIN_DIR=$missing_bin" "HOME=$missing_home"
assert_eq "PLUM-7 missing CLI: hook still exits 0" "0" "$HOOK_RC"
assert_contains "PLUM-7 missing CLI: blocks with stable class" "$HOOK_OUT" \
  "PRIL_CLI_UNAVAILABLE"
assert_contains "PLUM-7 missing CLI: names exact executable" "$HOOK_OUT" \
  "plumbline-reality-check"

# --- 13. PLUM-9: resolve a real, auditable Git baseline; never HEAD fallback. --
# Local master is a supported default fallback (foreign_repo above also proves
# the full real-CLI path on master).
run_hook_with_env "$foreign_repo" '{}' "PLUMBLINE_BIN_DIR=$BIN_SRC"
assert_eq "PLUM-9 local master: in-scope committed work passes" "" "$HOOK_OUT"
assert_contains "PLUM-9 local master: base source audited" "$HOOK_ERR" \
  "source=local-master"

# Remote default may be neither main nor master.
remote_default_repo="$(make_feature_repo remotefeat trunk)"
printf 'remotefeat' >"$remote_default_repo/docs/context/.active-feature"
trunk_sha="$(git -C "$remote_default_repo" rev-parse trunk)"
git -C "$remote_default_repo" update-ref refs/remotes/origin/trunk "$trunk_sha"
git -C "$remote_default_repo" symbolic-ref refs/remotes/origin/HEAD \
  refs/remotes/origin/trunk
git -C "$remote_default_repo" branch -D trunk >/dev/null
printf 'def remote_default():\n    return 1\n' \
  >"$remote_default_repo/src/feature/remote.py"
git -C "$remote_default_repo" add src/feature/remote.py
git -C "$remote_default_repo" commit -q -m "remote-default feature"
run_hook "$remote_default_repo" '{}'
assert_eq "PLUM-9 remote default: custom default branch passes" "" "$HOOK_OUT"
assert_contains "PLUM-9 remote default: source audited" "$HOOK_ERR" \
  "source=remote-default"
assert_contains "PLUM-9 remote default: ref audited" "$HOOK_ERR" \
  "ref=origin/trunk"

# Explicit origin/main and origin/master fallbacks are both covered without a
# network call. Remove the local baseline so only the remote-tracking ref exists.
for default_name in main master; do
  origin_repo="$(make_feature_repo "origin-$default_name" "$default_name")"
  printf 'origin-%s' "$default_name" \
    >"$origin_repo/docs/context/.active-feature"
  default_sha="$(git -C "$origin_repo" rev-parse "$default_name")"
  git -C "$origin_repo" update-ref \
    "refs/remotes/origin/$default_name" "$default_sha"
  git -C "$origin_repo" branch -D "$default_name" >/dev/null
  printf 'def remote_ref():\n    return 1\n' \
    >"$origin_repo/src/feature/remote-ref.py"
  git -C "$origin_repo" add src/feature/remote-ref.py
  git -C "$origin_repo" commit -q -m "origin fallback feature"
  run_hook "$origin_repo" '{}'
  assert_eq "PLUM-9 origin/$default_name: committed work passes" "" "$HOOK_OUT"
  assert_contains "PLUM-9 origin/$default_name: source audited" "$HOOK_ERR" \
    "source=origin-$default_name"
done

# Stacked branch: an explicit parent pin excludes the parent's deliberately
# out-of-scope edit and checks only the child increment. Without the pin the
# conservative default-branch surface includes the whole stack and blocks.
stack_repo="$(make_feature_repo stackfeat)"
git -C "$stack_repo" branch -m stack/parent
mkdir -p "$stack_repo/src/shared"
printf 'parent\n' >"$stack_repo/src/shared/parent.py"
git -C "$stack_repo" add src/shared/parent.py
git -C "$stack_repo" commit -q -m "stack parent"
git -C "$stack_repo" checkout -q -b feat/stackfeat
printf 'child\n' >"$stack_repo/src/feature/child.py"
git -C "$stack_repo" add src/feature/child.py
git -C "$stack_repo" commit -q -m "stack child"
printf 'stackfeat' >"$stack_repo/docs/context/.active-feature"
run_hook_with_env "$stack_repo" '{}' "PLUMBLINE_STACK_BASE=stack/parent"
assert_eq "PLUM-9 stacked with pin: child increment passes" "" "$HOOK_OUT"
assert_contains "PLUM-9 stacked with pin: source audited" "$HOOK_ERR" \
  "source=PLUMBLINE_STACK_BASE"
run_hook "$stack_repo" '{}'
assert_contains "PLUM-9 stacked without pin: whole stack blocks safely" \
  "$HOOK_OUT" "scope"

# An out-of-scope child edit remains visible even with a valid stack pin.
printf 'own violation\n' >"$stack_repo/src/shared/child.py"
git -C "$stack_repo" add src/shared/child.py
run_hook_with_env "$stack_repo" '{}' "PLUMBLINE_STACK_BASE=stack/parent"
assert_contains "PLUM-9 stack pin: own uncommitted scope violation blocks" \
  "$HOOK_OUT" "scope"

# A committed foreign file is part of the surface as well.
committed_bad_repo="$(make_feature_repo committedbad)"
printf 'committedbad' >"$committed_bad_repo/docs/context/.active-feature"
mkdir -p "$committed_bad_repo/src/billing"
printf 'committed violation\n' >"$committed_bad_repo/src/billing/committed.py"
git -C "$committed_bad_repo" add src/billing/committed.py
git -C "$committed_bad_repo" commit -q -m "committed scope violation"
run_hook "$committed_bad_repo" '{}'
assert_contains "PLUM-9 committed foreign file blocks" "$HOOK_OUT" "scope"

# No known base: classify and block. The old implementation silently replaced
# this with HEAD and evaluated the vacuous HEAD...HEAD range.
unknown_base_repo="$(make_feature_repo unknownbase trunk)"
printf 'unknownbase' >"$unknown_base_repo/docs/context/.active-feature"
run_hook "$unknown_base_repo" '{}'
assert_contains "PLUM-9 unknown base: blocks with stable class" "$HOOK_OUT" \
  "PRIL_GIT_BASE_UNRESOLVED"

# An explicit but unknown pin is authoritative: do not silently fall back.
run_hook_with_env "$committed_bad_repo" '{}' \
  "PLUMBLINE_STACK_BASE=does-not-exist"
assert_contains "PLUM-9 unknown explicit pin: blocks with stable class" \
  "$HOOK_OUT" "PRIL_GIT_BASE_UNRESOLVED"

# A ref can resolve to a valid commit and still have no common ancestor.
unrelated_tree="$(git -C "$committed_bad_repo" mktree </dev/null)"
unrelated_commit="$(printf 'unrelated\n' | \
  git -C "$committed_bad_repo" commit-tree "$unrelated_tree")"
git -C "$committed_bad_repo" update-ref refs/heads/unrelated "$unrelated_commit"
run_hook_with_env "$committed_bad_repo" '{}' \
  "PLUMBLINE_STACK_BASE=unrelated"
assert_contains "PLUM-9 unrelated explicit pin: blocks with stable class" \
  "$HOOK_OUT" "PRIL_GIT_BASE_UNRELATED"

# --- 14. PLUM-8: interpreter contract + distinct runtime error classes. -------
# An explicit interpreter is authoritative. A missing override must never be
# ignored in favor of a host python3, because that recreates the pilot's
# false-green/false-diagnosis split between environments.
missing_python="$WORK/does-not-exist/python"
override_out="$WORK/plum8-override.out"
override_err="$WORK/plum8-override.err"
PLUMBLINE_PYTHON="$missing_python" \
  "$BIN_SRC/plumbline-scope-check" --help \
  >"$override_out" 2>"$override_err"
override_rc=$?
assert_eq "PLUM-8 missing explicit interpreter: stable unavailable exit" \
  "120" "$override_rc"
assert_contains "PLUM-8 missing explicit interpreter: machine code" \
  "$(cat "$override_err")" "code=PRIL_TOOL_UNAVAILABLE"
assert_contains "PLUM-8 missing explicit interpreter: error class" \
  "$(cat "$override_err")" "error_class=tool_unavailable"
assert_contains "PLUM-8 missing explicit interpreter: affected CLI" \
  "$(cat "$override_err")" "cli=plumbline-scope-check"
assert_contains "PLUM-8 missing explicit interpreter: interpreter source" \
  "$(cat "$override_err")" "interpreter=PLUMBLINE_PYTHON"

# An executable that is found but cannot run a trivial Python probe is a broken
# tool, not a policy violation and not an unavailable executable.
broken_python="$WORK/broken-python"
printf '#!/usr/bin/env bash\nexit 9\n' >"$broken_python"
chmod +x "$broken_python"
broken_err="$WORK/plum8-broken.err"
PLUMBLINE_PYTHON="$broken_python" \
  "$BIN_SRC/plumbline-context-check" --help \
  >/dev/null 2>"$broken_err"
broken_rc=$?
assert_eq "PLUM-8 broken interpreter: stable broken-tool exit" "121" "$broken_rc"
assert_contains "PLUM-8 broken interpreter: distinct machine code" \
  "$(cat "$broken_err")" "code=PRIL_TOOL_BROKEN"
assert_contains "PLUM-8 broken interpreter: distinct error class" \
  "$(cat "$broken_err")" "error_class=tool_broken"

# A launcher can fail with the SAME numeric exit used by a policy checker.
# Prove the wrapper requires evidence that Python actually started the checker
# before accepting a policy exit; numeric coincidence alone is not governance
# evidence.
policy_like_broken="$WORK/policy-like-broken-python"
cat >"$policy_like_broken" <<'EOF'
#!/usr/bin/env bash
case "${2:-}" in
  *version_info*) exec "$PLUM8_REAL_PYTHON" "$@" ;;
  *) exit 3 ;;
esac
EOF
chmod +x "$policy_like_broken"
policy_like_err="$WORK/plum8-policy-like-broken.err"
PLUM8_REAL_PYTHON="$(command -v python3)" \
  PLUMBLINE_PYTHON="$policy_like_broken" \
  "$BIN_SRC/plumbline-scope-check" --help \
  >/dev/null 2>"$policy_like_err"
policy_like_rc=$?
assert_eq "PLUM-8 policy-like launcher failure: classified as tool broken" \
  "121" "$policy_like_rc"
assert_contains "PLUM-8 policy-like launcher failure: not numeric-policy confusion" \
  "$(cat "$policy_like_err")" "error_class=tool_broken"
assert_not_contains "PLUM-8 policy-like launcher failure: never policy violation" \
  "$(cat "$policy_like_err")" "error_class=policy_violation"

# With no explicit override, uv wins before python3 and receives a project- and
# config-independent `run --no-project --no-config python3` prefix. A real
# uv.toml plus the mutation tripwire make the test fail if the wrapper lets uv
# discover configuration or update the governed repository before the hook has
# classified the working tree.
real_python="$(python3 -c 'import os, sys; print(os.path.realpath(sys.executable))')"
uv_bin="$WORK/uv-bin"
mkdir -p "$uv_bin"
cat >"$uv_bin/uv" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >"$PLUM8_UV_LOG"
case " $* " in
  *" --no-project "*) ;;
  *)
    if [ -f uv.toml ]; then
      mkdir -p .project-cache
      printf 'configuration mutation attempted\n' >"$PLUM8_UV_PROJECT_MUTATION"
    fi
    exit 89
    ;;
esac
case " $* " in
  *" --no-config "*) ;;
  *)
    if [ -f uv.toml ]; then
      mkdir -p .project-cache
      printf 'configuration mutation attempted\n' >"$PLUM8_UV_PROJECT_MUTATION"
    fi
    exit 89
    ;;
esac
[ "${1:-}" = "run" ] && [ "${2:-}" = "--no-project" ] && \
  [ "${3:-}" = "--no-config" ] && [ "${4:-}" = "python3" ] || exit 88
shift 4
exec "$PLUM8_REAL_PYTHON" "$@"
EOF
chmod +x "$uv_bin/uv"
uv_log="$WORK/plum8-uv.log"
uv_err="$WORK/plum8-uv.err"
uv_config_repo="$WORK/plum8-uv-config-repo"
uv_project_mutation="$uv_config_repo/project-mutation"
mkdir -p "$uv_config_repo"
printf 'cache-dir = ".project-cache"\n' >"$uv_config_repo/uv.toml"
(
  cd "$uv_config_repo"
  env -u PLUMBLINE_PYTHON \
    PATH="$uv_bin:$PATH" \
    PLUM8_UV_LOG="$uv_log" \
    PLUM8_UV_PROJECT_MUTATION="$uv_project_mutation" \
    PLUM8_REAL_PYTHON="$real_python" \
    PLUMBLINE_RUNTIME_DIAGNOSTICS=1 \
    "$BIN_SRC/plumbline-reality-check" --help \
    >/dev/null 2>"$uv_err"
)
uv_rc=$?
assert_eq "PLUM-8 uv fallback: wrapper succeeds through uv" "0" "$uv_rc"
assert_contains "PLUM-8 uv fallback: exact command prefix" \
  "$(cat "$uv_log")" "run --no-project --no-config python3"
assert_contains "PLUM-8 uv fallback: interpreter is audited" \
  "$(cat "$uv_err")" "interpreter=uv-run-python3"
assert "PLUM-8 uv fallback: governed project is not mutated" \
  "test ! -e '$uv_project_mutation' && test ! -d '$uv_config_repo/.project-cache'"

# If uv is absent, python3 is the final fallback. Isolate PATH to prove the
# branch rather than accidentally observing the developer machine's uv.
python_bin="$WORK/python-bin"
mkdir -p "$python_bin"
for tool in bash dirname mktemp rm rmdir; do
  tool_path="$(command -v "$tool")"
  ln -s "$tool_path" "$python_bin/$tool"
done
ln -s "$real_python" "$python_bin/python3"
python_err="$WORK/plum8-python.err"
env -u PLUMBLINE_PYTHON \
  PATH="$python_bin" \
  PLUMBLINE_RUNTIME_DIAGNOSTICS=1 \
  "$BIN_SRC/plumbline-redact" --help \
  >/dev/null 2>"$python_err"
python_rc=$?
assert_eq "PLUM-8 python3 fallback: wrapper succeeds" "0" "$python_rc"
assert_contains "PLUM-8 python3 fallback: interpreter is audited" \
  "$(cat "$python_err")" "interpreter=python3"

# The stop hook must transport the runtime classification all the way to its
# decision JSON and name CLI + interpreter + class. All three CLIs intentionally
# see the same unusable explicit interpreter; any one is sufficient to block.
unavailable_repo="$(make_feature_repo unavailablefeat)"
printf 'unavailablefeat' >"$unavailable_repo/docs/context/.active-feature"
run_hook_with_env "$unavailable_repo" '{}' \
  "PLUMBLINE_PYTHON=$missing_python"
assert_eq "PLUM-8 unavailable interpreter: hook still exits 0" "0" "$HOOK_RC"
assert_contains "PLUM-8 unavailable interpreter: decision machine code" \
  "$HOOK_OUT" "PRIL_TOOL_UNAVAILABLE"
assert_contains "PLUM-8 unavailable interpreter: decision error class" \
  "$HOOK_OUT" "error_class=tool_unavailable"
assert_contains "PLUM-8 unavailable interpreter: decision names CLI" \
  "$HOOK_OUT" "cli=plumbline-scope-check"
assert_contains "PLUM-8 unavailable interpreter: decision names interpreter" \
  "$HOOK_OUT" "interpreter=PLUMBLINE_PYTHON"
assert_not_contains "PLUM-8 unavailable interpreter: not mislabeled as policy" \
  "$HOOK_OUT" "error_class=policy_violation"

# The second runtime-failure branch must also survive the hook boundary. This
# separately falsifies a regression that collapses every tool failure back to
# `tool_unavailable`.
broken_repo="$(make_feature_repo brokenfeat)"
printf 'brokenfeat' >"$broken_repo/docs/context/.active-feature"
run_hook_with_env "$broken_repo" '{}' \
  "PLUMBLINE_PYTHON=$broken_python"
assert_contains "PLUM-8 broken interpreter hook: distinct machine code" \
  "$HOOK_OUT" "PRIL_TOOL_BROKEN"
assert_contains "PLUM-8 broken interpreter hook: distinct error class" \
  "$HOOK_OUT" "error_class=tool_broken"
assert_contains "PLUM-8 broken interpreter hook: names CLI" \
  "$HOOK_OUT" "cli=plumbline-scope-check"
assert_contains "PLUM-8 broken interpreter hook: names interpreter" \
  "$HOOK_OUT" "interpreter=PLUMBLINE_PYTHON"
assert_not_contains "PLUM-8 broken interpreter hook: not policy violation" \
  "$HOOK_OUT" "error_class=policy_violation"

# An older or externally selected CLI can fail without emitting PRIL_RUNTIME.
# Unknown exits are still fail-closed, but they are tool failures rather than
# fabricated governance evidence. Only known checker exits may claim policy.
unknown_exit_repo="$(make_feature_repo unknownexit main no-vendor)"
printf 'unknownexit' >"$unknown_exit_repo/docs/context/.active-feature"
unknown_exit_bin="$WORK/unknown-exit-bin"
mkdir -p "$unknown_exit_bin"
printf '#!/usr/bin/env bash\nexit 1\n' \
  >"$unknown_exit_bin/plumbline-scope-check"
for cli in plumbline-context-check plumbline-reality-check; do
  printf '#!/usr/bin/env bash\nexit 0\n' >"$unknown_exit_bin/$cli"
done
chmod +x "$unknown_exit_bin/"*
run_hook_with_env "$unknown_exit_repo" '{}' \
  "PLUMBLINE_BIN_DIR=$unknown_exit_bin"
assert_contains "PLUM-8 unknown external exit: classified as tool broken" \
  "$HOOK_OUT" "PRIL_TOOL_BROKEN"
assert_contains "PLUM-8 unknown external exit: distinct error class" \
  "$HOOK_OUT" "error_class=tool_broken"
assert_contains "PLUM-8 unknown external exit: names failing CLI" \
  "$HOOK_OUT" "cli=plumbline-scope-check"
assert_not_contains "PLUM-8 unknown external exit: never policy violation" \
  "$HOOK_OUT" "PRIL_POLICY_VIOLATION"

# A real out-of-scope change remains fail-closed, but is explicitly classified
# as a policy violation with a distinct machine code.
policy_repo="$(make_feature_repo policyfeat)"
printf 'policyfeat' >"$policy_repo/docs/context/.active-feature"
mkdir -p "$policy_repo/src/outside"
printf 'violation\n' >"$policy_repo/src/outside/file.py"
run_hook_with_env "$policy_repo" '{}' \
  "PLUMBLINE_PYTHON=$real_python"
assert_contains "PLUM-8 real scope violation: distinct machine code" \
  "$HOOK_OUT" "PRIL_POLICY_VIOLATION"
assert_contains "PLUM-8 real scope violation: distinct error class" \
  "$HOOK_OUT" "error_class=policy_violation"
assert_contains "PLUM-8 real scope violation: names scope CLI" \
  "$HOOK_OUT" "cli=plumbline-scope-check"
assert_contains "PLUM-8 real scope violation: names interpreter" \
  "$HOOK_OUT" "interpreter=PLUMBLINE_PYTHON"
assert_not_contains "PLUM-8 real scope violation: not tool unavailable" \
  "$HOOK_OUT" "PRIL_TOOL_UNAVAILABLE"

# The operator-facing resolution contract is part of the tested interface.
setup_text="$(cat "$REPO_DIR/SETUP.md")"
assert_contains "PLUM-8 docs: explicit interpreter is documented" \
  "$setup_text" "PLUMBLINE_PYTHON"
assert_contains "PLUM-8 docs: uv interpreter is documented" \
  "$setup_text" "uv run --no-project --no-config python3"
assert_contains "PLUM-8 docs: python3 fallback is documented" \
  "$setup_text" "python3"

finish "test_pril_enforce_hook"
