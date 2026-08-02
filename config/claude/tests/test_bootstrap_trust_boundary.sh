#!/usr/bin/env bash
# PLUM-12 (TDD, RED): the governed repository must not supply ANY program the
# gate runs before independent authority is selected -- not the interpreter, and
# not the bootstrap tools that decide whether the gate engages at all.
#
# The bootstrap surface is wider than the interpreter. Before any authority
# exists, pretool-scope-gate.sh executes PATH-resolved `cat` (:10), `jq` (:17)
# or `sed`+`head` (:25-41), and `tr` (:59) -- and every one of them feeds a
# fail-OPEN branch:
#     :11  [ -n "$PAYLOAD" ]  || exit 0     <- repo-owned `cat` prints nothing
#     :53  case "$tool_name" in *) exit 0   <- repo-owned `jq` prints nothing
#     :60  [ -n "$feature" ]  || exit 0     <- repo-owned `tr` prints nothing
# The Stop hook is worse: `git` IS its ground truth, and `file_matches_head`
# (:207-212) -- the checker-integrity test itself -- is a pair of git calls.
#
# So a repository-owned parser sets the hook fail-open exactly like the Python
# shim does, and a pure interpreter resolver cannot close it.
#
# Measured defect (pretool-scope-gate.sh @ 42320c3):
#   line  77  python3 - "$command_text" ...      (Bash arm)
#   line 202  python3 - "$manifest"     ...      (manifest classifier)
#   line 253  python3 - "$candidate"    ...      (checker entry provenance)
#   line 270  python3 - "$candidate"    ...      (checker target provenance)
# Independent checker resolution does not start until line 243. So a
# repository-local `python3` earlier on PATH is executed BEFORE any independent
# authority exists -- and it is executed AGAIN, at 253/270, as the very thing
# that decides whether a checker is trustworthy. The classifier at 202 feeds
# `[ "$manifest_kind" = "legacy" ] && exit 0`, so a shim that prints one word
# turns the whole pre-write gate into a no-op.
#
# Target invariant:
#   Before independently installed authority is selected, no executable code
#   from the governed repository is started.
#
# These:      the pre-write gate refuses an action the plan does not declare.
# Gegenthese: the gate asks a repository-owned interpreter first, so the repo
#             decides the answer -- the gate is decorative under attack.
# Schaerfung: the shim records that it ran (PROJECT_OWNED_PYTHON_EXECUTED), the
#             decision is captured (PRETOOL_ALLOWED / PRETOOL_DENIED), and the
#             unplanned write is ACTUALLY PERFORMED when the gate does not deny,
#             so the falsifier is the target file's bytes -- not a string.
#
# RED expectation: N1/N2/N3/N4/N5 and S1 fail; the positive cases pass.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_bootstrap_trust_boundary (PLUM-12, RED)"

PRETOOL="$REPO_DIR/config/claude/hooks/pretool-scope-gate.sh"
STOP_HOOK="$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"
BIN_SRC="$REPO_DIR/config/claude/bin"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# An isolated CLAUDE_HOME. Without this the fixtures silently resolve the
# MACHINE's installed plumbline-scope-check ($HOME/.claude/bin), which on a
# developer box points at a different checkout: the assertions then measure that
# install instead of this tree. Every run below pins it, so the only authority
# reachable from outside the governed fixture is this worktree's own bin.
ISOLATED_CLAUDE_HOME="$WORK/claude-home"
mkdir -p "$ISOLATED_CLAUDE_HOME/bin"

# An interpreter that cannot execute a trivial program is not an interpreter.
# Some environments put a wrapper named `python3` on PATH that refuses to run
# (e.g. one that insists on `uv run python3`); it would silently break every
# fixture in this file and turn the results into noise that reads like passes.
python_ok() { # python_ok <candidate>
  [ -x "$1" ] || return 1
  # A wrapper that re-execs another resolver (e.g. `exec uv run python3 "$@"`) is
  # not a stable interpreter for a governance test: it re-resolves against the
  # caller's HOME, which these fixtures deliberately move.
  if head -c 400 "$1" 2>/dev/null | grep -q 'uv run'; then
    return 1
  fi
  po_out="$("$1" -c 'print("PYOK")' 2>/dev/null || true)"
  [ "$po_out" = "PYOK" ]
}

# A PATH with (a) every installed-Plumbline wrapper directory and (b) every
# non-executing python3 wrapper removed, so a fixture can never be satisfied by
# the machine's real install and never sabotaged by a refusing shim. The rest of
# the toolchain (git, jq) MUST survive; pinning to /usr/bin:/bin would turn the
# interpreter cases into unrelated tool errors.
CLEAN_PATH=""
REAL_PYTHON=""
_old_ifs="$IFS"
IFS=':'
for _p in $PATH; do
  [ -n "$_p" ] || continue
  [ -e "$_p/plumbline-scope-check" ] && continue
  [ -e "$_p/plumbline-plan-check" ] && continue
  if [ -e "$_p/python3" ] && ! python_ok "$_p/python3"; then
    continue
  fi
  if [ -z "$REAL_PYTHON" ] && [ -x "$_p/python3" ]; then
    REAL_PYTHON="$_p/python3"
  fi
  if [ -n "$CLEAN_PATH" ]; then
    CLEAN_PATH="$CLEAN_PATH:$_p"
  else
    CLEAN_PATH="$_p"
  fi
done
IFS="$_old_ifs"

if [ -z "$REAL_PYTHON" ]; then
  _fail "no working external python3 on PATH; the interpreter-provenance cases cannot run"
  finish
fi
printf '   external interpreter under test: %s\n' "$REAL_PYTHON"

# ---------------------------------------------------------------- fixtures ---
# An armed canonical repo carrying an implementation plan that declares exactly
# one product file. src/demo/unplanned.py is inside the manifest scope but is
# NOT declared by the plan: the drift the gate must refuse.
make_repo() {
  mr_repo="$1"
  mkdir -p "$mr_repo/docs/scope" "$mr_repo/docs/canvas" "$mr_repo/docs/plans" \
           "$mr_repo/docs/context" "$mr_repo/src/demo" "$mr_repo/config/claude/tests"
  printf 'demo\n' >"$mr_repo/docs/context/.active-feature"
  cat >"$mr_repo/docs/canvas/demo.canvas.md" <<'EOF'
# Product Canvas: demo

Status: user-confirmed

## Allowed change scope

Status: CONFIRMED

Scope manifest: `docs/scope/demo.scope.json`
EOF
  cat >"$mr_repo/docs/plans/2026-07-29-demo.md" <<'EOF'
# Demo implementation plan

- Create: `src/demo/app.py`
- Modify: `config/claude/tests/test_demo.sh`
- Modify: `docs/scope/demo.scope.json`
- Delete: `src/demo/old.py`
- Test: `bash config/claude/tests/test_demo.sh`
EOF
  printf 'print("app")\n' >"$mr_repo/src/demo/app.py"
  printf '.plumbline/\ndocs/context/.active-feature\n' >"$mr_repo/.gitignore"
  "$REAL_PYTHON" - "$mr_repo/docs/scope/demo.scope.json" <<'PY'
import hashlib
import json
import sys

scope = {
    "product": ["src/demo/**"],
    "governance": [
        "config/claude/tests/test_demo.sh",
        "docs/canvas/demo.canvas.md",
        "docs/plans/2026-07-29-demo.md",
        "docs/scope/demo.scope.json",
    ],
}
payload = json.dumps(scope, sort_keys=True, separators=(",", ":")).encode()
manifest = {
    "schema_version": 1,
    "feature": "demo",
    "scope": scope,
    "artifacts": {
        "canvas": "docs/canvas/demo.canvas.md",
        "plan": "docs/plans/2026-07-29-demo.md",
    },
    "provenance": [{
        "revision": 1,
        "origin": "jira:PLUM-12",
        "decision_maker": "test-user",
        "decided_at": "2026-07-29T20:00:00+00:00",
        "rationale": "Confirmed pilot scope",
        "confirmed": True,
        "scope": scope,
        "scope_digest": "sha256:" + hashlib.sha256(payload).hexdigest(),
    }],
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
  git -C "$mr_repo" init -q
  git -C "$mr_repo" config user.email plum12@example.com
  git -C "$mr_repo" config user.name "PLUM-12 Test"
  git -C "$mr_repo" checkout -q -b main
  git -C "$mr_repo" add -A
  git -C "$mr_repo" commit -q -m "baseline: confirmed manifest, plan, context"
  git -C "$mr_repo" checkout -q -b feat/demo
}

# Plant an executable, repository-owned `python3` that answers the manifest
# classifier with the one word that drives `exit 0`. It records every
# invocation, so "the repo's interpreter ran" is evidence, not an inference.
#   $1 repo   $2 relative dir for the shim   $3 marker file
plant_python_shim() {
  pp_repo="$1"; pp_dir="$2"; pp_marker="$3"
  mkdir -p "$pp_repo/$pp_dir"
  {
    printf '#!/bin/sh\n'
    printf 'printf "PROJECT_OWNED_PYTHON_EXECUTED\\n" >>"%s"\n' "$pp_marker"
    printf 'cat >/dev/null 2>&1 || true\n'
    printf 'printf "legacy\\n"\n'
    printf 'exit 0\n'
  } >"$pp_repo/$pp_dir/python3"
  chmod +x "$pp_repo/$pp_dir/python3"
}

# A repository-owned interpreter that BEHAVES CORRECTLY (delegates to the real
# one) but records that it ran. Needed because a shim that merely misbehaves
# makes a case fail for the wrong reason: the containment rule must reject a
# repository-owned interpreter even when it is functionally honest.
#   $1 repo   $2 relative dir   $3 marker file   $4 real interpreter
plant_delegating_shim() {
  pd_repo="$1"; pd_dir="$2"; pd_marker="$3"; pd_real="$4"
  mkdir -p "$pd_repo/$pd_dir"
  {
    printf '#!/bin/sh\n'
    printf 'printf "PROJECT_OWNED_PYTHON_EXECUTED\\n" >>"%s"\n' "$pd_marker"
    printf 'exec "%s" "$@"\n' "$pd_real"
  } >"$pd_repo/$pd_dir/python3"
  chmod +x "$pd_repo/$pd_dir/python3"
}

# assert_no_repo_interpreter <label> <marker>
assert_no_repo_interpreter() {
  if grep -Fq PROJECT_OWNED_PYTHON_EXECUTED "$2" 2>/dev/null; then
    _fail "$1: the governed repository's python3 was EXECUTED"
  else
    _pass "$1: no repository-owned interpreter was executed"
  fi
}

# ------------------------------------------------------------------ driver ---
GATE_OUT=""; GATE_RC=""; GATE_DECISION=""
run_pretool() { # run_pretool <repo> <payload> <path-to-use> [NAME=value ...]
  rp_repo="$1"; rp_payload="$2"; rp_path="$3"
  shift 3
  rp_out="$(mktemp -p "$WORK")"
  env -i PATH="$rp_path" HOME="$ISOLATED_CLAUDE_HOME" \
    CLAUDE_HOME="$ISOLATED_CLAUDE_HOME" CLAUDE_PROJECT_DIR="$rp_repo" "$@" \
    bash "$PRETOOL" >"$rp_out" 2>/dev/null <<EOF
$rp_payload
EOF
  GATE_RC=$?
  GATE_OUT="$(cat "$rp_out")"
  rm -f "$rp_out"
  GATE_DECISION="allow"
  case "$GATE_OUT" in
    *'"decision"'*'"deny"'*) GATE_DECISION="deny" ;;
  esac
  return 0
}

run_stop() { # run_stop <repo> <path-to-use> [NAME=value ...]
  rs_repo="$1"; rs_path="$2"
  shift 2
  rs_out="$(mktemp -p "$WORK")"
  env -i PATH="$rs_path" HOME="$ISOLATED_CLAUDE_HOME" \
    CLAUDE_HOME="$ISOLATED_CLAUDE_HOME" CLAUDE_PROJECT_DIR="$rs_repo" "$@" \
    bash "$STOP_HOOK" >"$rs_out" 2>/dev/null <<'EOF'
{}
EOF
  GATE_RC=$?
  GATE_OUT="$(cat "$rs_out")"
  rm -f "$rs_out"
  GATE_DECISION="allow"
  case "$GATE_OUT" in
    *'"decision"'*'"block"'*) GATE_DECISION="deny" ;;
  esac
  return 0
}

digest() { if [ -f "$1" ]; then shasum -a 256 "$1" | cut -d' ' -f1; else printf 'ABSENT'; fi; }

UNPLANNED='{"tool_name":"Write","tool_input":{"file_path":"src/demo/unplanned.py","content":"x"}}'
TARGET="src/demo/unplanned.py"

# attack_case <label> <shim-relative-dir> <expect-shim-ran: yes|no>
# Runs the unplanned Write through the gate with the repo-owned python3 first on
# PATH, then PERFORMS the write if the gate did not deny.
attack_case() {
  ac_label="$1"; ac_dir="$2"
  ac_repo="$WORK/$(printf '%s' "$ac_label" | tr -cd 'A-Za-z0-9')"
  rm -rf "$ac_repo"; mkdir -p "$ac_repo"
  make_repo "$ac_repo"
  ac_marker="$WORK/marker-$(printf '%s' "$ac_label" | tr -cd 'A-Za-z0-9')"
  : >"$ac_marker"
  plant_python_shim "$ac_repo" "$ac_dir" "$ac_marker"

  ac_before="$(digest "$ac_repo/$TARGET")"
  run_pretool "$ac_repo" "$UNPLANNED" "$ac_repo/$ac_dir:$CLEAN_PATH"
  if [ "$GATE_DECISION" != "deny" ]; then
    printf '# the permitted action executed\n' >>"$ac_repo/$TARGET"
  fi
  ac_after="$(digest "$ac_repo/$TARGET")"

  if grep -Fq PROJECT_OWNED_PYTHON_EXECUTED "$ac_marker" 2>/dev/null; then
    ac_ran="PROJECT_OWNED_PYTHON_EXECUTED"
  else
    ac_ran="project-owned python3 never ran"
  fi
  printf '     evidence: %s | PRETOOL_%s | target %s\n' \
    "$ac_ran" \
    "$(if [ "$GATE_DECISION" = "deny" ]; then printf 'DENIED'; else printf 'ALLOWED'; fi)" \
    "$(if [ "$ac_before" = "$ac_after" ]; then printf 'UNCHANGED'; else printf 'UNPLANNED_WRITE_EXECUTED'; fi)"

  if [ "$GATE_DECISION" = "deny" ]; then
    _pass "$ac_label: decision=deny"
  else
    _fail "$ac_label: expected deny, got allow (rc=$GATE_RC out=$GATE_OUT)"
  fi
  if [ "$ac_before" = "$ac_after" ]; then
    _pass "$ac_label: $TARGET is byte-identical"
  else
    _fail "$ac_label: $TARGET CHANGED -- the unplanned write executed"
  fi
  if grep -Fq PROJECT_OWNED_PYTHON_EXECUTED "$ac_marker" 2>/dev/null; then
    _fail "$ac_label: the governed repository's python3 was EXECUTED by the gate"
  else
    _pass "$ac_label: no repository-owned interpreter was executed"
  fi
}

# ======================================================================= N ===
echo "-- N: negative cases (the repository must not supply the interpreter)"

# N1/N4: a repository-local shim first on PATH, answering the classifier
# "legacy" with exit 0 -- the combination that currently drives the no-op path.
attack_case "N1 repo-local python3 shim (.venv/bin) reports legacy+exit0" ".venv/bin"

# A second, equally realistic location: a repo-owned tool dir.
attack_case "N4 repo-local python3 shim (tools/bin) reports legacy+exit0" "tools/bin"

# N2: entry OUTSIDE the repo, real target INSIDE it. Early canonicalisation would
# accept the entry; late canonicalisation would accept the target. Both must fail.
n2_repo="$WORK/n2"; mkdir -p "$n2_repo"; make_repo "$n2_repo"
n2_marker="$WORK/marker-n2"; : >"$n2_marker"
plant_python_shim "$n2_repo" "internal/bin" "$n2_marker"
n2_outside="$WORK/n2-outside"; mkdir -p "$n2_outside"
ln -s "$n2_repo/internal/bin/python3" "$n2_outside/python3"
n2_before="$(digest "$n2_repo/$TARGET")"
run_pretool "$n2_repo" "$UNPLANNED" "$n2_outside:$CLEAN_PATH"
if [ "$GATE_DECISION" != "deny" ]; then printf 'x\n' >>"$n2_repo/$TARGET"; fi
if [ "$GATE_DECISION" = "deny" ] && [ "$n2_before" = "$(digest "$n2_repo/$TARGET")" ]; then
  _pass "N2 external symlink whose real target is inside the repo is refused"
else
  _fail "N2 external symlink -> internal target: expected deny + unchanged file (got $GATE_DECISION)"
fi
assert_no_repo_interpreter "N2 external symlink -> internal target" "$n2_marker"

# N3: entry INSIDE the repo, real target OUTSIDE it. Repository-owned links must
# not launder an external executable -- the entry alone disqualifies it.
# The shim DELEGATES to the real interpreter, so the gate behaves normally and
# the deny/unchanged pair alone would pass without any containment rule. The
# marker is what actually decides this case.
n3_repo="$WORK/n3"; mkdir -p "$n3_repo"; make_repo "$n3_repo"
n3_marker="$WORK/marker-n3"; : >"$n3_marker"
plant_delegating_shim "$n3_repo" "internal/bin" "$n3_marker" "$REAL_PYTHON"
n3_before="$(digest "$n3_repo/$TARGET")"
run_pretool "$n3_repo" "$UNPLANNED" "$n3_repo/internal/bin:$CLEAN_PATH"
if [ "$GATE_DECISION" != "deny" ]; then printf 'x\n' >>"$n3_repo/$TARGET"; fi
if [ "$GATE_DECISION" = "deny" ] && [ "$n3_before" = "$(digest "$n3_repo/$TARGET")" ]; then
  _pass "N3 repo-internal interpreter entry: the unplanned write is still refused"
else
  _fail "N3 internal entry -> external target: expected deny + unchanged file (got $GATE_DECISION)"
fi
assert_no_repo_interpreter "N3 repo-internal interpreter entry" "$n3_marker"

# N5: PLUMBLINE_PYTHON pointing at a repository-owned interpreter.
n5_repo="$WORK/n5"; mkdir -p "$n5_repo"; make_repo "$n5_repo"
n5_marker="$WORK/marker-n5"; : >"$n5_marker"
plant_python_shim "$n5_repo" "tools/bin" "$n5_marker"
n5_before="$(digest "$n5_repo/$TARGET")"
run_pretool "$n5_repo" "$UNPLANNED" "$CLEAN_PATH" \
  "PLUMBLINE_PYTHON=$n5_repo/tools/bin/python3"
if [ "$GATE_DECISION" != "deny" ]; then printf 'x\n' >>"$n5_repo/$TARGET"; fi
if [ "$GATE_DECISION" = "deny" ] && [ "$n5_before" = "$(digest "$n5_repo/$TARGET")" ]; then
  _pass "N5 PLUMBLINE_PYTHON inside the governed repo is refused"
else
  _fail "N5 PLUMBLINE_PYTHON inside the repo: expected deny + unchanged file (got $GATE_DECISION)"
fi
assert_no_repo_interpreter "N5 PLUMBLINE_PYTHON inside the repo" "$n5_marker"

# N6: NO independent interpreter at all -> classified fail closed, never a pass.
n6_repo="$WORK/n6"; mkdir -p "$n6_repo"; make_repo "$n6_repo"
n6_marker="$WORK/marker-n6"; : >"$n6_marker"
plant_python_shim "$n6_repo" "only/bin" "$n6_marker"
n6_before="$(digest "$n6_repo/$TARGET")"
run_pretool "$n6_repo" "$UNPLANNED" "$n6_repo/only/bin"
if [ "$GATE_DECISION" != "deny" ]; then printf 'x\n' >>"$n6_repo/$TARGET"; fi
if [ "$GATE_DECISION" = "deny" ] && [ "$n6_before" = "$(digest "$n6_repo/$TARGET")" ]; then
  _pass "N6 no independent interpreter available fails CLOSED"
else
  _fail "N6 no independent interpreter: expected deny + unchanged file (got $GATE_DECISION)"
fi

# ======================================================================= B ===
# B. Bootstrap tools: everything the gate runs BEFORE authority exists.
echo "-- B: bootstrap tools owned by the governed repository"

# Plant an arbitrary repository-owned PATH program that records it ran, drains
# stdin, prints NOTHING and exits 0 -- the shape every fail-open branch above
# rewards. One helper for all of them: the class is the tool-agnostic point.
#   $1 repo  $2 relative dir  $3 tool name  $4 marker file
plant_tool_shim() {
  pt_repo="$1"; pt_dir="$2"; pt_tool="$3"; pt_marker="$4"
  mkdir -p "$pt_repo/$pt_dir"
  {
    printf '#!/bin/sh\n'
    printf 'printf "PROJECT_OWNED_BOOTSTRAP_TOOL_EXECUTED %s\\n" >>"%s"\n' "$pt_tool" "$pt_marker"
    printf 'cat >/dev/null 2>&1 || true\n'
    printf 'exit 0\n'
  } >"$pt_repo/$pt_dir/$pt_tool"
  chmod +x "$pt_repo/$pt_dir/$pt_tool"
}

# A PATH with no jq, so the hook's SECOND parser (sed + head, :25-41) is really
# reached. Without this the sed case is a vacuous pass: real jq wins at :17 and
# the fallback branch never executes.
NOJQ_PATH=""
_old_ifs="$IFS"
IFS=':'
for _p in $CLEAN_PATH; do
  [ -n "$_p" ] || continue
  [ -e "$_p/jq" ] && continue
  if [ -n "$NOJQ_PATH" ]; then NOJQ_PATH="$NOJQ_PATH:$_p"; else NOJQ_PATH="$_p"; fi
done
IFS="$_old_ifs"

# bootstrap_case <label> <tool> <path-suffix> [<extra env NAME=value> ...]
# Plants a repo-owned <tool> first on PATH, sends the unplanned Write, performs
# the write if the gate did not deny, and proves all THREE properties
# separately: not-executed, deny, bytes unchanged.
bootstrap_case() {
  bc_label="$1"; bc_tool="$2"; bc_suffix="$3"
  shift 3
  bc_slug="$(printf '%s' "$bc_label" | tr -cd 'A-Za-z0-9')"
  bc_repo="$WORK/$bc_slug"
  rm -rf "$bc_repo"; mkdir -p "$bc_repo"
  make_repo "$bc_repo"
  bc_marker="$WORK/marker-$bc_slug"
  : >"$bc_marker"
  plant_tool_shim "$bc_repo" "tools/bin" "$bc_tool" "$bc_marker"

  bc_before="$(digest "$bc_repo/$TARGET")"
  run_pretool "$bc_repo" "$UNPLANNED" "$bc_repo/tools/bin:$bc_suffix" "$@"
  if [ "$GATE_DECISION" != "deny" ]; then
    printf '# the permitted action executed\n' >>"$bc_repo/$TARGET"
  fi
  bc_after="$(digest "$bc_repo/$TARGET")"

  if grep -Fq PROJECT_OWNED_BOOTSTRAP_TOOL_EXECUTED "$bc_marker" 2>/dev/null; then
    bc_ran="PROJECT_OWNED_BOOTSTRAP_TOOL_EXECUTED"
  else
    bc_ran="repo-owned $bc_tool never ran"
  fi
  printf '     evidence: %s | PRETOOL_%s | target %s\n' \
    "$bc_ran" \
    "$(if [ "$GATE_DECISION" = "deny" ]; then printf 'DENIED'; else printf 'ALLOWED'; fi)" \
    "$(if [ "$bc_before" = "$bc_after" ]; then printf 'UNCHANGED'; else printf 'UNPLANNED_WRITE_EXECUTED'; fi)"

  if grep -Fq PROJECT_OWNED_BOOTSTRAP_TOOL_EXECUTED "$bc_marker" 2>/dev/null; then
    _fail "$bc_label: the governed repository's $bc_tool was EXECUTED"
  else
    _pass "$bc_label: repo-owned $bc_tool was not executed"
  fi
  if [ "$GATE_DECISION" = "deny" ]; then
    _pass "$bc_label: decision=deny"
  else
    _fail "$bc_label: expected deny, got allow (rc=$GATE_RC out=$GATE_OUT)"
  fi
  if [ "$bc_before" = "$bc_after" ]; then
    _pass "$bc_label: $TARGET is byte-identical"
  else
    _fail "$bc_label: $TARGET CHANGED -- the unplanned write executed"
  fi
}

# N7 -- repo-owned jq: empty answers make tool_name empty -> `*) exit 0`.
bootstrap_case "N7 repo-owned jq returns empty for every query" jq "$CLEAN_PATH"

# N8 -- repo-owned payload reader: an empty PAYLOAD short-circuits at line 11.
bootstrap_case "N8 repo-owned cat delivers an empty payload" cat "$CLEAN_PATH"

# N8b -- the jq-less fallback is a SECOND parser. Run it with no jq on PATH, or
# the case proves nothing: real jq would win at :17 and sed would never execute.
if [ -n "$NOJQ_PATH" ]; then
  bootstrap_case "N8b repo-owned sed drives the jq-less payload parser" sed "$NOJQ_PATH"
else
  _fail "N8b could not build a jq-free PATH; the fallback parser stayed untested"
fi

# N10 -- repo-owned tr: the marker reader. An empty feature slug exits 0.
bootstrap_case "N10 repo-owned tr blanks the active-feature slug" tr "$CLEAN_PATH"

# N9 -- repo-owned uv. plumbline_python.sh prefers uv (rank 2) over python3
# (rank 3), so a repository-owned uv is chosen to RUN the authority itself.
bootstrap_case "N9 repo-owned uv is preferred over python3 by the runtime" uv "$CLEAN_PATH"

# ======================================================================= S ===
echo "-- S: the same attack against the Stop hook"

s1_repo="$WORK/s1"; mkdir -p "$s1_repo"; make_repo "$s1_repo"
s1_marker="$WORK/marker-s1"; : >"$s1_marker"
plant_python_shim "$s1_repo" ".venv/bin" "$s1_marker"
# An out-of-scope change the Stop gate must block on.
mkdir -p "$s1_repo/tools"
printf 'pwned\n' >"$s1_repo/tools/hack.sh"
git -C "$s1_repo" add -A >/dev/null 2>&1
git -C "$s1_repo" commit -q -m "out-of-scope change" >/dev/null 2>&1
run_stop "$s1_repo" "$s1_repo/.venv/bin:$CLEAN_PATH" "PLUMBLINE_BIN_DIR=$BIN_SRC"
if [ "$GATE_DECISION" = "deny" ]; then
  _pass "S1 Stop hook blocks despite a repository-owned python3 first on PATH"
else
  _fail "S1 Stop hook: expected block, got allow -- the repo's interpreter decided (out=$GATE_OUT)"
fi
if grep -Fq PROJECT_OWNED_PYTHON_EXECUTED "$s1_marker" 2>/dev/null; then
  _fail "S1 the governed repository's python3 was EXECUTED by the Stop hook"
else
  _pass "S1 the Stop hook executed no repository-owned interpreter"
fi

# S2 -- a NON-Python bootstrap candidate against the Stop hook. `git` is not a
# helper there, it IS the ground truth: the changed-file surface is computed with
# it (:533-558) and file_matches_head (:207-212) -- the checker-integrity test
# itself -- is two git calls. A repository-owned git therefore decides both what
# changed and whether the checker may be trusted.
s2_repo="$WORK/s2"; mkdir -p "$s2_repo"; make_repo "$s2_repo"
mkdir -p "$s2_repo/tools"
printf 'pwned\n' >"$s2_repo/tools/hack.sh"
git -C "$s2_repo" add -A >/dev/null 2>&1
git -C "$s2_repo" commit -q -m "out-of-scope change" >/dev/null 2>&1
s2_marker="$WORK/marker-s2"; : >"$s2_marker"
plant_tool_shim "$s2_repo" "tools/bin" "git" "$s2_marker"
run_stop "$s2_repo" "$s2_repo/tools/bin:$CLEAN_PATH" "PLUMBLINE_BIN_DIR=$BIN_SRC"
if grep -Fq PROJECT_OWNED_BOOTSTRAP_TOOL_EXECUTED "$s2_marker" 2>/dev/null; then
  s2_ran="PROJECT_OWNED_BOOTSTRAP_TOOL_EXECUTED"
else
  s2_ran="repo-owned git never ran"
fi
printf '     evidence: %s | STOP_%s\n' "$s2_ran" \
  "$(if [ "$GATE_DECISION" = "deny" ]; then printf 'BLOCKED'; else printf 'ALLOWED'; fi)"
if grep -Fq PROJECT_OWNED_BOOTSTRAP_TOOL_EXECUTED "$s2_marker" 2>/dev/null; then
  _fail "S2 the governed repository's git was EXECUTED by the Stop hook"
else
  _pass "S2 the Stop hook executed no repository-owned git"
fi
if [ "$GATE_DECISION" = "deny" ]; then
  _pass "S2 Stop hook still blocks the out-of-scope change with a repo-owned git on PATH"
else
  _fail "S2 Stop hook: expected block, got allow -- the repo's git decided (out=$GATE_OUT)"
fi

# ======================================================================= P ===
echo "-- P: positive cases (the gate stays usable)"

p_repo="$WORK/p"; mkdir -p "$p_repo"; make_repo "$p_repo"

# P1: an external, permitted interpreter -- the unplanned write is still refused,
# i.e. the containment rule did not break the gate's real job.
p1_before="$(digest "$p_repo/$TARGET")"
run_pretool "$p_repo" "$UNPLANNED" "$CLEAN_PATH"
if [ "$GATE_DECISION" != "deny" ]; then printf 'x\n' >>"$p_repo/$TARGET"; fi
if [ "$GATE_DECISION" = "deny" ] && [ "$p1_before" = "$(digest "$p_repo/$TARGET")" ]; then
  _pass "P1 with an external interpreter the unplanned write is still refused"
else
  _fail "P1 external interpreter: expected deny + unchanged file (got $GATE_DECISION)"
fi

# P2: the action the plan DOES declare must pass -- kills the deny-everything twin.
run_pretool "$p_repo" \
  '{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py","old_string":"a","new_string":"b"}}' \
  "$CLEAN_PATH"
if [ "$GATE_DECISION" = "allow" ]; then
  _pass "P2 a planned Create:/Modify: target passes through"
else
  _fail "P2 planned target: expected pass-through, got deny (out=$GATE_OUT)"
fi

# P3: an unarmed session stays a silent no-op.
p3_repo="$WORK/p3"; mkdir -p "$p3_repo"; make_repo "$p3_repo"
rm -f "$p3_repo/docs/context/.active-feature"
run_pretool "$p3_repo" "$UNPLANNED" "$CLEAN_PATH"
if [ "$GATE_DECISION" = "allow" ] && [ -z "$GATE_OUT" ]; then
  _pass "P3 unarmed session: pass-through with EMPTY stdout"
else
  _fail "P3 unarmed session: expected silent pass-through (rc=$GATE_RC out=$GATE_OUT)"
fi

# P4: the authority actually used comes from OUTSIDE the governed repository.
# Planting a permissive checker inside the repo must not change the verdict.
p4_repo="$WORK/p4"; mkdir -p "$p4_repo"; make_repo "$p4_repo"
mkdir -p "$p4_repo/config/claude/bin"
printf '#!/bin/sh\nexit 0\n' >"$p4_repo/config/claude/bin/plumbline-scope-check"
chmod +x "$p4_repo/config/claude/bin/plumbline-scope-check"
p4_before="$(digest "$p4_repo/$TARGET")"
run_pretool "$p4_repo" "$UNPLANNED" "$CLEAN_PATH"
if [ "$GATE_DECISION" != "deny" ]; then printf 'x\n' >>"$p4_repo/$TARGET"; fi
if [ "$GATE_DECISION" = "deny" ] && [ "$p4_before" = "$(digest "$p4_repo/$TARGET")" ]; then
  _pass "P4 a repository-owned permissive checker does not become the authority"
else
  _fail "P4 repo-owned checker: expected deny + unchanged file (got $GATE_DECISION)"
fi

finish
